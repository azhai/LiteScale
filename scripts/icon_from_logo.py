#!/usr/bin/env python3
"""Builds the LiteScale launcher icons from app-logo.png.

The source is a rounded-square logo rendered on a white sheet: the four corners
are cut away and carry a shadow, an edge highlight and a watermark. Rather than
repairing those pixels, the artwork is cropped by ~4% — enough to push the
rounded silhouette (radius ~11% of the side) outside the frame — which yields a
clean full-bleed square without touching a single pixel of the design.

    python3 scripts/icon_from_logo.py

Outputs:
    app-icon-1024.png                      master, opaque, full-bleed
    assets/icon/adaptive-background.png    plate-free gradient (Android)
    assets/icon/adaptive-foreground.png    plate + glyph, transparent (Android)
    /tmp/adaptive_preview.png              what a launcher composes
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "app-logo.png"
MASTER = ROOT / "app-icon-1024.png"
ICON_DIR = ROOT / "assets" / "icon"
SIZE = 1024

CROP = 0.08          # per side; the rounded corners have a ~22.5% radius
PAD = 0.06           # mirrored gradient added back so the mark keeps its size
PLATE_RATIO = 0.72   # launcher adds a 16% inset, leaving ~0.60 visible
PLATE_RADIUS = 0.175 # plate corner radius, relative to its side


def plate_box(a: np.ndarray) -> tuple[int, int, int, int]:
    """Bounding box of the pale scale plate (the white paper is neutral)."""
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    pale = (r > 185) & (g > 205) & (b > 195) & (g - r > 6) & (g - r < 45) & (g - b < 25)
    # The tile's outer edge has a pale rim highlight; erode it away.
    mask = Image.fromarray((pale * 255).astype(np.uint8))
    mask = mask.filter(ImageFilter.MinFilter(15)).filter(ImageFilter.MaxFilter(15))
    ys, xs = np.nonzero(np.array(mask) > 127)
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def gradient_only(a: np.ndarray) -> np.ndarray:
    """Rebuilds the background without the plate.

    Each row is interpolated between its own two edge pixels, which are pure
    gradient. The artwork's light beam is close to linear across x, so this
    reproduces the backdrop closely enough to sit under the plate layer.
    """
    h, w = a.shape[:2]
    left = a[:, 8].astype(float)
    right = a[:, w - 9].astype(float)
    t = np.linspace(0.0, 1.0, w)[None, :, None]
    rows = left[:, None, :] * (1 - t) + right[:, None, :] * t
    return rows.round().clip(0, 255).astype(np.uint8)


def plate_layer(a: np.ndarray, box: tuple[int, int, int, int]) -> Image.Image:
    """Plate + Bluetooth glyph, alpha-masked, ready to scale into the safe zone."""
    x0, y0, x1, y1 = box
    side = max(x1 - x0, y1 - y0)
    pad = 8
    img = Image.fromarray(a[y0 - pad:y1 + pad, x0 - pad:x1 + pad]).convert("RGBA")
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, img.size[0] - 1, img.size[1] - 1),
        radius=int(side * PLATE_RADIUS),
        fill=255,
    )
    img.putalpha(mask.filter(ImageFilter.GaussianBlur(1.2)))
    return img


def main() -> None:
    src = Image.open(SRC).convert("RGB")
    a = np.array(src)

    inset = int(round(src.size[0] * CROP))
    core = a[inset:-inset, inset:-inset]

    # Cropping removes the rounded silhouette; mirroring the (now pure gradient)
    # border back keeps the plate at the size the artwork intended.
    pad = int(round(SIZE * PAD))
    inner = SIZE - 2 * pad
    small = np.array(Image.fromarray(core).resize((inner, inner), Image.LANCZOS))
    master = np.pad(small, ((pad, pad), (pad, pad), (0, 0)), mode="reflect")
    assert master.shape[:2] == (SIZE, SIZE), master.shape
    Image.fromarray(master).save(MASTER)
    print(f"wrote {MASTER.relative_to(ROOT)}  (crop {inset}px, pad {pad}px)")

    ICON_DIR.mkdir(parents=True, exist_ok=True)
    bg = Image.fromarray(gradient_only(core)).resize((SIZE, SIZE), Image.LANCZOS)
    bg.save(ICON_DIR / "adaptive-background.png")
    print("wrote assets/icon/adaptive-background.png")

    box = plate_box(core)
    plate = plate_layer(core, box)
    target = int(SIZE * PLATE_RATIO)
    ratio = target / max(plate.size)
    plate = plate.resize(
        (max(1, round(plate.size[0] * ratio)), max(1, round(plate.size[1] * ratio))),
        Image.LANCZOS,
    )
    fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    fg.alpha_composite(plate, ((SIZE - plate.size[0]) // 2, (SIZE - plate.size[1]) // 2))
    fg.save(ICON_DIR / "adaptive-foreground.png")
    print("wrote assets/icon/adaptive-foreground.png")

    # Launcher simulation: background + foreground inside the 72% safe zone.
    preview = bg.convert("RGBA").copy()
    inner = fg.resize((int(SIZE * 0.72), int(SIZE * 0.72)), Image.LANCZOS)
    preview.alpha_composite(inner, (int(SIZE * 0.14), int(SIZE * 0.14)))
    preview.resize((512, 512), Image.LANCZOS).save("/tmp/adaptive_preview.png")


if __name__ == "__main__":
    main()
