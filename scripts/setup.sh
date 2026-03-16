#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MODELS_DIR="$PROJECT_DIR/models"
OWL_DIR="$PROJECT_DIR/OwlWhisper"

echo "=== OwlWhisper 环境初始化 ==="

# 1. 下载 sherpa-onnx 原生库和头文件
FRAMEWORKS_DIR="$OWL_DIR/Frameworks"
HEADERS_DIR="$OWL_DIR/Headers"

mkdir -p "$FRAMEWORKS_DIR" "$HEADERS_DIR/sherpa-onnx/c-api"

if [ ! -f "$FRAMEWORKS_DIR/libsherpa-onnx-c-api.dylib" ]; then
    echo ">>> 下载 sherpa-onnx 原生库..."

    # 从 sherpa-onnx pip 包复制（需先 pip install sherpa-onnx）
    SITE_PKGS=$(python3 -c "import site; print(site.getsitepackages()[0])" 2>/dev/null || true)
    SHERPA_PKG="${SITE_PKGS}/sherpa_onnx"

    if [ -f "$SHERPA_PKG/lib/libsherpa-onnx-c-api.dylib" ]; then
        cp "$SHERPA_PKG/lib/libsherpa-onnx-c-api.dylib" "$FRAMEWORKS_DIR/"
        cp "$SHERPA_PKG/lib/libonnxruntime.1.23.2.dylib" "$FRAMEWORKS_DIR/"
        cp "$SHERPA_PKG/include/sherpa-onnx/c-api/c-api.h" "$HEADERS_DIR/sherpa-onnx/c-api/"
        echo "    原生库已复制"
    else
        echo "    错误: 未找到 sherpa-onnx 包，请先安装: pip install sherpa-onnx"
        exit 1
    fi
else
    echo ">>> sherpa-onnx 原生库已存在"
fi

# 2. 下载模型
mkdir -p "$MODELS_DIR"

# FireRedASR2 int8 模型
MODEL_NAME="sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26"
MODEL_DIR="$MODELS_DIR/$MODEL_NAME"

if [ ! -d "$MODEL_DIR" ]; then
    echo ">>> 下载 FireRedASR2 int8 模型..."
    cd "$MODELS_DIR"
    wget -q --show-progress \
        "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/${MODEL_NAME}.tar.bz2"
    tar xf "${MODEL_NAME}.tar.bz2"
    rm "${MODEL_NAME}.tar.bz2"
    echo ">>> 模型已下载到: $MODEL_DIR"
else
    echo ">>> 模型已存在: $MODEL_DIR"
fi

# 标点恢复模型
PUNCT_NAME="sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12"
PUNCT_DIR="$MODELS_DIR/$PUNCT_NAME"

if [ ! -d "$PUNCT_DIR" ]; then
    echo ">>> 下载标点恢复模型..."
    cd "$MODELS_DIR"
    wget -q --show-progress \
        "https://github.com/k2-fsa/sherpa-onnx/releases/download/punctuation-models/${PUNCT_NAME}.tar.bz2"
    tar xf "${PUNCT_NAME}.tar.bz2"
    rm "${PUNCT_NAME}.tar.bz2"
    echo ">>> 标点模型已下载到: $PUNCT_DIR"
else
    echo ">>> 标点模型已存在: $PUNCT_DIR"
fi

# Silero VAD 模型
VAD_MODEL="$MODELS_DIR/silero_vad.onnx"
if [ ! -f "$VAD_MODEL" ]; then
    echo ">>> 下载 Silero VAD 模型..."
    wget -q --show-progress -O "$VAD_MODEL" \
        "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx"
    echo ">>> VAD 模型已下载"
else
    echo ">>> VAD 模型已存在"
fi

echo ""
echo "=== 初始化完成 ==="
echo "原生库:      $FRAMEWORKS_DIR"
echo "模型目录:    $MODELS_DIR"
echo ""
echo "用 Xcode 打开 OwlWhisper.xcodeproj 编译运行即可。"
