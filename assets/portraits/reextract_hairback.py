# -*- coding: utf-8 -*-
"""只重做后发件: hair_back 之前被「只在光头轮廓外」的规则砍掉了整个头顶/后脑勺,
导致合成后头顶露皮肤。改规则后按 parts.json 的 file 重新提取并做数值审计。

用法: python reextract_hairback.py [--apply]
默认输出到 _ai/out/ 做审计; 加 --apply 才写回 _ai/parts/。
"""
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image

DST = os.path.dirname(os.path.abspath(__file__))
PY = r"C:\Users\iaek\.workbuddy\binaries\python\envs\default\Scripts\python.exe"
OUT = os.path.join(DST, "_ai", "out")
PARTS = os.path.join(DST, "_ai", "parts")
RAW = os.path.join(DST, "_ai", "raw")

# 生成图 -> parts.json 里的后发文件名
GEN2FILE = {
    "hair_m1": "hair_back/18m.png", "hair_m2": "hair_back/19m.png", "hair_m3": "hair_back/20m.png",
    "hair_f1": "hair_back/22f.png", "hair_f2": "hair_back/23f.png", "hair_f3": "hair_back/24f.png",
}


def run(base, gen, out, kind):
    cmd = [PY, os.path.join(DST, "extract_part.py"), base, gen, out, "magenta", kind]
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r.returncode == 0, (r.stdout + r.stderr).strip()


def top_coverage(p, face_a, top=25):
    """该件在头顶区(y<=top 且脸不透明)的覆盖率。"""
    a = np.array(Image.open(p).convert("RGBA"))[..., 3]
    band = (np.arange(192)[:, None] <= top) & (face_a > 128)
    if band.sum() == 0:
        return float("nan")
    return float((a > 128)[band].mean())


def cheek_coverage(p, face_a, y0=60, y1=84):
    """脸颊中部覆盖率 —— 后发不该糊住脸中间, 应接近 0。"""
    a = np.array(Image.open(p).convert("RGBA"))[..., 3]
    band = (np.arange(192)[:, None] >= y0) & (np.arange(192)[:, None] < y1) & (face_a > 128)
    if band.sum() == 0:
        return float("nan")
    return float((a > 128)[band].mean())


def main():
    apply = "--apply" in sys.argv
    report = []
    for gender_dir, base_name, tag in (("male", "base_male.png", "m"), ("female", "base_female.png", "f")):
        base = os.path.join(DST, "_candidates", base_name)
        face_a = np.array(Image.open(os.path.join(DST, "face", "1%s.png" % tag)).convert("RGBA"))[..., 3]
        for stem, rel in GEN2FILE.items():
            if not rel.endswith("%s.png" % tag):
                continue
            gen = os.path.join(RAW, stem + ".png")
            if not os.path.exists(gen):
                print("缺失", gen)
                continue
            probe = os.path.join(OUT, "%s_back2.png" % stem)
            ok, log = run(base, gen, probe, "hair_back")
            if not ok:
                print("提取失败", stem, log)
                continue
            tc = top_coverage(probe, face_a)
            cc = cheek_coverage(probe, face_a)
            old = os.path.join(PARTS, rel)
            otc = top_coverage(old, face_a) if os.path.exists(old) else float("nan")
            print("%-8s -> %-18s 头顶覆盖 %.2f (旧 %.2f)  脸颊 %.2f" % (stem, rel, tc, otc, cc))
            report.append((rel, tc, cc))
            if apply:
                os.replace(probe, old)
                print("        写回", old)
    if apply:
        print("\n已写回 %d 件; 接着跑 recolor_hair.py -> import_chara_parts.py -> Godot --import" % len(report))
    else:
        print("\n(--apply 未写回, 仅审计)")


if __name__ == "__main__":
    main()
