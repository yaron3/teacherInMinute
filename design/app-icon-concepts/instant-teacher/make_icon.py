"""Instant Teacher app icon (concept E): the shared stopwatch with its
colours swapped (orange field, blue accents) and a lightning bolt in place of
the clock hands.

Geometry is lifted from the shared 1024 icon so the two apps stay siblings.
Everything is drawn at 4x and downsampled for clean edges.

    python3 make_icon.py <out-dir>

Superseded: the shipped icon is now the art in
teacher-minute/Darwin/Assets.xcassets/AppIconStudent.appiconset, and
export_android.py cuts the Android and Play Store icons from it. Running this
into this folder would bring the old design back.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

S = 4                  # supersample factor
N = 1024 * S
CX, CY = 623, 522      # stopwatch centre (1024 space)

_BOLT = [(604, 330), (506, 556), (612, 556), (566, 748), (754, 486), (646, 486), (700, 330)]
# shrunk to clear the 12 o'clock tick, and centred on the dial
BOLT = [(CX + (x - 630) * 0.88, CY + (y - 539) * 0.88) for x, y in _BOLT]


def s(v):
    return round(v * S)


def gradient(start, end):
    """Diagonal top-left -> bottom-right gradient, like the shared icon."""
    small = Image.new("RGB", (256, 256))
    px = small.load()
    for y in range(256):
        for x in range(256):
            t = (x + y) / 510
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(start, end))
    return small.resize((N, N), Image.BILINEAR)


def pill(d, x0, y0, x1, y1, fill):
    d.rounded_rectangle([s(x0), s(y0), s(x1), s(y1)], radius=s((y1 - y0) / 2), fill=fill)


def bolt(d, fill, grow=0):
    """The lightning bolt; `grow` > 0 draws it fattened by that many px
    (1024 space), used to knock a gap around it."""
    pts = [(s(x), s(y)) for x, y in BOLT]
    d.polygon(pts, fill=fill)
    if grow:
        d.line(pts + [pts[0]], fill=fill, width=s(grow * 2), joint="curve")


def artwork(p, mono=False):
    """Draws the mark (no background) onto a transparent RGBA canvas.
    p: palette dict. mono=True gives a single-colour silhouette with the
    face knocked out, for Android themed icons."""
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ink = p["accent"]

    # crown + stem
    d.rounded_rectangle([s(554), s(113), s(694), s(186)], radius=s(30), fill=ink)
    d.rectangle([s(594), s(180), s(654), s(222)], fill=ink)

    # speed lines
    pill(d, 40, 355, 270, 408, ink)
    pill(d, 86, 469, 282, 522, ink)
    pill(d, 40, 583, 280, 636, ink)

    # case + face
    R, r = 308, 262
    d.ellipse([s(CX - R), s(CY - R), s(CX + R), s(CY + R)], fill=p["rim"])
    clear = (0, 0, 0, 0)
    d.ellipse([s(CX - r), s(CY - r), s(CX + r), s(CY + r)], fill=clear if mono else p["face"])

    # time wedge: 12 o'clock clockwise to ~4 o'clock
    w = 238
    d.pieslice([s(CX - w), s(CY - w), s(CX + w), s(CY + w)], start=-90, end=30, fill=p["wedge"])

    # ticks
    for x0, y0, x1, y1 in [(613, 266, 635, 312), (613, 732, 635, 778), (368, 511, 414, 533), (834, 511, 880, 533)]:
        d.rounded_rectangle([s(x0), s(y0), s(x1), s(y1)], radius=s(11), fill=p["ink"])

    # bolt, with a face-coloured halo so it separates from the wedge
    bolt(d, clear if mono else p["face"], grow=14)
    bolt(d, p["ink"])
    return img


def flat(img):
    return img.resize((1024, 1024), Image.LANCZOS)


PALETTES = {
    "light": dict(bg=((250, 165, 30), (236, 102, 10)), accent=(27, 79, 191, 255), rim=(255, 255, 255, 255),
                  face=(255, 246, 234, 255), wedge=(27, 79, 191, 255), ink=(14, 42, 107, 255)),
    "dark": dict(bg=((178, 84, 8), (92, 36, 4)), accent=(84, 132, 232, 255), rim=(236, 238, 244, 255),
                 face=(222, 226, 236, 255), wedge=(40, 92, 204, 255), ink=(14, 34, 84, 255)),
    # iOS tints this one itself, so it is greyscale on near-black
    "tinted": dict(bg=((34, 34, 34), (18, 18, 18)), accent=(150, 150, 150, 255), rim=(235, 235, 235, 255),
                   face=(205, 205, 205, 255), wedge=(110, 110, 110, 255), ink=(30, 30, 30, 255)),
}


def ios_icon(name):
    p = PALETTES[name]
    bg = gradient(*p["bg"]).convert("RGBA")
    bg.alpha_composite(artwork(p))
    return flat(bg).convert("RGB")


def android_layers(out):
    """Adaptive-icon foreground + monochrome, recomposed into the same box
    the shared icon's layers use (inside the 72dp mask circle), plus the
    legacy square ic_launcher.png."""
    densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    src_box = (40, 113, 931, 830)          # mark bounds in 1024 space
    dst_box = (89, 102, 339, 303)          # same bounds in the 432px layer

    p = PALETTES["light"]
    fg = artwork(p)
    mono_p = {k: (0, 0, 0, 255) for k in ("accent", "rim", "face", "wedge", "ink")}
    mono = artwork(mono_p, mono=True)
    # the bolt sits inside a solid wedge: punch a gap around it for the silhouette
    gap = Image.new("L", (N, N), 0)
    bolt(ImageDraw.Draw(gap), 255, grow=14)
    inner = Image.new("L", (N, N), 0)
    bolt(ImageDraw.Draw(inner), 255)
    a = mono.split()[3]
    a = Image.composite(Image.new("L", (N, N), 0), a, gap)
    a = Image.composite(Image.new("L", (N, N), 255), a, inner)
    mono.putalpha(a)

    legacy = ios_icon("light")
    for dens, k in densities.items():
        d = out / "android" / f"mipmap-{dens}"
        d.mkdir(parents=True, exist_ok=True)
        size = round(108 * k)
        scale = size / 432
        for layer, fname in ((fg, "ic_launcher_foreground.png"), (mono, "ic_launcher_monochrome.png")):
            crop = layer.crop(tuple(s(v) for v in src_box))
            w = round((dst_box[2] - dst_box[0]) * scale)
            h = round((dst_box[3] - dst_box[1]) * scale)
            canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
            canvas.alpha_composite(crop.resize((w, h), Image.LANCZOS),
                                   (round(dst_box[0] * scale), round(dst_box[1] * scale)))
            canvas.save(d / fname)
        legacy.resize((round(48 * k),) * 2, Image.LANCZOS).save(d / "ic_launcher.png")


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    ios_icon("light").save(out / "AppIcon1024x1024.png")
    ios_icon("dark").save(out / "AppIcon1024x1024-dark.png")
    ios_icon("tinted").save(out / "AppIcon1024x1024-tinted.png")
    android_layers(out)
    # Play Console store-listing icon: a full square, since Play rounds the
    # corners and adds the shadow itself.
    ios_icon("light").resize((512, 512), Image.LANCZOS).save(out / "play-store-512.png", optimize=True)


if __name__ == "__main__":
    main()
