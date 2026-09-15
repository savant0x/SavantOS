#!/usr/bin/env python3
"""Generate the SavantOS wallpaper: industrial traffic-lights housing, top right.

v4 — operator direction from the reference mock:
- Three-lens assembly moved to the TOP-RIGHT corner
- Lenses read as physical: recessed bezel rings, radial lens gradients with a
  hot but red-shifted core (the v3 pure #ff2d55 core read pink), specular arc
- Glow softened ~40% (v3 halo read harsh)
- Dark industrial housing panel behind the lenses with corner bolts
- SavantOS wordmark stays lower-left with the cyan accent bar

Deterministic: fixed seed RNG, no timestamps.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 3840, 2160

# Housing geometry (top-right): panel + three lenses, traffic-light order.
PANEL_W, PANEL_H = 1560, 560
PANEL_X = W - PANEL_W - 140
PANEL_Y = 120
LENS_R = 150
LENS_CY = PANEL_Y + PANEL_H // 2
LENS_SPACING = 470
X_GREEN = PANEL_X + 250
X_AMBER = X_GREEN + LENS_SPACING
X_RED = X_AMBER + LENS_SPACING

# Savant palette (savant-code palette.ts). Red is deepened toward pure red so
# the hot core does not read pink on the void field.
GREEN = np.array([57, 255, 20], dtype=float)
AMBER = np.array([255, 176, 0], dtype=float)
RED = np.array([248, 24, 40], dtype=float)

VOID_CENTER = np.array([5, 5, 8], dtype=float)
VOID_EDGE = np.array([2, 2, 4], dtype=float)

rng = np.random.default_rng(0x5AA7)

WORDMARK = "SavantOS"
WORDMARK_SIZE = 300
WORDMARK_XY = (int(W * 0.065), int(H * 0.665))
FOREGROUND = (232, 232, 239)
CYAN = (24, 250, 249)

_FONT_CANDIDATES = (
    "C:/Windows/Fonts/segoeuib.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
)


def _load_font() -> ImageFont.FreeTypeFont:
    for cand in _FONT_CANDIDATES:
        if Path(cand).is_file():
            return ImageFont.truetype(cand, WORDMARK_SIZE)
    raise SystemExit(
        "gen-wallpaper: no wordmark font found (looked for "
        + ", ".join(_FONT_CANDIDATES) + ")"
    )


def radial_mask(xx, yy, cx, cy, r):
    return np.exp(-(((xx - cx) ** 2 + (yy - cy) ** 2) / (2.0 * r * r)))


def draw_housing(img: Image.Image) -> Image.Image:
    """Industrial lens panel: dark housing, bezels, lenses, bolts — vector
    layer composited over the void field."""
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)

    # --- housing panel with a soft edge highlight
    d.rounded_rectangle(
        (PANEL_X, PANEL_Y, PANEL_X + PANEL_W, PANEL_Y + PANEL_H),
        radius=36,
        fill=(10, 10, 15, 235),
        outline=(38, 38, 50, 255),
        width=3,
    )
    # corner bolts
    for bx in (PANEL_X + 60, PANEL_X + PANEL_W - 60):
        for by in (PANEL_Y + 60, PANEL_Y + PANEL_H - 60):
            d.ellipse((bx - 14, by - 14, bx + 14, by + 14), fill=(28, 28, 36, 255))
            d.ellipse((bx - 8, by - 8, bx + 8, by + 8), fill=(16, 16, 22, 255))
            d.line((bx - 5, by, bx + 5, by), fill=(44, 44, 56, 255), width=3)

    # --- three lens assemblies
    for cx, color in ((X_GREEN, GREEN), (X_AMBER, AMBER), (X_RED, RED)):
        # recessed bezel: outer dark ring + metallic rim + inner shadow
        d.ellipse(
            (cx - LENS_R - 42, LENS_CY - LENS_R - 42,
             cx + LENS_R + 42, LENS_CY + LENS_R + 42),
            fill=(20, 20, 27, 255),
            outline=(52, 52, 66, 255),
            width=4,
        )
        d.ellipse(
            (cx - LENS_R - 20, LENS_CY - LENS_R - 20,
             cx + LENS_R + 20, LENS_CY + LENS_R + 20),
            outline=(70, 70, 86, 255),
            width=5,
        )
        # lens well (dark pit the glowing lens sits in)
        d.ellipse(
            (cx - LENS_R, LENS_CY - LENS_R, cx + LENS_R, LENS_CY + LENS_R),
            fill=(6, 6, 9, 255),
        )

    img_rgba = img.convert("RGBA")

    # --- lens glow (softened: fewer/smaller halo layers, lower gains)
    yy, xx = np.mgrid[0:H, 0:W].astype(float)
    glow = np.zeros((H, W, 3), dtype=float)
    for cx, color in ((X_GREEN, GREEN), (X_AMBER, AMBER), (X_RED, RED)):
        for r, k in ((LENS_R * 3.4, 0.16), (LENS_R * 1.9, 0.30)):
            m = radial_mask(xx, yy, cx, LENS_CY, r) ** 2.4
            glow += color[None, None, :] * (k * m)[:, :, None]
    glow_img = Image.fromarray(np.clip(glow, 0, 255).astype(np.uint8), "RGB")
    img_rgba = Image.alpha_composite(img_rgba, glow_img.convert("RGBA"))

    # --- lens cores: radial gradient (hot center -> deep edge) + specular arc
    core = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dc = ImageDraw.Draw(core)
    for cx, color in ((X_GREEN, GREEN), (X_AMBER, AMBER), (X_RED, RED)):
        steps = 26
        for i in range(steps, 0, -1):
            t = i / steps  # 1 = rim, ->0 = center
            r = LENS_R * t
            # hot pale center, hue deepens to the rim
            c = color * (1 - 0.30 * (1 - t)) + np.array([110, 110, 110]) * (1 - t) ** 2.5
            dc.ellipse(
                (cx - r, LENS_CY - r, cx + r, LENS_CY + r),
                fill=(int(min(c[0], 255)), int(min(c[1], 255)), int(min(c[2], 255)), 255),
            )
        # specular highlight (upper-left arc)
        dc.arc(
            (cx - LENS_R * 0.72, LENS_CY - LENS_R * 0.72,
             cx + LENS_R * 0.72, LENS_CY + LENS_R * 0.72),
            start=200, end=290,
            fill=(255, 255, 255, 150),
            width=10,
        )
    core = core.filter(ImageFilter.GaussianBlur(2))
    img_rgba = Image.alpha_composite(img_rgba, core)

    # --- wordmark with halo + cyan accent bar (unchanged since v3)
    font = _load_font()
    wm = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(wm)
    bbox = d.textbbox(WORDMARK_XY, WORDMARK, font=font)
    halo = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(halo).text(WORDMARK_XY, WORDMARK, font=font, fill=(0, 0, 0, 200))
    halo = halo.filter(ImageFilter.GaussianBlur(18))
    wm = Image.alpha_composite(wm, halo)
    d = ImageDraw.Draw(wm)
    d.text(WORDMARK_XY, WORDMARK, font=font, fill=FOREGROUND + (240,))
    bar_y = bbox[3] + 34
    d.rectangle((bbox[0], bar_y, bbox[0] + (bbox[2] - bbox[0]), bar_y + 7), fill=CYAN + (210,))

    return Image.alpha_composite(img_rgba, wm).convert("RGB")


def main() -> None:
    yy, xx = np.mgrid[0:H, 0:W].astype(float)

    # --- void field: radial falloff + faint horizon band (kept from v3)
    field = radial_mask(xx, yy, W * 0.42, H * 0.48, W * 0.75)
    img = VOID_EDGE[None, None, :] + (VOID_CENTER - VOID_EDGE)[None, None, :] * field[:, :, None]
    horizon = np.exp(-((yy - H * 0.78) ** 2) / (2 * (H * 0.16) ** 2))
    img += (np.array([6, 6, 10])[None, None, :] * horizon[:, :, None])

    out = np.clip(img, 0, 255).astype(np.uint8)
    out_img = Image.fromarray(out, "RGB")

    # --- industrial traffic-lights housing (v4)
    out_img = draw_housing(out_img)

    # --- film grain (deterministic; single texture over everything)
    g = np.asarray(out_img).astype(float)
    g += rng.normal(0, 1.35, size=(H, W, 1))
    out_img = Image.fromarray(np.clip(g, 0, 255).astype(np.uint8), "RGB")

    dest = (
        Path(__file__).resolve().parent.parent
        / "skeletons" / "usr" / "share" / "wallpapers" / "savant"
        / "contents" / "images"
    )
    dest.mkdir(parents=True, exist_ok=True)
    dest_f = dest / "savant-traffic-lights-4k.png"
    out_img.save(dest_f, optimize=True)
    # canonical name too (the L&F defaults + appletsrc reference it)
    out_img.save(dest / "savant-traffic-lights.png", optimize=True)
    print(f"wrote {dest_f} ({dest_f.stat().st_size // 1024} KiB)")


if __name__ == "__main__":
    main()
