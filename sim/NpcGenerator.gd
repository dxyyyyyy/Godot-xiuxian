extends RefCounted
## 随机 NPC 生成(GDD §7.3 + 性格系统 §6): 八原型 × 12 性格标签(四组各一枚) × 萌点 × 外观部件(画像预留) × 双层口味先验(势力味 × 性格修正)。
## 名字程序化生成: 真名式(姓×名) 与 诨名式(地标×营生) 两路混拼, 与既有 NPC/互相之间防重。
## 生成结果为 run 侧快照(name/appearance/persona/taste_base/identity), 入册走 Game._enroll_npc。

const IDENTITIES := ["baimenzong", "tongming", "jianpai", "yoududao", "shanshen", "huizu", "wenmai", "fangshi"]
const ID_NAMES := {
	"baimenzong": "百味宗弟子", "tongming": "仙门修士", "jianpai": "剑修", "yoududao": "散修(来历不明)",
	"shanshen": "山神庙祝", "huizu": "妖族商贩", "wenmai": "说书人", "fangshi": "坊市散修",
}
## 势力味标签先验(8.4 §2.3): 出身势力 → 默认喜味
const TASTE_BY_ID := {
	"baimenzong": "温", "tongming": "清", "jianpai": "辛", "yoududao": "猎奇",
	"shanshen": "素", "huizu": "鲜", "wenmai": "甘", "fangshi": "饱腹",
}
const BIAODA := ["zuidu", "ruanruo", "guayan"]
const DAIREN := ["xinruan", "manre", "zilaishu"]
const XINGSHI := ["qinkuai", "lansan", "jiaozhen"]
const DONGXIN := ["zhiqui", "kouyan", "xishui"]
## 外观部件: 部件目录 catalog.json 为单一数据源(见下方目录 API), 由
## assets/portraits/import_chara_parts.py 从 CharaGraphicMaker 脸C/脸D 套件生成(GDD §10)。
## 气质仍走常量池(不出图, 作头像背景色)。
const AURAS := ["疏懒", "清冷", "热络", "拘谨", "悠然"]

## —— 部件目录 API ——
## catalog.json: {"male"/"female": {slot: [{id,name,n,back,back_only,color,skin,base?,src}]}}
## slot ∈ SLOTS; 文件约定 res://assets/portraits/<slot>/<n>{m|f}.png(+_back.png 背面层)。
const CATALOG_PATH := "res://assets/portraits/catalog.json"
const PORTRAIT_ROOT := "res://assets/portraits/"
## 槽位表层深度(底→顶, 与素材 Setting.txt 实测一致; $ 背面层深度见 BACK_DEPTH)
const SLOT_DEPTH := {"face": 1, "cloth": 3, "hair_back": 6, "ears": 7, "eyes": 9,
	"brows": 10, "mouth": 10, "hair_front": 12}
const BACK_DEPTH := {"hair_back": 0, "hair_front": 0, "eyes": 8}
const SLOTS := ["face", "cloth", "hair_back", "ears", "eyes", "brows", "mouth", "hair_front"]
## 允许「无」的槽位(空串 = 不画);其余槽位缺件/旧值自动落默认。饰品/底饰槽已按需求废弃, 暂无可空槽。
const OPTIONAL_SLOTS: Array[String] = []

static var _cat: Dictionary = {}


static func catalog() -> Dictionary:
	if _cat.is_empty():
		var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
		if f:
			var v: Variant = JSON.parse_string(f.get_as_text())
			if v is Dictionary:
				_cat = v
	return _cat


static func options(male: bool, slot: String) -> Array:
	var g := "male" if male else "female"
	return (catalog().get(g, {}) as Dictionary).get(slot, [])


static func entry(male: bool, slot: String, id: String) -> Dictionary:
	for e in options(male, slot):
		if String((e as Dictionary).get("id", "")) == id:
			return e
	return {}


static func default_id(male: bool, slot: String) -> String:
	var arr := options(male, slot)
	return String((arr[0] as Dictionary).get("id", "")) if not arr.is_empty() else ""


## 外观字典 → 归一化目录外观: 旧版中文名/缺槽落默认(可空槽落「无」), 耳朵随脸型肤色换同形件。
## 兼容旧版单发槽 key「hair」→「hair_front」。
static func resolve_look(ap: Dictionary, male: bool) -> Dictionary:
	var look := {}
	for slot in SLOTS:
		var v := String(ap.get(slot, ""))
		if slot == "hair_front" and v == "":
			v = String(ap.get("hair", ""))
		if v == "" or entry(male, slot, v).is_empty():
			v = "" if slot in OPTIONAL_SLOTS else default_id(male, slot)
		look[slot] = v
	look["ears"] = _ear_for_face(male, String(look["face"]), String(look["ears"]))
	look.merge(COLOR_IDENTITY)   # 缺调色键的旧档 → identity
	return look


## 各槽位取默认的全新外观(可空槽为「无」；调色为 identity=原色)。
static func default_look(male: bool) -> Dictionary:
	var look := {}
	for slot in SLOTS:
		look[slot] = "" if slot in OPTIONAL_SLOTS else default_id(male, slot)
	look.merge(COLOR_IDENTITY)
	return look


## 调色 identity(0°/100%) 与随机权重(仿原版 GraphicMaker 色相·彩度)
const COLOR_IDENTITY := {"hair_hue": 0, "hair_sat": 100, "eye_hue": 0, "eye_sat": 100}


## 随机拼装一套外观(GDD §7.3): 前后发同色优先, 耳朵随脸型肤色, 饰品/底饰五成空。
static func random_look(rng, male: bool) -> Dictionary:
	var look := {}
	for slot in SLOTS:
		var arr := options(male, slot)
		if arr.is_empty():
			look[slot] = ""
		elif slot == "ears":
			look[slot] = default_id(male, slot)   # 耳朵不作选择: 固定默认人耳(肤色随后随脸型配对)
		elif slot in OPTIONAL_SLOTS and rng.randf() < 0.5:
			look[slot] = ""
		else:
			look[slot] = String((arr[rng.randi_range(0, arr.size() - 1)] as Dictionary).get("id", ""))
	var hf := entry(male, "hair_front", String(look["hair_front"]))
	if not hf.is_empty():
		var same: Array = options(male, "hair_back").filter(
			func(e): return String((e as Dictionary).get("color", "")) == String(hf.get("color", "")))
		if not same.is_empty():
			look["hair_back"] = String((same[rng.randi_range(0, same.size() - 1)] as Dictionary).get("id", ""))
	look["ears"] = _ear_for_face(male, String(look["face"]), String(look["ears"]))
	# 调色随机: 五成(瞳六成)守原色, 彩度收敛防过艳
	look["hair_hue"] = 0 if rng.randf() < 0.5 else rng.randi_range(0, 359)
	look["hair_sat"] = rng.randi_range(17, 23) * 5
	look["eye_hue"] = 0 if rng.randf() < 0.6 else rng.randi_range(0, 359)
	look["eye_sat"] = rng.randi_range(18, 22) * 5
	return look


## 耳朵肤色联动(素材「基础层,耳朵」同色组): 所选耳朵与脸型肤色不符时, 换同形异肤版本。
static func _ear_for_face(male: bool, face_id: String, ear_id: String) -> String:
	var face := entry(male, "face", face_id)
	var ear := entry(male, "ears", ear_id)
	if face.is_empty() or ear.is_empty() or String(face.get("skin", "")) == String(ear.get("skin", "")):
		return ear_id
	for e in options(male, "ears"):
		if String((e as Dictionary).get("base", "")) == String(ear.get("base", "")) \
				and String((e as Dictionary).get("skin", "")) == String(face.get("skin", "")):
			return String((e as Dictionary).get("id", ""))
	return ear_id


## appearance 槽位 → 实际叠绘 [depth, path] 列表(含背面层;空件返回 [])。
static func layer_paths(look: Dictionary, slot: String, male: bool) -> Array:
	var out := []
	var e := entry(male, slot, String(look.get(slot, "")))
	if e.is_empty():
		return out
	var sfx := "m" if male else "f"
	if not bool(e.get("back_only", false)):
		out.append([int(SLOT_DEPTH.get(slot, 1)), "%s%s/%d%s.png" % [PORTRAIT_ROOT, slot, int(e["n"]), sfx]])
	if bool(e.get("back", false)) or bool(e.get("back_only", false)):
		out.append([int(BACK_DEPTH.get(slot, 0)), "%s%s/%d%s_back.png" % [PORTRAIT_ROOT, slot, int(e["n"]), sfx]])
	return out


## 名字生成池: 真名式(姓×名) 程序化拼名(组合 240+, 防重重试+序号兜底); 诨名池降级为「人称」别号(alias)
const SURNAMES := ["林", "沈", "顾", "苏", "柳", "秦", "陆", "江", "裴", "宋", "崔", "韩", "谢", "阮", "洛"]
const GIVEN := ["青梧", "晚棠", "既明", "子渡", "听澜", "疏影", "折柳", "映雪", "云归", "南絮", "望舒", "之焕", "栖迟", "兰舟", "静尘", "拂衣"]
const EPITHET_PLACES := ["城西", "山南", "渡口", "桥头", "夜市", "东巷", "塔下", "泽畔", "岭上"]
const EPITHET_TRADES := ["卖花的", "修剑的", "算命的", "卖酒的", "收皮子的", "驮货的", "点灯的", "卖炭的", "说媒的", "卖伞的"]
## 旧版风味名池(已废弃): 旧档迁移时替换为程序化新名
const OLD_FLAVOR_NAMES := ["卖灯笼的", "唱曲的", "抄书的", "驯雀的", "酿醋的", "画符的", "修伞的", "摆渡的", "打铁的", "种花的"]

## 程序化名字(全真名式): 姓+名, 与 used(在册名) 防重重试 8 次, 仍撞则双名+序号兜底
func generate_name(rng, used: Dictionary) -> String:
	for _i in range(8):
		var n := String(SURNAMES[rng.randi_range(0, SURNAMES.size() - 1)]) + String(GIVEN[rng.randi_range(0, GIVEN.size() - 1)])
		if not used.has(n):
			return n
	return String(SURNAMES[rng.randi_range(0, SURNAMES.size() - 1)]) + String(GIVEN[rng.randi_range(0, GIVEN.size() - 1)]) + String.num(rng.randi_range(2, 99), 0)

## 人称别号(诨名, 仅快照 alias/tooltip 风味): 地标+营生
func generate_epithet(rng) -> String:
	return String(EPITHET_PLACES[rng.randi_range(0, EPITHET_PLACES.size() - 1)]) + String(EPITHET_TRADES[rng.randi_range(0, EPITHET_TRADES.size() - 1)])

func generate(rng, existing: Dictionary, filter_ids: Array = []) -> Dictionary:
	var used := {}
	for k in existing:
		used[String(existing[k].get("name", ""))] = true
	var npc_name := generate_name(rng, used)
	var ids := IDENTITIES if filter_ids.is_empty() else filter_ids
	var identity := String(ids[rng.randi_range(0, ids.size() - 1)])
	var persona := {
		"biaoda": String(BIAODA[rng.randi_range(0, BIAODA.size() - 1)]),
		"dairen": String(DAIREN[rng.randi_range(0, DAIREN.size() - 1)]),
		"xingshi": String(XINGSHI[rng.randi_range(0, XINGSHI.size() - 1)]),
		"dongxin": String(DONGXIN[rng.randi_range(0, DONGXIN.size() - 1)]),
	}
	# 口味双层先验: 势力味(先验一) × 性格修正(先验二: 懒散→饱腹/细水长流→温, 其余守先验) —— 性格系统 §4.4
	var base := String(TASTE_BY_ID[identity])
	var final := base
	if String(persona.xingshi) == "lansan":
		final = "饱腹"
	elif String(persona.dongxin) == "xishui":
		final = "温"
	var idx := 1
	for k in existing:
		if String(k).begins_with("rand_"):
			idx = maxi(idx, int(String(k).trim_prefix("rand_")) + 1)
	var gender := "male" if rng.randf() < 0.5 else "female"
	var appearance := random_look(rng, gender == "male")
	appearance["aura"] = String(AURAS[rng.randi_range(0, AURAS.size() - 1)])
	# 随机 NPC 境界轮盘: 炼气偏多、元婴稀有(GDD 未定具体分布, M0 取 flat 轮盘)
	const REALM_WHEEL := [0, 0, 0, 0, 1, 1, 1, 2, 2, 3]
	var realm_ord: int = REALM_WHEEL[rng.randi_range(0, REALM_WHEEL.size() - 1)]
	return {
		"key": "rand_%d" % idx,
		"name": npc_name,
		"gender": gender,
		"realm_ord": realm_ord,
		"identity": identity,
		"id_name": String(ID_NAMES[identity]),
		"persona": persona,
		"moe": "一面之缘, 各有各的忙",
		"appearance": appearance,
		"alias": generate_epithet(rng),
		"taste_base": base,
		"taste_final": final,
		"scene": "坊市",
		"blurb": "%s(%s) —— 游历与市井之间入世的新面孔" % [npc_name, String(ID_NAMES[identity])],
	}


## ---- 遗传造娃(婚配子嗣用) ----

## 槽位遗传: 50/50 取双亲之一(须存在于子女性别目录), 双亲皆不合法则随机; 10% 变异重抽。
func _inherit_slot(rng, child_male: bool, slot: String, id_a: String, id_b: String) -> String:
	var first := id_a if rng.randf() < 0.5 else id_b
	var second := id_b if first == id_a else id_a
	if rng.randf() < 0.10:
		return _random_option(rng, child_male, slot)
	for cand in [first, second]:
		if not entry(child_male, slot, cand).is_empty():
			return cand
	return _random_option(rng, child_male, slot)


func _random_option(rng, child_male: bool, slot: String) -> String:
	var opts: Array = options(child_male, slot)
	if opts.is_empty():
		return ""
	return String((opts[rng.randi_range(0, opts.size() - 1)] as Dictionary).get("id", ""))


## 色相遗传: 0 是「原色」哨兵非真色 —— 双 0 则 0; 否则取一非零亲值, 10% 随机色相。
func _inherit_hue(rng, h_a: int, h_b: int) -> int:
	if h_a == 0 and h_b == 0:
		return 0
	if rng.randf() < 0.10:
		return rng.randi_range(0, 359)
	return h_a if (h_a != 0 and rng.randf() < 0.5) else h_b


## 彩度遗传: 取一亲值 ±5, 钳 85~115(与 random_look 同带)。
func _inherit_sat(rng, s_a: int, s_b: int) -> int:
	var s: int = s_a if rng.randf() < 0.5 else s_b
	return clampi(s + rng.randi_range(-5, 5), 85, 115)


## 孩子快照: 双亲(pa=父姓来源)混出 —— 槽位/色/气质/性格逐位遗传, 收尾 resolve_look 修三约束。
## 姓名=父姓+随机名(在册去重); identity 随父母之一; 口味双层先验照 generate 旧规。
func breed_child(rng, pa: Dictionary, pb: Dictionary, existing: Dictionary) -> Dictionary:
	var child_male: bool = rng.randf() < 0.5
	var a: Dictionary = pa.get("appearance", {})
	var b: Dictionary = pb.get("appearance", {})
	var ap := {}
	for slot in SLOTS:
		ap[slot] = _inherit_slot(rng, child_male, String(slot), String(a.get(slot, "")), String(b.get(slot, "")))
	ap["hair_hue"] = _inherit_hue(rng, int(a.get("hair_hue", 0)), int(b.get("hair_hue", 0)))
	ap["hair_sat"] = _inherit_sat(rng, int(a.get("hair_sat", 100)), int(b.get("hair_sat", 100)))
	ap["eye_hue"] = _inherit_hue(rng, int(a.get("eye_hue", 0)), int(b.get("eye_hue", 0)))
	ap["eye_sat"] = _inherit_sat(rng, int(a.get("eye_sat", 100)), int(b.get("eye_sat", 100)))
	ap = resolve_look(ap, child_male)   # 性别目录校验 + 耳肤耦合 + 前后发色标(不碰 aura)
	var aura := ""
	if rng.randf() < 0.5:
		aura = String(a.get("aura", "")) if rng.randf() < 0.5 else String(b.get("aura", ""))
	if aura == "":
		aura = String(AURAS[rng.randi_range(0, AURAS.size() - 1)])
	ap["aura"] = aura
	var pa_p: Dictionary = pa.get("persona", {})
	var pb_p: Dictionary = pb.get("persona", {})
	var persona := {}
	for g in ["biaoda", "dairen", "xingshi", "dongxin"]:
		persona[g] = String(pa_p.get(g, "")) if rng.randf() < 0.5 else String(pb_p.get(g, ""))
	var identity := String(pa.get("identity", ""))
	if rng.randf() < 0.5:
		identity = String(pb.get("identity", identity))
	if identity == "" or not ID_NAMES.has(identity):
		identity = "fangshi"
	var base := String(TASTE_BY_ID.get(identity, "温"))
	var final := base
	if String(persona.get("xingshi", "")) == "lansan":
		final = "饱腹"
	elif String(persona.get("dongxin", "")) == "xishui":
		final = "温"
	var used := {}
	for k in existing:
		used[String(existing[k].get("name", ""))] = true
	var surname := String(String(pa.get("name", "林")).left(1))
	var kid_name := surname + String(GIVEN[rng.randi_range(0, GIVEN.size() - 1)])
	if used.has(kid_name):
		kid_name = generate_name(rng, used)
	var idx := 1
	for k in existing:
		if String(k).begins_with("rand_"):
			idx = maxi(idx, int(String(k).trim_prefix("rand_")) + 1)
	return {
		"key": "rand_%d" % idx,
		"name": kid_name,
		"gender": "male" if child_male else "female",
		"realm_ord": 0,
		"identity": identity,
		"id_name": String(ID_NAMES[identity]),
		"persona": persona,
		"moe": "各家有各忙的娃",
		"appearance": ap,
		"alias": generate_epithet(rng),
		"taste_base": base,
		"taste_final": final,
		"scene": "坊市",
		"blurb": "%s(%s) —— 某家新添的小辈" % [kid_name, String(ID_NAMES[identity])],
	}
