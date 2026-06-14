#!/usr/bin/env bash
set -euo pipefail

# Собирает САМОДОСТАТОЧНЫЙ "Lyra Voice.app" для распространения:
#   1) обычная сборка + бандл (build-dev-app.sh),
#   2) вшивание движков whisper.cpp/llama.cpp + dylib (bundle-engines.sh),
#   3) финальная подпись всего бандла (--deep) — запечатывает вложенные движки.
#
# Результат печатается последней строкой (путь к .app). Движки больше НЕ нужны из
# homebrew у конечного пользователя; модели приложение докачивает само при первом запуске.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/Lyra Voice.app"
ENTITLEMENTS_FILE="$ROOT_DIR/LyraVoice.entitlements"
HELPER_ENTITLEMENTS="$ROOT_DIR/LyraVoiceHelper.entitlements"
BUNDLE_ID="local.lyravoice.app"
SIGN_IDENTITY="LyraVoice Dev"
SIGNING_KC="$HOME/Library/Keychains/lyravoice-signing.keychain-db"

cd "$ROOT_DIR"

# 1. Обычная сборка бандла (включая первичную подпись без движков).
scripts/build-dev-app.sh >/dev/null

# 2. Вшить движки + пофиксить пути (подпись слетит — переподпишем ниже).
scripts/bundle-engines.sh "$APP_DIR"

# 3. Финальная подпись всего бандла в staging вне синхронизируемой папки
#    (тот же приём, что в build-dev-app: fileprovider не вернёт xattr во время codesign).
[[ -f "$SIGNING_KC" ]] && security unlock-keychain -p "lyravoice-local-signing" "$SIGNING_KC" 2>/dev/null || true

# Подпись INSIDE-OUT (НЕ --deep!): сначала dylib, потом бинарники движков (с
# disable-library-validation — иначе hardened runtime + самоподпись без Team ID
# отвергает вшитые dylib), потом главный .app — он запечатывает уже подписанное
# вложенное. --deep здесь нельзя: он перезатёр бы entitlements движков.
ADHOC=0
security find-identity -p codesigning "$SIGNING_KC" 2>/dev/null | grep -q "$SIGN_IDENTITY" || ADHOC=1

cs() { # $@ = доп. флаги + цель; подпись сертификатом или ad-hoc
  if [[ "$ADHOC" == 1 ]]; then
    codesign --force --timestamp=none --sign - "$@"
  else
    codesign --force --timestamp=none --sign "$SIGN_IDENTITY" --keychain "$SIGNING_KC" "$@"
  fi
}

sign_staged() {
  local stage; stage="$(mktemp -d)/$(basename "$APP_DIR")"
  ditto "$APP_DIR" "$stage"
  xattr -cr "$stage" 2>/dev/null || true
  find "$stage" -exec xattr -c {} \; 2>/dev/null || true

  # 1) dylib движков (hardened runtime, без entitlements).
  local f
  for f in "$stage"/Contents/Helpers/lib/*.dylib; do
    cs --options runtime "$f"
  done
  # 2) бинарники движков (hardened + disable-library-validation).
  for f in "$stage"/Contents/Helpers/bin/*; do
    cs --options runtime --entitlements "$HELPER_ENTITLEMENTS" "$f"
  done
  # 3) главный .app (его entitlements + стабильный идентификатор; БЕЗ --deep).
  cs --options runtime --entitlements "$ENTITLEMENTS_FILE" --identifier "$BUNDLE_ID" "$stage"

  codesign --verify --strict --deep "$stage"
  ditto "$stage" "$APP_DIR"
}

[[ -f "$SIGNING_KC" ]] && security unlock-keychain -p "lyravoice-local-signing" "$SIGNING_KC" 2>/dev/null || true
ok=0
for _ in 1 2 3; do if sign_staged; then ok=1; break; fi; sleep 0.3; done
[[ "$ok" == 1 ]] || { echo "ERROR: финальная подпись не удалась" >&2; exit 1; }
if [[ "$ADHOC" == 1 ]]; then
  echo "WARN: подписано ad-hoc (сертификат '$SIGN_IDENTITY' не найден) — Accessibility будет слетать" >&2
else
  echo "signed (release, inside-out): $SIGN_IDENTITY" >&2
fi

echo "$APP_DIR"
