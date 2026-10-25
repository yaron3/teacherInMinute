"""Instant Teacher's Android launcher icons and Play Store icon, cut from the
iOS icon art in Darwin/Assets.xcassets/AppIconStudent.appiconset.

The art is one flat bitmap (stopwatch on an orange field), so it cannot be
split into real layers. The adaptive foreground is the whole picture scaled to
68dp in the 108dp canvas, which keeps everything, the speed streaks' tips
included, inside the 72dp mask circle; its orange border is smeared outward
and blurred to fill the rest of the canvas, so no launcher mask shows a seam.
The monochrome layer keeps whatever is not orange field: the stopwatch and the
streaks, lighter parts stronger so the dial and hands still read when themed.

    python3 export_android.py
"""
import colorsys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[3]
ART = ROOT / "teacher-minute/Darwin/Assets.xcassets/AppIconStudent.appiconset/Stopwatch_app_icon_20261022173837.jpg"
RES = ROOT / "teacher-minute/Android/app/src/student/res"
HERE = Path(__file__).resolve().parent

DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
ART_DP = 68            # the art's side inside the 108dp adaptive canvas
CANVAS_DP = 108


def foreground(art):
    """Art centred at ART_DP in a CANVAS_DP square, at 1024 px per ART_DP."""
    side = round(1024 * CANVAS_DP / ART_DP)
    pad = (side - 1024) // 2
    a = np.asarray(art)
    padded = np.pad(a, ((pad, side - 1024 - pad), (pad, side - 1024 - pad), (0, 0)), mode="edge")
    smeared = Image.fromarray(padded).filter(ImageFilter.GaussianBlur(40))
    # Original inside, the blurred smear outside, a short ramp between them.
    mask = Image.new("L", (side, side), 0)
    mask.paste(255, (pad + 12, pad + 12, pad + 1024 - 12, pad + 1024 - 12))
    mask = mask.filter(ImageFilter.GaussianBlur(6))
    smeared.paste(Image.fromarray(padded), (0, 0), mask)
    return smeared


def monochrome_alpha(art):
    """0 on the orange field and its shadows, up to 255 on the stopwatch."""
    a = np.asarray(art).astype(np.float32) / 255
    hsv = np.vectorize(colorsys.rgb_to_hsv)(a[..., 0], a[..., 1], a[..., 2])
    hue, sat, val = (np.asarray(c) for c in hsv)
    hue_off = np.abs(hue * 360 - 28)
    orange = np.clip((sat - 0.45) / 0.2, 0, 1) * np.clip(1 - (hue_off - 14) / 10, 0, 1)
    shape = 1 - orange
    lum = 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]
    alpha = shape * (0.3 + 0.7 * lum)
    return Image.fromarray(np.uint8(np.clip(alpha, 0, 1) * 255))


def main():
    art = Image.open(ART).convert("RGB")
    assert art.size == (1024, 1024), art.size

    fg = foreground(art).convert("RGBA")
    mono_alpha = monochrome_alpha(art)
    side = fg.size[0]
    pad = (side - 1024) // 2
    mono = Image.new("RGBA", (side, side), (255, 255, 255, 0))
    full_alpha = Image.new("L", (side, side), 0)
    full_alpha.paste(mono_alpha, (pad, pad))
    mono.putalpha(full_alpha)

    for dens, k in DENSITIES.items():
        px = round(CANVAS_DP * k)
        for out in (RES / f"mipmap-{dens}", HERE / "android" / f"mipmap-{dens}"):
            out.mkdir(parents=True, exist_ok=True)
            fg.resize((px, px), Image.LANCZOS).save(out / "ic_launcher_foreground.png", optimize=True)
            mono.resize((px, px), Image.LANCZOS).save(out / "ic_launcher_monochrome.png", optimize=True)
            # Pre-Oreo launchers draw the legacy bitmap as is, full bleed.
            art.resize((round(48 * k),) * 2, Image.LANCZOS).save(out / "ic_launcher.png", optimize=True)

    art.resize((512, 512), Image.LANCZOS).save(HERE / "play-store-512.png", optimize=True)


if __name__ == "__main__":
    main()
