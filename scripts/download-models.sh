#!/usr/bin/env bash
set -euo pipefail

MODEL_DIR="${LYRAVOICE_MODEL_DIR:-$HOME/Library/Application Support/LyraVoice/Models}"
mkdir -p "$MODEL_DIR"

download_model() {
  local name="$1"
  local url="$2"
  local destination="$MODEL_DIR/$name"

  if [[ -s "$destination" ]]; then
    echo "Already present: $destination"
    return
  fi

  echo "Downloading: $name"
  curl -L --fail --progress-bar "$url" -o "$destination.tmp"
  mv "$destination.tmp" "$destination"
  echo "Saved: $destination"
}

download_model \
  "ggml-tiny.bin" \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"

download_model \
  "ggml-small.bin" \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"

download_model \
  "ggml-medium.bin" \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin"

download_model \
  "ggml-large-v3-turbo.bin" \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"

download_model \
  "ggml-large-v3.bin" \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin"

# VAD-модель Silero — нужна для режима обрезки пауз (--vad)
download_model \
  "ggml-silero-v5.1.2.bin" \
  "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin"

echo "Models ready in: $MODEL_DIR"
