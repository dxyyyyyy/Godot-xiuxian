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
var _preview_box: CenterContainer
var _note: Label = null            # 应用/复原结果提示
var _aura_note: Label = null
var _val_labels := {}
var _color_labels := {}
var _color_swatches := {}
var _rebuild_pending := false
var _stage := "pick"          # pick=选人页 / edit=捏脸页（两级界面，不挤在一起）
var _key: String = FIXED_KEYS[0]
var _work := {}
var _msg := ""            # 应用/复原结果(重建后仍需保留)
var _rng := RandomNumberGenerator.new()


func _build_content(vb: VBoxContainer) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiKit.label("捏脸 · 他人", 18, UiKit.PINK_600, 600))
	head.add_child(UiKit.label("六位固定 NPC", 11, UiKit.PINK_400))
	var hw := UiKit.margin_wrap(head, 16)
	hw.add_theme_constant_override("margin_top", 8)
	hw.add_theme_constant_override("margin_bottom", 4)
	vb.add_child(hw)
	_rng.randomize()
	_load_work()
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 4)
	var cw := UiKit.margin_wrap(_content, 16)
	cw.add_theme_constant_override("margin_top", 0)
	cw.add_theme_constant_override("margin_bottom", 12)
	vb.add_child(cw)
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

	# 预览（三生石同款玉阵头像框）
	var preview_section := CenterContainer.new()
	preview_section.custom_minimum_size = Vector2(0, 190)
	_preview_box = CenterContainer.new()
	_preview_box.add_child(_preview_frame())
	_content.add_child(preview_section)
	preview_section.add_child(_preview_box)

	# 调色
	for r in COLOR_ROWS:
		_content.add_child(_color_row(String(r[0]), String(r[1]), String(r[2])))

	# 容貌
	for f in FIELDS:
		_content.add_child(_row(String(f[0]), String(f[1])))

	# 气质
	_aura_note = UiKit.label(_aura_note_text(), 10, UiKit.PINK_400)
	_aura_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_aura_note)

	# 操作
	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 6)
	act.add_child(_sec_button("复原", _reset_look))
	act.add_child(_sec_button("随机", _randomize_look))
	var apply := _big_button("应用容貌", _apply)
	apply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	act.add_child(apply)
	_content.add_child(act)

	# 提示（紧凑单行）
	if _msg != "":
		_note = UiKit.label(_msg, 10, UiKit.JADE_700)
		_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(_note)


# ---- 选人页（第一级）----

func _build_pick() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	var hint := UiKit.label("点一位进去捏脸。标「已改」的是本轮动过容貌的。", 12, UiKit.PINK_400)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hint)
	for key in FIXED_KEYS:
		vb.add_child(_npc_row(String(key)))
	_content.add_child(vb)


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
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var back := Button.new()
	back.text = "‹ 换人"
	back.focus_mode = Control.FOCUS_NONE
	back.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back.custom_minimum_size = Vector2(60, 30)
	back.add_theme_font_override("font", UiKit.font(600))
	back.add_theme_font_size_override("font_size", 12)
	back.add_theme_color_override("font_color", UiKit.PINK_600)
	back.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.PINK_50, 6))
	back.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.PINK_100, 6))
	back.add_theme_stylebox_override("pressed", UiKit.stylebox(UiKit.PINK_500, 6))
	back.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	back.pressed.connect(_back_to_pick)
	hb.add_child(back)

	var av := Portrait.build_for(_key, 32)
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(av)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 0)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(UiKit.label(Game.npc_name(_key), 13, UiKit.PINK_700, 600))
	hb.add_child(vb)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 4)
	m.add_theme_constant_override("margin_bottom", 2)
	m.add_theme_constant_override("margin_left", 0)
	m.add_theme_constant_override("margin_right", 0)
	m.add_child(hb)
	return m


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
	t.custom_minimum_size = Vector2(72, 0)
	row.add_child(t)
	row.add_child(_step_btn("‹", func() -> void: _cycle(field, -1)))
	var val := UiKit.label(_disp(field, String(_work.get(field, ""))), 13, UiKit.PINK_600, 600, HORIZONTAL_ALIGNMENT_CENTER)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_val_labels[field] = val
	row.add_child(val)
	row.add_child(_step_btn("›", func() -> void: _cycle(field, 1)))
	return row


## 调色行：标题 + 色块预览 + 当前值 + 色相滑杆(彩虹轨) + 彩度滑杆(渐变轨)。
func _color_row(title: String, hue_key: String, sat_key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var t := UiKit.label(title, 13, UiKit.PINK_700, 600)
	t.custom_minimum_size = Vector2(72, 0)
	row.add_child(t)
	var swatch := _make_swatch(_cur_color(hue_key, sat_key))
	_color_swatches[hue_key] = swatch
	row.add_child(swatch)
	var val := UiKit.label(_color_text(hue_key, sat_key), 11, UiKit.PINK_500, 500)
	val.custom_minimum_size = Vector2(80, 0)
	_color_labels[hue_key] = val
	row.add_child(val)
	var update := func() -> void:
		val.text = _color_text(hue_key, sat_key)
		_set_swatch_color(swatch, _cur_color(hue_key, sat_key))
		_refresh_preview()
	row.add_child(_gradient_slider(0, 359, 1, float(int(_work.get(hue_key, 0))), _hue_gradient(), func(v: float) -> void:
		_work[hue_key] = int(v)
		update.call()))
	var base_color := Color.from_hsv(float(int(_work.get(hue_key, 0))) / 360.0, 1.0, 0.9)
	row.add_child(_gradient_slider(0, 200, 5, float(int(_work.get(sat_key, 100))), _sat_gradient(base_color), func(v: float) -> void:
		_work[sat_key] = int(v)
		update.call()))
	return row


func _color_text(hue_key: String, sat_key: String) -> String:
	return "%d° · %d%%" % [int(_work.get(hue_key, 0)), int(_work.get(sat_key, 100))]


func _cur_color(hue_key: String, sat_key: String) -> Color:
	return Color.from_hsv(float(int(_work.get(hue_key, 0))) / 360.0, min(float(int(_work.get(sat_key, 100))) / 100.0, 1.0), 0.9)


static func _make_swatch(color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(24, 24)
	p.add_theme_stylebox_override("panel", UiKit.stylebox(color, 6))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func _set_swatch_color(swatch: PanelContainer, color: Color) -> void:
	swatch.add_theme_stylebox_override("panel", UiKit.stylebox(color, 6))


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


## 预览框：三生石同款玉阵头像框(随气质染色) + 当前工作台容貌（换件/调色后整体重建，代价可忽略）。
func _preview_frame() -> Control:
	return UiKit.jade_frame(Portrait.build_from(_work, 132, _male()), UiKit.aura_tint(String(_work.get("aura", ""))))


func _refresh_preview() -> void:
	if _preview_box == null or not is_instance_valid(_preview_box):
		return
	for c in _preview_box.get_children():
		_preview_box.remove_child(c)
		c.queue_free()
	_preview_box.add_child(_preview_frame())


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


## 给滑杆套一层 1px 粉边框，轨道边界清晰可见。
static func _bordered_wrap(s: Control) -> PanelContainer:
	var w := PanelContainer.new()
	w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = UiKit.PINK_200
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 2
	sb.content_margin_right = 2
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	w.add_theme_stylebox_override("panel", sb)
	w.add_child(s)
	return w


func _slider(vmin: float, vmax: float, vstep: float, val: float, cb: Callable) -> Control:
	var s := HSlider.new()
	s.min_value = vmin
	s.max_value = vmax
	s.step = vstep
	s.value = val
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0, 20)
	s.focus_mode = Control.FOCUS_NONE
	s.add_theme_stylebox_override("slider", UiKit.stylebox(Color(0, 0, 0, 0), 3))
	s.add_theme_stylebox_override("grabber_area", UiKit.stylebox(UiKit.PINK_400, 3))
	s.add_theme_stylebox_override("grabber_area_highlight", UiKit.stylebox(UiKit.PINK_500, 3))
	s.add_theme_icon_override("grabber", app_face_dot(14, UiKit.PINK_600))
	s.add_theme_icon_override("grabber_highlight", app_face_dot(14, UiKit.PINK_500))
	s.add_theme_icon_override("grabber_pressed", app_face_dot(14, UiKit.PINK_700))
	s.value_changed.connect(cb)
	return _bordered_wrap(s)


## 渐变轨道滑杆：自定义 track 背景为传入的渐变贴图，外套 1px 粉边框。
func _gradient_slider(vmin: float, vmax: float, vstep: float, val: float, gradient: Gradient, cb: Callable) -> Control:
	var s := HSlider.new()
	s.min_value = vmin
	s.max_value = vmax
	s.step = vstep
	s.value = val
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0, 20)
	s.focus_mode = Control.FOCUS_NONE
	var gt := GradientTexture1D.new()
	gt.gradient = gradient
	gt.width = 256
	var track := StyleBoxTexture.new()
	track.texture = gt
	track.content_margin_left = 3
	track.content_margin_right = 3
	track.content_margin_top = 0
	track.content_margin_bottom = 0
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", UiKit.stylebox(Color(0, 0, 0, 0), 3))
	s.add_theme_stylebox_override("grabber_area_highlight", UiKit.stylebox(Color(0, 0, 0, 0), 3))
	s.add_theme_icon_override("grabber", app_face_dot(14, UiKit.WHITE))
	s.add_theme_icon_override("grabber_highlight", app_face_dot(14, UiKit.PINK_100))
	s.add_theme_icon_override("grabber_pressed", app_face_dot(14, UiKit.PINK_200))
	s.value_changed.connect(cb)
	return _bordered_wrap(s)


## 色相渐变：0°→360° 彩虹。
static func _hue_gradient() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color.from_hsv(0.0, 1.0, 0.9))
	g.add_point(0.167, Color.from_hsv(0.167, 1.0, 0.9))
	g.add_point(0.333, Color.from_hsv(0.333, 1.0, 0.9))
	g.add_point(0.5, Color.from_hsv(0.5, 1.0, 0.9))
	g.add_point(0.667, Color.from_hsv(0.667, 1.0, 0.9))
	g.add_point(0.833, Color.from_hsv(0.833, 1.0, 0.9))
	g.set_color(6, Color.from_hsv(1.0, 1.0, 0.9))
	return g


## 彩度渐变：灰 → 满彩。
static func _sat_gradient(base: Color) -> Gradient:
	var g := Gradient.new()
	var gray := Color(base.v, base.v, base.v)
	g.set_color(0, gray)
	g.set_color(1, base)
	return g


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
	b.custom_minimum_size = Vector2(32, 28)
	b.add_theme_font_override("font", UiKit.font(600))
	b.add_theme_font_size_override("font_size", 14)
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
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_override("font", UiKit.font(600))
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", UiKit.WHITE)
	b.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.PINK_500, 10))
	b.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.PINK_600, 10))
	b.add_theme_stylebox_override("pressed", UiKit.stylebox(UiKit.PINK_600, 10))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b


## 次要按钮：透明底 + 粉色描边，悬停/按下填色。
func _sec_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_override("font", UiKit.font(600))
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", UiKit.PINK_500)
	b.add_theme_color_override("font_hover_color", UiKit.WHITE)
	b.add_theme_color_override("font_pressed_color", UiKit.WHITE)
	var normal := UiKit.stylebox(UiKit.WHITE, 10)
	normal.border_width_left = 2
	normal.border_width_right = 2
	normal.border_width_top = 2
	normal.border_width_bottom = 2
	normal.border_color = UiKit.PINK_300
	b.add_theme_stylebox_override("normal", normal)
	var hover := UiKit.stylebox(UiKit.PINK_100, 10)
	hover.border_width_left = 2
	hover.border_width_right = 2
	hover.border_width_top = 2
	hover.border_width_bottom = 2
	hover.border_color = UiKit.PINK_400
	b.add_theme_stylebox_override("hover", hover)
	var pressed := UiKit.stylebox(UiKit.PINK_500, 10)
	pressed.border_width_left = 2
	pressed.border_width_right = 2
	pressed.border_width_top = 2
	pressed.border_width_bottom = 2
	pressed.border_color = UiKit.PINK_500
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b
