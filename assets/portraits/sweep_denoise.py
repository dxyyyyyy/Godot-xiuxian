# -*- coding: utf-8 -*-
"""扫描去噪方案: 目标是把 AI 发件的高频噪点压回原版水平(高频≈0.011, Lap≈0.04),
同时不把发丝纹理糊掉。评估指标: 高频能量 + 与原版同量级的对比度(标准差)。"""
import os

import cv2
import numpy as np
from PIL import Image

DST = os.path.dirname(os.path.abspath(__file__))
PARTS = os.path.join(DST, "_ai", "parts")
BLACK = os.path.join(DST, "_ai", "parts_black")
SAMPLES = ["hair_front/19m.png", "hair_front/21m.png", "hair_back/18m.png",
           "hair_front/20f.png", "hair_back/23f.png"]

import recolor_hair as RH


def metrics(v, al):
    """v: float32 明度图; al: alpha。返回 (高频, Laplacian, 标准差)。"""
    v = v.astype(np.float32)
    core = cv2.erode((al >= 250).astype(np.uint8), np.ones((3, 3), np.uint8)).astype(bool)
    if core.sum() < 300:
        return float("nan"), float("nan"), float("nan")
    vf = cv2.blur(v, (3, 3))
    hp = float(np.abs(v - vf)[core].mean())
    lap = float(np.abs(cv2.Laplacian(v, cv2.CV_32F))[core].mean())
    sd = float(v[core].std())
    return hp, lap, sd


def variants(v_src):
    """v_src: float [0,1] 明度。返回 {名称: 平滑后的 v}。"""
    u8 = (np.clip(v_src, 0, 1) * 255).astype(np.uint8)
    out = {"none(现状)": v_src}
    out["median3"] = cv2.medianBlur(u8, 3).astype(np.float32) / 255.0
    out["median5"] = cv2.medianBlur(u8, 5).astype(np.float32) / 255.0
    out["bilateral(5,25,25)"] = cv2.bilateralFilter(u8, 5, 25, 25).astype(np.float32) / 255.0
    out["bilateral(9,40,40)"] = cv2.bilateralFilter(u8, 9, 40, 40).astype(np.float32) / 255.0
    out["gauss0.8"] = cv2.GaussianBlur(u8, (3, 3), 0.8).astype(np.float32) / 255.0
    f32 = v_src.astype(np.float32)
    out["guided(11,1e-3)"] = cv2.ximgproc.guidedFilter(
        u8, (f32 * 255).astype(np.float32), 11, 1e-3).astype(np.float32) / 255.0 \
        if hasattr(cv2, "ximgproc") else None
    return {k: v for k, v in out.items() if v is not None}


def main():
    print("参考: 原版发件 高频≈0.011  Lap≈0.040  对比度(标准差)≈0.10")
    print()
    print("%-22s %-20s %8s %8s %8s" % ("样本", "去噪", "高频", "Lap", "对比度"))
    agg = {}
    for f in SAMPLES:
        src = os.path.join(BLACK, f)          # 用未映射的黑发原件做源
        if not os.path.exists(src):
            continue
        a = np.array(Image.open(src).convert("RGBA"))
        al = a[..., 3]
        v_src = (a[..., :3].astype(np.float32) / 255.0).max(axis=-1)
        for name, v_s in variants(v_src).items():
            v = RH.v_curve(v_s, al)
            hp, lap, sd = metrics(v, al)
            agg.setdefault(name, []).append((hp, lap, sd))
            print("%-22s %-20s %8.4f %8.4f %8.4f" % (f, name, hp, lap, sd))
        print()
    print("%-20s %8s %8s %8s" % ("方案(全样本中位)", "高频", "Lap", "对比度"))
    for name, vals in agg.items():
        arr = np.array(vals)
        print("%-20s %8.4f %8.4f %8.4f" % (name, np.median(arr[:, 0]), np.median(arr[:, 1]),
                                           np.median(arr[:, 2])))


if __name__ == "__main__":
    main()
