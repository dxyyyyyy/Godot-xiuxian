# -*- coding: utf-8 -*-
"""AI 生成图 → 192x192 部件提取管线（试点）。
步骤: 水印修复 → 背景抠除 → 多尺度配准到垫图 → 差分+几何分区抠部件 → 清理 → 缩到192 → 校验合成图。
用法: python extract_part.py <base_192> <gen_1024> <out_png> <bg:magenta|white> [y_min]
"""
import os
import sys

import cv2
import numpy as np
from PIL import Image

DST = os.path.dirname(os.path.abspath(__file__))
S = 1024 / 192.0            # 缩放比
Y_MIN = 124                 # 192 空间: 服装只可能出现在这条线以下
MOUTH = (38, 110, 100, 150) # 192 空间: 脸中部保护区 (x0,y0,x1,y1), 防嘴/下巴重绘漏进部件
# 前发: 额头以上可取, 避开眉/眼/嘴三个保护区
BROWS = (26, 46, 108, 92)
EYES = (26, 66, 108, 106)
MOUTH2 = (44, 110, 98, 152)
WM_BOX = (830, 900, 1024, 1024)  # 水印角区(1024 空间)


def load_rgb(p):
    im = Image.open(p)
    if im.mode == "RGBA":   # 透明铺白, 避免 RGBA→RGB 变黑底
        bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
        bg.alpha_composite(im)
        im = bg
    im = im.convert("RGB")
    return np.array(im)


def kill_watermark(img):
    x0, y0, x1, y1 = WM_BOX
    box = img[y0:y1, x0:x1]
    gray = cv2.cvtColor(box, cv2.COLOR_RGB2GRAY)
    med = np.median(gray)
    mask = (gray > med + 25).astype(np.uint8) * 255
    mask = cv2.dilate(mask, np.ones((5, 5), np.uint8), iterations=2)
    if mask.any():
        box = cv2.inpaint(box, mask, 5, cv2.INPAINT_TELEA)
        img[y0:y1, x0:x1] = box
    return img


def fg_mask(img, mode):
    if mode == "magenta":
        d = np.abs(img.astype(int) - np.array([255, 0, 255])).sum(axis=2)
        return (d > 180).astype(np.uint8)
    # white: 从边缘洪水填充
    h, w = img.shape[:2]
    ff = img.copy()
    mask = np.zeros((h + 2, w + 2), np.uint8)
    cv2.floodFill(ff, mask, (0, 0), (0, 0, 0), (26, 26, 26), (26, 26, 26))
    return (~ff.astype(bool).all(axis=2)).astype(np.uint8)  # 填不到的=前景


def register(gen, ref, ref_fg1024):
    """多尺度边缘匹配: 把 gen 对齐到 ref 坐标系, 返回 warp 后的图与 fg。
    对画风/亮度差异稳健: Canny 边缘 + TM_CCORR_NORMED, 搜索窗限制在预期位置附近。"""
    tx0, ty0, tx1, ty1 = int(60 * S), int(10 * S), int(160 * S), int(120 * S)
    tmpl = cv2.Canny(cv2.cvtColor(ref[ty0:ty1, tx0:tx1], cv2.COLOR_RGB2GRAY), 80, 200)
    WIN = 180   # 允许的漂移半径(px @1024)
    best = None
    for sc in np.linspace(0.85, 1.15, 31):
        g = cv2.resize(gen, None, fx=sc, fy=sc, interpolation=cv2.INTER_LANCZOS4)
        gg = cv2.Canny(cv2.cvtColor(g, cv2.COLOR_RGB2GRAY), 80, 200)
        if gg.shape[0] < tmpl.shape[0] or gg.shape[1] < tmpl.shape[1]:
            continue
        r = cv2.matchTemplate(gg, tmpl, cv2.TM_CCORR_NORMED)
        r = np.nan_to_num(r, nan=-1, posinf=-1, neginf=-1)
        # 只保留预期落点附近的结果
        keep = np.full(r.shape, -1, np.float32)
        y_lo, y_hi = max(0, ty0 - WIN), min(r.shape[0], ty0 + WIN)
        x_lo, x_hi = max(0, tx0 - WIN), min(r.shape[1], tx0 + WIN)
        keep[y_lo:y_hi, x_lo:x_hi] = r[y_lo:y_hi, x_lo:x_hi]
        _, score, _, loc = cv2.minMaxLoc(keep)
        if best is None or score > best[0]:
            best = (score, sc, loc[0] - tx0, loc[1] - ty0)
    score, sc, dx, dy = best
    # ref 坐标 p → gen 坐标 q=(p-d)/s
    M = np.array([[1 / sc, 0, -dx / sc], [0, 1 / sc, -dy / sc]], np.float32)
    w = cv2.warpAffine(gen, M, (1024, 1024), flags=cv2.INTER_LANCZOS4, borderValue=(255, 255, 255))
    fgm = cv2.warpAffine(fg_mask(gen, MODE), M, (1024, 1024), flags=cv2.INTER_NEAREST, borderValue=0)
    print(f"  配准: score={score:.3f} scale={sc:.3f} offset=({dx},{dy})")
    return w, fgm


def main():
    global MODE
    base_p, gen_p, out_p, mode = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    MODE = mode
    kind = sys.argv[5] if len(sys.argv) > 5 else "cloth"   # cloth | hair_front | hair_back
    y_min = float(sys.argv[6]) if len(sys.argv) > 6 else Y_MIN

    ref = load_rgb(base_p)                      # 192 RGBA→RGB(透明铺白)
    im0 = Image.open(base_p)
    ref_a = np.array(im0.split()[-1]) if "A" in im0.getbands() else np.full((192, 192), 255, np.uint8)
    ref1024 = np.array(Image.fromarray(ref).resize((1024, 1024), Image.LANCZOS))
    ref_a1024 = np.array(Image.fromarray(ref_a).resize((1024, 1024), Image.NEAREST))
    gen = kill_watermark(load_rgb(gen_p))
    fgm_full = fg_mask(gen, mode)

    wimg, fgm = register(gen, ref1024, ref_a1024)
    fgm = cv2.erode(fgm, np.ones((5, 5), np.uint8))  # 去背景边缘色边(洋红/白晕)

    # --- 差分 + 几何分区 ---
    diff = np.abs(wimg.astype(int) - ref1024.astype(int)).sum(axis=2)
    H, W = diff.shape
    ys, xs = np.mgrid[0:H, 0:W]
    y192, x192 = ys / S, xs / S
    if kind == "hair_back":
        # 后发: 只取露出轮廓外的部分(被脸挡住的部分游戏里本来就在脸后)
        sil = cv2.dilate((ref_a1024 > 128).astype(np.uint8), np.ones((11, 11), np.uint8))
        zone = (sil == 0) & (y192 <= 176)
    elif kind == "hair_front":
        zone = (y192 <= 152)
        for a, b, c, d in (BROWS, EYES, MOUTH2):
            zone &= ~((x192 >= a) & (x192 <= c) & (y192 >= b) & (y192 <= d))
    else:
        mx0, my0, mx1, my1 = MOUTH
        zone = (y192 >= y_min)
        zone &= ~((x192 >= mx0) & (x192 <= mx1) & (y192 >= my0) & (y192 <= my1))
    mask = ((diff > 70) & (fgm > 0) & zone).astype(np.uint8)

    # --- 清理: 闭→开→保留所有面积足够的块(部件可能被保护区切成多块)→填洞 ---
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((7, 7), np.uint8))
    n, lab, stats, _ = cv2.connectedComponentsWithStats(mask, 8)
    keep = np.zeros_like(mask)
    for i in range(1, n):
        if stats[i, cv2.CC_STAT_AREA] > 400:
            keep[lab == i] = 1
    mask = keep
    for _ in range(3):  # 填洞
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((15, 15), np.uint8))
    # 羽化 1px
    alpha = cv2.GaussianBlur(mask * 255, (3, 3), 0)

    # --- 缩到 192 并落盘 ---
    part = cv2.resize(wimg, (192, 192), interpolation=cv2.INTER_AREA)
    a = cv2.resize(alpha, (192, 192), interpolation=cv2.INTER_AREA)
    rgba = np.dstack([part, a])
    os.makedirs(os.path.dirname(out_p), exist_ok=True)
    Image.fromarray(rgba, "RGBA").save(out_p)
    print("  部件 →", out_p, "遮罩覆盖率 %.1f%%" % (100 * (a > 128).mean()))

    # --- 校验合成图: 棋盘底 + 垫图 + 叠部件, 4x ---
    chk = np.zeros((192, 192, 3), np.uint8)
    for i in range(0, 192, 16):
        for j in range(0, 192, 16):
            chk[i:i + 16, j:j + 16] = 210 if (i // 16 + j // 16) % 2 else 160
    comp = chk.copy()
    af = a.astype(float)[..., None] / 255
    comp = (part * af + comp * (1 - af)).astype(np.uint8)
    zf = lambda im: cv2.resize(im, (384, 384), interpolation=cv2.INTER_NEAREST)
    panel = np.zeros((384, 384 * 3 + 20, 3), np.uint8)
    panel[:, :384] = zf(chk)
    panel[:, 384 + 10:768 + 10] = zf(ref)
    panel[:, 768 + 20:] = zf(comp)
    cv2.imwrite(out_p.replace(".png", "_check.png"), cv2.cvtColor(panel, cv2.COLOR_RGB2BGR))
    print("  校验图 → ", out_p.replace(".png", "_check.png"))


if __name__ == "__main__":
    main()
