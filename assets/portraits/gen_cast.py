# -*- coding: utf-8 -*-
# 角色立绘批量出图助手：从 npcs.json 真实人设 + 8 身份原型 + 主角/出身，
# 生成成套角色提示词 → cast_prompts.md + cast_batch.json。
# 用法: python gen_cast.py            # 生成清单与提示词
#       python gen_cast.py --api      # 设了 OPENAI_API_KEY 时逐件调接口(否则仅打印)
import sys, json, io, os

NPCS = json.load(io.open("E:/Game/Godot-xiuxian/data/npcs.json", encoding="utf-8"))

# 部件可视化描述（与 gen_parts.py 对齐，保证纸娃娃零件与立绘同调）
FACE_DESC = {"鹅蛋脸": "oval soft face", "剑客脸": "sharp angular swordsman face, keen brows",
             "圆脸": "round friendly face", "清瘦面": "lean long face", "丰润面": "full plump face"}
HAIR_DESC = {"高马尾": "high ponytail", "垂鬓": "loose side-locks", "束发": "tied-up topknot",
             "披发": "long flowing loose hair", "双丫髻": "twin buns"}
EYE_DESC  = {"琥珀瞳": "amber eyes", "墨瞳": "ink-black eyes", "浅褐瞳": "light-brown eyes",
             "灰蓝瞳": "grey-blue eyes", "绯瞳": "crimson eyes"}
CLOTH_DESC= {"靛青布衣": "indigo coarse cloth robe", "月白衫": "pale moon-white robe",
             "玄色劲装": "black fitted martial garb", "藕荷襦裙": "lotus-root pink ruqun dress",
             "灰褐短打": "grey-brown short working jacket"}
# 性格标签(四组)中文
TAG_CN = {"zuidu":"嘴毒","ruanruo":"软糯","guayan":"寡言","xinruan":"心软","manre":"慢热",
          "zilaishu":"自来熟","qinkuai":"勤快","lansan":"懒散","jiaozhen":"较真",
          "zhiqui":"直球","kouyan":"口嫌体正直","xishui":"细水长流"}
TAG_EN = {"zuidu":"sharp-tongued","ruanruo":"soft-spoken","guayan":"taciturn","xinruan":"warm-hearted",
          "manre":"slow-to-warm","zilaishu":"quick to warm up","qinkuai":"diligent","lansan":"laid-back",
          "jiaozhen":"meticulous","zhiqui":"forthright","kouyan":"tsundere","xishui":"steady and long-lasting"}

IDENTITY_EN = {
 "baimenzong": ("百味宗弟子", "a Baiwei-sect disciple in neat daoist robe, humble and diligent"),
 "tongming":   ("仙门修士", "an elegant Tongming immortal-sect cultivator in white-and-blue robes"),
 "jianpai":    ("掬霜剑修", "a cold sword immortal, steel blade on back, sharp gaze"),
 "yoududao":   ("幽都道散修", "a mysterious rogue cultivator of Youdu path, dark loose garb"),
 "shanshen":   ("山神庙祝", "a mountain-god priest in ritual robe, serene with faint divine aura"),
 "huizu":      ("妖族商贩", "a fox-eared demon-folk merchant, sly warm smile, silken robes"),
 "wenmai":     ("说书人", "a storyteller scholar with a folding fan, ink-stained sleeve"),
 "fangshi":    ("坊市散修", "a common market cultivator in a short work-jacket, worldly and friendly"),
}
# 出身
ORIGINS = [
 ("灵田农家子", "木", "a farm-born youth with a hoe, rolled sleeves, soil-stained hands, fresh fields behind"),
 ("药商世家女", "水", "an apothecary-heir girl with medicine pouches, faint herb-mist around her"),
 ("世族送修子", "金", "a noble youth holding a half family cultivation scroll and a clan jade"),
 ("灶下无名儿", "火", "a kitchen child with flour-smudged face and easy smile, apron by the hearth"),
]
PROTAG = ("主角·下凡历劫的女修",
  "a gentle female cultivator in plain daoist robes, wooden hairpin, holding a bamboo basket, warm composed half-smile, otome-style not showing full face")

STYLE_AV  = ("Chinese xianxia cultivation game character portrait, front-facing head, soft cel-shaded illustration, "
             "clean thick outlines, gentle rim light, plain pastel background, otome art style, high detail, no text, no watermark")
STYLE_FUL = ("Chinese xianxia cultivation game full-body character standing sprite illustration, soft cel-shaded, "
             "clean thick outlines, gentle rim light, plain pastel background, otome art style, full figure, high detail, no text, no watermark")
NEG = "photorealistic, 3d render, text, watermark, logo, extra limbs, deformed hands, gore, horror, nsfw, busy background, different head size, off-center"

def persona_str(p):
    return "、".join([TAG_CN.get(p.get(k, ""), "") for k in ("biaoda","dairen","xingshi","dongxin")]).strip("、")
def persona_en(p):
    return ", ".join([TAG_EN.get(p.get(k, ""), "") for k in ("biaoda","dairen","xingshi","dongxin")]).strip(", ")

def fixed_prompts():
    out = []
    for x in NPCS:
        a = x.get("appearance", {}); p = x.get("persona", {})
        face = FACE_DESC.get(a.get("face",""), a.get("face",""))
        hair = HAIR_DESC.get(a.get("hair",""), a.get("hair",""))
        eyes = EYE_DESC.get(a.get("eyes",""), a.get("eyes",""))
        cloth= CLOTH_DESC.get(a.get("cloth",""), a.get("cloth",""))
        idzh, iden = IDENTITY_EN.get(x.get("identity",""), (x.get("identity",""), "a wandering cultivator"))
        mood = x.get("moe", "")
        # 自然语言完整句式（实测远好于标签串）：先主体身份，再五官衣着，最后神情气质收束
        core_en_av = ("A portrait of %s, %s. The character has %s, %s and %s, wearing %s. "
                      "The calm front-facing bust carries a %s temperament, conveying the air of '%s'." %
                      (x["name"], iden, face, eyes, hair, cloth, persona_en(p), mood))
        core_en_full = ("A full-body standing illustration of %s, %s. The character has %s, %s and %s, wearing %s, "
                        "with a %s temperament, holding props that reflect the cultivation realm of '%s'; "
                        "the entire figure is centered and fully visible in frame." %
                        (x["name"], iden, face, eyes, hair, cloth, persona_en(p), x.get("realm","")))
        core_zh = ("%s·%s：一张%s、%s、%s，着%s，性取 %s" %
                   (x["name"], idzh, a.get("face",""), a.get("eyes",""), a.get("hair",""), a.get("cloth",""), persona_str(p)))
        out.append({"file":"npc/%s_avatar.png" % x["key"], "kind":"头像", "size":"1:1",
                    "zh": core_zh + "，神情贴合『%s』气质，正面胸像" % mood,
                    "en": core_en_av, "style_av": True})
        out.append({"file":"npc/%s_full.png" % x["key"], "kind":"全身立绘", "size":"3:4",
                    "zh": core_zh + "，全身站姿、境界(%s)相应气质与随身法器" % x.get("realm",""),
                    "en": core_en_full, "style_av": False})
    return out

def role_prompts():
    out = []
    for key,(zh,en) in IDENTITY_EN.items():
        if key in (x.get("identity") for x in NPCS):   # 已有固定角色的原型，仍给“通用款”便于随机NPC复用
            pass
        out.append({"file":"role/%s_avatar.png" % key, "kind":"身份原型", "size":"1:1",
                    "zh": "随机NPC通用身份·%s：%s，正面胸像，中性表情可套用" % (zh, en),
                    "en": "A front-facing bust portrait of a generic interchangeable NPC character. This %s has a calm, neutral expression suitable for reuse. " % en,
                    "style_av": True})
    return out

def protagonist_prompts():
    out = [{"file":"protagonist/avatar.png","kind":"主角","size":"1:1",
            "zh": PROTAG[0]+"，正面胸像，乙女向不露全脸","en": PROTAG[1] + ", shown as a front-facing bust",
            "style_av": True}]
    for name, elem, en in ORIGINS:
        out.append({"file":"origin/%s_avatar.png" % name, "kind":"出身立绘", "size":"3:4",
                    "zh": "出身·%s（%s属）：全身像，%s" % (name, elem, en),
                    "en": "A full-body standing illustration depicting a character of the '%s' origin, %s. The entire figure is centered and fully visible in frame." % (name, en),
                    "style_av": False})
    return out

def emit(batch_api):
    items = fixed_prompts() + role_prompts() + protagonist_prompts()
    md = ["# 《百味长生》角色出图提示词（固定NPC+主角/出身+8身份原型）\n",
          "> 每条 = 主体描述 + 风格后缀；头像 1:1、立绘 3:4。成套一致：MJ 同 `--seed`+`--sref`、SD 同 LoRA+ControlNet。\n",
          "## 风格后缀 · 头像\n```\n%s\n```" % STYLE_AV,
          "## 风格后缀 · 全身立绘\n```\n%s\n```" % STYLE_FUL,
          "## 负向词\n```\n%s\n```\n" % NEG,
          "## 逐条"]
    batch = []
    for it in items:
        suffix = STYLE_AV if it["style_av"] else STYLE_FUL
        ren = it["en"] + ". " + suffix
        md.append("### %s ｜ %s ｜ %s" % (it["file"], it["kind"], it["size"]))
        md.append("- 中文：%s" % it["zh"])
        md.append("- EN:\n```\n%s\n```\n" % ren)
        batch.append({"file": it["file"], "size": it["size"], "prompt": ren, "negative": NEG})
    io.open("cast_prompts.md","w",encoding="utf-8").write("\n".join(md)+"\n")
    io.open("cast_batch.json","w",encoding="utf-8").write(json.dumps(batch, ensure_ascii=False, indent=1))
    print("生成 %d 条角色提示词 → cast_prompts.md / cast_batch.json" % len(batch))
    if batch_api: try_api(batch, "--dry" in sys.argv)

def try_api(batch, dry):
    key = os.environ.get("OPENAI_API_KEY","")
    if not key:
        print("[api] 未设 OPENAI_API_KEY，跳过联网。清单已生成。"); return
    import urllib.request
    for it in batch:
        if dry: print("WILL-POST", it["file"]); continue
        body=json.dumps({"model":"gpt-image-1","prompt":it["prompt"]}).encode()
        req=urllib.request.Request("https://api.openai.com/v1/images/generations",data=body,
             headers={"Authorization":"Bearer "+key,"Content-Type":"application/json"})
        try: urllib.request.urlopen(req,timeout=120); print("OK",it["file"])
        except Exception as e: print("FAIL",it["file"],e)

if __name__ == "__main__":
    emit("--api" in sys.argv)
