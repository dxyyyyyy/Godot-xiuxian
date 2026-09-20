# -*- coding: utf-8 -*-
"""最终验收: 用游戏真实合成层级(RENDER_ORDER)拼 AI 部件 + 原版五官, 出对照表。"""
import json
import os
import random

from PIL import Image

DST = os.path.dirname(os.path.abspath(__file__))
TILE = 192
SUF = {"male": "m", "female": "f"}
ORDER = ["face", "cloth", "hair_back", "ears", "eyes", "brows", "mouth", "hair_front"]


def compose(cat, g, parts, size=192):
    suf = SUF[g]
    c = Image.new("RGBA", (192, 192), (0, 0, 0, 0))
    for slot in ORDER:
        e = parts.get(slot)
        if not e:
            continue
        p = os.path.join(DST, slot, "%d%s.png" % (e["n"], suf))
        if os.path.exists(p):
            c.alpha_composite(Image.open(p).convert("RGBA"))
        pb = os.path.join(DST, slot, "%d%s_back.png" % (e["n"], suf))
        if os.path.exists(pb) and slot in ("hair_back",):
            c.alpha_composite(Image.open(pb).convert("RGBA"))
    bg = Image.new("RGBA", (192, 192), (96, 128, 96, 255))
    bg.alpha_composite(c)
    return bg.convert("RGB").resize((size, size), Image.NEAREST)


def sheet(cat, rows, name):
    w = max(len(r) for r in rows)
    im = Image.new("RGB", (TILE * w, TILE * len(rows)), (40, 40, 48))
    for i, cells in enumerate(rows):
        for j, cell in enumerate(cells):
            im.paste(cell, (j * TILE, i * TILE))
    im.resize((TILE * w * 2, TILE * len(rows) * 2), Image.NEAREST).save(os.path.join(DST, "_ai", "out", name))
    print("saved", name)


def main():
    cat = json.load(open(os.path.join(DST, "catalog.json"), encoding="utf-8"))
    rng = random.Random(3)
    # --- 服装表: 每个 AI 服装 × 随机原版五官/发型 ---
    rows = []
    for g in ("male", "female"):
        ai = [e for e in cat[g]["cloth"] if e["id"].startswith("AI_")]
        for e in ai:
            cells = []
            for k in range(2):
                face = rng.choice(cat[g]["face"])
                parts = {"face": face, "cloth": e,
                         "hair_back": rng.choice([x for x in cat[g]["hair_back"] if not x["id"].startswith("AI_")]),
                         "hair_front": rng.choice([x for x in cat[g]["hair_front"] if not x["id"].startswith("AI_")]),
                         "eyes": rng.choice(cat[g]["eyes"]), "brows": rng.choice(cat[g]["brows"]),
                         "mouth": rng.choice(cat[g]["mouth"])}
                cells.append(compose(cat, g, parts))
            rows.append(cells)
    sheet(cat, rows, "final_cloth.png")

    # --- 发型表: 每个 AI 发型(前后配对) × 随机原版服装/五官 ---
    rows = []
    for g in ("male", "female"):
        fronts = [e for e in cat[g]["hair_front"] if e["id"].startswith("AI_")]
        backs = [e for e in cat[g]["hair_back"] if e["id"].startswith("AI_")]
        for i, hf in enumerate(fronts):
            hb = backs[i] if i < len(backs) else None
            cells = []
            for k in range(2):
                parts = {"face": rng.choice(cat[g]["face"]),
                         "cloth": rng.choice([x for x in cat[g]["cloth"] if not x["id"].startswith("AI_")]),
                         "hair_back": hb, "hair_front": hf,
                         "eyes": rng.choice(cat[g]["eyes"]), "brows": rng.choice(cat[g]["brows"]),
                         "mouth": rng.choice(cat[g]["mouth"])}
                cells.append(compose(cat, g, parts))
            rows.append(cells)
    sheet(cat, rows, "final_hair.png")


if __name__ == "__main__":
    main()
