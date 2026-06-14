#!/usr/bin/env bash
set -euo pipefail

# Собирает самодостаточный .app и упаковывает в DMG для GitHub-релиза.
# Раскладка DMG: "Lyra Voice.app" + симлинк на /Applications (классический drag-to-install).
#
# Использование: make-dmg.sh [версия]   (по умолчанию версия из AppBrand = 0.1.0)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Lyra Voice"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
VERSION="${1:-$(grep -m1 'versionString' "$ROOT_DIR/Sources/LyraVoiceCore/AppBrand.swift" | sed -E 's/.*"([0-9.]+)".*/\1/')}"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/LyraVoice-v$VERSION.dmg"

cd "$ROOT_DIR"

# 1. Самодостаточный .app.
scripts/build-release-app.sh >/dev/null
echo "→ app ready: $APP_DIR"

# 2. Staging для DMG.
mkdir -p "$DIST_DIR"
STAGE="$(mktemp -d)/dmg"
mkdir -p "$STAGE"
ditto "$APP_DIR" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

# В синхронизируемой Documents fileprovider возвращает xattr (FinderInfo) → codesign
# --verify ругается «detritus not allowed». В staging (/tmp) чистим — это НЕ ломает
# подпись (xattr не подписываются) и даёт чистый бандл в DMG.
xattr -cr "$STAGE/$APP_NAME.app" 2>/dev/null || true
find "$STAGE/$APP_NAME.app" -exec xattr -c {} \; 2>/dev/null || true
if ! codesign --verify --strict --deep "$STAGE/$APP_NAME.app" 2>/dev/null; then
  echo "ERROR: подпись бандла в DMG невалидна" >&2
  exit 1
fi
echo "✓ подпись бандла валидна"

# 3. Сборка сжатого DMG.
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG_PATH" >/dev/null

SIZE="$(du -h "$DMG_PATH" | cut -f1 | tr -d ' ')"
echo "✓ DMG готов: $DMG_PATH ($SIZE)"
echo "$DMG_PATH"
