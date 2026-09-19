# -*- coding: utf-8 -*-
"""量出现有 192x192 部件的几何: 各槽位内容的 alpha 包围盒(均值/范围), 用于定 AI 出图模板。"""
import json
import os
from PIL import Image

DST = os.path.dirname(os.path.abspath(__file__))
CAT = json.load(open(os.path.join(DST, "catalog.json"), encoding="utf-8"))

ORDER = ["face", "cloth", "hair_back", "ears", "eyes", "brows", "mouth", "hair_front"]


def bbox(img):
    a = img.split()[-1]
    return a.getbbox()


def stat(g, suffix, slot, n=6):
    es = CAT[g][slot]
    d = os.path.join(DST, slot)
    xs0, ys0, xs1, ys1 = [], [], [], []
    for e in es[:n]:
        fn = f"{e['n']}{suffix}_back.png" if e.get("back_only") else f"{e['n']}{suffix}.png"
        p = os.path.join(d, fn)
        if not os.path.exists(p):
            continue
        bb = bbox(Image.open(p).convert("RGBA"))
        if not bb:
            continue
        xs0.append(bb[0]); ys0.append(bb[1]); xs1.append(bb[2]); ys1.append(bb[3])
    if not xs0:
        return None
    f = lambda a: (min(a), int(sum(a) / len(a)), max(a))
    return f(xs0), f(ys0), f(xs1), f(ys1)


def main():
    for g, suffix in (("male", "m"), ("female", "f")):
        print("==", g)
        for slot in ORDER:
            s = stat(g, suffix, slot)
            if not s:
                continue
            (x0a, x0m, x0b), (y0a, y0m, y0b), (x1a, x1m, x1b), (y1a, y1m, y1b) = s
            print(f"  {slot:10s} x:[{x0a:3d}/{x0m:3d}/{x0b:3d}] y:[{y0a:3d}/{y0m:3d}/{y0b:3d}]"
                  f"  右下 x:[{x1a:3d}/{x1m:3d}/{x1b:3d}] y:[{y1a:3d}/{y1m:3d}/{y1b:3d}]"
                  f"  中心x~{(x0m+x1m)//2}")

    # 出一张"裸底稿": face#1 + ears + eyes#1 + brows#1 + mouth#1
    for g, suffix in (("male", "m"), ("female", "f")):
        canvas = Image.new("RGBA", (192, 192), (0, 0, 0, 0))
        for slot in ("face", "ears", "eyes", "brows", "mouth"):
            e = CAT[g][slot][0]
            p = os.path.join(DST, slot, f"{e['n']}{suffix}.png")
            if os.path.exists(p):
                canvas.alpha_composite(Image.open(p).convert("RGBA"))
        out = os.path.join(DST, "_candidates", f"base_{g}.png")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        canvas.save(out)
        print("saved", out, canvas.size)


if __name__ == "__main__":
    main()
