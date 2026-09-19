# -*- coding: utf-8 -*-
# 纸娃娃零件批量出图助手：生成清单 + 逐件提示词 + 可喂给批量工具的 JSON。
# 用法:
#   python gen_parts.py            # 产出通用 20 件 (mode=generic)
#   python gen_parts.py --gender   # 产出男女各一套 40 件 (mode=gendered, 文件名 1m/1f)
#   python gen_parts.py --api      # 若已设 OPENAI_API_KEY, 尝试逐件调用图像接口(否则只打印清单)
#   python gen_parts.py --api --dry  # 只演示将发送的请求, 不真正联网
import sys, json, io, os

FACES = ["鹅蛋脸", "剑客脸", "圆脸", "清瘦面", "丰润面"]
HAIRS = ["高马尾", "垂鬓", "束发", "披发", "双丫髻"]
EYES = ["琥珀瞳", "墨瞳", "浅褐瞳", "灰蓝瞳", "绯瞳"]
CLOTHS = ["靛青布衣", "月白衫", "玄色劲装", "藕荷襦裙", "灰褐短打"]

# 每件一句可视化描述（英文为主，中文辅）
FACE_DESC = {
    "鹅蛋脸": "oval soft face", "剑客脸": "sharp angular swordsman face, keen brows",
    "圆脸": "round friendly face", "清瘦面": "lean long face", "丰润面": "full plump face",
}
HAIR_DESC = {
    "高马尾": "high ponytail", "垂鬓": "loose side-locks", "束发": "tied-up topknot",
    "披发": "long flowing loose hair", "双丫髻": "twin buns",
}
EYE_DESC = {
    "琥珀瞳": "amber eyes", "墨瞳": "ink-black eyes", "浅褐瞳": "light-brown eyes",
    "灰蓝瞳": "grey-blue eyes", "绯瞳": "crimson eyes",
}
CLOTH_DESC = {
    "靛青布衣": "indigo coarse cloth robe", "月白衫": "pale moon-white robe",
    "玄色劲装": "black fitted martial garb", "藕荷襦裙": "lotus-root pink ruqun dress",
    "灰褐短打": "grey-brown short working jacket",
}

STYLE = ("Chinese xianxia cultivation game character portrait, front-facing centered bust, soft cel-shaded "
         "illustration, clean thick outlines, gentle rim light, isolated on transparent background PNG, "
         "same head position and scale across the whole set, high detail, no text, no watermark")
NEG = "photorealistic, 3d, text, watermark, blurry, extra limbs, gore, horror, different head size, off-center"

SLOTS = [("face", FACES, FACE_DESC), ("hair", HAIRS, HAIR_DESC), ("eyes", EYES, EYE_DESC), ("cloth", CLOTHS, CLOTH_DESC)]
GENDER_NOTE = {"m": " (male)", "f": " (female)"}

def build():
    parts = []
    for slot, arr, dmap in SLOTS:
        for i, val in enumerate(arr, start=1):
            d = dmap.get(val, val)
            if slot == "face":
                zh = "正面居中胸像，一张%s的底脸，中性平静表情，五官清晰，肤色自然，含颈部与少量肩" % val
                en = "base front-facing bust portrait head: %s, neutral calm expression, clear features, natural skin, neck and a bit of shoulder" % d
            elif slot == "hair":
                zh = "以标准正脸底图为准，只绘制【%s】发型，头顶与两侧，脸部位置与大小完全不变，其余全透明" % val
                en = "hair layer only: %s, sitting on the SAME standard head template, face untouched, everything else transparent" % d
            elif slot == "eyes":
                zh = "透明底，仅绘制一双【%s】，双眼居中落在标准眼位线上，位置严格统一" % val
                en = "eyes layer only, transparent bg: %s, positioned on the fixed standard eye line" % d
            else:
                zh = "透明底，仅绘制【%s】的肩颈与领口，向上衔接下巴，其余全透明" % val
                en = "clothing/shoulders layer only, transparent bg: %s, collar under the chin, rest transparent" % d
            parts.append({"slot": slot, "index": i, "value": val, "zh": zh, "en": en})
    return parts

def emit(mode):
    parts = build()
    rows = []
    batch = []
    md = ["# 纸娃娃零件出图清单（mode=%s）\n" % mode,
          "## 对齐铁律（决定能不能拼上）",
          "1. **先单独生成 `face/…` 底脸并定稿**，它定义了头位与构图；",
          "2. 其余 hair/eyes/cloth 一律**以该底脸为图生图/垫图（锁同一 seed、同尺寸、同构图）**，只用提示词或局部重绘换对应部位；",
          "3. 全部 **512×512、头居中、透明背景 PNG**，画布尺寸一致。",
          "4. Midjourney 用 `--cref <底脸图> --seed <固定>`；SD 用 ControlNet(lineart/openpose) 锁构图 + inpaint 换部位。",
          "5. 未放的性别版会自动回退通用版，可先做通用 20 张再逐件补。\n",
          "## 通用风格后缀（每条末尾都接）",
          "```\n%s\n```" % STYLE,
          "## 负向词\n```\n%s\n```\n" % NEG,
          "## 逐件提示词"]
    genders = ["m", "f"] if mode == "gendered" else [""]
    for p in parts:
        for g in genders:
            fname = "%s/%d%s.png" % (p["slot"], p["index"], g)
            gnote = GENDER_NOTE.get(g, "")
            full_en = p["en"] + (". masculine features" if g == "m" else "") + (". feminine features" if g == "f" else "") + ". " + STYLE
            rows.append("%s,%s,%d,%s,%s" % (fname, p["slot"], p["index"], p["value"], g or "neutral"))
            md.append("### %s\n- 中文：%s%s\n- EN:\n```\n%s\n```\n" % (fname, p["zh"], gnote, full_en))
            batch.append({"file": fname, "prompt": full_en, "negative": NEG, "size": "512x512", "ref": "face/%d%s.png" % (p["index"], g)})
    io.open("parts_manifest.csv", "w", encoding="utf-8").write("file,slot,index,value,gender\n" + "\n".join(rows) + "\n")
    io.open("parts_prompts.md", "w", encoding="utf-8").write("\n".join(md) + "\n")
    io.open("parts_batch.json", "w", encoding="utf-8").write(json.dumps(batch, ensure_ascii=False, indent=1))
    print("生成 %d 件 → parts_manifest.csv / parts_prompts.md / parts_batch.json" % len(batch))
    return batch

def try_api(batch, dry):
    key = os.environ.get("OPENAI_API_KEY", "")
    if not key:
        print("[api] 未检测到 OPENAI_API_KEY，跳过联网。清单已生成，可导入你自己的批量出图工具。")
        return
    import urllib.request, urllib.error
    for item in batch:
        if dry:
            print("WILL-POST", item["file"], "->", item["prompt"][:70], "...")
            continue
        body = json.dumps({"model": "gpt-image-1", "prompt": item["prompt"], "size": "1024x1024"}).encode()
        req = urllib.request.Request("https://api.openai.com/v1/images/generations", data=body,
                                     headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
        try:
            urllib.request.urlopen(req, timeout=120)
            print("OK", item["file"])
        except Exception as e:
            print("FAIL", item["file"], e)

if __name__ == "__main__":
    mode = "gendered" if "--gender" in sys.argv else "generic"
    b = emit(mode)
    if "--api" in sys.argv:
        try_api(b, "--dry" in sys.argv)
