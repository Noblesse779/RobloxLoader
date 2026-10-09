"""Draw every stage into one PNG:  python BattleCity/tests/render_stages.py BattleCity/docs/stages.png  (needs pillow)"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import luaenv
from PIL import Image, ImageDraw

stages = luaenv.to_py(luaenv.load_file(luaenv.new_runtime(), luaenv.path("BattleCityStages.lua")))
C = 8  # px per cell
COL = {".": (0, 0, 0), "B": (176, 88, 40), "S": (190, 190, 200), "W": (40, 90, 220), "T": (46, 140, 46), "I": (205, 230, 255), "E": (255, 200, 40)}
cols, pad, label = 7, 10, 14
W = 26 * C
img = Image.new("RGB", (cols * (W + pad) + pad, ((len(stages) + cols - 1) // cols) * (W + pad + label) + pad), (99, 99, 99))
d = ImageDraw.Draw(img)
for k, st in enumerate(stages):
    ox = pad + (k % cols) * (W + pad)
    oy = pad + (k // cols) * (W + pad + label)
    d.text((ox, oy), f"{k + 1}. {st['name']}", fill=(255, 255, 255))
    oy += label
    for r, row in enumerate(st["map"]):
        for c, ch in enumerate(row):
            x, y = ox + c * C, oy + r * C
            d.rectangle([x, y, x + C - 1, y + C - 1], fill=COL[ch])
            if ch == "B":  # mortar line like NES bricks
                d.line([x, y + C // 2, x + C - 1, y + C // 2], fill=(110, 50, 20))
    for sx in (0, 12, 24):
        d.rectangle([ox + sx * C, oy, ox + sx * C + 2 * C - 1, oy + 2 * C - 1], outline=(220, 60, 60))
    for sx in (8, 16):
        d.rectangle([ox + sx * C, oy + 24 * C, ox + sx * C + 2 * C - 1, oy + 26 * C - 1], outline=(255, 230, 0))
img.save(sys.argv[1])
print(img.size)
