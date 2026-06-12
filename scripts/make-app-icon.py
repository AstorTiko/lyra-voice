#!/usr/bin/env python3
"""Собирает macOS app-иконку из исходного логотипа.

Исходный logo — это уже готовая «стеклянная плитка»-squircle с волной внутри,
центрированная, с мягкой тенью по краям. Сам Big Sur-канон с полями ~0.805 здесь
НЕ нужен: он ужимал плитку до ~74% холста, и значок выглядел маленьким и будто
«обрезанным» в пустоте. Запрос пользователя — плитка должна занимать почти весь
холст. Поэтому мы:
  1. обрезаем исходник по телу плитки (порог альфы отсекает размытую ambient-тень);
  2. приводим к квадрату по центру;
  3. вписываем почти во весь холст (BODY_RATIO ≈ 0.97), оставляя лишь тонкий
     зазор, чтобы скруглённые углы squircle не упирались в край.
"""
import os
import sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
BRAND = os.path.join(HERE, "..", "Assets", "Brand")
SOURCE = os.path.join(BRAND, "lyravoice-source.png")
ICONSET = os.path.join(BRAND, "LyraVoice.iconset")
MARK = os.path.join(BRAND, "LyraVoiceMark.png")

# Плитка занимает почти весь холст; тонкий зазор бережёт углы squircle от среза.
BODY_RATIO = 0.97
# Порог альфы для отделения тела плитки от размытой ambient-тени (край резкий).
ALPHA_THRESHOLD = 40
MASTER = 1024

ICONSET_SIZES = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]


def content_square(img: Image.Image) -> Image.Image:
    """Обрезает по телу плитки (порог альфы) и кладёт на квадратный прозрачный холст.

    `getbbox()` по alpha>0 захватил бы размытую тень, разлитую по всему холсту, и
    плитка снова уехала бы в центр с большими полями. Поэтому границы берём по
    маске alpha>=ALPHA_THRESHOLD — это резкий край стеклянной плитки без тени.
    """
    img = img.convert("RGBA")
    alpha = img.split()[3]
    mask = alpha.point(lambda v: 255 if v >= ALPHA_THRESHOLD else 0)
    bbox = mask.getbbox() or img.getbbox()
    if bbox:
        img = img.crop(bbox)
    w, h = img.size
    side = max(w, h)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - w) // 2, (side - h) // 2), img)
    return canvas


def build_master(content: Image.Image) -> Image.Image:
    """Вписывает содержимое в MASTER-холст с полями безопасной зоны."""
    body = int(MASTER * BODY_RATIO)
    scaled = content.resize((body, body), Image.LANCZOS)
    canvas = Image.new("RGBA", (MASTER, MASTER), (0, 0, 0, 0))
    offset = (MASTER - body) // 2
    canvas.paste(scaled, (offset, offset), scaled)
    return canvas


def main() -> int:
    if not os.path.exists(SOURCE):
        print(f"нет исходника: {SOURCE}", file=sys.stderr)
        return 1

    content = content_square(Image.open(SOURCE))
    master = build_master(content)

    os.makedirs(ICONSET, exist_ok=True)
    for name, size in ICONSET_SIZES:
        master.resize((size, size), Image.LANCZOS).save(os.path.join(ICONSET, name))

    # Внутри-приложенческий логотип (онбординг, меню-бар, шапка) — логотип целиком
    # без полей: он показывается мелко в NSImageView, поля там не нужны.
    content.resize((512, 512), Image.LANCZOS).save(MARK)

    print("iconset + mark обновлены из", os.path.basename(SOURCE))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
