"""Export ClassPages branding from the selected Imagegen PNGs using Pillow."""

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


ASSETS = Path(__file__).resolve().parent
BRAND = ASSETS / "brand"
MEDIA = ASSETS.parents[1] / "ClassPages" / "Media"
LANCZOS = Image.Resampling.LANCZOS


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--icon-source", type=Path, default=BRAND / "icon_1024.png")
    parser.add_argument("--banner-source", type=Path, default=BRAND / "banner_1920.png")
    parser.add_argument("--font", type=Path, help="Optional libre serif font for the title")
    args = parser.parse_args()

    with Image.open(args.icon_source) as source:
        if source.width != source.height:
            parser.error("the icon source must be square")
        icon = source.convert("RGBA").resize((1024, 1024), LANCZOS)
    with Image.open(args.banner_source) as source:
        banner = ImageOps.fit(source.convert("RGB"), (1920, 1080), LANCZOS)

    BRAND.mkdir(parents=True, exist_ok=True)
    MEDIA.mkdir(parents=True, exist_ok=True)
    icon.save(BRAND / "icon_1024.png")
    icon.resize((400, 400), LANCZOS).save(BRAND / "icon_400.png")
    icon.resize((32, 32), LANCZOS).save(BRAND / "icon_preview_32.png")
    icon.resize((64, 64), LANCZOS).save(MEDIA / "icon.tga", compression=None)
    banner.save(BRAND / "banner_1920.png")

    if args.font:
        draw = ImageDraw.Draw(banner)
        font = ImageFont.truetype(str(args.font), 91)
        draw.text((104, 540), "ClassPages", font=font, fill="#FFD173", anchor="lm")
        banner.save(BRAND / "banner_1920_text.png")


if __name__ == "__main__":
    main()
