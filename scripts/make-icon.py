#!/usr/bin/env python3
"""make-icon.py — render the Auricle app icon per docs/recon/ui-spec.md §12.

Renders a 1024x1024 master with PIL (squircle, gradient, rim light, waveform
bars, under-glow), plus the recommended 5-bar variant for the small sizes,
then sips-resizes into AppIcon.iconset and iconutil-compiles to
Resources/AppIcon.icns.
"""
import os
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, ".build", "icon-work")
ICONSET = os.path.join(WORK, "AppIcon.iconset")
RESOURCES = os.path.join(ROOT, "Resources")

S = 1024          # canvas
SS = 2            # supersample factor for crisp shape edges
INSET = 100       # macOS icon grid margin (~10%)
RADIUS = 185      # 0.225 * 824 — reads as the macOS squircle
BG_TOP, BG_BOT = (0x1E, 0x24, 0x30), (0x0C, 0x0F, 0x16)
BAR_TOP, BAR_BOT = (0x5A, 0xC8, 0xFA), (0x7A, 0x5C, 0xFF)


def vgrad(w, h, top, bot):
    """Vertical linear gradient image (RGB)."""
    strip = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / (h - 1)
        strip.putpixel((0, y), tuple(round(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
    return strip.resize((w, h))


def bar_geometry(widths_heights):
    """(bar_width, gap, heights) -> list of (x0, y0, x1, y1) boxes, centered."""
    bw, gap, heights = widths_heights
    n = len(heights)
    group_w = n * bw + (n - 1) * gap
    x = S / 2 - group_w / 2
    boxes = []
    for h in heights:
        boxes.append((x, S / 2 - h / 2, x + bw, S / 2 + h / 2))
        x += bw + gap
    return bw, boxes


def capsule_mask(boxes, bw, only=None):
    """Supersampled L mask of capsules (radius = bw/2)."""
    m = Image.new("L", (S * SS, S * SS), 0)
    d = ImageDraw.Draw(m)
    for i, b in enumerate(boxes):
        if only is not None and i not in only:
            continue
        d.rounded_rectangle([c * SS for c in b], radius=(bw / 2) * SS, fill=255)
    return m.resize((S, S), Image.LANCZOS)


def render(bars_spec, glow_indices):
    """Render one 1024px icon. bars_spec = (bar_width, gap, heights)."""
    # 1. transparent canvas
    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # 2. squircle mask (supersampled)
    sq = Image.new("L", (S * SS, S * SS), 0)
    ImageDraw.Draw(sq).rounded_rectangle(
        [INSET * SS, INSET * SS, (S - INSET) * SS, (S - INSET) * SS],
        radius=RADIUS * SS, fill=255)
    sq = sq.resize((S, S), Image.LANCZOS)

    # 3. background gradient masked by squircle
    bg = vgrad(S, S, BG_TOP, BG_BOT).convert("RGBA")
    icon.paste(bg, (0, 0), sq)

    # 4. inner rim light: 3px stroke, white @ 8%, just inside the edge
    rim = Image.new("RGBA", (S * SS, S * SS), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle(
        [(INSET + 1.5) * SS, (INSET + 1.5) * SS, (S - INSET - 1.5) * SS, (S - INSET - 1.5) * SS],
        radius=(RADIUS - 1.5) * SS, outline=(255, 255, 255, 20), width=3 * SS)
    icon.alpha_composite(rim.resize((S, S), Image.LANCZOS))

    # 5. waveform bars — one shared vertical gradient masked per bar
    bw, boxes = bar_geometry(bars_spec)
    top_y = min(b[1] for b in boxes)
    bot_y = max(b[3] for b in boxes)
    grad = Image.new("RGB", (S, S), tuple(BAR_BOT))
    grad.paste(vgrad(S, int(bot_y - top_y), BAR_TOP, BAR_BOT), (0, int(top_y)))
    # fill above the group with the top color
    grad.paste(Image.new("RGB", (S, int(top_y)), tuple(BAR_TOP)), (0, 0))

    bars_mask = capsule_mask(boxes, bw)
    bars_layer = grad.convert("RGBA")
    bars_layer.putalpha(bars_mask)

    # 6. subtle glow under the bars: duplicate middle bars, blur 40, 22% alpha
    glow_mask = capsule_mask(boxes, bw, only=glow_indices)
    glow_layer = grad.convert("RGBA")
    glow_layer.putalpha(glow_mask)
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(40))
    r, g, b, a = glow_layer.split()
    glow_layer = Image.merge("RGBA", (r, g, b, a.point(lambda v: int(v * 0.22))))

    icon.alpha_composite(glow_layer)   # under the bars
    icon.alpha_composite(bars_layer)

    # keep everything inside the squircle (glow must not bleed past the shape edge)
    from PIL import ImageChops
    r, g, b, a = icon.split()
    return Image.merge("RGBA", (r, g, b, ImageChops.darker(a, sq)))


def main():
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(ICONSET, exist_ok=True)
    os.makedirs(RESOURCES, exist_ok=True)

    # 7-bar master (spec step 5): width 44, gap 36, arch heights
    master = render((44, 36, [180, 300, 460, 620, 460, 300, 180]), glow_indices={2, 3, 4})
    master_png = os.path.join(WORK, "icon-1024.png")
    master.save(master_png)

    # recommended 5-bar variant for 16–32 px sizes (spec step 7)
    small = render((56, 48, [300, 460, 620, 460, 300]), glow_indices={1, 2, 3})
    small_png = os.path.join(WORK, "icon-small-1024.png")
    small.save(small_png)

    # iconset: sips-resize. Small-point sizes (rendered at 16/32/64 px) use the 5-bar art.
    plan = [
        ("icon_16x16.png",       16, small_png),
        ("icon_16x16@2x.png",    32, small_png),
        ("icon_32x32.png",       32, small_png),
        ("icon_32x32@2x.png",    64, small_png),
        ("icon_128x128.png",    128, master_png),
        ("icon_128x128@2x.png", 256, master_png),
        ("icon_256x256.png",    256, master_png),
        ("icon_256x256@2x.png", 512, master_png),
        ("icon_512x512.png",    512, master_png),
        ("icon_512x512@2x.png", 1024, master_png),
    ]
    for name, px, src in plan:
        dst = os.path.join(ICONSET, name)
        if px == 1024:
            shutil.copyfile(src, dst)
        else:
            subprocess.run(["sips", "-z", str(px), str(px), src, "--out", dst],
                           check=True, capture_output=True)

    icns = os.path.join(RESOURCES, "AppIcon.icns")
    subprocess.run(["iconutil", "-c", "icns", ICONSET, "-o", icns], check=True)
    print("Wrote", icns)


if __name__ == "__main__":
    sys.exit(main())
