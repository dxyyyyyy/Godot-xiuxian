extends Node
## 头像叠绘冒烟: 默认容/旧档兼容/6 固定 NPC/随机拼装/捏脸 App 交互 全链路不崩且出真图(非占位圆)。
## 运行: Godot --headless --path . res://tests/portrait_smoke.tscn

const Portrait := preload("res://scripts/portrait.gd")
const NG := preload("res://sim/NpcGenerator.gd")

var _fails := 0


func _ready() -> void:
	if NG.catalog().is_empty():
		_fail("catalog.json 未加载")
	# 目录自洽: 目录返回的每件必需图必在盘上(图被删的条目应已被 catalog() 剪掉, 不再出现在选项里)
	var cat_total := 0
	for kit in ["male", "female", "kid"]:
		for slot in NG.SLOTS:
			for e in NG.options_kit(kit, slot):
				cat_total += 1
				var id := String((e as Dictionary).get("id", ""))
				for p in NG.layer_paths_kit({slot: id}, slot, kit):
					if not ResourceLoader.exists(String(p[1])):
						_fail("缺图未剪: %s/%s id=%s %s" % [kit, slot, id, String(p[1])])
	print("CATALOG_CONSISTENT 目录在册部件 %d 件, 必需图全存在" % cat_total)
	for male in [false, true]:
		_check("default %s" % ("m" if male else "f"), Portrait.build_from(Portrait.default_look(male), 64, male))
	# 旧档兼容: 旧版中文名 + 旧单发槽 key「hair」→ 全落默认件
	var legacy := {"gender": "female", "face": "鹅蛋脸", "hair": "高马尾", "eyes": "琥珀瞳", "cloth": "月白衫", "aura": "清冷"}
	_check("legacy", Portrait.build_from(legacy, 64, false))
	for key in ["jianshu", "yaoshi", "shanjun", "moxiu", "shushu", "huzhu"]:
		_check("npc " + key, Portrait.build_for(key, 52))
	# kid 套(脸A 幼儿): k 件真叠绘
	_check("default kid", Portrait.build_from_kit(NG.default_look_kit("kid"), 64, "kid"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 30:
		var male := rng.randf() < 0.5
		var ap := NG.random_look(rng, male)
		ap["aura"] = String(NG.AURAS[rng.randi_range(0, NG.AURAS.size() - 1)])
		_check("rand%d" % i, Portrait.build_from(ap, 40, male))
	for i in 10:
		var kap := NG.random_look_kit(rng, "kid")
		kap["aura"] = String(NG.AURAS[rng.randi_range(0, NG.AURAS.size() - 1)])
		_check("rand_kid%d" % i, Portrait.build_from_kit(kap, 40, "kid"))
	# 捏脸 App: 实例化 + 逐字段 ‹› 切换 + 换性别重置 + 应用写档
	var app := Control.new()
	app.set_script(load("res://scripts/apps/app_face.gd"))
	add_child(app)
	await get_tree().process_frame
	var fields := ["face", "brows", "eyes", "mouth", "hair_front", "hair_back", "cloth", "aura"]
	for f in fields:
		app._cycle(f, 1)
	app._cycle("gender", 1)
	await get_tree().process_frame
	for f in fields:
		app._cycle(f, -1)
	# 随机按钮: 除性别外全槽随机, 性别/气质不动
	var aura_before := String(app._work.get("aura", ""))
	app._randomize_look()
	await get_tree().process_frame
	if String(app._work.get("gender", "")) != "male":
		_fail("randomize 不应改性别")
	if String(app._work.get("aura", "")) != aura_before:
		_fail("randomize 不应改气质")
	for k in ["hair_hue", "hair_sat", "eye_hue", "eye_sat"]:
		if not app._work.has(k):
			_fail("randomize 缺颜色键 " + k)
	_check("randomized app", Portrait.build_from(app._work, 40, Game.player_male()))
	# 调色: 非 identity → 发/眼层挂材质, 脸/衣层不挂
	var tinted := Portrait.default_look(false)
	tinted["hair_hue"] = 120
	tinted["hair_sat"] = 80
	tinted["eye_hue"] = 200
	var tc := Portrait.build_from(tinted, 64, false)
	var mat_n := 0
	var plain_n := 0
	for ch in tc.get_children():
		if ch is TextureRect:
			if ch.material != null:
				mat_n += 1
			else:
				plain_n += 1
	if mat_n < 4:
		_fail("tint: 挂材质层=%d 期望>=4(前后发/眉/眼含背面)" % mat_n)
	if plain_n < 2:
		_fail("tint: 未挂材质层=%d 期望>=2(脸/衣)" % plain_n)
	app._work["aura"] = "悠然"
	Game.set_player_look(app._work)
	_check("applied", Portrait.build_from(Game.player_look(), 40, Game.player_male()))
	print("PORTRAIT_SMOKE ", "PASS" if _fails == 0 else "FAIL(%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


## 真叠绘 = Control(非占位圆 PanelContainer) 且至少 4 层(底圆盘+脸+衣+发)
func _check(label: String, c: Control) -> void:
	if c == null or c is PanelContainer or c.get_child_count() < 4:
		_fail("%s: 未叠绘出真图(children=%s)" % [label, c.get_child_count() if c else -1])


func _fail(msg: String) -> void:
	_fails += 1
	print("FAIL: ", msg)
