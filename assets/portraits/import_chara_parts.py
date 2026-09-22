# -*- coding: utf-8 -*-
"""
CharaGraphicMaker(グラフィック合成器)部件 → 百味长生捏脸系统 导入脚本。

源: E:\\Game\\CharaGraphicMaker\\角色图形合成器\\Graphics\\脸C(青年男)/脸D(青年女)/脸A(幼儿)/脸B(少年)
    脸B 少年件并入 male/female 成年组末尾(脸型底稿不并入, 显示名带「(少年)」); 脸A 独立成 kid 组。
目标约定:
  assets/portraits/<slot>/<n>m.png(男/脸C) <n>f.png(女/脸D) <n>k.png(幼儿/脸A), 1 基序号;
  同名 $ 配对图存为 <n>{m,f,k}_back.png(背面层)。
  assets/portraits/catalog.json —— 每性别每槽位的部件目录(id/显示名/序号/肤色/发色/背面图),
  portrait.gd 与 NpcGenerator 均以此为单一数据源。

图层实测结论(与 Setting.txt 第三参数一致, 见会话记录):
  饰品$=-1 → 后发$/前发$=0(垫脸后) → 基础层=1 → 底饰$=2 → 服装=3 → 后发=6
  → 耳朵=7 → 眼睛$=8 → 眼睛=9 → 眉毛/嘴巴=10 → 底层装饰=11 → 前发=12 → 饰品=13

用法: python import_chara_parts.py            # 全量重导(先清空已生成目录)
      python import_chara_parts.py --preview  # 只重出校验图, 不动部件
"""
import json
import math
import os
import random
import re
import shutil
import sys

from PIL import Image, ImageDraw

SRC_ROOT = r"E:\Game\CharaGraphicMaker\角色图形合成器\Graphics"
KIT_M = "脸C[青年男192x192]（キタカライ老师底稿）"
KIT_F = "脸D[青年女192x192]（キタカライ老师底稿）"
KIT_K = "脸A[幼儿192x192]（キタカライ老师底稿）"
KIT_T = "脸B[少年192x192]（キタカライ老师底稿）"
KITS = (("male", "m", KIT_M), ("female", "f", KIT_F), ("kid", "k", KIT_K))
DST = os.path.dirname(os.path.abspath(__file__))          # .../assets/portraits
PREVIEW = r"E:\Game\CharaGraphicMaker\_import_preview"

# 素材文件夹 → 游戏槽位(底层装饰/decor 与 饰品/acc 槽已按需求废弃, 不再导入)
SLOT_MAP = {
    "基础层": "face", "前发": "hair_front", "后发": "hair_back", "眉毛": "brows",
    "眼睛": "eyes", "嘴巴": "mouth", "耳朵": "ears", "服装": "cloth",
}
SLOT_CN = {
    "face": "脸型", "brows": "眉", "eyes": "眼", "mouth": "嘴", "ears": "耳",
    "hair_front": "前发", "hair_back": "后发", "cloth": "服装", "aura": "气质",
}
SLOT_DEPTH = {"face": 1, "cloth": 3, "hair_back": 6, "ears": 7, "eyes": 9,
              "brows": 10, "mouth": 10, "hair_front": 12}
BACK_DEPTH = {"hair_back": 0, "hair_front": 0, "eyes": 8}
RENDER_ORDER = ["face", "cloth", "hair_back", "ears", "eyes", "brows", "mouth", "hair_front"]

# 跑题/破损部件黑名单(子串匹配原文件名)
BLACKLIST = ["骷髅", "宇航服", "电动装甲", "变身", "科幻", "机器人风", "猫耳终端",
             "[H]", "涂鸦", "瞄准镜", "面·般若", "网眼"]
# 仙侠古风清洗: 现代/西式/科幻服饰与道具(子串匹配, 仅作用于 cloth 槽; acc/decor 槽已废弃)
STYLE_BLACKLIST = [
    "T恤", "衬衫", "西装", "领带", "丝绸礼帽", "围裙", "羽绒", "针织", "长领", "高领",
    "马甲", "魔术师", "修女", "兔女郎", "女仆", "军服", "睡衣", "丝带", "礼裙", "联邦",
    "内衣", "泳装", "背心", "冰之棺", "女武神", "小熊", "泰迪熊", "魔女帽子", "口罩",
    "眼镜", "泳镜", "神秘战士盔", "意式头盔",
    # 幼儿套(cloth)清洗: 现代童装(泳装/园服/水手领/背带/无袖)
    "死库水", "水手", "背带裤", "幼儿园", "无袖",
    # 少年套(cloth)清洗: 现代休闲(V领/连帽衫/颈绳/吊裤带)与机甲
    "V领", "连帽衫", "颈绳", "吊裤带", "装甲",
    # 服装槽二轮严选: 蒙面紧身衣/欧式甲胄/西式立领裙装(和服类因交领长袍剪影保留, 见 NAME_OVERRIDES)
    "打底衫2", "漆黑铠", "甲胄", "量产铠", "板链甲", "铁铠", "锁子甲", "黄金铠", "铠甲",
    "面罩披风", "古典服装", "服装[紫]", "雅致服装",
]
STYLE_SLOTS = {"cloth"}
# 脸槽专属清洗(幼儿套基础层里混有拆件/废稿): 头顶补件、空底、痕迹杂图
FACE_CLEAN = ["痕迹", "上头", "（无）", "(无)"]
# 显示名映射(id 不变, 仅 UI 名): 和服→交领/广袖袍, 打底衫→中衣, 去日式/现代词
NAME_OVERRIDES = {
    "青年男和服": "交领长袍",
    "和服": "交领袍",
    "和服[素色]": "交领袍[素色]", "和服[花纹]": "交领袍[花纹]",
    "和服2[素色]": "广袖袍[素色]", "和服2[花纹]": "广袖袍[花纹]",
    "打底衫浅": "素色中衣", "打底衫深": "深色中衣",
    "青年男披风": "赤色披风",
}

# 前缀剥离: 单数字或画师标记字母, 且后随 CJK/〔/[ 才算前缀(保护 T恤/EX2 这类词)
PREFIX_RE = re.compile(r"^([0-9]|[cChiknosSDE])(?=[一-鿿〔\[])")
TAG_RE = re.compile(r"[〔\[]([^〔〕\[\]]+)[〕\]]")
HAIR_COLORS = ["浅棕", "棕", "金", "黑", "蓝", "绿", "红", "白", "灰", "银", "粉", "紫", "藏青"]
# 发件只留棕系: 无标签件(默认画稿即棕色) + 棕/浅棕; 金灰粉蓝红白金等彩色件全部排除
HAIR_BROWN = {"", "棕", "浅棕"}
# 深棕按需求亦排除(子串匹配发件 stem): 脸B 的「(深)」与「[深棕]」两款
HAIR_DARK = ["深棕", "(深)", "（深）"]


def blacklist_hit(stem: str) -> str:
    for k in BLACKLIST:
        if k in stem:
            return k
    return ""


def hair_is_brown(path: str) -> bool:
    """发件棕画稿像素闸: 主色相圆均值落棕域 12~50° 且有彩度占比。
    标签过滤挡不住未标注的银白/灰黑/粉红画稿, 按像素兜底。"""
    if not os.path.exists(path):
        return False
    im = Image.open(path).convert("RGBA")
    rgba = list(im.getdata())
    hsv = list(im.convert("HSV").getdata())
    opaque = chroma = 0
    cs = sn = 0.0
    for (_r, _g, _b, a), (h, s, v) in zip(rgba, hsv):
        if a <= 128:
            continue
        opaque += 1
        if s > 40 and v > 40:   # 有效彩像素(0-255 域): 排除近黑/近灰
            chroma += 1
            ang = h / 255.0 * 2.0 * math.pi
            cs += math.cos(ang)
            sn += math.sin(ang)
    if opaque == 0 or chroma < opaque * 0.15:
        return False            # 银白/灰/黑系画稿
    hue = math.degrees(math.atan2(sn / chroma, cs / chroma)) % 360.0
    return 12.0 <= hue <= 50.0  # 棕域(金发>50 已按标签先行排除, 此处再兜未标注的)


def skin_of(stem: str) -> str:
    if "肤色黑" in stem or "深肤" in stem:
        return "black"
    if stem.startswith("暗色") and "[美白]" not in stem:
        return "black"
    return "white"


def color_of(stem: str) -> str:
    for tag in TAG_RE.findall(stem):
        if tag in HAIR_COLORS:
            return tag
    return ""


def base_name(name: str) -> str:
    """耳朵同形不同肤色的归组键: 去肤色词与括号标注(含全角括号, 幼儿套用「(深肤色用)」)。"""
    b = name.replace("肤色白", "").replace("肤色黑", "").replace("[美白]", "")
    b = unbracket(b)
    return b.strip()


def unbracket(b: str) -> str:
    return re.sub(r"[〔\[（(][^〔〕\[\]（）()]*[〕\]）)]", "", b)


def scan_kit(kit: str) -> dict:
    """扫一个套件 → {slot: [entry...]}; entry 含 id/name/n/back/back_only/color/skin/base/src。"""
    per_slot = {}
    for folder, slot in SLOT_MAP.items():
        d = os.path.join(SRC_ROOT, kit, folder)
        stems = {}          # 去掉 $ 后的 stem → {"plain":bool,"back":bool}
        order = []
        for fn in sorted(os.listdir(d)):
            if not fn.lower().endswith(".png"):
                continue
            raw = fn[:-4]
            back = raw.endswith("$")
            stem = raw[:-1] if back else raw
            if blacklist_hit(raw):
                continue
            if slot in STYLE_SLOTS and any(k in raw for k in STYLE_BLACKLIST):
                continue
            if slot == "face" and any(k in raw for k in FACE_CLEAN):
                continue
            if slot == "ears" and "普通耳" not in stem:
                continue    # 耳朵只保留默认人耳(普通耳系列)
            if slot in ("hair_front", "hair_back") and color_of(stem) not in HAIR_BROWN:
                continue    # 发只留棕色系(含无标签原棕画稿), 其余彩发按需求排除
            if slot in ("hair_front", "hair_back") and any(k in raw for k in HAIR_DARK):
                continue    # 深棕排除(亮度分布与棕连续, 只能按命名闸)
            if stem not in stems:
                stems[stem] = {"plain": False, "back": False}
                order.append(stem)
            stems[stem]["back" if back else "plain"] = True
        entries = []
        for stem in order:
            s = stems[stem]
            if not s["plain"] and slot == "cloth":
                continue    # 服装必须正面件(背面-only 会画空)
            if slot in ("hair_front", "hair_back"):
                probe = os.path.join(d, stem + (".png" if s["plain"] else "$.png"))
                if not hair_is_brown(probe):
                    continue    # 只留棕画稿(无标签不等于棕色: 银白/粉红旗稿像素兜底剔除)
            name = NAME_OVERRIDES.get(stem, PREFIX_RE.sub("", stem))
            e = {
                "id": stem, "name": name, "n": len(entries) + 1,
                "back": s["back"], "back_only": not s["plain"],
                "color": color_of(stem) if slot in ("hair_front", "hair_back") else "",
                "skin": skin_of(stem),
                "src": f"{folder}/{stem}",   # 原件 = src+".png", 背面件 = src+"$.png"
            }
            if slot == "ears":
                e["base"] = base_name(name)
            entries.append(e)
        per_slot[slot] = entries
    return per_slot


def merge_teen(base: dict, teen: dict) -> dict:
    """把脸B(少年)件续接进成年组末尾(序号接排, 既有件序号不动)。
    规则: 基础层(脸型)不并入(按需求只留成年底稿); 同 id 成年件优先; 耳朵同形同肤去重; 显示名加「(少年)」。"""
    for slot, entries in teen.items():
        if slot not in base or slot == "face":
            continue
        have = {e["id"] for e in base[slot]}
        have_ear = {(e.get("base", ""), e["skin"]) for e in base.get("ears", [])}
        nxt = max((e["n"] for e in base[slot]), default=0)
        for e in entries:
            if e["id"] in have:
                continue
            if slot == "ears" and (e.get("base", ""), e["skin"]) in have_ear:
                continue
            nxt += 1
            e["n"] = nxt
            e["name"] = e["name"] + "(少年)"
            e["kit_src"] = KIT_T   # 写入/回拷时按脸B目录取原图(不随所在组目录)
            base[slot].append(e)
            have.add(e["id"])
    return base


def load_ai_parts() -> dict:
    """AI 生成部件清单(_ai/parts.json) → {gender: {slot: [entry...]}}; 序号接在原版件之后。"""
    mf = os.path.join(DST, "_ai", "parts.json")
    if not os.path.exists(mf):
        return {}
    manifest = json.load(open(mf, encoding="utf-8"))
    out = {}
    for g, suffix in (("male", "m"), ("female", "f")):
        out[g] = {}
        for item in manifest.get(g, []):
            slot = item["slot"]
            entries = out[g].setdefault(slot, [])
            n = len(entries) + 1
            entries.append({
                "id": f"AI_{item['name']}", "name": item["name"], "n": n,
                "back": item.get("back", False), "back_only": False,
                "color": item.get("color", ""), "skin": "white",
                "src": f"_ai/parts/{item['file']}",   # DST 相对路径(文件名自带序号)
            })
    return out


def write_parts(catalog: dict) -> None:
    for g, suffix, kit in KITS:
        for slot, entries in catalog[g].items():
            os.makedirs(os.path.join(DST, slot), exist_ok=True)
            for e in entries:
                if e["src"].startswith("_ai/"):          # AI 件: 从持久目录复制
                    shutil.copyfile(os.path.join(DST, e["src"]),
                                    os.path.join(DST, slot, f"{e['n']}{suffix}.png"))
                    continue
                kit_root = e.get("kit_src", kit)   # 少年并入件: 原图在脸B目录
                if not e["back_only"]:
                    shutil.copyfile(os.path.join(SRC_ROOT, kit_root, e["src"] + ".png"),
                                    os.path.join(DST, slot, f"{e['n']}{suffix}.png"))
                if e["back"] or e["back_only"]:
                    shutil.copyfile(os.path.join(SRC_ROOT, kit_root, e["src"] + "$.png"),
                                    os.path.join(DST, slot, f"{e['n']}{suffix}_back.png"))
    for old in ("hair",):   # 旧空目录清理
        p = os.path.join(DST, old)
        if os.path.isdir(p) and not os.listdir(p):
            os.rmdir(p)


# ---------------- 校验图 ----------------
BG = (96, 128, 96, 255)


def compose(parts, suffix, size=192):
    """parts: [(slot, entry)];按实测层级(表/背)叠成整脸。"""
    canvas = Image.new("RGBA", (192, 192), (0, 0, 0, 0))
    layers = []
    for slot, e in parts:
        if not e.get("back_only"):
            layers.append((SLOT_DEPTH[slot], os.path.join(DST, slot, f"{e['n']}{suffix}.png")))
        if e.get("back") or e.get("back_only"):
            layers.append((BACK_DEPTH.get(slot, 0), os.path.join(DST, slot, f"{e['n']}{suffix}_back.png")))
    for _, path in sorted(layers, key=lambda x: x[0]):
        canvas.alpha_composite(Image.open(path).convert("RGBA"))
    return canvas.resize((size, size), Image.LANCZOS)


def sheet_thumbs(catalog, g, suffix):
    rows = []
    for slot in RENDER_ORDER:
        es = catalog[g][slot]
        for i in range(0, len(es), 16):
            rows.append((slot, es[i:i + 16]))
    H = len(rows) * 78 + 20
    im = Image.new("RGB", (16 * 64 + 90, H), (34, 34, 40))
    dr = ImageDraw.Draw(im)
    y = 10
    for slot, es in rows:
        dr.text((4, y + 24), f"{SLOT_CN[slot]}\n{len(catalog[g][slot])}件", fill=(230, 230, 230))
        for j, e in enumerate(es):
            fn = f"{e['n']}{suffix}_back.png" if e["back_only"] else f"{e['n']}{suffix}.png"
            t = Image.open(os.path.join(DST, slot, fn)).convert("RGBA")
            tile = Image.new("RGBA", (64, 64), BG)
            tile.alpha_composite(t.resize((64, 64), Image.LANCZOS))
            im.paste(tile.convert("RGB"), (90 + j * 64, y))
        y += 78
    im.save(os.path.join(PREVIEW, f"thumbs_{g}.png"))


def sheet_combos(catalog, g, suffix, n=12, seed=7):
    rng = random.Random(seed)
    cols, size = 6, 128
    rows = (n + cols - 1) // cols
    im = Image.new("RGB", (cols * size, rows * size), (34, 34, 40))
    for k in range(n):
        face = rng.choice(catalog[g]["face"])
        hair_c = rng.choice(["", "", "棕", "金", "浅棕"])
        hf = rng.choice([e for e in catalog[g]["hair_front"] if not hair_c or e["color"] in ("", hair_c)])
        hb = rng.choice([e for e in catalog[g]["hair_back"] if not hair_c or e["color"] in ("", hair_c)]
                        or catalog[g]["hair_back"])
        parts = [("face", face), ("cloth", rng.choice(catalog[g]["cloth"])),
                 ("hair_back", hb), ("hair_front", hf),
                 ("eyes", rng.choice(catalog[g]["eyes"])),
                 ("brows", rng.choice(catalog[g]["brows"])),
                 ("mouth", rng.choice(catalog[g]["mouth"]))]
        ears = [e for e in catalog[g]["ears"] if e["skin"] == face["skin"]]
        if ears and rng.random() < 0.5:
            parts.append(("ears", rng.choice(ears)))
        cell = compose(parts, suffix, size)
        tile = Image.new("RGBA", (size, size), BG)
        tile.alpha_composite(cell)
        im.paste(tile.convert("RGB"), ((k % cols) * size, (k // cols) * size))
    im.save(os.path.join(PREVIEW, f"combos_{g}.png"))


def main():
    preview_only = "--preview" in sys.argv
    catalog = {g: scan_kit(kit) for g, _sfx, kit in KITS}
    # 脸B(少年)件并入成年组(脸型底稿除外)
    catalog["male"] = merge_teen(catalog["male"], scan_kit(KIT_T))
    catalog["female"] = merge_teen(catalog["female"], scan_kit(KIT_T))
    os.makedirs(PREVIEW, exist_ok=True)
    if not preview_only:
        ai = load_ai_parts()
        for g in catalog:
            for slot, entries in ai.get(g, {}).items():
                base_n = max((e["n"] for e in catalog[g].get(slot, [])), default=0)
                for i, e in enumerate(entries, 1):
                    e["n"] = base_n + i
                catalog[g][slot] = catalog[g].get(slot, []) + entries
        for slot in list(SLOT_MAP.values()) + ["decor", "acc"]:   # 废弃槽一并清残留
            p = os.path.join(DST, slot)
            if not os.path.isdir(p):
                continue
            # 只删 .png / .godot 缓存清单, 保留 *.import 侧车(否则 Godot 需整库重导, 运行期纹理全空)
            for fn in os.listdir(p):
                if fn.lower().endswith((".png", ".tmp")):
                    os.remove(os.path.join(p, fn))
        write_parts(catalog)
        with open(os.path.join(DST, "catalog.json"), "w", encoding="utf-8") as f:
            json.dump(catalog, f, ensure_ascii=False, indent=1)
    for g, suffix, _kit in KITS:
        sheet_thumbs(catalog, g, suffix)
        sheet_combos(catalog, g, suffix)
    total = sum(len(v) for g in catalog for v in catalog[g].values())
    print("== 导入统计 ==")
    for g, _sfx, _kit in KITS:
        row = "  ".join(f"{SLOT_CN[s]}:{len(catalog[g][s])}" for s in RENDER_ORDER)
        print(f"{g:6s} {row}")
    print(f"合计部件 {total} 件 → {DST}")
    bad = []
    for slot in SLOT_MAP.values():
        d = os.path.join(DST, slot)
        if not os.path.isdir(d):
            continue
        for fn in os.listdir(d):
            if fn.endswith(".png") and Image.open(os.path.join(d, fn)).size != (192, 192):
                bad.append(f"{slot}/{fn}")
    print("非192x192:", bad if bad else "无")


if __name__ == "__main__":
    main()
