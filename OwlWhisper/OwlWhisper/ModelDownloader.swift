import Foundation

/// 分块并行下载器，支持断点续传。
/// 参考 OwlUploader 的 R2Service.downloadObjectChunked() 实现。
class ModelDownloader {

    struct Progress {
        let bytesDownloaded: Int64
        let totalBytes: Int64
        var fraction: Double { totalBytes > 0 ? Double(bytesDownloaded) / Double(totalBytes) : 0 }
    }

    private let chunkSize: Int64 = 5 * 1024 * 1024  // 5MB per chunk
    private let maxConcurrency = 6
    private let cancelLock = NSLock()
    private var _cancelled = false
    private var cancelled: Bool {
        get { cancelLock.lock(); defer { cancelLock.unlock() }; return _cancelled }
        set { cancelLock.lock(); defer { cancelLock.unlock() }; _cancelled = newValue }
    }

    /// 下载文件，支持分块并行和断点续传。
    /// - Parameters:
    ///   - url: 下载地址
    ///   - destination: 本地保存路径
    ///   - progress: 进度回调（主线程）
    func download(
        from url: URL,
        to destination: URL,
        progress: @escaping (Progress) -> Void
    ) async throws {
        cancelled = false

        // 1. HEAD 请求获取文件大小，并跟随重定向拿到最终 URL
        let (finalURL, totalBytes) = try await resolveDownload(url)

        // 拿不到大小时回退到简单下载
        if totalBytes <= 0 {
            try await simpleDownload(from: finalURL, to: destination, progress: progress)
            return
        }

        let fm = FileManager.default
        let filePath = destination.path

        // 2. 计算分块
        let chunks = buildChunks(totalBytes: totalBytes)
        let metaPath = filePath + ".chunks"

        // 3. 加载已完成的 chunk（断点续传）
        var completedChunks = loadCompletedChunks(from: metaPath)

        // 4. 预分配文件（仅首次）
        if !fm.fileExists(atPath: filePath) {
            guard fm.createFile(atPath: filePath, contents: nil) else {
                throw DownloadError.fileCreationFailed(path: filePath)
            }
            let handle = try FileHandle(forWritingTo: destination)
            try handle.truncate(atOffset: UInt64(totalBytes))
            try handle.close()
        }

        // 5. 计算已下载字节数
        let initialBytes: Int64 = completedChunks.reduce(0) { sum, idx in
            sum + chunks[idx].length
        }
        let downloaded = LockedCounter(initialValue: initialBytes)

        DispatchQueue.main.async {
            progress(Progress(bytesDownloaded: initialBytes, totalBytes: totalBytes))
        }

        // 6. 序列化文件写入的 actor
        let fileWriter = try FileWriter(url: destination)

        // 7. 并行下载未完成的 chunk
        let pendingIndices = chunks.indices.filter { !completedChunks.contains($0) }

        // 用 iterator 节流并发：先填满 maxConcurrency 个任务，每完成一个再添加下一个
        try await withThrowingTaskGroup(of: Int.self) { group in
            var iterator = pendingIndices.makeIterator()

            // 初始填充
            for _ in 0..<maxConcurrency {
                guard let idx = iterator.next() else { break }
                let chunk = chunks[idx]
                group.addTask {
                    guard !self.cancelled else { throw DownloadError.cancelled }
                    let data = try await self.downloadChunk(from: finalURL, chunk: chunk)
                    try await fileWriter.write(data: data, at: UInt64(chunk.offset))
                    return idx
                }
            }

            // 每完成一个，补充一个新任务
            for try await completedIdx in group {
                guard !cancelled else { throw DownloadError.cancelled }

                let bytesAdded = chunks[completedIdx].length
                let newTotal = downloaded.add(bytesAdded)

                completedChunks.insert(completedIdx)
                saveCompletedChunks(completedChunks, to: metaPath)

                DispatchQueue.main.async {
                    progress(Progress(bytesDownloaded: newTotal, totalBytes: totalBytes))
                }

                // 补充下一个 chunk
                if let idx = iterator.next() {
                    let chunk = chunks[idx]
                    group.addTask {
                        guard !self.cancelled else { throw DownloadError.cancelled }
                        let data = try await self.downloadChunk(from: finalURL, chunk: chunk)
                        try await fileWriter.write(data: data, at: UInt64(chunk.offset))
                        return idx
                    }
                }
            }
        }

        try await fileWriter.close()

        // 8. 下载完成，清理元数据
        do {
            try fm.removeItem(atPath: metaPath)
        } catch {
            NSLog("[ModelDownloader] 清理元数据失败: %@", error.localizedDescription)
        }
    }

    func cancel() {
        cancelled = true
    }

    // MARK: - 分块逻辑

    private struct Chunk {
        let index: Int
        let offset: Int64
        let length: Int64
    }

    private func buildChunks(totalBytes: Int64) -> [Chunk] {
        var chunks = [Chunk]()
        var offset: Int64 = 0
        var idx = 0
        while offset < totalBytes {
            let length = min(chunkSize, totalBytes - offset)
            chunks.append(Chunk(index: idx, offset: offset, length: length))
            offset += length
            idx += 1
        }
        return chunks
    }

    // MARK: - 简单下载（无 Content-Length 时回退）

    private func simpleDownload(
        from url: URL, to destination: URL,
        progress: @escaping (Progress) -> Void
    ) async throws {
        let (tmpURL, response) = try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<(URL, URLResponse), Error>) in
            let task = URLSession.shared.downloadTask(with: url) { tmpURL, response, error in
                if let error { cont.resume(throwing: error); return }
                guard let tmpURL, let response else {
                    cont.resume(throwing: DownloadError.noData); return
                }
                cont.resume(returning: (tmpURL, response))
            }
            task.resume()
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw DownloadError.serverError(statusCode: http.statusCode)
        }

        let fm = FileManager.default
        do {
            try fm.removeItem(at: destination)
        } catch {
            NSLog("[ModelDownloader] 清理旧文件失败: %@", error.localizedDescription)
        }
        try fm.moveItem(at: tmpURL, to: destination)
    }

    // MARK: - 网络请求

    private func resolveDownload(_ url: URL) async throws -> (URL, Int64) {
        // 用 Range: bytes=0-0 获取文件大小（比 HEAD 更可靠，GitHub CDN 一定返回 Content-Range）
        var request = URLRequest(url: url)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DownloadError.serverError(statusCode: 0)
        }
        guard (200...299).contains(http.statusCode) else {
            throw DownloadError.serverError(statusCode: http.statusCode)
        }

        let finalURL = http.url ?? url

        // 从 Content-Range: bytes 0-0/总大小 解析
        var totalBytes: Int64 = -1
        if let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
           let slashIdx = contentRange.lastIndex(of: "/"),
           let size = Int64(contentRange[contentRange.index(after: slashIdx)...]) {
            totalBytes = size
        } else {
            // 回退到 Content-Length
            totalBytes = http.expectedContentLength
        }

        return (finalURL, totalBytes)
    }

    /// 下载单个 chunk，返回数据（不写文件）。
    private func downloadChunk(from url: URL, chunk: Chunk) async throws -> Data {
        let endByte = chunk.offset + chunk.length - 1
        var request = URLRequest(url: url)
        request.setValue("bytes=\(chunk.offset)-\(endByte)", forHTTPHeaderField: "Range")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DownloadError.serverError(statusCode: 0)
        }
        // 206 = 正常分块响应；200 = 服务器忽略了 Range，返回了全文件
        if http.statusCode == 200 {
            throw DownloadError.rangeNotSupported
        }
        guard http.statusCode == 206 else {
            throw DownloadError.serverError(statusCode: http.statusCode)
        }

        // 校验返回数据长度
        guard Int64(data.count) == chunk.length else {
            NSLog("[ModelDownloader] chunk %d 大小不匹配: 期望 %lld, 收到 %d",
                  chunk.index, chunk.length, data.count)
            throw DownloadError.dataSizeMismatch(expected: chunk.length, got: Int64(data.count))
        }

        return data
    }

    // MARK: - 断点续传元数据

    private func loadCompletedChunks(from path: String) -> Set<Int> {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let indices = text.split(separator: ",").compactMap { Int($0) }
        return Set(indices)
    }

    private func saveCompletedChunks(_ chunks: Set<Int>, to path: String) {
        let text = chunks.sorted().map(String.init).joined(separator: ",")
        do {
            try text.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            NSLog("[ModelDownloader] 保存 chunk 元数据失败: %@", error.localizedDescription)
        }
    }

    // MARK: - 错误类型

    enum DownloadError: LocalizedError {
        case serverError(statusCode: Int)
        case rangeNotSupported
        case noData
        case cancelled
        case dataSizeMismatch(expected: Int64, got: Int64)
        case fileCreationFailed(path: String)

        var errorDescription: String? {
            switch self {
            case .serverError(let code): return "服务器错误 (HTTP \(code))"
            case .rangeNotSupported: return "服务器不支持分块下载"
            case .noData: return "未收到数据"
            case .cancelled: return "下载已取消"
            case .dataSizeMismatch(let expected, let got): return "数据大小不匹配: 期望 \(expected), 收到 \(got)"
            case .fileCreationFailed(let path): return "无法创建文件: \(path)"
            }
        }
    }
}

// MARK: - 序列化文件写入 Actor

private actor FileWriter {
    private let handle: FileHandle

    init(url: URL) throws {
        handle = try FileHandle(forWritingTo: url)
    }

    func write(data: Data, at offset: UInt64) throws {
        try handle.seek(toOffset: offset)
        handle.write(data)
    }

    func close() throws {
        try handle.close()
    }
}

// MARK: - 线程安全计数器

private final class LockedCounter: @unchecked Sendable {
    private var value: Int64
    private let lock = NSLock()

    init(initialValue: Int64 = 0) {
        self.value = initialValue
    }

    func add(_ delta: Int64) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        value += delta
        return value
    }
}


