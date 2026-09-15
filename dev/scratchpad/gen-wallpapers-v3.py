#!/usr/bin/env python3
"""Wallpaper v3 — off-center light source, diagonal dot constellation,
vignette, fixed-seed film grain. Deterministic; staged in scratchpad
until the in-flight dual-build gate closes, then promoted into
guest-image/skeletons (FID-2026-0915-006 D2).

Same palette + output names as v2 (layout js + assembly probes untouched);
sizes 2560x1440 primary + 1920x1080 (the probe-gated PNG keeps its name).
"""

import os

from PIL import Image, ImageDraw, ImageFilter

STAGE = os.path.join(os.path.dirname(__file__), "wall-v3")
SIZES = [(2560, 1440), (1920, 1080)]

THEMES = {
    "savant": {
        "bg": (5, 5, 8),
        "glow": (24, 250, 249),     # cyan light source
        "dots": [(57, 255, 20), (255, 149, 0), (255, 45, 85)],
    },
    "savant-light": {
        "bg": (250, 250, 250),
        "glow": (8, 145, 178),
        "dots": [(5, 150, 105), (217, 119, 6), (220, 38, 38)],
    },
}

# Diagonal constellation (fractions of W/H), largest dot first — composition
# anchored to the light source, not a centered row.
DOTS = [  # (fx, fy, radius_frac)
    (0.700, 0.615, 0.042),
    (0.575, 0.500, 0.030),
    (0.815, 0.745, 0.021),
]
GRAIN_SEED = 20260915  # fixed: determinism gate reads these bytes


def light_source(img, spec, w, h):
    """Off-center glow: ambient bloom upper-right (tight, subtle — it must
    read as light in haze, not a fog disc) + horizon."""
    lx, ly = int(w * 0.78), int(h * 0.30)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    # 12 rings with geometric alpha falloff: no visible ring boundary
    for i in range(12):
        t = i / 11.0
        r_frac = 0.055 + (0.46 - 0.055) * t
        alpha = int(90 * (1 - t) ** 1.7) + 18
        r = int(min(w, h) * r_frac)
        d.ellipse([lx - r, ly - r, lx + r, ly + r], fill=spec["glow"] + (alpha,))
    layer = layer.filter(ImageFilter.GaussianBlur(int(min(w, h) * 0.06)))
    img.alpha_composite(layer)
    # horizon: faint line low in frame
    hl = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hl)
    y = int(h * 0.86)
    hd.line([(0, y), (w, y)], fill=spec["glow"] + (34,), width=2)
    img.alpha_composite(hl.filter(ImageFilter.GaussianBlur(4)))


def constellation(img, spec, w, h):
    for i, (fx, fy, rf) in enumerate(DOTS):
        color = spec["dots"][i]
        cx, cy, r = int(w * fx), int(h * fy), int(min(w, h) * rf)
        for mr, alpha, blur in ((3.2, 60, r), (2.1, 95, r // 2), (1.5, 150, r // 4)):
            g = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            rr = int(r * mr)
            ImageDraw.Draw(g).ellipse([cx - rr, cy - rr, cx + rr, cy + rr],
                                      fill=color + (alpha,))
            img.alpha_composite(g.filter(ImageFilter.GaussianBlur(blur)))
        core = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        ImageDraw.Draw(core).ellipse([cx - r, cy - r, cx + r, cy + r],
                                     fill=color + (255,))
        img.alpha_composite(core)


def vignette(img, spec, w, h):
    """Dark corners (light theme: warm darken, not gray)."""
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    strength = 120 if spec["bg"][0] < 128 else 60
    d.ellipse([-int(w * 0.35), -int(h * 0.45), int(w * 1.35), int(h * 1.45)], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(int(min(w, h) * 0.18)))
    dark = Image.new("RGBA", (w, h), (0, 0, 0, strength))
    if spec["bg"][0] >= 128:
        dark = Image.new("RGBA", (w, h), (40, 36, 30, strength))
    inv = mask.point(lambda p: 255 - p)
    img.paste(Image.alpha_composite(img.crop((0, 0, w, h)).convert("RGBA"),
              Image.composite(dark, Image.new("RGBA", (w, h), (0, 0, 0, 0)), inv)),
              (0, 0))


def grain(img, w, h):
    import random
    rnd = random.Random(GRAIN_SEED)
    g = Image.new("L", (w // 2, h // 2))
    g.putdata([rnd.randint(0, 255) for _ in range((w // 2) * (h // 2))])
    g = g.resize((w, h))
    noise = Image.merge("RGBA", (g, g, g, Image.new("L", (w, h), 10)))
    img.alpha_composite(noise)


def build(spec_name, w, h):
    spec = THEMES[spec_name]
    img = Image.new("RGBA", (w, h), spec["bg"] + (255,))
    light_source(img, spec, w, h)
    constellation(img, spec, w, h)
    vignette(img, spec, w, h)
    grain(img, w, h)
    return img.convert("RGB")


def main():
    for name in THEMES:
        d = os.path.join(STAGE, name, "contents", "images")
        os.makedirs(d, exist_ok=True)
        for w, h in SIZES:
            suffix = "" if (w, h) == (1920, 1080) else f"-{h}p"
            build(name, w, h).save(os.path.join(d, f"savant-traffic-lights{suffix}.png"))
        print(f"{name}: {', '.join(str(s) for s in SIZES)} written to stage")


if __name__ == "__main__":
    main()
