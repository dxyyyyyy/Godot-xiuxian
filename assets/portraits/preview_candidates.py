# -*- coding: utf-8 -*-
"""候选部件预览图：把「可补进捏脸」的部件叠到青年底稿上出对照表（先看图再决定是否导入）。

源: CharaGraphicMaker 角色图形合成器/Graphics 的 脸E(中年男)/脸F(中年女)/脸G(老年男)/脸H(老年女)
    服装 + 饰品/底层装饰；底稿用游戏现役的 脸C(青年男)/脸D(青年女)。
输出: _candidates/cloth_candidates.png  服装候选（含现役对照）
      _candidates/acc_candidates.png    发饰/装饰候选
用法: python preview_candidates.py
"""
import os
from PIL import Image, ImageDraw, ImageFont

SRC = r"E:\Game\CharaGraphicMaker\角色图形合成器\Graphics"
KIT_M = "脸C[青年男192x192]（キタカライ老师底稿）"
KIT_F = "脸D[青年女192x192]（キタカライ老师底稿）"
KIT_EM = "脸E[中年男192x192]（キタカライ老师底稿）"
KIT_EF = "脸F[中年女192x192]（キタカライ老师底稿）"
KIT_OM = "脸G[老年男192x192]（キタカライ老师底稿）"
KIT_OF = "脸H[老年女192x192]（キタカライ老师底稿）"
DST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_candidates")
FONT_PATH = r"C:\Windows\Fonts\msyh.ttc"
BG = (250, 245, 247, 255)
CELL, COLS = 150, 6

CURRENT_M = [(KIT_M, "服装", "打底衫浅"), (KIT_M, "服装", "打底衫深"), (KIT_M, "服装", "青年男和服"), (KIT_M, "服装", "青年男披风")]
CURRENT_F = [(KIT_F, "服装", "和服[素色]"), (KIT_F, "服装", "和服[花纹]"), (KIT_F, "服装", "和服2[素色]"),
             (KIT_F, "服装", "无袖中式〔藏青〕"), (KIT_F, "服装", "露胸中式有袖")]
CAND_M = [(KIT_EM, "服装", "和服[素色]"), (KIT_EM, "服装", "和服[花纹]"), (KIT_EM, "服装", "和服2[素色绿]"),
          (KIT_EM, "服装", "和服2[花纹]"), (KIT_OM, "服装", "长袍白")]
CAND_F = [(KIT_EF, "服装", "披肩[素色]"), (KIT_EF, "服装", "披肩[花纹]"), (KIT_EF, "服装", "简约上衣"),
          (KIT_OF, "服装", "素色和服[紫]"), (KIT_OF, "服装", "花纹和服[绿]"), (KIT_OF, "服装", "民族风服装"),
          (KIT_OF, "服装", "老奶奶服装")]
ACC_F = [(KIT_F, "饰品", "发带"), (KIT_F, "饰品", "发簪"), (KIT_F, "饰品", "头纱"), (KIT_F, "底层装饰", "护额"),
         (KIT_F, "底层装饰", "耳环[红]"), (KIT_F, "底层装饰", "珍珠项链"), (KIT_F, "底层装饰", "脸颊红晕"),
         (KIT_F, "底层装饰", "雀斑"), (KIT_F, "底层装饰", "追加鬓角"), (KIT_F, "饰品", "追加呆毛[棕]"),
         (KIT_F, "饰品", "追加麻花辫发型"), (KIT_F, "饰品", "追加丸子头发型"), (KIT_F, "饰品", "狐狸面具"),
         (KIT_F, "饰品", "冠冕")]
ACC_M = [(KIT_M, "底层装饰", "发箍"), (KIT_M, "饰品", "乱髭"), (KIT_M, "饰品", "伤痕累累"), (KIT_M, "饰品", "脸红")]


def load(path):
    if not os.path.exists(path):
        return None
    return Image.open(path).convert("RGBA")


def base_of(gender):
    kit = KIT_M if gender == "m" else KIT_F
    for n in ("青年底稿.png", "女性底稿.png"):
        p = os.path.join(SRC, kit, "基础层", n)
        if os.path.exists(p):
            return Image.open(p).convert("RGBA")
    return Image.new("RGBA", (192, 192), (0, 0, 0, 0))


def hair_of(gender):
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hair_front", "1%s.png" % gender)
    return load(p)


def compose(layers, size):
    c = Image.new("RGBA", (192, 192), (0, 0, 0, 0))
    for im in layers:
        if im is not None:
            c.alpha_composite(im)
    return c.resize((size, size), Image.LANCZOS)


def sheet(fname, title, groups, with_hair=False):
    """groups: [(组标题, gender('m'/'f'), [(kit, folder, stem), ...]), ...]"""
    font = ImageFont.truetype(FONT_PATH, 13)
    font_s = ImageFont.truetype(FONT_PATH, 15)
    rows = []
    for _gt, gender, items in groups:
        for kit, folder, stem in items:
            path = os.path.join(SRC, kit, folder, stem + ".png")
            if not os.path.exists(path):
                path = os.path.join(SRC, kit, folder, stem + "$.png")
            im = load(path)
            if im is None:
                print("  缺件:", kit[1:2], stem)
                continue
            layers = [base_of(gender)]
            if with_hair:
                layers.append(hair_of(gender))
            layers.append(im)
            rows.append(("%s·%s" % (kit[1:2], stem), compose(layers, CELL)))
    n_rows = max(1, (len(rows) + COLS - 1) // COLS)
    W = COLS * CELL
    H = 34 + n_rows * (CELL + 28)
    canvas = Image.new("RGB", (W, H), (34, 34, 40))
    dr = ImageDraw.Draw(canvas)
    dr.text((8, 8), title, font=font_s, fill=(255, 255, 255))
    for i, (label, im) in enumerate(rows):
        x, y = (i % COLS) * CELL, 30 + (i // COLS) * (CELL + 28)
        tile = Image.new("RGBA", (CELL, CELL), BG)
        tile.alpha_composite(im)
        canvas.paste(tile.convert("RGB"), (x, y))
        dr.text((x + 3, y + CELL + 5), label, font=font, fill=(226, 226, 232))
    os.makedirs(DST, exist_ok=True)
    out = os.path.join(DST, fname)
    canvas.save(out)
    print(out, len(rows), "件")


def main():
    sheet("cloth_candidates.png", "服装候选：先男(现役4+候选5)，后女(现役5+候选7)",
          [("现役男", "m", CURRENT_M), ("候选男", "m", CAND_M),
           ("现役女", "f", CURRENT_F), ("候选女", "f", CAND_F)])
    sheet("acc_candidates.png", "发饰/装饰候选：叠在底稿+现役第1件前发上（女 14 + 男 4）",
          [("女", "f", ACC_F), ("男", "m", ACC_M)], with_hair=True)


if __name__ == "__main__":
    main()
