# -*- coding: utf-8 -*-
# 捏脸系统成套出图助手：纸娃娃分层件 40 件（face/hair/eyes/cloth ×5 × 男女两版）
# + 搭配预览成妆图 8 张（覆盖全部部件取值，供捏脸UI预设/宣传/拼合验收），
# 产出 face_prompts.md + face_batch.json。
# 用法: cd assets/portraits && python gen_face.py            # 仅生成清单与提示词
#       python gen_face.py --api      # 设了 OPENAI_API_KEY 时逐件调接口(否则仅打印)
#       python gen_face.py --api --dry  # 只演示将发送的请求
# 注意: 部件池顺序必须与 sim/NpcGenerator.gd 的 FACES/HAIRS/EYES/CLOTHS 逐字一致，
#       顺序 = 文件序号(<slot>/<n>[m|f].png)，改序会错位运行时 portrait.gd 的图层。
import sys, json, io, os

FACES = ["鹅蛋脸", "剑客脸", "圆脸", "清瘦面", "丰润面"]
HAIRS = ["高马尾", "垂鬓", "束发", "披发", "双丫髻"]
EYES  = ["琥珀瞳", "墨瞳", "浅褐瞳", "灰蓝瞳", "绯瞳"]
CLOTHS= ["靛青布衣", "月白衫", "玄色劲装", "藕荷襦裙", "灰褐短打"]
# aura 不出图：运行时 portrait.gd 画背景色底圆盘（色值同步 AURA_COLOR）
AURAS = {"疏懒": "#f59e0b", "清冷": "#38bdf8", "热络": "#f472b6", "拘谨": "#9ca3af", "悠然": "#2dd4bf"}

FACE_DESC = {"鹅蛋脸": "oval soft face", "剑客脸": "sharp angular swordsman face, keen brows",
             "圆脸": "round friendly face", "清瘦面": "lean long face", "丰润面": "full plump face"}
HAIR_DESC = {"高马尾": "high ponytail", "垂鬓": "loose side-locks", "束发": "tied-up topknot",
             "披发": "long flowing loose hair", "双丫髻": "twin buns"}
EYE_DESC  = {"琥珀瞳": "amber eyes", "墨瞳": "ink-black eyes", "浅褐瞳": "light-brown eyes",
             "灰蓝瞳": "grey-blue eyes", "绯瞳": "crimson eyes"}
CLOTH_DESC= {"靛青布衣": "indigo coarse cloth robe", "月白衫": "pale moon-white robe",
             "玄色劲装": "black fitted martial garb", "藕荷襦裙": "lotus-root pink ruqun dress",
             "灰褐短打": "grey-brown short working jacket"}

STYLE_PART = ("Chinese xianxia cultivation game character portrait, front-facing centered bust, soft cel-shaded "
              "illustration, clean thick outlines, gentle rim light, isolated on transparent background PNG, "
              "same head position and scale across the whole set, high detail, no text, no watermark")
NEG_PART = "photorealistic, 3d, text, watermark, blurry, extra limbs, gore, horror, different head size, off-center"
STYLE_LOOK = ("Chinese xianxia cultivation game character portrait, front-facing head, soft cel-shaded illustration, "
              "clean thick outlines, gentle rim light, plain pastel background, otome art style, high detail, no text, no watermark")
NEG_LOOK = "photorealistic, 3d render, text, watermark, logo, extra limbs, deformed hands, gore, horror, nsfw, busy background, transparent background"

GENDER_CN = {"m": "男相", "f": "女相"}
GENDER_EN = {"m": "masculine features, short practical hairstyle", "f": "feminine features, softer jaw and skin"}

# (key, 名称, gender, face, hair, eyes, cloth, aura, 一句话人设, 英文vibe)
PRESETS = [
 ("qingleng_shijie", "清冷小师姐", "f", "鹅蛋脸", "束发",   "琥珀瞳", "月白衫",   "清冷",
  "仙门内门弟子，眉眼清淡、脊背挺直", "calm aloof inner-sect senior sister"),
 ("ruannuo_shimei",  "软糯小师妹", "f", "圆脸",   "双丫髻", "浅褐瞳", "藕荷襦裙", "热络",
  "灶房帮工的小姑娘，笑起来有两个酒窝", "sweet round-faced junior sister with a warm giggle"),
 ("shaonian_jianke", "少年剑客",   "m", "剑客脸", "高马尾", "墨瞳",   "玄色劲装", "清冷",
  "掬霜峰俗家弟子，眉头总像压着一缕剑意", "sharp young swordsman, brows edged like a blade"),
 ("shulan_sanshi",   "疏懒散修",   "m", "清瘦面", "披发",   "灰蓝瞳", "靛青布衣", "疏懒",
  "坊市挂牌算命的游方道人，眼皮半抬", "languid roguish wanderer with half-lidded eyes"),
 ("zaoxia_tuzi",     "灶下徒弟",   "m", "丰润面", "高马尾", "琥珀瞳", "灰褐短打", "悠然",
  "百味宗外门烧火小子，脸颊沾了点面粉", "cheerful kitchen apprentice, flour-smudged cheeks"),
 ("humei_shangfan",  "狐媚商贩",   "f", "鹅蛋脸", "垂鬓",   "绯瞳",   "藕荷襦裙", "热络",
  "妖族行商，眼波流转、笑意不达眼底", "sly demon-folk merchant, crimson knowing eyes"),
 ("nongjia_zi",      "灵田农家子", "m", "圆脸",   "高马尾", "浅褐瞳", "灰褐短打", "悠然",
  "药田里长大的憨实少年，袖口卷到肘", "honest farm-born youth with rolled sleeves"),
 ("gujin_yaotong",   "拘谨药童",   "f", "清瘦面", "垂鬓",   "墨瞳",   "靛青布衣", "拘谨",
  "药商家世的小学徒，见人先低头半步", "timid apothecary apprentice, chin slightly lowered"),
]

def part_prompts():
    """40 件分层零件：face 为不透明基准底头，其余透明底叠加层。"""
    out = []
    slots = [("face", FACES, FACE_DESC), ("hair", HAIRS, HAIR_DESC),
             ("eyes", EYES, EYE_DESC), ("cloth", CLOTHS, CLOTH_DESC)]
    for slot, arr, dmap in slots:
        for i, val in enumerate(arr, start=1):
            d = dmap.get(val, val)
            if slot == "face":
                core_zh = ("基准底头·正面居中胸像，一张%s的底脸，中性平静表情，五官清晰，肤色自然，"
                           "含颈部与少量肩，完整不透明底图（本件定义头位与构图，其余层以此对齐）" % val)
                core_en = ("base front-facing bust portrait head: %s, neutral calm expression, clear features, "
                           "natural skin, neck and a bit of shoulder, fully opaque base image that defines "
                           "head position and composition for the whole set" % d)
            elif slot == "hair":
                core_zh = "发型叠加层·以标准正脸底图为准，只绘制【%s】发型，头顶与两侧，脸部位置与大小完全不变，其余全透明" % val
                core_en = "hair layer only: %s, sitting on the SAME standard head template, face untouched, everything else transparent" % d
            elif slot == "eyes":
                core_zh = "眼睛叠加层·透明底，仅绘制一双【%s】，双眼居中落在标准眼位线上，位置严格统一" % val
                core_en = "eyes layer only, transparent bg: %s, positioned on the fixed standard eye line" % d
            else:
                core_zh = "衣装叠加层·透明底，仅绘制【%s】的肩颈与领口，向上衔接下巴，其余全透明" % val
                core_en = "clothing/shoulders layer only, transparent bg: %s, collar under the chin, rest transparent" % d
            for g in ("m", "f"):
                out.append({"file": "%s/%d%s.png" % (slot, i, g), "kind": "分层零件·%s·%s" % (slot, GENDER_CN[g]),
                            "size": "512x512", "index": i, "value": val,
                            "zh": core_zh + "（%s版：%s）" % (GENDER_CN[g], "骨相硬朗、喉结/鬓角" if g == "m" and slot == "face" else
                                                              ("发式利落、无饰件" if g == "m" else ("骨相柔和、下颌收细" if slot == "face" else "发式与饰件偏柔美"))),
                            "en": core_en + ". " + GENDER_EN[g],
                            "ref": "" if slot == "face" else "face/%d%s.png" % (i, g)})
    return out

def look_prompts():
    """8 张搭配预览成妆图：完整胸像、纯色浅底，供捏脸UI预设/宣传/验收。"""
    out = []
    for key, name, g, face, hair, eyes, cloth, aura, zh_line, en_vibe in PRESETS:
        zh = ("捏脸预设·%s（%s，气质%s%s）：%s，%s、%s、%s，着%s，正面完整胸像成妆图，中性浅底"
              % (name, GENDER_CN[g], aura, AURAS[aura], zh_line, face, eyes, hair, cloth))
        en = ("complete front-facing bust portrait, preset look '%s' (%s): %s with %s and %s, wearing %s, "
              "all features drawn together, %s" % (name, en_vibe, FACE_DESC[face], EYE_DESC[eyes],
              HAIR_DESC[hair], CLOTH_DESC[cloth], GENDER_EN[g]))
        out.append({"file": "look/%s.png" % key, "kind": "搭配预览", "size": "1:1",
                    "zh": zh, "en": en + ". " + STYLE_LOOK, "ref": ""})
    return out

def emit(batch_api):
    items = part_prompts() + look_prompts()
    md = ["# 《百味长生》捏脸系统出图提示词（40 分层零件 + 8 搭配预览）\n",
          "> 零件 = 纸娃娃可叠加层；预览 = 完整成妆胸像（不进运行时，供UI预设/宣传/拼合验收）。\n",
          "## 叠绘与命名（portrait.gd 约定）",
          "1. 叠绘底→顶：`cloth → face → eyes → hair`；aura 不出图，运行时画背景色底圆盘：",
          "   " + "、".join("%s %s" % (k, v) for k, v in AURAS.items()) + "；",
          "2. 文件名 `<slot>/<序号>[m|f].png`，序号与 NpcGenerator.gd 的 FACES/HAIRS/EYES/CLOTHS **顺序一致、不可错位**；",
          "3. 全部 **512×512、头居中、透明背景 PNG**（face 件为不透明底图，出图后其余层垫它对齐；接口出图可 1024×1024 再缩到 512）。\n",
          "## 对齐铁律（决定任意 5×5×5×5 组合能不能拼上）",
          "1. **先出 10 张 `face/<i>[m|f].png` 基准底头并定稿**，它定义头位与构图；",
          "2. hair/eyes/cloth 一律**垫同序号同性别的底脸图生图（锁同一 seed、同尺寸、同构图）**，只换对应部位；",
          "3. 发只画头顶与两侧、脸部不动；眼严格落在标准眼位线；衣装只画肩颈、领口上衔下巴；",
          "4. 全套同头位同缩放——任何一件换掉，其余三件像素不许动；",
          "5. 缺性别版时运行时自动回退通用件（`<slot>/<n>.png`），可先跑通用 20 件再逐件补男女版。\n",
          "## 风格后缀 · 分层零件\n```\n%s\n```" % STYLE_PART,
          "## 负向词 · 分层零件\n```\n%s\n```" % NEG_PART,
          "## 风格后缀 · 搭配预览\n```\n%s\n```" % STYLE_LOOK,
          "## 负向词 · 搭配预览\n```\n%s\n```\n" % NEG_LOOK,
          "## 逐条"]
    batch = []
    for it in items:
        neg = NEG_LOOK if it["kind"] == "搭配预览" else NEG_PART
        md.append("### %s ｜ %s ｜ %s" % (it["file"], it["kind"], it["size"]))
        if it.get("ref"): md.append("- 垫图：%s" % it["ref"])
        md.append("- 中文：%s" % it["zh"])
        md.append("- EN:\n```\n%s\n```\n" % it["en"])
        batch.append({"file": it["file"], "kind": it["kind"], "size": it["size"],
                      "prompt": it["en"], "negative": neg, "ref": it.get("ref", "")})
    io.open("face_prompts.md", "w", encoding="utf-8").write("\n".join(md) + "\n")
    io.open("face_batch.json", "w", encoding="utf-8").write(json.dumps(batch, ensure_ascii=False, indent=1))
    print("生成 %d 条捏脸提示词（零件 %d + 预览 %d）→ face_prompts.md / face_batch.json"
          % (len(batch), len(batch) - len(PRESETS), len(PRESETS)))
    if batch_api: try_api(batch, "--dry" in sys.argv)

def try_api(batch, dry):
    key = os.environ.get("OPENAI_API_KEY", "")
    if not key:
        print("[api] 未设 OPENAI_API_KEY，跳过联网。清单已生成，可导入批量出图工具。"); return
    import urllib.request
    for it in batch:
        if dry: print("WILL-POST", it["file"]); continue
        body = json.dumps({"model": "gpt-image-1", "prompt": it["prompt"], "size": "1024x1024"}).encode()
        req = urllib.request.Request("https://api.openai.com/v1/images/generations", data=body,
                                     headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
        try: urllib.request.urlopen(req, timeout=120); print("OK", it["file"])
        except Exception as e: print("FAIL", it["file"], e)

if __name__ == "__main__":
    emit("--api" in sys.argv)
