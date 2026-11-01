"""Convert the actual RTL testbench frames to portable PNG previews.

Run sim/run.py --icarus <...> tb_dual_lcd first. These previews are the
RTL raster, not a separate reimplementation of the LCD drawing code.
"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "lcd_previews"
NAMES = ["lcd_dual_live", "lcd_dual_clip"]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    tiles = []
    for name in NAMES:
        src = ROOT / "sim" / "results" / (name + ".ppm")
        with Image.open(src) as raster:
            assert raster.size == (480, 272)
            frame = raster.convert("RGB")
        frame.save(OUT / (name + ".png"))
        tiles.append(frame)
    contact = Image.new("RGB", (1008, 28 + ((len(tiles)+1)//2)*304), "#171e28")
    pen = ImageDraw.Draw(contact)
    for index, (name, tile) in enumerate(zip(NAMES, tiles)):
        left = 16 + (index % 2) * 496
        top = 28 + (index // 2) * 304
        pen.text((left, top - 19), name.removeprefix("lcd_cn_").replace("_", " ").upper(), fill="#d8e7ef")
        contact.paste(tile, (left, top))
    contact.save(OUT / "lcd_cn_overview.png")
    print(f"PASS: converted {len(tiles)} actual RTL frames to {OUT}")


if __name__ == "__main__":
    main()
