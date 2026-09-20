# -*- coding: utf-8 -*-
"""把 AI 生成的纯黑发件映射成「可染」的中性暖棕发件。

背景
----
assets/portraits/recolor.gdshader 只做 色相旋转 + 彩度缩放, **明度不变**:
    hsv.x = fract(hsv.x + hue_shift)
    hsv.y = clamp(hsv.y * sat_scale, 0, 1)
纯黑发(V≈0.1)无论怎么转色相都还是黑的, 所以原版导入脚本才会把全部黑发件剔除。
AI 生成的发件全是黑发 -> 必须在贴图层面补一层「明度 / 彩度映射」, 先把黑发抬到
中间调并赋予基础彩度, 之后着色器才染得动。

映射设计
--------
1) 明度: 逐件做分位数归一化。每件取自身 V 的 p8/p50/p92 三个锚点, 线性拉伸到
   0.20 / 0.50 / 0.70。锚点取自原版「棕」发件实测: 描边≈0.14, 主体 0.45~0.64,
   高光 0.60~0.75。用逐件分位数而不是全局曲线, 是因为后发件整体比前发暗一档
   (中位 0.11 vs 0.19), 全局曲线会把后发压成近黑、和前发接不上。
2) 彩度: S = 0.54 - 0.20 * V, 夹到 [0.30, 0.58]。原版棕发 S≈0.43~0.52,
   金发更亮更淡 S≈0.32~0.43, 即「越亮越淡」。
3) 色相: H = 0.050 + 0.045 * t, t = (V-0.14)/0.66。暗部偏红棕(0.050, 男款实测值),
   亮部偏黄棕(0.090, 女款实测值), 中位 0.065 —— 一个中性暖棕, 往任意色相旋转都自然。

用法
----
python recolor_hair.py [--dry]
默认改写 _ai/parts/hair_*/; 首次运行会把原始黑发件备份到 _ai/parts_black/。
"""
import os
import shutil
import sys

import cv2
import numpy as np
from PIL import Image

DST = os.path.dirname(os.path.abspath(__file__))
PARTS = os.path.join(DST, "_ai", "parts")
BACKUP = os.path.join(DST, "_ai", "parts_black")

# 明度锚点: 源分位 -> 目标明度
SRC_PCT = (8, 50, 92)
DST_V = (0.20, 0.50, 0.70)
MIN_GAP = 0.02          # 锚点之间最小间隔, 防止分位重合导致除零/阶跃

# 彩度 / 色相随明度变化
S_A, S_B = 0.54, 0.20
S_LO, S_HI = 0.30, 0.58
H_LO, H_SPAN = 0.050, 0.045
V_LO, V_SPAN = 0.14, 0.66

# 去噪: 明度曲线会把源的细微噪声放大 1.5~2.7 倍(分位数归一化本质是拉伸对比度),
# 实测不做处理时 AI 发件高频噪点是原版的 3 倍(0.035 vs 0.011)。
# bilateral(9,40,40) 保边去噪后高频降到 0.013(原版 0.011), 且对比度不降(0.162 vs 原版 0.10)。
# 核太小(median3/bilateral5)压不下来, 高斯会糊掉发丝。
DENOISE_D, DENOISE_SC, DENOISE_SS = 9, 40, 40
SOLID = 250          # alpha 达到该值才算「实心」, 以下视为羽化边缘需延展


def hsv_to_rgb(h, s, v):
    """向量化 HSV->RGB, h/s/v 均为 [0,1] 的同形数组。"""
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


def v_curve(v_src: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    """按该件自身分位数把源明度拉伸到目标色阶。

    锚点只在 alpha>128 的不透明像素上统计: 透明区 RGB 通常是 0(透明黑),
    混进来会把分位数整体拉低, 导致映射偏暗。
    """
    m = alpha > 128
    vs = v_src[m] if m.any() else v_src
    lo = np.percentile(vs, SRC_PCT[0])
    mid = np.percentile(vs, SRC_PCT[1])
    hi = np.percentile(vs, SRC_PCT[2])
    lo = min(lo, mid - MIN_GAP)
    hi = max(hi, mid + MIN_GAP)
    lo = max(lo, 0.0)
    hi = min(max(hi, lo + MIN_GAP), 1.0)
    return np.interp(v_src, [lo, mid, hi], DST_V)


def denoise_v(v_src: np.ndarray) -> np.ndarray:
    """保边去噪: 压掉源图的随机噪点, 保留发丝结构。bilateral 对 uint8 输入。"""
    u8 = (np.clip(v_src, 0.0, 1.0) * 255.0).astype(np.uint8)
    return cv2.bilateralFilter(u8, DENOISE_D, DENOISE_SC, DENOISE_SS).astype(float) / 255.0


def bleed_v(v: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    """把实心区的明度延展到羽化/透明区。

    alpha 做了 1px 羽化但 RGB 没有, 羽化带上的 RGB 还掺着生成图背景(洋红/白),
    映射后会变成一圈偏亮或偏暗的杂边。用 inpaint 把邻近头发色推进去即可。
    """
    solid = alpha >= SOLID
    if solid.all() or not solid.any():
        return v
    hole = (~solid).astype(np.uint8)
    u8 = (np.clip(v, 0.0, 1.0) * 255.0).astype(np.uint8)
    filled = cv2.inpaint(u8, hole, 3, cv2.INPAINT_TELEA).astype(float) / 255.0
    return np.where(solid, v, filled)


def map_hair(im: Image.Image) -> np.ndarray:
    rgba = np.array(im.convert("RGBA"))
    rgb = rgba[..., :3].astype(float) / 255.0
    v_src = denoise_v(rgb.max(axis=-1))
    v = v_curve(v_src, rgba[..., 3])
    v = bleed_v(v, rgba[..., 3])
    s = np.clip(S_A - S_B * v, S_LO, S_HI)
    h = H_LO + H_SPAN * np.clip((v - V_LO) / V_SPAN, 0.0, 1.0)
    out = np.clip(hsv_to_rgb(h, s, v) * 255.0, 0, 255).astype(np.uint8)
    res = np.dstack([out, rgba[..., 3]])
    return res


def stats(arr):
    """返回 (V p5, V p50, V p95, S 中位, H 中位)。"""
    rgb = arr[..., :3].astype(float) / 255.0
    a = arr[..., 3]
    m = a > 128
    if not m.any():
        return (0.0, 0.0, 0.0, 0.0, 0.0)
    c = rgb[m]
    v = c.max(axis=-1)
    mn = c.min(axis=-1)
    s = np.where(v > 0.02, (v - mn) / np.maximum(v, 1e-6), 0.0)
    d = v - mn
    sel = d > 0.05
    h_med = 0.0
    if sel.any():
        r, g, b = c[sel, 0], c[sel, 1], c[sel, 2]
        mx = v[sel]
        dd = d[sel]
        h = np.where(mx == r, ((g - b) / np.maximum(dd, 1e-6)) % 6,
            np.where(mx == g, (b - r) / np.maximum(dd, 1e-6) + 2,
                     (r - g) / np.maximum(dd, 1e-6) + 4)) / 6.0
        h_med = float(np.median(h))
    return (float(np.percentile(v, 5)), float(np.percentile(v, 50)),
            float(np.percentile(v, 95)), float(np.median(s)), h_med)


def main():
    dry = "--dry" in sys.argv
    for slot in ("hair_front", "hair_back"):
        d = os.path.join(PARTS, slot)
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.lower().endswith(".png"):
                continue
            p = os.path.join(d, fn)
            before = np.array(Image.open(p).convert("RGBA"))
            after = map_hair(Image.open(p))
            b0 = stats(before)
            a0 = stats(after)
            print(f"{slot}/{fn}")
            print(f"   V p5/p50/p95  {b0[0]:.2f}/{b0[1]:.2f}/{b0[2]:.2f}"
                  f"  ->  {a0[0]:.2f}/{a0[1]:.2f}/{a0[2]:.2f}")
            print(f"   S 中位 {b0[3]:.2f} -> {a0[3]:.2f}    H 中位 {b0[4]:.3f} -> {a0[4]:.3f}")
            if not dry:
                bk = os.path.join(BACKUP, slot)
                os.makedirs(bk, exist_ok=True)
                bp = os.path.join(bk, fn)
                if not os.path.exists(bp):
                    shutil.copyfile(p, bp)
                Image.fromarray(after, "RGBA").save(p)
    if dry:
        print("\n(--dry 未写入)")


if __name__ == "__main__":
    main()
