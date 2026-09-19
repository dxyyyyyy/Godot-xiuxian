extends "res://scripts/apps/app_base.gd"
## 捏脸：主角容貌工坊 —— 性别 + 脸/眉/眼/嘴/前发/后发/衣 逐件切换 + 发色/瞳色滑杆（CharaGraphicMaker
## 部件库编目；耳朵固定默认人耳，饰品/底饰槽已废弃），实时叠绘预览；应用后写入本世(run.look)，
## 日程人物卡头像随之更新。切换性别即换整套部件目录（男=脸C、女=脸D），各槽重置为新性别默认件。

const Portrait := preload("res://scripts/portrait.gd")
const NG := preload("res://sim/NpcGenerator.gd")

var _content: VBoxContainer
var _rebuild_pending := false
var _work := {}
var _preview_box: PanelContainer
var _val_labels := {}
var _aura_note: Label = null   # 气质效果说明(‹› 切气质时同步刷新)
var _rng := RandomNumberGenerator.new()

const FIELDS := [
	["gender", "性别"], ["face", "脸型"], ["brows", "眉"], ["eyes", "眼"], ["mouth", "嘴"],
	["hair_front", "前发"], ["hair_back", "后发"], ["cloth", "服装"], ["aura", "气质"],
]
## 调色区: [标题, 色相键, 彩度键] —— 色相 0-359°, 彩度 0-200%(发色联动前发/后发/眉, 瞳色作用于眼)
const COLOR_ROWS := [["发色", "hair_hue", "hair_sat"], ["瞳色", "eye_hue", "eye_sat"]]
var _color_labels := {}


func _build_content(vb: VBoxContainer) -> void:
	vb.add_child(bleed_head("捏脸", "主角容貌工坊 —— 七件叠绘成一张脸。"))
	_rng.randomize()
	if _work.is_empty():
		var saved := Game.player_look()
		var male := String(saved.get("gender", "female")) == "male"
		_work = NG.resolve_look(saved, male)
		_work["gender"] = String(saved.get("gender", "female"))
		_work["aura"] = String(saved.get("aura", NG.AURAS[0]))
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

	# 实时预览（青玉底粉盒里居中放大）
	_preview_box = UiKit.padded(UiKit.pink_box(UiKit.JADE_50), 16)
	_preview_box.add_child(Portrait.build_from(_work, 128, _male()))
	_content.add_child(_preview_box)

	# 调色区：发色/瞳色 色相·彩度滑杆
	_color_labels.clear()
	var colors := VBoxContainer.new()
	colors.add_theme_constant_override("separation", 6)
	for r in COLOR_ROWS:
		colors.add_child(_color_row(String(r[0]), String(r[1]), String(r[2])))
	_content.add_child(colors)

	# 十二件切换行
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	for f in FIELDS:
		rows.add_child(_row(String(f[0]), String(f[1])))
	_content.add_child(rows)

	# 气质效果说明(气质已玩法化, 见 data/auras.json)
	_aura_note = UiKit.label(_aura_note_text(), 11, UiKit.PINK_400)
	_aura_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_aura_note)

	# 操作：重置 / 应用
	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 6)
	act.add_child(_big_button("重置", func() -> void:
		_work = Portrait.default_look(_male())
		_rebuild()
	))
	act.add_child(_big_button("随机", _randomize_look))
	var apply := _big_button("应用容貌", func() -> void:
		Game.set_player_look(_work)
		exit_app.emit()   # 定容完成 → 离开玉牌，进入游戏主界面
	)
	apply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	act.add_child(apply)
	_content.add_child(act)


## 随机除性别外的全部部件槽(气质保留)：走 NpcGenerator 的目录随机(前后发同色/耳随肤色已内置)。
func _randomize_look() -> void:
	var look: Dictionary = NG.random_look(_rng, _male())
	for k in look:
		_work[k] = look[k]
	_rebuild()


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


## 调色行：标题 + 当前值 + 色相滑杆 + 彩度滑杆。
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
	s.add_theme_icon_override("grabber", _dot_texture(14, UiKit.PINK_600))
	s.add_theme_icon_override("grabber_highlight", _dot_texture(14, UiKit.PINK_500))
	s.add_theme_icon_override("grabber_pressed", _dot_texture(14, UiKit.PINK_700))
	s.value_changed.connect(cb)
	return s


## 圆形滑块贴图(4x 超采样抗锯齿)。
static func _dot_texture(d: int, color: Color) -> ImageTexture:
	var big := d * 4
	var img := Image.create(big, big, false, Image.FORMAT_RGBA8)
	var c := big * 0.5 - 0.5
	for y in big:
		for x in big:
			img.set_pixel(x, y, color if Vector2(x - c, y - c).length() <= c else Color(0, 0, 0, 0))
	img.resize(d, d, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


func _cycle(field: String, dir: int) -> void:
	var arr: Array = _arr(field)
	if arr.is_empty():
		return
	var i := arr.find(String(_work.get(field, "")))
	_work[field] = String(arr[posmod(i + dir, arr.size())])
	if field == "gender":
		# 换性别 = 换整套部件目录，各槽重置为新性别默认件（保留气质；default_look 已带性别）
		var aura := String(_work.get("aura", NG.AURAS[0]))
		_work = Portrait.default_look(_male())
		_work["aura"] = aura
	for f in _val_labels:
		(_val_labels[f] as Label).text = _disp(f, String(_work.get(f, "")))
	if _aura_note != null and is_instance_valid(_aura_note):
		_aura_note.text = _aura_note_text()
	_refresh_preview()


## 气质效果说明文案(‹› 切气质后即时重算)
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
	_preview_box.add_child(Portrait.build_from(_work, 128, _male()))


func _male() -> bool:
	return String(_work.get("gender", "female")) == "male"


## 显示文本：性别用中文、空件为「无」，其余为部件名 + 序号（如「垂眼 3/33」）。
func _disp(field: String, val: String) -> String:
	if field == "gender":
		return "男" if val == "male" else "女"
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
	match field:
		"gender":
			return ["female", "male"]
		"aura":
			return NG.AURAS
		_:
			return _option_ids(field)


## 当前性别某槽位的可选值（可空槽位把「无」排最前）。
func _option_ids(field: String) -> Array:
	var ids: Array = []
	if field in NG.OPTIONAL_SLOTS:
		ids.append("")
	for e in NG.options(_male(), field):
		ids.append(String((e as Dictionary).get("id", "")))
	return ids


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
