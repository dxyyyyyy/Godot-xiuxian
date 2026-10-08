extends "res://scripts/apps/app_base.gd"
## 设置：音量/画质/红点总开关 + 时速档（灰盒月时钟，暂停~100×）。
## 音量目前只存数值，接入音频系统后应用到 AudioServer 总线即可。

var quality_group := ButtonGroup.new()
var speed_group := ButtonGroup.new()
var speed_caption: Label
var _save_status: Label


func _build_content(vb: VBoxContainer) -> void:
	vb.add_child(bleed_head("设置", "音量、画质、红点与时间流速。"))
	vb.add_child(_volume_card("volume-2", "音效", "sound"))
	vb.add_child(_volume_card("music", "音乐", "music"))
	vb.add_child(_quality_card())
	vb.add_child(_red_dot_card())
	vb.add_child(_speed_card())
	vb.add_child(_save_card())
	vb.add_child(_about_card())
	Game.changed.connect(_update_speed_caption)


func _volume_card(icon_name: String, title: String, which: String) -> PanelContainer:
	var initial: int = GameState.sound_volume if which == "sound" else GameState.music_volume
	var c := bleed_section()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 12)
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 12)
	ch.add_child(UiKit.icon_rect(icon_name, 20, UiKit.PINK_500))
	ch.add_child(UiKit.label(title, 16, UiKit.PINK_700, 600))
	cv.add_child(ch)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var s := UiKit.slider(initial)
	var val := UiKit.label("%d%%" % initial, 14, UiKit.PINK_600, 600)
	val.custom_minimum_size = Vector2(40, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(v: float) -> void:
		val.text = "%d%%" % int(v)
		if which == "sound":
			GameState.sound_volume = int(v)
		else:
			GameState.music_volume = int(v)
	)
	row.add_child(s)
	row.add_child(val)
	cv.add_child(row)
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c


func _quality_card() -> PanelContainer:
	var c := bleed_section()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 12)
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 12)
	ch.add_child(UiKit.icon_rect("eye", 20, UiKit.PINK_500))
	ch.add_child(UiKit.label("画质", 16, UiKit.PINK_700, 600))
	cv.add_child(ch)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var qualities := [["low", "低"], ["medium", "中"], ["high", "高"], ["ultra", "超高"]]
	for q in qualities:
		var b := UiKit.seg_button(q[1], quality_group, String(q[0]) == GameState.quality)
		var qid: String = q[0]
		b.pressed.connect(func() -> void: GameState.quality = qid)
		row.add_child(b)
	cv.add_child(row)
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c


## 红点总开关（眼不见为净）：关闭后玉牌照常可用，只是没有提醒。
func _red_dot_card() -> PanelContainer:
	var c := bleed_section()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var left := HBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(UiKit.icon_rect("bell", 20, UiKit.PINK_500))
	left.add_child(UiKit.label("红点提醒", 16, UiKit.PINK_700, 600))
	row.add_child(left)
	row.add_child(_make_switch(GameState.notifications, func(v: bool) -> void: GameState.set_notifications(v)))
	cv.add_child(row)
	cv.add_child(UiKit.label("眼不见为净——关闭后玉牌照常可用，只是没有提醒。", 12, UiKit.PINK_400))
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c


## 时速档（灰盒月时钟）：0=暂停；1×≈2秒/月，最快 100×。
func _speed_card() -> PanelContainer:
	var c := bleed_section()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 12)
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 12)
	ch.add_child(UiKit.icon_rect("clock", 20, UiKit.PINK_500))
	ch.add_child(UiKit.label("时间流速（月历）", 16, UiKit.PINK_700, 600))
	cv.add_child(ch)

	var gears: Array = Game.tune("speed_gears", [1, 2, 5, 10, 25, 50, 100])
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var pause := UiKit.seg_button("暂停", speed_group, Game.speed == 0)
	pause.pressed.connect(func() -> void: Game.set_speed(0))
	grid.add_child(pause)
	for g in gears:
		var v := int(g)
		var b := UiKit.seg_button("%d×" % v, speed_group, Game.speed == v)
		b.pressed.connect(func() -> void: Game.set_speed(v))
		grid.add_child(b)
	cv.add_child(grid)

	speed_caption = UiKit.label("", 12, UiKit.PINK_400)
	cv.add_child(speed_caption)
	_update_speed_caption()
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c


func _update_speed_caption() -> void:
	if speed_caption == null:
		return
	if Game.is_ended():
		speed_caption.text = "当前时间流速: 停（此世已了结）"
	elif not Game.pending.is_empty():
		speed_caption.text = "当前时间流速: 停（事件待拍板）"
	else:
		speed_caption.text = "当前时间流速: %s · %s" % [str(Game.speed) + "×" if Game.speed > 0 else "暂停", Game.calendar()]


## 存档卡: 每年腊月自动落盘(tick_month, 写前轮转 3 代备份), 此处可手动补一手; 状态行显示上次落盘。
func _save_card() -> PanelContainer:
	var c := bleed_section()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 12)
	ch.add_child(UiKit.icon_rect("package", 20, UiKit.PINK_500))
	ch.add_child(UiKit.label("存档", 16, UiKit.PINK_700, 600))
	cv.add_child(ch)
	cv.add_child(UiKit.label("每年腊月自动落盘一次(写前轮转 .bak 备份可回滚); 也可随手存一手。", 12, UiKit.PINK_400))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var b := Button.new()
	b.text = "立即存档"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(104, 34)
	b.add_theme_font_override("font", UiKit.font(600))
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", UiKit.WHITE)
	b.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.PINK_500, 8))
	b.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.PINK_600, 8))
	b.add_theme_stylebox_override("pressed", UiKit.stylebox(UiKit.PINK_600, 8))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(_on_save_pressed)
	row.add_child(b)
	_save_status = UiKit.label(_last_saved_text(), 12, UiKit.PINK_500)
	row.add_child(_save_status)
	cv.add_child(row)
	# 闲话壁称全名开关(称谓规约 §8.1): 关=主角帖只称代称, 不落真名
	var sw_row := HBoxContainer.new()
	sw_row.add_theme_constant_override("separation", 12)
	var left := HBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(UiKit.label("闲话壁称全名", 13, UiKit.PINK_600, 500))
	sw_row.add_child(left)
	sw_row.add_child(_make_switch(GameState.wall_full_name, func(v: bool) -> void: GameState.set_wall_full_name(v)))
	cv.add_child(sw_row)
	cv.add_child(UiKit.label("关 = 照壁主角帖只称代称（那位），不落真名；对已上壁的旧帖同样生效。", 11, UiKit.PINK_400))
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c


func _on_save_pressed() -> void:
	if _save_status == null:
		return
	var res: Dictionary = Game.save_now()
	if String(res.get("day", "")) == "":
		_save_status.text = "此世未启 · 无可存"
		return
	if bool(res.get("ok", false)):
		_save_status.text = "已存 · %s · %s" % [String(res.day), Time.get_time_string_from_system().left(5)]
	else:
		_save_status.text = "⚠ 写入失败 · 检查磁盘/存档目录"


## 上次落盘时间: 读本世存档文件的修改时间(MM-DD HH:MM)。
func _last_saved_text() -> String:
	var path := "user://baiwei_run_life_%d.json" % int(Game.run.get("life", 1))
	if not FileAccess.file_exists(path):
		return "尚无落盘记录"
	var t := FileAccess.get_modified_time(path)
	if t <= 0:
		return "尚无落盘记录"
	var ds := Time.get_datetime_string_from_unix_time(t)
	return "上次落盘 %s %s" % [ds.substr(5, 5), ds.substr(11, 5)]


## 「关于本牌」
func _about_card() -> PanelContainer:
	var c := bleed_section()
	var cv := VBoxContainer.new()
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_theme_constant_override("separation", 4)
	cv.add_child(UiKit.label("百味长生 · 月历常流 · 一切结算只走 tick_month 唯一入口。", 13, UiKit.PINK_600, 400, HORIZONTAL_ALIGNMENT_CENTER))
	cv.add_child(UiKit.label("版本 v2.0.0", 12, UiKit.PINK_400, 400, HORIZONTAL_ALIGNMENT_CENTER))
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c


## iOS 风格开关（48x24 滑块）
func _make_switch(initial: bool, on_change: Callable) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = initial
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(48, 24)
	b.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.GRAY_300, 999))
	b.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.GRAY_300, 999))
	b.add_theme_stylebox_override("pressed", UiKit.stylebox(UiKit.PINK_500, 999))
	b.add_theme_stylebox_override("hover_pressed", UiKit.stylebox(UiKit.PINK_500, 999))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var knob := Panel.new()
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	knob.add_theme_stylebox_override("panel", UiKit.stylebox(UiKit.WHITE, 999))
	knob.custom_minimum_size = Vector2(20, 20)
	knob.size = Vector2(20, 20)
	knob.position = Vector2(26 if initial else 2, 2)
	b.add_child(knob)
	b.toggled.connect(func(on_now: bool) -> void:
		knob.position.x = 26.0 if on_now else 2.0
		on_change.call(on_now)
	)
	return b
