extends RefCounted
## 纸娃娃头像合成器：把 appearance 叠绘成一张分层头像（素材源自 CharaGraphicMaker 脸C/脸D(青年)与脸A(幼儿) 部件库）。
## 部件目录 catalog.json 由 assets/portraits/import_chara_parts.py 生成，查询统一走 NpcGenerator；
## 零件约定 res://assets/portraits/<slot>/<序号>{m|f|k}.png，带背面配对的再加 <序号>{m|f|k}_back.png。
## 套件选择走 Game.npc_kit：未成年用脸A(kid, 快照键 kid_look)，成年按性别用 appearance。
## 层深（底→顶，与素材 Setting.txt 实测一致）：饰品$ -1 → 后发$/前发$ 0 → 脸 1 → 底饰$ 2 → 衣 3
## → 后发 6 → 耳 7 → 眼$ 8 → 眼 9 → 眉/嘴 10 → 底饰 11 → 前发 12 → 饰品 13。
## 任一零件都缺失时回退 users 占位圆；aura 不出图，作背景色底。

const UiKit := preload("res://scripts/ui_kit.gd")
const NG := preload("res://sim/NpcGenerator.gd")

## 气质色（与 data/auras.json 的 color 字段保持一致；app_base._aura_tint 亦取自该数据）
const AURA_COLOR := {
	"疏懒": Color("f59e0b"), "清冷": Color("38bdf8"), "热络": Color("f472b6"),
	"拘谨": Color("9ca3af"), "悠然": Color("2dd4bf"),
}
## 发色/瞳色运行时调色(仿原版色相·彩度): 材质按 (色相,彩度) 缓存; identity 不挂。
const RECOLOR_SHADER := "res://assets/portraits/recolor.gdshader"
const HAIR_SLOTS := ["hair_front", "hair_back", "brows"]   # 素材連動组: 前发,后发,眉毛
const EYE_SLOTS := ["eyes"]
static var _mat_cache := {}


static func _recolor_mat(hue_deg: int, sat_pct: int) -> ShaderMaterial:
	if hue_deg == 0 and sat_pct == 100:
		return null
	var key := "%d_%d" % [hue_deg, sat_pct]
	if not _mat_cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = load(RECOLOR_SHADER)
		m.set_shader_parameter("hue_shift", hue_deg / 360.0)
		m.set_shader_parameter("sat_scale", sat_pct / 100.0)
		_mat_cache[key] = m
	return _mat_cache[key]


## 生成一个 px×px 的分层头像控件（放进 avatar_wrap 等，徽标由其上层叠加）。
## 按 Game.npc_kit 选套（脸C=男 / 脸D=女 / 脸A=幼儿），appearance 旧值自动落默认。
static func build_for(key: String, px: float) -> Control:
	var kit := Game.npc_kit(key)
	if kit == "kid":
		return build_from_kit(_kid_appearance(key), px, "kid")
	return build_from_kit(_appearance(key), px, kit)


## 直接给一份 appearance 字典叠绘（捏脸工坊预览、主角头像用）。
static func build_from(ap: Dictionary, px: float, male := false) -> Control:
	return build_from_kit(ap, px, "male" if male else "female")


static func build_from_kit(ap: Dictionary, px: float, kit := "female") -> Control:
	var look := NG.resolve_look_kit(ap, kit)
	var layers: Array = []   # [depth, seq, path, slot]，depth 相同按加入序稳定
	var seq := 0
	for slot in NG.SLOTS:
		for p in NG.layer_paths_kit(look, slot, kit):
			layers.append([p[0], seq, p[1], slot])
			seq += 1
	if layers.is_empty():
		return _fallback(px)
	layers.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	var hair_mat := _recolor_mat(int(ap.get("hair_hue", 0)), int(ap.get("hair_sat", 100)))
	var eye_mat := _recolor_mat(int(ap.get("eye_hue", 0)), int(ap.get("eye_sat", 100)))

	var root := Control.new()
	root.custom_minimum_size = Vector2(px, px)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# aura 色底圆盘
	var disc := PanelContainer.new()
	var sb := UiKit.stylebox(AURA_COLOR.get(String(ap.get("aura", "")), UiKit.PINK_300), 999)
	disc.add_theme_stylebox_override("panel", sb)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(disc)
	# 逐层叠绘(发/眼层按调色挂材质)
	for lay in layers:
		var tr := TextureRect.new()
		tr.texture = load(String(lay[2]))
		var slot := String(lay[3])
		var mat: ShaderMaterial = hair_mat if slot in HAIR_SLOTS else (eye_mat if slot in EYE_SLOTS else null)
		if mat:
			tr.material = mat
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(tr)
	return root


## 默认容貌（各部件取目录首个，饰品/底饰为「无」；主角默认女相，可工坊切换）。
static func default_look(male := false) -> Dictionary:
	var d := NG.default_look(male)
	d["gender"] = "male" if male else "female"
	d["aura"] = String(NG.AURAS[0])
	return d


## 幼儿相: 快照 kid_look(脸A 套件)缺省时自动落幼儿默认; aura 底随成年相快照, 换套不断档。
static func _kid_appearance(key: String) -> Dictionary:
	var e := Game._npc_entry(key)
	var kid: Dictionary = (e.get("kid_look", {}) as Dictionary).duplicate(true)
	kid["aura"] = String(_appearance(key).get("aura", ""))
	return kid


static func _appearance(key: String) -> Dictionary:
	var arch := Game.npc_arch(key)
	var a: Dictionary = {}
	var av: Variant = arch.get("appearance", null)
	if av is Dictionary:
		a = (av as Dictionary).duplicate()
	if Game.run.npcs.has(key):
		var rv: Variant = Game.run.npcs[key].get("appearance", null)
		if rv is Dictionary:
			for k in (rv as Dictionary):
				a[k] = (rv as Dictionary)[k]   # 随机 NPC 快照覆盖档案
	elif Game.run.has("world_npcs") and (Game.run.world_npcs as Dictionary).has(key):
		var wv: Variant = ((Game.run.world_npcs as Dictionary)[key] as Dictionary).get("appearance", null)
		if wv is Dictionary:
			for k in (wv as Dictionary):
				a[k] = (wv as Dictionary)[k]   # 世界池未识者: 快照出脸(仅调试/传闻视图用, 名录不露)
	return a


static func _fallback(px: float) -> Control:
	return UiKit.circle(px, UiKit.PINK_300, UiKit.PINK_400, "users", px * 0.46, UiKit.WHITE, true)
