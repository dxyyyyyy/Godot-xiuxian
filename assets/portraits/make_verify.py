# -*- coding: utf-8 -*-
"""发型/服装验收总表: 行=款式, 列= 后发件|前发件|合成。"""
import os
from PIL import Image

d = r"E:\Game\Godot-xiuxian\assets\portraits"
out = os.path.join(d, "_ai", "out")
TILE = 192


def compose(files):
    c = Image.new("RGBA", (192, 192), (0, 0, 0, 0))
    for p in files:
        if p and os.path.exists(p):
            c.alpha_composite(Image.open(p).convert("RGBA"))
    bg = Image.new("RGBA", (192, 192), (96, 128, 96, 255))
    bg.alpha_composite(c)
    return bg.convert("RGB")


def sheet(rows, name):
    w = max(len(r) for r in rows)
    im = Image.new("RGB", (TILE * w, TILE * len(rows)), (40, 40, 48))
    for i, fs in enumerate(rows):
        for j, f in enumerate(fs):
            if f is None:
                continue
            im.paste(compose(f), (j * TILE, i * TILE))
    im.resize((TILE * w * 2, TILE * len(rows) * 2), Image.NEAREST).save(os.path.join(out, name))
    print("saved", name)


rows = []
for g in ("m", "f"):
    base = os.path.join(d, "_candidates", "base_%s.png" % ("male" if g == "m" else "female"))
    for i in (1, 2, 3):
        rows.append([
            [os.path.join(out, "hair_%s%d_back.png" % (g, i))],
            [os.path.join(out, "hair_%s%d_front.png" % (g, i))],
            [base],
            [base, os.path.join(out, "hair_%s%d_back.png" % (g, i)),
             os.path.join(out, "hair_%s%d_front.png" % (g, i))],
        ])
sheet(rows, "verify_hair2.png")

# 服装: 部件 | 合成 | 合成+随机发型
import random
import json

cat = json.load(open(os.path.join(d, "catalog.json"), encoding="utf-8"))
rng = random.Random(5)
rows = []
for g in ("m", "f"):
    base = os.path.join(d, "_candidates", "base_%s.png" % ("male" if g == "m" else "female"))
    for i in (1, 2, 3, 4, 5):
        p = os.path.join(out, "cloth_%s%d_part.png" % (g, i))
        if not os.path.exists(p):
            continue
        hf = rng.choice(cat["male" if g == "m" else "female"]["hair_front"])
        hb = rng.choice(cat["male" if g == "m" else "female"]["hair_back"])
        rows.append([
            [p],
            [base, p],
            [base, p,
             os.path.join(d, "hair_back", "%d%s_back.png" % (hb["n"], g)),
             os.path.join(d, "hair_front", "%d%s.png" % (hf["n"], g))],
        ])
sheet(rows, "verify_cloth2.png")
