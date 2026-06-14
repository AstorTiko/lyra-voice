#!/usr/bin/env bash
set -euo pipefail

# Делает .app самодостаточным: копирует движки whisper.cpp / llama.cpp + все их
# не-системные dylib внутрь бандла (Contents/Helpers/{bin,lib}) и переписывает
# абсолютные homebrew-пути на @rpath, чтобы приложение работало на ЛЮБОМ Apple
# Silicon Mac без homebrew. ПОДПИСЬ здесь НЕ делается — её ставит build-release-app.sh
# финальным проходом (codesign --deep) уже после правки путей.
#
# Использование: bundle-engines.sh "/path/to/Lyra Voice.app"
#
# Структура rpath движков уже = @loader_path/../lib, поэтому bin/../lib совпадает,
# и @rpath-зависимости разрешаются без правок. Чиним только абсолютные /opt/homebrew.

APP_DIR="${1:?Usage: bundle-engines.sh <App.app>}"
HELPERS="$APP_DIR/Contents/Helpers"
BIN_DIR="$HELPERS/bin"
LIB_DIR="$HELPERS/lib"

BREW_OPT="/opt/homebrew/opt"

# Бинарники движков (homebrew symlink → реальный файл резолвится cp -L).
BINARIES=(
  "/opt/homebrew/bin/whisper-server"
  "/opt/homebrew/bin/whisper-cli"
  "/opt/homebrew/bin/llama-server"
)

# ggml-backend'ы (BLAS/Metal/CPU) — отдельные .so, которые ggml dlopen-ит в РАНТАЙМЕ
# из директории исполняемого файла (проверено: ищет рядом с бинарником). Кладём их в
# bin/. Metal-шейдеры встроены в .so (embedded), внешних .metal не нужно. CPU-варианты
# под все чипы Apple Silicon (m1/m2_m3/m4) — ggml сам выбирает подходящий в рантайме.
GGML_LIBEXEC="/opt/homebrew/Cellar/ggml/0.13.1/libexec"
BACKENDS=(
  "libggml-blas.so"
  "libggml-metal.so"
  "libggml-cpu-apple_m1.so"
  "libggml-cpu-apple_m2_m3.so"
  "libggml-cpu-apple_m4.so"
)

# dylib: "источник|имя-в-бандле" (имя = basename, как его ищут @rpath/абсолютные ссылки).
LIBS=(
  "$BREW_OPT/whisper-cpp/lib/libwhisper.1.dylib|libwhisper.1.dylib"
  "$BREW_OPT/ggml/lib/libggml.0.dylib|libggml.0.dylib"
  "$BREW_OPT/ggml/lib/libggml-base.0.dylib|libggml-base.0.dylib"
  "$BREW_OPT/libomp/lib/libomp.dylib|libomp.dylib"
  "$BREW_OPT/llama.cpp/lib/libllama.0.dylib|libllama.0.dylib"
  "$BREW_OPT/llama.cpp/lib/libllama-common.0.dylib|libllama-common.0.dylib"
  "$BREW_OPT/llama.cpp/lib/libllama-server-impl.dylib|libllama-server-impl.dylib"
  "$BREW_OPT/llama.cpp/lib/libmtmd.0.dylib|libmtmd.0.dylib"
  "$BREW_OPT/openssl@3/lib/libssl.3.dylib|libssl.3.dylib"
  "$BREW_OPT/openssl@3/lib/libcrypto.3.dylib|libcrypto.3.dylib"
)

echo "→ bundling engines into $APP_DIR"
rm -rf "$HELPERS"
mkdir -p "$BIN_DIR" "$LIB_DIR"

# 1. Копируем бинарники (резолвим symlink в реальный файл).
for src in "${BINARIES[@]}"; do
  [ -e "$src" ] || { echo "MISSING binary: $src" >&2; exit 1; }
  cp -L "$src" "$BIN_DIR/$(basename "$src")"
  chmod u+w "$BIN_DIR/$(basename "$src")"
done

# 1b. Копируем ggml-backend .so в bin/ (ggml ищет их рядом с исполняемым файлом).
for so in "${BACKENDS[@]}"; do
  [ -e "$GGML_LIBEXEC/$so" ] || { echo "MISSING backend: $GGML_LIBEXEC/$so" >&2; exit 1; }
  cp -L "$GGML_LIBEXEC/$so" "$BIN_DIR/$so"
  chmod u+w "$BIN_DIR/$so"
done

# 2. Копируем dylib под нужными именами.
for pair in "${LIBS[@]}"; do
  src="${pair%%|*}"; name="${pair##*|}"
  [ -e "$src" ] || { echo "MISSING lib: $src" >&2; exit 1; }
  cp -L "$src" "$LIB_DIR/$name"
  chmod u+w "$LIB_DIR/$name"
done

# Переписать все абсолютные homebrew-ссылки в файле на @rpath/<basename>.
# Зависимости собираем в переменную (без pipe→while), иначе пустой grep + pipefail
# роняет скрипт на файлах без homebrew-зависимостей (напр. libcrypto).
rewrite_homebrew_deps() {
  local f="$1" deps dep
  deps="$(otool -L "$f" | tail -n +2 | awk '{print $1}' | grep '^/opt/homebrew' || true)"
  for dep in $deps; do
    install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$f"
  done
}

# 3. Чиним dylib: id = @rpath/<name>, rpath @loader_path (свой каталог), абсолютные → @rpath.
for lib in "$LIB_DIR"/*.dylib; do
  name="$(basename "$lib")"
  install_name_tool -id "@rpath/$name" "$lib"
  # @loader_path как rpath: @rpath/X из этого dylib → его же каталог (lib/). Идемпотентно.
  install_name_tool -add_rpath "@loader_path" "$lib" 2>/dev/null || true
  rewrite_homebrew_deps "$lib"
done

# 4. Чиним бинарники: абсолютные homebrew-ссылки → @rpath (rpath @loader_path/../lib уже есть).
for bin in "$BIN_DIR"/*; do
  rewrite_homebrew_deps "$bin"
done

# 5. Проверка: не осталось ни одной абсолютной homebrew-ссылки.
LEFT="$(for f in "$BIN_DIR"/* "$LIB_DIR"/*.dylib; do otool -L "$f" | tail -n +2 | awk '{print $1}'; done | grep '^/opt/homebrew' || true)"
if [ -n "$LEFT" ]; then
  echo "ERROR: остались homebrew-зависимости:" >&2
  echo "$LEFT" >&2
  exit 1
fi

echo "✓ движки забандлены: $(ls "$BIN_DIR" | tr '\n' ' ')| dylib: $(ls "$LIB_DIR" | wc -l | tr -d ' ')"
