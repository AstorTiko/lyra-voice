#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$("$ROOT_DIR/scripts/build-dev-app.sh" | tail -n 1)"

# Убиваем старый экземпляр: `open` на уже запущенном приложении НЕ загружает новый
# бинарь (просто активирует процесс) — без этого правки кода «не применяются».
pkill -x LyraVoice 2>/dev/null || true
sleep 0.5

open "$APP_PATH"
