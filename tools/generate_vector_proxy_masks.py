#!/usr/bin/env python3
"""Regenerate semantic vector-target masks from canonical VS layout schemas.

The FX shader is texture based. Side fields, name plates and accent lines remain
canonical Polygon2D/Line2D composition geometry in `vs_screen.gd`; the lab uses
1280x720 alpha-mask proxies derived from the same authored geometry. This tool
makes those proxy assets reproducible instead of hand-maintained.
"""
from pathlib import Path
import json, math
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "project/assets/vs/schema"
OUT = ROOT / "project/assets/vs/generated"
SIZE = (1280, 720)
PLATE_SHEAR = 0.2
PLATE_RISE = 0.01
ACCENT_INSET = 5.0


def white_canvas():
    return Image.new("RGBA", SIZE, (0, 0, 0, 0))


def save_polygon(path: Path, points):
    im = white_canvas()
    ImageDraw.Draw(im).polygon([(round(x), round(y)) for x, y in points], fill=(255,255,255,255))
    im.save(path)


def save_line(path: Path, points, width: int):
    im = white_canvas()
    ImageDraw.Draw(im).line([(round(x), round(y)) for x, y in points], fill=(255,255,255,255), width=max(1,width))
    im.save(path)


def plate_points(rect):
    x,y,w,h = map(float, rect)
    rise = PLATE_RISE * w
    shear = PLATE_SHEAR * h
    return [
        (x, y + rise),
        (x + w - shear, y),
        (x + w, y + h - rise),
        (x + shear, y + h),
    ]


def accent_points(rect):
    pts = plate_points(rect)
    ax,ay = pts[0]; bx,by = pts[1]
    dx,dy = bx-ax, by-ay
    length = max(math.hypot(dx,dy), 1e-9)
    ux,uy = dx/length, dy/length
    return [(ax+ux*ACCENT_INSET, ay+uy*ACCENT_INSET), (bx-ux*ACCENT_INSET, by-uy*ACCENT_INSET)]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    layout = json.loads((SCHEMA / "vs_layout_1280x720.json").read_text(encoding="utf-8"))
    mp = json.loads((SCHEMA / "multiplayer_layouts_1280x720.json").read_text(encoding="utf-8"))

    fields = layout["side_fields"]
    save_polygon(OUT / "side_field_left_mask.png", fields["left_points"])
    save_polygon(OUT / "side_field_right_mask.png", fields["right_points"])

    plates = layout["nameplates"]
    save_polygon(OUT / "name_plate_left_mask.png", plates["left_points"])
    save_polygon(OUT / "name_plate_right_mask.png", plates["right_points"])
    save_line(OUT / "accent_left_mask.png", plates["left_accent_line"], int(plates.get("accent_line_width",3)))
    save_line(OUT / "accent_right_mask.png", plates["right_accent_line"], int(plates.get("accent_line_width",3)))

    accent_width = int(plates.get("accent_line_width",3))
    for family_name, family in mp.get("families",{}).items():
        prefix = family_name.lower()
        for slot, geometry in family.get("slots",{}).items():
            rect = geometry.get("name",[])
            if len(rect) != 4:
                continue
            slot_id = str(slot).lower()
            save_polygon(OUT / f"{prefix}_plate_{slot_id}_mask.png", plate_points(rect))
            save_line(OUT / f"{prefix}_accent_{slot_id}_mask.png", accent_points(rect), accent_width)

    checker = Image.new("RGBA", SIZE, (0,0,0,255))
    d = ImageDraw.Draw(checker)
    cell = 24
    c0=(52,55,61,255); c1=(74,78,86,255)
    for y in range(0,SIZE[1],cell):
        for x in range(0,SIZE[0],cell):
            d.rectangle((x,y,min(x+cell-1,SIZE[0]-1),min(y+cell-1,SIZE[1]-1)), fill=c0 if ((x//cell+y//cell)&1)==0 else c1)
    checker.save(OUT / "study_checker.png")

    print(f"generated vector proxy masks in {OUT}")

if __name__ == "__main__":
    main()
