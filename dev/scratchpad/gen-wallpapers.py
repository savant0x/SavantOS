#!/usr/bin/env python3
"""Generate Savant theme wallpapers, previews, and unlock screens.

Traffic-lights identity (savant-code palette.ts, dark + light):
- dark: void #050508 field, three glowing dots right-aligned
        success #39ff14 / warning #ff9500 / error #ff2d55
- light: off-white #fafafa field with the light semantic dots
         success #059669 / warning #d97706 / error #dc2626

Glow = layered Gaussian blurs of the dot cores. Deterministic output.
"""

import os

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "out")
W, H = 1920, 1080

THEMES = {
    "savant": {
        "bg": (5, 5, 8),          # #050508 void
        "dots": [(57, 255, 20), (255, 149, 0), (255, 45, 85)],
        #               #39ff14      #ff9500       #ff2d55
        "subtle": (24, 250, 249),  # #18faf9 — faint cyan horizon line
    },
    "savant-light": {
        "bg": (250, 250, 250),    # #fafafa
        "dots": [(5, 150, 105), (217, 119, 6), (220, 38, 38)],
        #               #059669     #d97706      #dc2626
        "subtle": (8, 145, 178),   # #0891b2
    },
}

DOT_R = 26
DOT_GAP = 30
RIGHT_MARGIN = 120
TOP_MARGIN = 96


def draw_dots(layer, y, dots, glow):
    total = 3 * (2 * DOT_R) + 2 * DOT_GAP
    x = W - RIGHT_MARGIN - total + DOT_R
    for color in dots:
        cx = x
        # glow: three expanding blurred discs
        for r, alpha, blur in ((DOT_R * 3, 60, 40), (DOT_R * 2, 90, 18), (int(DOT_R * 1.4), 140, 6)):
            g = Image.new("RGBA", layer.size, (0, 0, 0, 0))
            ImageDraw.Draw(g).ellipse(
                [cx - r, y - r, cx + r, y + r], fill=color + (alpha,)
            )
            g = g.filter(ImageFilter.GaussianBlur(blur))
            layer.alpha_composite(g)
        core = Image.new("RGBA", layer.size, (0, 0, 0, 0))
        ImageDraw.Draw(core).ellipse(
            [cx - DOT_R, y - DOT_R, cx + DOT_R, y + DOT_R],
            fill=color + ((255,) if glow else (230,)),
        )
        layer.alpha_composite(core)
        x += 2 * DOT_R + DOT_GAP


def horizon(layer, color):
    h = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(h)
    d.line([(0, H - 3), (W, H - 3)], fill=color + (26,), width=2)
    d.line([(0, H - 2), (W, H - 2)], fill=color + (14,), width=4)
    layer.alpha_composite(h.filter(ImageFilter.GaussianBlur(3)))


def build(name, spec):
    base = Image.new("RGBA", (W, H), spec["bg"] + (255,))
    base.alpha_composite(_horizon_layer(spec))
    dots_y = H - 140
    draw_dots(base, dots_y, spec["dots"], glow=True)
    return base


def _horizon_layer(spec):
    h = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    horizon(h, spec["subtle"])
    return h


def center_crop(img, w, h):
    left = (img.width - w) // 2
    top = (img.height - h) // 2
    return img.crop((left, top, left + w, top + h))


def main():
    for name, spec in THEMES.items():
        d = os.path.join(OUT, name, "backgrounds")
        os.makedirs(d, exist_ok=True)
        wall = build(name, spec)
        wall.convert("RGB").save(os.path.join(d, "savant.png"))
        # previews = downscaled wallpaper; unlock = center-cropped portrait-ish
        wall.resize((960, 540)).convert("RGB").save(
            os.path.join(d.replace("backgrounds", ""), "preview.png")
        )
        center_crop(wall, 1080, 1920).convert("RGB").save(
            os.path.join(d.replace("backgrounds", ""), "unlock.png")
        )
        center_crop(wall, 960, 540).convert("RGB").save(
            os.path.join(d.replace("backgrounds", ""), "preview-unlock.png")
        )
        print(f"{name}: wall+preview+unlock written")


if __name__ == "__main__":
    main()
