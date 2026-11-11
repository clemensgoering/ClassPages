"""ClassPages: generates the addon's own art set (ClassPages/Media/*.tga) and PNG copies for the layout preview
(tools/assets/png). Every texture is a white shape with an alpha channel; the addon tints it with SetVertexColor.
Sizes are powers of two (WoW requirement). Run: python tools/assets/make_assets.py
"""
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TGA = os.path.join(ROOT, "ClassPages", "Media")
PNG = os.path.join(ROOT, "tools", "assets", "png")
SS = 8  # supersampling factor


def save(name, alpha):
    """alpha: L image at final size -> white RGBA texture."""
    img = Image.merge("RGBA", (Image.new("L", alpha.size, 255),) * 3 + (alpha,))
    os.makedirs(TGA, exist_ok=True)
    os.makedirs(PNG, exist_ok=True)
    img.save(os.path.join(TGA, name + ".tga"))
    img.save(os.path.join(PNG, name + ".png"))


def canvas(w, h):
    img = Image.new("L", (w * SS, h * SS), 0)
    return img, ImageDraw.Draw(img)


def down(img, w, h):
    return img.resize((w, h), Image.LANCZOS)


def rounded(name, size, radius, ring=0, corners=(True, True, True, True)):
    """Filled rounded rectangle, or its outline when ring > 0 (ring width in px)."""
    img, d = canvas(size, size)
    box = [0, 0, size * SS - 1, size * SS - 1]
    d.rounded_rectangle(box, radius * SS, fill=255, corners=corners)
    if ring:
        inner = Image.new("L", img.size, 0)
        di = ImageDraw.Draw(inner)
        r = ring * SS
        # outline on all sides; square corners keep their straight edge
        di.rounded_rectangle([r, r, size * SS - 1 - r, size * SS - 1 - r], max(0, (radius - ring)) * SS, fill=255, corners=corners)
        img = Image.composite(Image.new("L", img.size, 0), img, inner)
    save(name, down(img, size, size))


def tab_ring(name, size, radius, ring):
    """Outline of a tab: left, top and right edge, open at the bottom."""
    img, d = canvas(size, size)
    corners = (True, True, False, False)
    d.rounded_rectangle([0, 0, size * SS - 1, size * SS - 1], radius * SS, fill=255, corners=corners)
    inner = Image.new("L", img.size, 0)
    r = ring * SS
    ImageDraw.Draw(inner).rounded_rectangle([r, r, size * SS - 1 - r, size * SS + r], max(0, radius - ring) * SS, fill=255, corners=corners)
    save(name, down(Image.composite(Image.new("L", img.size, 0), img, inner), size, size))


def shadow(name, size, pad, radius, blur):
    img = Image.new("L", (size * 2, size * 2), 0)
    ImageDraw.Draw(img).rounded_rectangle([pad * 2, pad * 2, (size - pad) * 2 - 1, (size - pad) * 2 - 1], radius * 2, fill=255)
    img = img.filter(ImageFilter.GaussianBlur(blur * 2))
    save(name, down(img, size, size))


def fade_v(name, w, h):
    img = Image.new("L", (w, h))
    for y in range(h):
        a = int(255 * (1 - y / (h - 1)) ** 1.6)
        for x in range(w):
            img.putpixel((x, y), a)
    save(name, img)


def fade_h(name, w, h):
    """Opaque in the middle, transparent at both ends (dividers, glow lines)."""
    img = Image.new("L", (w, h))
    for x in range(w):
        t = abs((x + 0.5) / w - 0.5) * 2
        a = int(255 * (1 - t) ** 1.4)
        for y in range(h):
            img.putpixel((x, y), a)
    save(name, img)


def glow(name, w, h):
    img = Image.new("L", (w * 2, h * 2), 0)
    ImageDraw.Draw(img).ellipse([w * 0.2, h * 0.7, w * 1.8, h * 1.3], fill=255)
    save(name, down(img.filter(ImageFilter.GaussianBlur(h * 0.35)), w, h))


def icon(name, draw, size=16):
    img, d = canvas(size, size)
    s = SS

    def line(points, width=1.8):
        pts = [(x * s, y * s) for x, y in points]
        d.line(pts, fill=255, width=int(width * s), joint="curve")
        r = width * s / 2
        for x, y in (pts[0], pts[-1]):
            d.ellipse([x - r, y - r, x + r, y + r], fill=255)

    draw(d, line, s)
    save(name, down(img, size, size))


def make():
    # Restrained rounding: radius 5 for windows, cards and popups, radius 3 for buttons, rows and inputs, 4 for tabs.
    # Pills only where the shape carries meaning (switch, scroll thumb). Icons and tiles stay square.
    rounded("rr5", 16, 5)
    rounded("rr5_ring", 16, 5, ring=1)
    rounded("rr3", 16, 3)
    rounded("rr3_ring", 16, 3, ring=1)
    rounded("pill", 32, 16)
    rounded("pill_ring", 32, 16, ring=1.5)
    rounded("tab", 16, 4, corners=(True, True, False, False))
    tab_ring("tab_ring", 16, 4, 1)
    rounded("mask_rr", 64, 5)       # mask that only softens the corners of list icons
    rounded("mask_logo", 64, 9)     # class logo: square with the window's corner radius (5 px at 36 px)
    shadow("shadow", 64, 16, 6, 7)
    fade_v("fade_v", 8, 32)
    fade_h("fade_h", 64, 4)
    glow("glow", 64, 16)

    icon("chevron", lambda d, line, s: line([(4, 6), (8, 10), (12, 6)]))
    icon("check", lambda d, line, s: line([(3.5, 8.5), (6.8, 11.5), (12.5, 4.8)], 2))
    icon("plus", lambda d, line, s: (line([(8, 3.5), (8, 12.5)]), line([(3.5, 8), (12.5, 8)])))
    icon("minus", lambda d, line, s: line([(3.5, 8), (12.5, 8)]))
    icon("close", lambda d, line, s: (line([(4.5, 4.5), (11.5, 11.5)]), line([(11.5, 4.5), (4.5, 11.5)])))

    def eye(d, line, s, off=False):
        d.ellipse([1.5 * s, 4.5 * s, 14.5 * s, 11.5 * s], outline=255, width=int(1.5 * s))
        d.ellipse([6 * s, 6 * s, 10 * s, 10 * s], fill=255)
        if off:
            line([(3, 13), (13, 3)], 1.6)
    icon("eye", eye)
    icon("eye_off", lambda d, line, s: eye(d, line, s, True))
    icon("grip", lambda d, line, s: (line([(13, 5), (5, 13)], 1.4), line([(13, 9), (9, 13)], 1.4)))


if __name__ == "__main__":
    make()
    print("assets:", len(os.listdir(TGA)), "tga in", TGA)
