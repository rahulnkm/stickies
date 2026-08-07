#!/usr/bin/env python3
"""Generate the Stickies app icon.

One cream note on an ink squircle, in the app's own palette (NoteTheme).
Art is tuned per output size: the text lines and the yellow hide-dot are
scaled up or dropped entirely at 32px and 16px, where full-detail art turns
to mush.

    python3 tools/make_icon.py            # write the .appiconset PNGs
    python3 tools/make_icon.py --preview  # also write a contact sheet to /tmp

Requires: pillow, numpy.
"""
from __future__ import annotations

import argparse
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONSET = os.path.join(ROOT, "Stickies", "Assets.xcassets", "AppIcon.appiconset")

# Palette lifted from NoteTheme in Stickies/Windows/NoteView.swift.
INK      = (0x2C, 0x2A, 0x33)   # NoteTheme.bg
INK_HI   = (0x3C, 0x39, 0x47)
INK_LO   = (0x22, 0x20, 0x29)
CREAM    = (0xE8, 0xE3, 0xD8)   # NoteTheme.text
CREAM_HI = (0xF6, 0xF2, 0xEA)
CREAM_LO = (0xDA, 0xD3, 0xC4)
YELLOW   = (0xFE, 0xBC, 0x2E)   # NoteTheme.hideYellow

WORK = 2048  # render resolution before downsampling to the target size

# Required macOS icon sizes -> output filename.
SIZES = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]


# --- primitives --------------------------------------------------------------
def rrect_mask(w: float, h: float, r: float, n: float = 5.0) -> np.ndarray:
    """Alpha mask for a rounded rect with Apple-style continuous ("squircle")
    corners. n=5 superellipse is a close visual match for the real curve."""
    w, h, r = int(round(w)), int(round(h)), float(r)
    y, x = np.mgrid[0:h, 0:w].astype(np.float64)
    x += 0.5
    y += 0.5
    dx = np.maximum(np.maximum(r - x, x - (w - r)), 0.0)
    dy = np.maximum(np.maximum(r - y, y - (h - r)), 0.0)
    return ((dx / r) ** n + (dy / r) ** n <= 1.0).astype(np.float64)


def vgrad(w: float, h: float, top, bottom) -> np.ndarray:
    w, h = int(round(w)), int(round(h))
    t = np.linspace(0.0, 1.0, h)[:, None]
    out = np.zeros((h, w, 3), np.float64)
    for i in range(3):
        out[:, :, i] = top[i] * (1 - t) + bottom[i] * t
    return out.astype(np.uint8)


def rgba(rgb: np.ndarray, alpha: np.ndarray) -> Image.Image:
    a = (np.clip(alpha, 0, 1) * 255).astype(np.uint8)
    return Image.fromarray(np.dstack([rgb, a]), "RGBA")


def shadow_of(src: Image.Image, blur: float, opacity: float) -> Image.Image:
    a = src.split()[3].filter(ImageFilter.GaussianBlur(blur))
    a = (np.asarray(a).astype(np.float64) * opacity).astype(np.uint8)
    sh = Image.new("RGBA", src.size, (0, 0, 0, 0))
    sh.putalpha(Image.fromarray(a))
    return sh


def downsample(img: Image.Image, size: int) -> Image.Image:
    """Progressive halving before the final resize - a single huge LANCZOS
    step softens small sizes noticeably."""
    while img.width // 2 >= size * 2:
        img = img.resize((img.width // 2, img.height // 2), Image.LANCZOS)
    return img.resize((size, size), Image.LANCZOS)


# --- art ---------------------------------------------------------------------
class Tier:
    """Per-size art parameters. Everything is a fraction of the icon body."""

    def __init__(self, body, card, lines, line_h, gap, top, dot, inset, rot, rim):
        self.body = body      # body edge / canvas edge
        self.card = card      # card edge / body edge
        self.lines = lines    # relative widths of the text lines
        self.line_h = line_h  # line thickness / card edge
        self.gap = gap        # space between lines / line thickness
        self.top = top        # first line's top / card edge
        self.dot = dot        # hide-dot diameter / card edge
        self.inset = inset    # dot inset from the card's top-right / card edge
        self.rot = rot        # card rotation, degrees
        self.rim = rim        # alpha of the frosted-glass top rim


def tier_for(size: int) -> Tier:
    if size <= 16:
        # 14x14 body, ~10px card. No room for lines; the dot survives as a
        # sub-pixel warm smudge, which is still worth having - it is the only
        # colour in the icon and it is what the eye picks up in a list.
        # Rotation is dropped: a 4-degree tilt on a 9px card only produces
        # ragged edges, it does not read as a tilt.
        return Tier(0.875, 0.62, (), 0.0, 0.0, 0.0, 0.145, 0.175, 0.0, 0)
    if size <= 32:
        # One thick line still reads as "a note" here; two merge into a blob.
        return Tier(0.8125, 0.65, (0.78,), 0.090, 0.0, 0.520, 0.150, 0.190, -3.0, 0)
    if size <= 64:
        return Tier(0.805, 0.655, (1.0, 0.70), 0.058, 1.45, 0.455, 0.100, 0.185, -4.0, 30)
    return Tier(0.805, 0.645, (1.0, 0.78, 0.45), 0.044, 1.45, 0.400, 0.076, 0.165, -4.0, 35)


def build_body(B: int, t: Tier, square: bool = False) -> Image.Image:
    """The squircle plus the note sitting on it, at edge length B.
    square=True leaves the ground uncut, for callers that get masked later."""
    ground = vgrad(B, B, INK_HI, INK_LO)
    img = rgba(ground, np.ones((B, B)) if square else rrect_mask(B, B, B * 0.225))

    C = int(round(B * t.card))
    card = rgba(vgrad(C, C, CREAM_HI, CREAM_LO), rrect_mask(C, C, C * 0.085))

    if t.rim:
        rim = Image.new("RGBA", (C, C), (0, 0, 0, 0))
        ImageDraw.Draw(rim).rounded_rectangle(
            [0, 0, C - 1, C - 1], radius=C * 0.085,
            outline=(255, 255, 255, t.rim), width=max(2, int(C * 0.004)))
        rim.putalpha(Image.fromarray(
            (np.asarray(rim.split()[3]).astype(np.float64)
             * np.linspace(1.0, 0.0, C)[:, None]).astype(np.uint8)))
        card.alpha_composite(rim)

    d = ImageDraw.Draw(card)
    if t.lines:
        lh = C * t.line_h
        for i, frac in enumerate(t.lines):
            yy = C * t.top + i * lh * (1 + t.gap)
            d.rounded_rectangle([C * 0.145, yy, C * 0.145 + C * 0.71 * frac, yy + lh],
                                radius=lh / 2, fill=INK + (170,))
    if t.dot:
        r = C * t.dot
        d.ellipse([C - C * t.inset - r, C * t.inset, C - C * t.inset, C * t.inset + r],
                  fill=YELLOW + (255,))

    pad = C // 2
    stage = Image.new("RGBA", (C + pad * 2, C + pad * 2), (0, 0, 0, 0))
    stage.paste(card, (pad, pad), card)
    sh = shadow_of(stage, B * 0.026, 0.38)
    if t.rot:
        stage = stage.rotate(t.rot, resample=Image.BICUBIC)
        sh = sh.rotate(t.rot, resample=Image.BICUBIC)

    # Nudged above geometric centre: the card's drop shadow adds visual mass
    # below it, so a dead-centre card reads as sitting low.
    x = (B - stage.width) // 2
    y = (B - stage.height) // 2 - int(B * 0.007)
    img.alpha_composite(sh, (x, y + int(B * 0.014)))
    img.alpha_composite(stage, (x, y))
    return img


def render(size: int, full_bleed: bool = False) -> Image.Image:
    """Full icon at `size` px, rendered large and downsampled."""
    t = tier_for(size)
    if full_bleed:
        # Tahoe / Icon Composer wants a plain edge-to-edge square with no
        # baked-in corners or margin - the system supplies the squircle mask
        # and the shadow. The card shrinks by the same 824/1024 factor so it
        # keeps the visual weight it has in the classic framing.
        t.card *= 824 / 1024
        return downsample(build_body(WORK, t, square=True), size)

    B = int(round(WORK * t.body))
    body = build_body(B, t)
    canvas = Image.new("RGBA", (WORK, WORK), (0, 0, 0, 0))
    stage = Image.new("RGBA", (WORK, WORK), (0, 0, 0, 0))
    stage.paste(body, ((WORK - B) // 2, (WORK - B) // 2), body)
    # Small sizes get a tighter, weaker shadow so it does not eat whole pixels.
    weak = size <= 32
    canvas.alpha_composite(
        shadow_of(stage, WORK * (0.008 if weak else 0.016), 0.22 if weak else 0.30),
        (0, int(WORK * (0.005 if weak else 0.009))))
    canvas.alpha_composite(stage)
    return downsample(canvas, size)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true",
                    help="also write a contact sheet to /tmp/stickies-icon-preview.png")
    ap.add_argument("--out", default=ICONSET)
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    for size, name in SIZES:
        render(size).save(os.path.join(args.out, name))
        print(f"  {name:24s} {size}x{size}")

    master = os.path.join(ROOT, "tools", "icon-fullbleed-1024.png")
    render(1024, full_bleed=True).save(master)
    print(f"  {os.path.basename(master):24s} 1024x1024 (Icon Composer source)")

    if args.preview:
        big, pad = 384, 32
        smalls = [128, 64, 48, 32, 16]
        W = pad + big + pad + 24 + sum(s + pad for s in smalls)
        H = (big + pad * 2) * 2
        sheet = Image.new("RGB", (W, H), (0x6E, 0x6E, 0x76))
        ImageDraw.Draw(sheet).rectangle([0, H // 2, W, H], fill=(0xEC, 0xEC, 0xEF))
        for row in range(2):
            y0, x = row * (big + pad * 2) + pad, pad
            b = render(1024).resize((big, big), Image.LANCZOS)
            sheet.paste(b, (x, y0), b)
            x += big + pad + 24
            for s in smalls:
                r = render(s)
                sheet.paste(r, (x, y0 + (big - s) // 2), r)
                x += s + pad
        sheet.save("/tmp/stickies-icon-preview.png")
        print("  preview -> /tmp/stickies-icon-preview.png")


if __name__ == "__main__":
    main()
