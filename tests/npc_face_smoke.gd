extends Node
## 他人捏脸冒烟: 六位固定 NPC 可选 / 逐件切换出真图 / 应用写回 data/npcs.json 且头像随之更新 /
## 性别锁档案值 / 复原回出厂容貌。运行: Godot --headless --path . res://tests/npc_face_smoke.tscn

const Portrait := preload("res://scripts/portrait.gd")
const NG := preload("res://sim/NpcGenerator.gd")
const APP := preload("res://scripts/apps/app_face_npc.gd")

var _fails := 0


func _ready() -> void:
	if NG.catalog().is_empty():
		_fail("catalog.json 未加载")
	var app := Control.new()
	app.set_script(APP)
	add_child(app)
	await get_tree().process_frame
	app._stage = "edit"   # 后面几段测捏脸页本身，先切进去
	app._schedule_rebuild()
	await get_tree().process_frame

	# 0) 性别锁死: 不出现性别行
	var has_gender := false
	for f in APP.FIELDS:
		if String(f[0]) == "gender":
			has_gender = true
	_check(not has_gender, "无可切换的性别行(性别锁档案值)")

	# 1) 六位固定 NPC 逐人可选: 工作台换人 + 叠绘出真图
	for key in APP.FIXED_KEYS:
		app._key = String(key)
		app._load_work()
		var look := Game.npc_look(String(key))
		if String(app._work.get("face", "")) != String(look.get("face", "")):
			_fail("%s: 工作台未载入该 NPC 容貌" % key)
		_check_portrait("pick " + key, Portrait.build_from(app._work, 64, app._male()))
		_check_portrait("arch " + key, Portrait.build_for(String(key), 52))

	# 2) 逐件切换: 七槽 + 气质各走一步, 仍是真图
	app._key = "huzhu"
	app._load_work()
	for f in ["face", "brows", "eyes", "mouth", "hair_front", "hair_back", "cloth", "aura"]:
		app._cycle(String(f), 1)
	_check_portrait("cycled", Portrait.build_from(app._work, 64, app._male()))

	# 3) 随机: 部件/调色重掷, 气质不动
	var aura_before := String(app._work.get("aura", ""))
	app._randomize_look()
	await get_tree().process_frame
	_check(String(app._work.get("aura", "")) == aura_before, "随机不改气质")
	for k in ["hair_hue", "hair_sat", "eye_hue", "eye_sat"]:
		if not app._work.has(k):
			_fail("随机缺调色键 " + k)
	_check_portrait("randomized", Portrait.build_from(app._work, 64, app._male()))

	# 4) 应用: 换脸型 + 调色 + 气质 → 内存档案 / 落盘 / 头像 三处一致
	var base_raw := DataManager.npc_raw_appearance("huzhu")
	app._cycle("face", 1)
	app._work["hair_hue"] = 200
	app._work["hair_sat"] = 40
	app._work["eye_hue"] = 90
	var new_face := String(app._work.get("face", ""))
	var new_aura := String(app._work.get("aura", ""))
	app._apply()
	await get_tree().process_frame
	_check(String(Game.npc_arch("huzhu").get("appearance", {}).get("face", "")) == new_face, "应用: 内存档案脸型已改")
	_check(String(Game.npc_arch("huzhu").get("appearance", {}).get("aura", "")) == new_aura, "应用: 气质入档案")
	var disk := _disk_appearance("huzhu")
	_check(String(disk.get("face", "")) == new_face, "应用: 落盘 data/npcs.json(脸型 %s)" % new_face)
	_check(int(disk.get("hair_hue", -1)) == 200 and int(disk.get("hair_sat", -1)) == 40, "应用: 调色落盘 200°/40%")
	_check_portrait("after apply", Portrait.build_for("huzhu", 52))
	_check(Game.npc_male("huzhu") == (String(Game.npc_arch("huzhu").get("gender", "male")) != "female"), "应用后性别仍锁档案值")

	# 5) 复原: 回到出厂容貌(内存 + 落盘)
	app._reset_look()
	await get_tree().process_frame
	disk = _disk_appearance("huzhu")
	_check(String(disk.get("face", "")) == String(base_raw.get("face", "")), "复原: 脸型回出厂值")
	_check(int(disk.get("hair_hue", 0)) == int(base_raw.get("hair_hue", 0)), "复原: 调色回出厂值")
	_check(String(Game.npc_arch("huzhu").get("appearance", {}).get("face", "")) == String(base_raw.get("face", "")), "复原: 内存档案同步")
	_check_portrait("after reset", Portrait.build_for("huzhu", 52))

	# 6) 测试页入口: 新卡片存在且上抛 npcface
	var t := Control.new()
	t.set_script(preload("res://scripts/apps/app_test.gd"))
	add_child(t)
	await get_tree().process_frame
	var got := {"id": ""}   # 闭包按值捕获, 用字典回传
	t.open_app.connect(func(id: String) -> void: got["id"] = String(id))
	var hit := false
	for b in _buttons(t):
		if String(b.text).contains("他人捏脸"):
			hit = true
			b.pressed.emit()
	_check(hit, "测试页出现「进入他人捏脸」入口")
	_check(String(got["id"]) == "npcface", "入口上抛 npcface(实 %s)" % String(got["id"]))

	# 7) 两级界面: 选人页列出六人 → 点选进捏脸页 → 「‹ 换人」回选人页
	var p := Control.new()
	p.set_script(APP)
	add_child(p)
	await get_tree().process_frame
	_check(p._stage == "pick", "打开默认是选人页(实 %s)" % p._stage)
	var txts := _labels(p)
	for key in APP.FIXED_KEYS:
		_check(txts.has(Game.npc_name(String(key))), "选人页列出 %s" % Game.npc_name(String(key)))
	_check(not _labels(p).has("脸型"), "选人页不含捏脸部件行(两级已分开)")
	p._select("huzhu")
	await get_tree().process_frame
	_check(p._stage == "edit" and p._key == "huzhu", "点选后进捏脸页(stage=%s key=%s)" % [p._stage, p._key])
	_check(_labels(p).has("脸型"), "捏脸页出现部件行")
	var back := false
	for b in _buttons(p):
		if String(b.text).contains("换人"):
			b.pressed.emit()
			back = true
			break
	await get_tree().process_frame
	_check(back and p._stage == "pick", "「‹ 换人」回选人页(实 %s)" % p._stage)

	print("NPC_FACE_SMOKE ", "PASS" if _fails == 0 else "FAIL(%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


## 真叠绘 = Control(非占位圆) 且至少 4 层(底圆盘+脸+衣+发)
func _check_portrait(label: String, c: Control) -> void:
	if c == null or c is PanelContainer or c.get_child_count() < 4:
		_fail("%s: 未叠绘出真图(children=%s)" % [label, c.get_child_count() if c else -1])


## 直接读盘校验(绕开内存缓存)
func _disk_appearance(key: String) -> Dictionary:
	var f := FileAccess.open("res://data/npcs.json", FileAccess.READ)
	if f == null:
		_fail("读不到 data/npcs.json")
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not data is Array:
		_fail("data/npcs.json 不是数组")
		return {}
	for n in (data as Array):
		if String((n as Dictionary).get("key", "")) == key:
			return (n as Dictionary).get("appearance", {}) as Dictionary
	_fail("data/npcs.json 里没有 %s" % key)
	return {}


## 递归收集页面内所有 Label 文本
func _labels(n: Node) -> Array:
	var out: Array = []
	if n is Label:
		out.append(String(n.text))
	for c in n.get_children():
		out.append_array(_labels(c))
	return out


## 递归收集页面内所有按钮
func _buttons(n: Node) -> Array:
	var out: Array = []
	if n is Button:
		out.append(n)
	for c in n.get_children():
		out.append_array(_buttons(c))
	return out


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)


func _fail(msg: String) -> void:
	_fails += 1
	print("FAIL: ", msg)
