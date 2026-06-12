#!/usr/bin/env bash
# Создаёт СТАБИЛЬНЫЙ самоподписанный сертификат для подписи LyraVoice.
#
# Зачем: ad-hoc-подпись привязывает разрешение «Универсальный доступ» (Accessibility)
# к CDHash бинаря, а он меняется при каждой пересборке → доступ слетает после каждого
# билда (поэтому авто-вставка «то работает, то нет»). Подпись стабильным сертификатом
# привязывает designated requirement к сертификату — выдаёшь Accessibility один раз,
# и он переживает все будущие пересборки.
#
# Запусти ОДИН раз:  bash scripts/setup-signing-cert.sh
# Идемпотентно. Пароль keychain служебный (не твой системный) — всё неинтерактивно.
set -euo pipefail

IDENTITY="LyraVoice Dev"
KC_NAME="lyravoice-signing"
KC_PATH="$HOME/Library/Keychains/$KC_NAME.keychain-db"
KC_PASS="lyravoice-local-signing"
LOGIN_KC="$HOME/Library/Keychains/login.keychain-db"

# 1. Идентичность уже есть в нашей keychain? Тогда только убедимся, что keychain
#    в search-list, и выходим.
if [[ -f "$KC_PATH" ]] && security find-identity -p codesigning "$KC_PATH" 2>/dev/null | grep -q "$IDENTITY"; then
    echo "✓ Идентичность «${IDENTITY}» уже существует."
else
    # 2. Создаём (или открываем) служебную keychain.
    if [[ ! -f "$KC_PATH" ]]; then
        security create-keychain -p "$KC_PASS" "$KC_NAME.keychain"
        echo "✓ Создана keychain $KC_PATH"
    fi
    security set-keychain-settings "$KC_PATH"            # без авто-лока по таймауту
    security unlock-keychain -p "$KC_PASS" "$KC_PATH"

    # 3. Генерируем самоподписанный сертификат code signing.
    TMP="$(mktemp -d)"
    cat > "$TMP/cert.conf" <<'CONF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = LyraVoice Dev
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONF
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
        -config "$TMP/cert.conf" -extensions v3 >/dev/null 2>&1

    # p12 в LEGACY-формате: OpenSSL 3 по умолчанию пакует MAC так, что Apple
    # `security import` его не принимает («MAC verification failed»).
    openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
        -out "$TMP/cert.p12" -passout pass:"$KC_PASS" -name "$IDENTITY" \
        -legacy -macalg sha1 >/dev/null 2>&1

    # 4. Импорт + разрешение codesign использовать ключ без GUI-промптов.
    security import "$TMP/cert.p12" -k "$KC_PATH" -P "$KC_PASS" -T /usr/bin/codesign -A
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KC_PATH" >/dev/null 2>&1
fi

# 5. Гарантируем, что keychain в пользовательском search-list (без неё codesign
#    не найдёт идентичность). Сохраняем уже существующие keychain.
EXISTING="$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//')"
if ! echo "$EXISTING" | grep -q "$KC_PATH"; then
    # shellcheck disable=SC2086
    security list-keychains -d user -s "$KC_PATH" $EXISTING
    echo "✓ Keychain добавлена в search-list."
fi

# 6. Самоподписанный сертификат имеет статус NOT_TRUSTED — это НЕ мешает codesign
#    подписывать им (важно лишь наличие приватного ключа). Поэтому проверяем
#    наличие идентичности, а не её «валидность» по trust.
echo "─────────────────────────────────────────────"
if security find-identity -p codesigning "$KC_PATH" | grep -q "$IDENTITY"; then
    echo "✓ Готово. Подпись настроена:"
    security find-identity -p codesigning "$KC_PATH" | grep "$IDENTITY"
    echo ""
    echo "Дальше: ./scripts/build-dev-app.sh  (подпишет этим сертификатом),"
    echo "затем выдай LyraVoice доступ в «Универсальный доступ» ОДИН раз —"
    echo "после стабильной подписи он больше слетать не будет."
else
    echo "⚠ Идентичность не найдена — что-то пошло не так." >&2
    exit 1
fi
