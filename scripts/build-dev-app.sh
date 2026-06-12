#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Lyra Voice"
SWIFT_PRODUCT_NAME="LyraVoice"
EXECUTABLE_NAME="LyraVoice"
BUNDLE_ID="local.lyravoice.app"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
# Старые имена бандла, которые чистим перед сборкой (без пробела и прошлый бренд).
LEGACY_APP_DIRS=("$ROOT_DIR/build/LyraVoice.app" "$ROOT_DIR/build/WhisperKey.app")
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_FILE="LyraVoice.icns"
LOGO_FILE="LyraVoiceMark.png"
ENTITLEMENTS_FILE="$ROOT_DIR/LyraVoice.entitlements"

cd "$ROOT_DIR"
swift build

rm -rf "$APP_DIR"
for legacy in "${LEGACY_APP_DIRS[@]}"; do rm -rf "$legacy"; done
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/debug/$SWIFT_PRODUCT_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

if [[ -f "$ROOT_DIR/tmp/russian-test.wav" ]]; then
    cp "$ROOT_DIR/tmp/russian-test.wav" "$RESOURCES_DIR/russian-test.wav"
fi

if [[ -f "$ROOT_DIR/Assets/Brand/$ICON_FILE" ]]; then
    cp "$ROOT_DIR/Assets/Brand/$ICON_FILE" "$RESOURCES_DIR/$ICON_FILE"
fi

if [[ -f "$ROOT_DIR/Assets/Brand/$LOGO_FILE" ]]; then
    cp "$ROOT_DIR/Assets/Brand/$LOGO_FILE" "$RESOURCES_DIR/$LOGO_FILE"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>$ICON_FILE</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Lyra Voice needs microphone access to transcribe your speech locally.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Lyra Voice uses paste commands to insert dictated text into the active app.</string>
</dict>
</plist>
PLIST

printf "APPL????" > "$CONTENTS_DIR/PkgInfo"
plutil -lint "$CONTENTS_DIR/Info.plist"

# Подпись. КЛЮЧЕВОЕ: подписываем стабильным самоподписанным сертификатом
# «LyraVoice Dev», если он настроен (scripts/setup-signing-cert.sh). Тогда
# designated requirement привязан к СЕРТИФИКАТУ, а не к CDHash, и выданный
# Accessibility-доступ переживает пересборки.
#
# Нюанс: папка лежит в синхронизируемых Documents, и fileprovider/Finder
# возвращают xattr (com.apple.FinderInfo) МЕЖДУ чисткой и подписью → codesign
# падает с «resource fork… detritus not allowed», и .app остаётся ad-hoc.
# Поэтому чистим+подписываем с ретраями и в конце ПРОВЕРЯЕМ, что подпись по
# сертификату (иначе Accessibility сломается — лучше упасть громко).
SIGN_IDENTITY="LyraVoice Dev"
SIGNING_KC="$HOME/Library/Keychains/lyravoice-signing.keychain-db"

clean_detritus() {
    dot_clean -m "$APP_DIR" 2>/dev/null || true
    find "$APP_DIR" -name '._*' -delete 2>/dev/null || true
    xattr -cr "$APP_DIR" 2>/dev/null || true
    # Рекурсивный -cr иногда оставляет com.apple.FinderInfo на отдельном вложенном
    # файле → codesign --strict падает. Дочищаем пофайлово (это и снимает детрит).
    find "$APP_DIR" -exec xattr -c {} \; 2>/dev/null || true
}

# Подпись СЕРТИФИКАТОМ в staging вне синхронизируемой папки: fileprovider не
# вернёт xattr во время codesign (главная причина срыва подписи в Documents).
# Подписываем по ИМЕНИ с явной keychain (надёжнее хэша для NOT_TRUSTED-сертификата).
sign_app_staged() {  # $1 — identity
    local stage; stage="$(mktemp -d)/$(basename "$APP_DIR")"
    ditto "$APP_DIR" "$stage" || return 1
    xattr -cr "$stage" 2>/dev/null || true
    find "$stage" -exec xattr -c {} \; 2>/dev/null || true
    codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS_FILE" --sign "$1" --keychain "$SIGNING_KC" --identifier "$BUNDLE_ID" "$stage" 2>/dev/null || return 1
    codesign --verify --strict "$stage" 2>/dev/null || return 1
    ditto "$stage" "$APP_DIR"           # вернуть подписанный бандл на место
    return 0
}

# Разблокируем служебную keychain ДО поиска идентичности (иначе ключ недоступен).
[[ -f "$SIGNING_KC" ]] && security unlock-keychain -p "lyravoice-local-signing" "$SIGNING_KC" 2>/dev/null || true
HAS_IDENTITY=0
security find-identity -p codesigning "$SIGNING_KC" 2>/dev/null | grep -q "$SIGN_IDENTITY" && HAS_IDENTITY=1

if [[ "$HAS_IDENTITY" == 1 ]]; then
    signed=0
    for _ in 1 2 3; do
        if sign_app_staged "$SIGN_IDENTITY"; then signed=1; break; fi
        sleep 0.3
    done
    # DR с «certificate leaf» = подпись сертификатом удалась (живой xattr в Documents
    # на --verify не проверяем: он косметический и встроенную подпись не ломает).
    if [[ "$signed" != 1 ]] || ! codesign -d -r- "$APP_DIR" 2>&1 | grep -q "certificate leaf"; then
        echo "ERROR: не удалось подписать сертификатом — Accessibility сломается. Проверь keychain." >&2
        exit 1
    fi
    echo "signed: stable certificate ($SIGN_IDENTITY)" >&2
else
    clean_detritus
    codesign --force --sign - --entitlements "$ENTITLEMENTS_FILE" --identifier "$BUNDLE_ID" "$APP_DIR" 2>/dev/null || true
    echo "signed: ad-hoc (нестабильно — запусти scripts/setup-signing-cert.sh, чтобы Accessibility не слетал)" >&2
fi

echo "$APP_DIR"
