# Lyra Voice Brand Assets

Светлый Liquid Glass знак Lyra Voice: мягкая glass-плитка, голубая аудиолиния и фиолетовый хвост.

- `lyravoice-source.png` — **источник истины**: логотип на прозрачном фоне (PNG с альфой).
- `LyraVoice.icns` — основная иконка приложения (генерируется).
- `LyraVoice.iconset/` — исходные PNG-renditions для `iconutil` (генерируются).
- `LyraVoiceMark.png` — компактный PNG для интерфейса: sidebar header, menu bar status item и другие маленькие бренд-точки (генерируется).
- `scripts/make-app-icon.py` — генератор iconset/icns/mark из `lyravoice-source.png`. Обрезает логотип по содержимому и вписывает в безопасную зону (~0.805 холста, канон macOS) с прозрачными полями, чтобы значок был виден целиком и «дышал». Запускать из папки `app`: `python3 scripts/make-app-icon.py` (требует Pillow), затем `iconutil -c icns Assets/Brand/LyraVoice.iconset -o Assets/Brand/LyraVoice.icns`. Чтобы поменять логотип — замени `lyravoice-source.png` и перезапусти.

Палитра:

- Glass: `#FFFFFF`, `#EEF7FF`, `#DAEBFF`
- Cyan: `#21D6EA`, `#2B99F3`
- Violet: `#7C5DFF`
- Edge glow: `#62A8FF`

Правило использования: `LyraVoice.icns` только для app bundle; `LyraVoiceMark.png` использовать в UI, где нужен небольшой узнаваемый логотип.
