# -*- coding: utf-8 -*-
"""扫描 CORE_ERODE, 挑出让 AI 后发剖面最接近原版的取值。只跑审计, 不写回。"""
import os
import subprocess

import numpy as np
from PIL import Image

DST = os.path.dirname(os.path.abspath(__file__))
PY = r"C:\Users\iaek\.workbuddy\binaries\python\envs\default\Scripts\python.exe"
RAW = os.path.join(DST, "_ai", "raw")
OUT = os.path.join(DST, "_ai", "out")

GENS = {"m": ["hair_m1", "hair_m2", "hair_m3"], "f": ["hair_f1", "hair_f2", "hair_f3"]}
YS = (0, 24, 36, 48, 60, 72, 84, 96)


def A(p):
    return np.array(Image.open(p).convert("RGBA"))[..., 3]


def profile(gen_paths, face_a):
    """返回各 y 带上的覆盖率中位数。"""
    rows = []
    for stem, p in gen_paths:
        h = A(p)
        rows.append([float((h[y:y + 12] > 128)[face_a[y:y + 12] > 128].mean()) for y in YS])
    return np.median(np.array(rows), axis=0)


def main():
    import json
    cat = json.load(open(os.path.join(DST, "catalog.json"), encoding="utf-8"))
    orig = {}
    for g, tag in (("male", "m"), ("female", "f")):
        fa = A(os.path.join(DST, "face", "1%s.png" % tag))
        hs = [A(os.path.join(DST, "hair_back", "%d%s.png" % (e["n"], tag)))
              for e in cat[g]["hair_back"]
              if not e["id"].startswith("AI_")
              and os.path.exists(os.path.join(DST, "hair_back", "%d%s.png" % (e["n"], tag)))]
        orig[g] = (fa, np.median([[float((h[y:y + 12] > 128)[fa[y:y + 12] > 128].mean()) for y in YS]
                                  for h in hs], axis=0))
    print("参考(原版中位)  y=" + " ".join("%5d" % y for y in YS))
    for g in ("male", "female"):
        print("   %-7s       " % g + " ".join("%5.2f" % v for v in orig[g][1]))

    for val in (4, 5, 6, 7, 8):
        print("\n--- CORE_ERODE=%d ---" % val)
        env = dict(os.environ, CORE_ERODE=str(val))
        for g, tag in (("male", "m"), ("female", "f")):
            base = os.path.join(DST, "_candidates", "base_%s.png" % ("male" if g == "male" else "female"))
            paths = []
            for stem in GENS[tag]:
                out = os.path.join(OUT, "%s_sw.png" % stem)
                cmd = [PY, os.path.join(DST, "extract_part.py"), base,
                       os.path.join(RAW, stem + ".png"), out, "magenta", "hair_back"]
                r = subprocess.run(cmd, capture_output=True, text=True, env=env)
                if r.returncode != 0:
                    print("  失败", stem, r.stderr[-200:])
                    continue
                paths.append((stem, out))
            fa, ref = orig[g]
            pr = profile(paths, fa)
            err = np.abs(pr - ref).mean()
            print("   %-7s       " % g + " ".join("%5.2f" % v for v in pr) + "   平均偏差 %.3f" % err)


if __name__ == "__main__":
    main()
