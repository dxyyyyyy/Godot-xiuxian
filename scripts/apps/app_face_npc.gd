extends "res://scripts/apps/app_base.gd"
## 捏脸 · 他人：给六位固定 NPC 捏脸 —— 先选人，再逐件换部件（脸/眉/眼/嘴/前发/后发/衣/气质）
## + 发色·瞳色滑杆，实时叠绘预览。性别锁死档案值（不换部件目录）。
## 应用 = 改写 data/npcs.json 该 NPC 的 appearance（跨世生效，非本世临时覆盖）；「复原」回到出厂容貌。

const Portrait := preload("res://scripts/portrait.gd")
const NG := preload("res://sim/NpcGenerator.gd")

## 可捏对象：六位固定 NPC（data/npcs.json）
const FIXED_KEYS := ["jianshu", "yaoshi", "shanjun", "moxiu", "shushu", "huzhu"]
## 可编辑槽位（耳朵随脸型肤色自动联动，不暴露；性别锁死）
const FIELDS := [
	["face", "脸型"], ["brows", "眉"], ["eyes", "眼"], ["mouth", "嘴"],
	["hair_front", "前发"], ["hair_back", "后发"], ["cloth", "服装"], ["aura", "气质"],
]
const EDIT_SLOTS := ["face", "brows", "eyes", "mouth", "hair_front", "hair_back", "cloth"]
const COLOR_KEYS := ["hair_hue", "hair_sat", "eye_hue", "eye_sat"]
const COLOR_ROWS := [["发色", "hair_hue", "hair_sat"], ["瞳色", "eye_hue", "eye_sat"]]

var _content: VBoxContainer
var _preview_box: PanelContainer
var _note: Label = null            # 应用/复原结果提示
var _aura_note: Label = null
var _val_labels := {}
var _color_labels := {}
var _rebuild_pending := false
var _stage := "pick"          # pick=选人页 / edit=捏脸页（两级界面，不挤在一起）
var _key: String = FIXED_KEYS[0]
var _work := {}
var _msg := ""            # 应用/复原结果(重建后仍需保留)
var _rng := RandomNumberGenerator.new()


func _build_content(vb: VBoxContainer) -> void:
	vb.add_child(bleed_head("捏脸 · 他人", "六位固定 NPC —— 选人，再捏一张脸。"))
	_rng.randomize()
	_load_work()
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 12)
	vb.add_child(_content)
	Game.changed.connect(_schedule_rebuild)
	_rebuild()


func _schedule_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_pending = false
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_val_labels.clear()
	_color_labels.clear()

	# 两级界面：先选人，再捏脸
	if _stage == "pick":
		_build_pick()
		return

	_content.add_child(_edit_header())

	# 实时预览
	_preview_box = UiKit.padded(UiKit.pink_box(UiKit.JADE_50), 16)
	var pc := CenterContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(Portrait.build_from(_work, 128, _male()))
	_preview_box.add_child(pc)
	_content.add_child(_preview_box)

	# 调色：发色/瞳色 色相·彩度
	var colors := VBoxContainer.new()
	colors.add_theme_constant_override("separation", 6)
	for r in COLOR_ROWS:
		colors.add_child(_color_row(String(r[0]), String(r[1]), String(r[2])))
	_content.add_child(colors)

	# 部件逐件切换
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	for f in FIELDS:
		rows.add_child(_row(String(f[0]), String(f[1])))
	_content.add_child(rows)

	_aura_note = UiKit.label(_aura_note_text(), 11, UiKit.PINK_400)
	_aura_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_aura_note)

	# 操作：复原 / 随机 / 应用
	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 6)
	act.add_child(_big_button("复原", _reset_look))
	act.add_child(_big_button("随机", _randomize_look))
	var apply := _big_button("应用容貌", _apply)
	apply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	act.add_child(apply)
	_content.add_child(act)

	_note = UiKit.label(_msg, 11, UiKit.JADE_700)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_note)
	_content.add_child(UiKit.label("应用即改写 data/npcs.json（跨世生效）；性别锁档案值，不可改。", 11, UiKit.PINK_400))


# ---- 选人页（第一级）----

func _build_pick() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	var hint := UiKit.label("点一位进去捏脸。标「已改」的是本轮动过容貌的。", 12, UiKit.PINK_400)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hint)
	for key in FIXED_KEYS:
		vb.add_child(_npc_row(String(key)))
	_content.add_child(UiKit.margin_wrap(vb, 16))


## 选人行：头像 + 姓名/身份·境界 + 「已改」角标 + 右箭头
func _npc_row(key: String) -> PanelContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	var av := Portrait.build_for(key, 56)
	hb.add_child(av)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 3)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.add_child(UiKit.label(Game.npc_name(key), 15, UiKit.PINK_700, 600))
	if _is_modified(key):
		line.add_child(UiKit.pill("已改", UiKit.WHITE, UiKit.GOLD_500, 10))
	line.add_child(UiKit.expander())
	vb.add_child(line)
	var sub := UiKit.label(_chip_sub(key), 11, UiKit.JADE_600, 400)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(sub)
	hb.add_child(vb)
	hb.add_child(UiKit.label("›", 20, UiKit.PINK_400, 600))
	return UiKit.tappable_row(hb, func() -> void: _select(key))


## 与出厂容貌有出入即算已改（含新增调色键）
func _is_modified(key: String) -> bool:
	var raw := DataManager.npc_raw_appearance(key)
	var cur: Dictionary = Game.npc_arch(key).get("appearance", {}) as Dictionary
	for k in raw:
		if str(cur.get(k, "")) != str(raw.get(k, "")):
			return true
	for k in cur:
		if not raw.has(k):
			return true
	return false


## 选人 → 捏脸页
func _select(key: String) -> void:
	_key = key
	_stage = "edit"
	_load_work()
	_note_text("")
	_schedule_rebuild()


## 捏脸页 → 回选人页
func _back_to_pick() -> void:
	_stage = "pick"
	_note_text("")
	_schedule_rebuild()


# ---- 捏脸页（第二级）----

## 顶部条：‹ 换人 + 当前对象头像/姓名，明确「在给谁捏」
func _edit_header() -> Control:
	var c := bleed_section()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var back := Button.new()
	back.text = "‹ 换人"
	back.focus_mode = Control.FOCUS_NONE
	back.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back.custom_minimum_size = Vector2(76, 40)
	back.add_theme_font_override("font", UiKit.font(600))
	back.add_theme_font_size_override("font_size", 13)
	back.add_theme_color_override("font_color", UiKit.PINK_600)
	back.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.PINK_50, 8))
	back.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.PINK_100, 8))
	back.add_theme_stylebox_override("pressed", UiKit.stylebox(UiKit.PINK_500, 8))
	back.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	back.pressed.connect(_back_to_pick)
	hb.add_child(back)

	var av := Portrait.build_for(_key, 44)
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(av)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(UiKit.label(Game.npc_name(_key), 15, UiKit.PINK_700, 600))
	vb.add_child(UiKit.label("性别锁档案值 · 应用后写入 data/npcs.json", 10, UiKit.JADE_600, 400))
	hb.add_child(vb)
	c.add_child(UiKit.margin_wrap(hb, 16))
	return c


## 胶囊副题：身份/境界（档案里有就显示）
func _chip_sub(key: String) -> String:
	var arch := Game.npc_arch(key)
	var idn := String(arch.get("id_name", ""))
	if idn == "":
		idn = String(NG.ID_NAMES.get(String(arch.get("identity", "")), ""))
	var realm := String(arch.get("realm", ""))
	return realm if idn == "" else "%s · %s" % [idn, realm] if realm != "" else idn


# ---- 部件 / 调色 ----

func _row(field: String, title: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var t := UiKit.label(title, 13, UiKit.PINK_700, 600)
	t.custom_minimum_size = Vector2(56, 0)
	row.add_child(t)
	row.add_child(_step_btn("‹", func() -> void: _cycle(field, -1)))
	var val := UiKit.label(_disp(field, String(_work.get(field, ""))), 13, UiKit.PINK_600, 600, HORIZONTAL_ALIGNMENT_CENTER)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_val_labels[field] = val
	row.add_child(val)
	row.add_child(_step_btn("›", func() -> void: _cycle(field, 1)))
	return row


func _color_row(title: String, hue_key: String, sat_key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var t := UiKit.label(title, 13, UiKit.PINK_700, 600)
	t.custom_minimum_size = Vector2(56, 0)
	row.add_child(t)
	var val := UiKit.label(_color_text(hue_key, sat_key), 11, UiKit.PINK_500, 500)
	val.custom_minimum_size = Vector2(104, 0)
	_color_labels[hue_key] = val
	row.add_child(val)
	row.add_child(_slider(0, 359, 1, float(int(_work.get(hue_key, 0))), func(v: float) -> void:
		_work[hue_key] = int(v)
		val.text = _color_text(hue_key, sat_key)
		_refresh_preview()))
	row.add_child(_slider(0, 200, 5, float(int(_work.get(sat_key, 100))), func(v: float) -> void:
		_work[sat_key] = int(v)
		val.text = _color_text(hue_key, sat_key)
		_refresh_preview()))
	return row


func _color_text(hue_key: String, sat_key: String) -> String:
	return "%d° · %d%%" % [int(_work.get(hue_key, 0)), int(_work.get(sat_key, 100))]


func _cycle(field: String, dir: int) -> void:
	var arr: Array = _arr(field)
	if arr.is_empty():
		return
	var i := arr.find(String(_work.get(field, "")))
	_work[field] = String(arr[posmod(i + dir, arr.size())])
	for f in _val_labels:
		(_val_labels[f] as Label).text = _disp(f, String(_work.get(f, "")))
	if _aura_note != null and is_instance_valid(_aura_note):
		_aura_note.text = _aura_note_text()
	_refresh_preview()


func _aura_note_text() -> String:
	var aura_name := String(_work.get("aura", ""))
	var note := String(DataManager.aura_def(aura_name).get("note", ""))
	return "气质 · %s：%s" % [aura_name, note] if note != "" else "气质 · %s" % aura_name


func _refresh_preview() -> void:
	if _preview_box == null or not is_instance_valid(_preview_box):
		return
	for c in _preview_box.get_children():
		_preview_box.remove_child(c)
		c.queue_free()
	var pc := CenterContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(Portrait.build_from(_work, 128, _male()))
	_preview_box.add_child(pc)


# ---- 操作 ----

## 载入当前选中 NPC 的生效容貌到工作台（性别锁死，不随工作台变）
func _load_work() -> void:
	_work = Game.npc_look(_key)


func _male() -> bool:
	return Game.npc_male(_key)


## 随机：七槽 + 调色重掷，气质保留（性别锁死）
func _randomize_look() -> void:
	var look := NG.random_look(_rng, _male())
	for k in EDIT_SLOTS:
		_work[k] = look[k]
	for k in COLOR_KEYS:
		_work[k] = look[k]
	_note_text("")
	_schedule_rebuild()


## 复原：回到出厂档案容貌（DataManager 启动时留的基线）
func _reset_look() -> void:
	if Game.reset_npc_look(_key):
		_note_text("已复原【%s】的出厂容貌。" % Game.npc_name(_key))
	else:
		_note_text("复原失败：该 NPC 不在档案中。")
	_load_work()
	_schedule_rebuild()


## 应用：耳朵随脸型肤色联动后写回档案（内存 + npcs.json）
func _apply() -> void:
	var look := NG.resolve_look(_work, _male())
	for k in COLOR_KEYS:
		look[k] = int(_work.get(k, 0))
	look["aura"] = String(_work.get("aura", ""))
	for k in EDIT_SLOTS:
		look[k] = String(_work.get(k, ""))
	if Game.set_npc_look(_key, look):
		_note_text("已应用【%s】的新容貌 —— 写入 data/npcs.json，跨世生效。" % Game.npc_name(_key))
	else:
		_note_text("已应用【%s】的新容貌（本进程生效，data/npcs.json 落盘失败）。" % Game.npc_name(_key))


func _note_text(msg: String) -> void:
	_msg = msg
	if _note != null and is_instance_valid(_note):
		_note.text = msg


# ---- 显示与控件 ----

func _disp(field: String, val: String) -> String:
	if field == "aura":
		return val
	if val == "":
		return "无"
	var arr := _arr(field)
	var e := NG.entry(_male(), field, val)
	var name := String(e.get("name", val))
	if arr.size() > 1:
		return "%s %d/%d" % [name, arr.find(val) + 1, arr.size()]
	return name


func _arr(field: String) -> Array:
	if field == "aura":
		return NG.AURAS
	var ids: Array = []
	if field in NG.OPTIONAL_SLOTS:
		ids.append("")
	for e in NG.options(_male(), field):
		ids.append(String((e as Dictionary).get("id", "")))
	return ids


func _slider(vmin: float, vmax: float, vstep: float, val: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = vmin
	s.max_value = vmax
	s.step = vstep
	s.value = val
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0, 24)
	s.focus_mode = Control.FOCUS_NONE
	s.add_theme_stylebox_override("slider", UiKit.stylebox(UiKit.PINK_100, 3))
	s.add_theme_stylebox_override("grabber_area", UiKit.stylebox(UiKit.PINK_400, 3))
	s.add_theme_stylebox_override("grabber_area_highlight", UiKit.stylebox(UiKit.PINK_500, 3))
	s.add_theme_icon_override("grabber", app_face_dot(14, UiKit.PINK_600))
	s.add_theme_icon_override("grabber_highlight", app_face_dot(14, UiKit.PINK_500))
	s.add_theme_icon_override("grabber_pressed", app_face_dot(14, UiKit.PINK_700))
	s.value_changed.connect(cb)
	return s


## 圆形滑块贴图（4x 超采样抗锯齿）
static func app_face_dot(d: int, color: Color) -> ImageTexture:
	var big := d * 4
	var img := Image.create(big, big, false, Image.FORMAT_RGBA8)
	var c := big * 0.5 - 0.5
	for y in big:
		for x in big:
			img.set_pixel(x, y, color if Vector2(x - c, y - c).length() <= c else Color(0, 0, 0, 0))
	img.resize(d, d, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


func _step_btn(glyph: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = glyph
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(40, 36)
	b.add_theme_font_override("font", UiKit.font(600))
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", UiKit.PINK_600)
	b.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.PINK_50, 8))
	b.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.PINK_100, 8))
	b.add_theme_stylebox_override("pressed", UiKit.stylebox(UiKit.PINK_500, 8))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b


func _big_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_override("font", UiKit.font(600))
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", UiKit.WHITE)
	b.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.PINK_500, 10))
	b.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.PINK_600, 10))
	b.add_theme_stylebox_override("pressed", UiKit.stylebox(UiKit.PINK_600, 10))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b
