# -*- coding: utf-8 -*-
"""批量跑 extract_part.py: 服装 8 件 + 发型 6 款(每款前发/后发两层)。"""
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

CLOTH = {
    "m": [("cloth_m1", "靛青交领袍", 1), ("cloth_m2", "玄色劲装", 2), ("cloth_m3", "月白鹤氅", 3),
          ("cloth_m4", "赭石道袍", 4), ("cloth_m5", "墨绿长衫", 5)],
    "f": [("cloth_f1", "月白襦裙", 1), ("cloth_f2", "藕荷襦裙", 2), ("cloth_f3", "水蓝广袖裙", 3),
          ("cloth_f4", "玄紫劲装", 4), ("cloth_f5", "素白道袍", 5)],
}
HAIR = {
    "m": [("hair_m1", "高马尾"), ("hair_m2", "束发道髻"), ("hair_m3", "垂鬓散发")],
    "f": [("hair_f1", "双环髻"), ("hair_f2", "长发垂鬓"), ("hair_f3", "垂肩长辫")],
}
SUFFIX = {"m": "m", "f": "f"}


def run(base, gen, out, bgmode, kind):
    cmd = [PY, os.path.join(DST, "extract_part.py"), base, gen, out, bgmode, kind]
    r = subprocess.run(cmd, capture_output=True, text=True)
    print("  ", (r.stdout + r.stderr).strip().replace("\n", "\n   "))
    return r.returncode == 0


def alpha_ratio(p):
    a = np.array(Image.open(p).convert("RGBA").split()[-1])
    return float((a > 128).mean())


def main():
    report = []
    for g in ("m", "f"):
        base = os.path.join(DST, "_candidates", "base_%s.png" % ("male" if g == "m" else "female"))
        suf = SUFFIX[g]
        for stem, name, idx in CLOTH[g]:
            gen = os.path.join(DST, "_ai", "raw", stem + ".png")
            bg = "white" if (g == "f" and idx == 1) else "magenta"
            out = os.path.join(OUT, "%s_part.png" % stem)
            if not os.path.exists(gen):
                print("缺失", gen); continue
            ok = run(base, gen, out, bg, "cloth")
            r = alpha_ratio(out) if ok else 0
            report.append((stem, name, "cloth/%d%s.png" % (idx, suf), r, ok))
            print("%-10s %-8s 覆盖率 %.1f%%" % (stem, name, r * 100))
        for i, (stem, name) in enumerate(HAIR[g], 1):
            gen = os.path.join(DST, "_ai", "raw", stem + ".png")
            if not os.path.exists(gen):
                print("缺失", gen); continue
            for kind in ("hair_front", "hair_back"):
                out = os.path.join(OUT, "%s_%s.png" % (stem, kind.split("_")[1]))
                ok = run(base, gen, out, "magenta", kind)
                r = alpha_ratio(out) if ok else 0
                report.append((stem, name, "%s/%d%s.png" % (kind, i, suf), r, ok))
                print("%-10s %-8s %-8s 覆盖率 %.1f%%" % (stem, name, kind, r * 100))
    json.dump([{"stem": a, "name": b, "file": c, "ratio": round(d, 4), "ok": e} for a, b, c, d, e in report],
              open(os.path.join(DST, "_ai", "extract_report.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    bad = [r for r in report if not r[4] or r[3] < 0.01]
    print("失败/近乎空的件:", bad if bad else "无")


if __name__ == "__main__":
    main()
