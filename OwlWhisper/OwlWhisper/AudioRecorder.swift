import AVFoundation

/// 麦克风录音器。
/// 使用 AVAudioEngine 录制 16kHz mono float32 PCM 音频。
class AudioRecorder {

    private let engine = AVAudioEngine()
    private var buffer = Data()
    private let lock = NSLock()
    private let targetSampleRate: Double = 16000

    /// 开始录音，音频数据累积到内部 buffer。
    func startRecording() {
        lock.lock()
        buffer = Data()
        lock.unlock()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // 目标格式：16kHz mono float32
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            NSLog("[AudioRecorder] 无法创建目标音频格式")
            return
        }

        // 如果输入格式与目标不同，使用转换器
        let converter: AVAudioConverter?
        if inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount != 1 {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        } else {
            converter = nil
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] pcmBuffer, _ in
            guard let self else { return }

            let outputBuffer: AVAudioPCMBuffer
            if let converter {
                // 计算输出帧数（按采样率比例换算）
                let ratio = targetSampleRate / inputFormat.sampleRate
                let outputFrameCount = AVAudioFrameCount(Double(pcmBuffer.frameLength) * ratio)
                guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else { return }

                var error: NSError?
                converter.convert(to: converted, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return pcmBuffer
                }
                if let error { NSLog("[AudioRecorder] 音频转换失败: %@", error.localizedDescription); return }
                outputBuffer = converted
            } else {
                outputBuffer = pcmBuffer
            }

            // 提取 float32 数据
            guard let channelData = outputBuffer.floatChannelData else { return }
            let frameCount = Int(outputBuffer.frameLength)
            let data = Data(bytes: channelData[0], count: frameCount * MemoryLayout<Float>.size)

            self.lock.lock()
            self.buffer.append(data)
            self.lock.unlock()
        }

        do {
            try engine.start()
        } catch {
            NSLog("[AudioRecorder] 启动失败: \(error)")
        }
    }

    /// 停止录音，返回累积的 float32 PCM 数据。
    func stopRecording() -> Data {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        lock.lock()
        let result = buffer
        buffer = Data()
        lock.unlock()

        return result
    }
}
