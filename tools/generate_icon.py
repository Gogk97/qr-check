#!/usr/bin/env python3
"""Generator ikon Qristal.

Menggambar ulang ikon aplikasi dari geometri yang sama dengan
`lib/widgets/app_logo.dart` (ruang koordinat 64 unit):

  - latar persegi membulat gelap
  - bingkai putih (finder frame)
  - persegi kristal berfaset (siluet persegi, isi 8 faset + meja)
  - kilau putih kecil di tengah
  - ekor brass diagonal

Output: mipmap Android (5 densitas) + AppIcon iOS + preview 1024.
Jalankan: python3 tools/generate_icon.py
"""

from __future__ import annotations

import json
import os
from pathlib import Path

from PIL import Image, ImageDraw

# Pillow >=10 memindahkan konstanta resampling ke enum Resampling.
RESAMPLE = getattr(Image, "Resampling", Image).LANCZOS

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android/app/src/main/res"
IOS = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"

# --- palet (samakan dengan AppTheme) ---------------------------------------
BG = (0x12, 0x18, 0x16)          # surfaceDark
BG_BORDER = (0x23, 0x2D, 0x29)   # borderDark
FRAME = (0xF1, 0xF5, 0xF3)       # textLight
BRASS = (0xC6, 0x7D, 0x15)       # qrAmber
WHITE = (255, 255, 255)

CRYSTAL = {
    "tl": (0xB7, 0xF5, 0xDC),
    "tr": (0x4F, 0xD3, 0xA6),
    "rt": (0x2C, 0xB9, 0x8D),
    "rb": (0x0E, 0x90, 0x68),
    "br": (0x08, 0x6B, 0x4E),
    "bl": (0x07, 0x72, 0x51),
    "lb": (0x0F, 0x94, 0x68),
    "lt": (0x1F, 0xA8, 0x7C),
    "table": (0x5F, 0xE0, 0xB4),
}

UNIT = 64.0          # ruang koordinat desain
SS = 4               # supersampling untuk antialias


def render(master_px: int = 1024, background: bool = True) -> Image.Image:
    """Render ikon pada ukuran master (px) dengan supersampling."""
    size = master_px * SS
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = size / UNIT

    def xy(x: float, y: float) -> tuple[float, float]:
        return (x * s, y * s)

    # 1. Latar persegi membulat (opsional — untuk logo transparan)
    if background:
        d.rounded_rectangle(
            [0, 0, size - 1, size - 1],
            radius=14.0 * s,  # 22% dari 64
            fill=BG,
        )

    # 2. Bingkai putih (RRect 11,11,38,38 r=9, stroke 5.5)
    stroke = 5.5 * s
    inset = stroke / 2
    d.rounded_rectangle(
        [11 * s + inset, 11 * s + inset, 49 * s - inset, 49 * s - inset],
        radius=9 * s - inset,
        outline=FRAME,
        width=int(round(stroke)),
    )

    # 3. Persegi kristal (22..38) — digambar di layer terpisah lalu di-clip
    crystal = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cd = ImageDraw.Draw(crystal)

    tl_c = xy(22, 22)
    tr_c = xy(38, 22)
    br_c = xy(38, 38)
    bl_c = xy(22, 38)
    top_m = xy(30, 22)
    right_m = xy(38, 30)
    bottom_m = xy(30, 38)
    left_m = xy(22, 30)
    n = xy(30, 25.6)
    e = xy(34.4, 30)
    south = xy(30, 34.4)
    w = xy(25.6, 30)

    facets = [
        ([tl_c, top_m, n, w], CRYSTAL["tl"]),
        ([top_m, tr_c, e, n], CRYSTAL["tr"]),
        ([tr_c, e, right_m], CRYSTAL["rt"]),
        ([right_m, br_c, south, e], CRYSTAL["rb"]),
        ([br_c, bottom_m, south], CRYSTAL["br"]),
        ([bottom_m, bl_c, w, south], CRYSTAL["bl"]),
        ([bl_c, left_m, w], CRYSTAL["lb"]),
        ([left_m, tl_c, n, w], CRYSTAL["lt"]),
        ([n, e, south, w], CRYSTAL["table"]),
    ]
    for points, color in facets:
        cd.polygon(points, fill=color)

    # Clip ke persegi membulat r=3.2
    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle(
        [22 * s, 22 * s, 38 * s, 38 * s],
        radius=3.2 * s,
        fill=255,
    )
    img.paste(crystal, (0, 0), mask)

    # 4. Kilau putih kecil (3.6 unit di tengah)
    glint = 3.6 * s
    gx, gy = 30 * s - glint / 2, 30 * s - glint / 2
    d.rounded_rectangle(
        [gx, gy, gx + glint, gy + glint],
        radius=0.9 * s,
        fill=WHITE,
    )

    # 5. Ekor brass (39,39 -> 53,53, stroke 6.5, ujung membulat)
    tail_w = 6.5 * s
    x1, y1 = 39 * s, 39 * s
    x2, y2 = 53 * s, 53 * s
    d.line([(x1, y1), (x2, y2)], fill=BRASS, width=int(round(tail_w)))
    r = tail_w / 2
    for cx, cy in ((x1, y1), (x2, y2)):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=BRASS)

    return img.resize((master_px, master_px), RESAMPLE)


ANDROID_SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


def main() -> None:
    master = render(1024)

    # Preview untuk review
    out_dir = ROOT / "assets/brand"
    out_dir.mkdir(parents=True, exist_ok=True)
    master.save(out_dir / "app_icon_1024.png")
    master.resize((192, 192), RESAMPLE).save(out_dir / "app_icon_192.png")
    master.resize((48, 48), RESAMPLE).save(out_dir / "app_icon_48.png")

    # Mark transparan (tanpa latar) untuk feature graphic & kebutuhan lain
    mark = render(1024, background=False)
    mark.save(out_dir / "mark_transparent_1024.png")

    # Android mipmaps (legacy, full-bleed)
    for folder, px in ANDROID_SIZES.items():
        target = RES / folder / "ic_launcher.png"
        master.resize((px, px), RESAMPLE).save(target)
        print(f"✓ {target.relative_to(ROOT)} ({px}px)")

    # iOS AppIcon — ukuran dibaca dari Contents.json
    contents = IOS / "Contents.json"
    if contents.exists():
        data = json.loads(contents.read_text())
        for image in data.get("images", []):
            filename = image.get("filename")
            size = image.get("size")
            scale = image.get("scale", "1x")
            if not filename or not size:
                continue
            base = float(size.split("x")[0])
            factor = float(scale.rstrip("x"))
            px = int(round(base * factor))
            master.resize((px, px), RESAMPLE).save(IOS / filename)
        print(f"✓ {len(data.get('images', []))} ikon iOS")

    print("Selesai.")


if __name__ == "__main__":
    main()
