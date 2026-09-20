# -*- coding: utf-8 -*-
"""发件可染性验收: 复刻 recolor.gdshader 的「色相旋转 + 彩度缩放(明度不变)」,
把每个 AI 发型在不同色相下合成出来, 并给出量化指标。

着色器原文:
    hsv.x = fract(hsv.x + hue_shift)
    hsv.y = clamp(hsv.y * sat_scale, 0, 1)
明度 V 不变 —— 这正是纯黑发染不动的原因, 所以贴图必须先由 recolor_hair.py 抬到中间调。
"""
import json
import os

import numpy as np
from PIL import Image

DST = os.path.dirname(os.path.abspath(__file__))
TILE = 192
SUF = {"male": "m", "female": "f"}
ORDER = ["face", "cloth", "hair_back", "ears", "eyes", "brows", "mouth", "hair_front"]
HAIR_SLOTS = ("hair_front", "hair_back", "brows")
# 列: (说明, 色相°, 彩度%)
COLS = [("原色 0°", 0, 100), ("60°", 60, 100), ("140°", 140, 100),
        ("220°", 220, 100), ("300°", 300, 100), ("灰 0%", 0, 0)]


def rgb_to_hsv(c):
    mx = c.max(axis=-1)
    mn = c.min(axis=-1)
    d = mx - mn
    dd = np.maximum(d, 1e-9)
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    h = np.where(mx == r, ((g - b) / dd) % 6.0,
        np.where(mx == g, (b - r) / dd + 2.0, (r - g) / dd + 4.0)) / 6.0
    h = np.where(d <= 1e-9, 0.0, h)
    s = np.where(mx > 1e-9, d / np.maximum(mx, 1e-9), 0.0)
    return h, s, mx


def hsv_to_rgb(h, s, v):
    i = np.floor(h * 6.0)
    f = h * 6.0 - i
    p = v * (1 - s)
    q = v * (1 - f * s)
    t = v * (1 - (1 - f) * s)
    i = (i % 6).astype(int)
    r = np.select([i == 0, i == 1, i == 2, i == 3, i == 4, i == 5], [v, q, p, p, t, v])
    g = np.select([i == 0, i == 1, i == 2, i == 3, i == 4, i == 5], [t, v, v, q, p, p])
    b = np.select([i == 0, i == 1, i == 2, i == 3, i == 4, i == 5], [p, p, t, v, v, q])
    return np.stack([r, g, b], axis=-1)


def recolor(im: Image.Image, hue_deg: int, sat_pct: int) -> Image.Image:
    """逐像素复刻 recolor.gdshader。"""
    a = np.array(im.convert("RGBA"))
    c = a[..., :3].astype(float) / 255.0
    h, s, v = rgb_to_hsv(c)
    h = np.mod(h + hue_deg / 360.0, 1.0)
    s = np.clip(s * sat_pct / 100.0, 0.0, 1.0)
    out = np.clip(hsv_to_rgb(h, s, v) * 255.0, 0, 255).astype(np.uint8)
    return Image.fromarray(np.dstack([out, a[..., 3]]), "RGBA")


def load(slot, n, g):
    p = os.path.join(DST, slot, "%d%s.png" % (n, SUF[g]))
    return Image.open(p).convert("RGBA") if os.path.exists(p) else None


def compose(g, parts, hue_deg, sat_pct, base=None):
    c = Image.new("RGBA", (192, 192), (0, 0, 0, 0))
    for slot in ORDER:
        e = parts.get(slot)
        if not e:
            continue
        im = base(slot, e) if base else None
        if im is None:
            im = load(slot, e["n"], g)
        if im is None:
            continue
        if slot in HAIR_SLOTS and (hue_deg or sat_pct != 100):
            im = recolor(im, hue_deg, sat_pct)
        c.alpha_composite(im)
        if slot == "hair_back":
            pb = os.path.join(DST, slot, "%d%s_back.png" % (e["n"], SUF[g]))
            if os.path.exists(pb):
                b = Image.open(pb).convert("RGBA")
                if slot in HAIR_SLOTS and (hue_deg or sat_pct != 100):
                    b = recolor(b, hue_deg, sat_pct)
                c.alpha_composite(b)
    bg = Image.new("RGBA", (192, 192), (96, 128, 96, 255))
    bg.alpha_composite(c)
    return bg.convert("RGB")


def main():
    cat = json.load(open(os.path.join(DST, "catalog.json"), encoding="utf-8"))
    rows = []
    print("== 可染性量化(头发区域平均 RGB / 相邻列色差) ==")
    for g in ("male", "female"):
        fronts = [e for e in cat[g]["hair_front"] if e["id"].startswith("AI_")]
        backs = [e for e in cat[g]["hair_back"] if e["id"].startswith("AI_")]
        for i, hf in enumerate(fronts):
            hb = backs[i] if i < len(backs) else None
            parts = {"face": cat[g]["face"][0], "cloth": cat[g]["cloth"][0],
                     "hair_back": hb, "hair_front": hf,
                     "eyes": cat[g]["eyes"][0], "brows": cat[g]["brows"][0],
                     "mouth": cat[g]["mouth"][0]}
            cells, means = [], []
            for label, hue, sat in COLS:
                im = compose(g, parts, hue, sat)
                cells.append(im)
                # 只在头发不透明像素上统计(排除脸/衣)
                m = np.array(load("hair_front", hf["n"], g))[..., 3] > 128
                rgb = np.array(im).astype(float)[m] / 255.0
                means.append(rgb.mean(axis=0))
            print(f"  {g:6s} {hf['name']}")
            for k, (label, hue, sat) in enumerate(COLS):
                r, gg, b = means[k]
                d = "" if k == 0 else "   Δprev=%.3f" % np.abs(means[k] - means[k - 1]).sum()
                print(f"     {label:8s} RGB=({r:.2f},{gg:.2f},{b:.2f}){d}")
            rows.append(cells)

    w = max(len(r) for r in rows)
    im = Image.new("RGB", (TILE * w, TILE * len(rows)), (40, 40, 48))
    for i, cells in enumerate(rows):
        for j, cell in enumerate(cells):
            im.paste(cell, (j * TILE, i * TILE))
    out = os.path.join(DST, "_ai", "out", "dye_verify.png")
    im.resize((TILE * w * 2, TILE * len(rows) * 2), Image.NEAREST).save(out)
    print("saved", out)


if __name__ == "__main__":
    main()
