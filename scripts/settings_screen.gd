extends "res://scripts/screen_base.gd"
## 设置页：音量滑条、画质/时间调速分段按钮、推送开关、版本信息

var quality_group := ButtonGroup.new()
var speed_group := ButtonGroup.new()
var speed_caption: Label


func _build(vb: VBoxContainer) -> void:
	vb.add_theme_constant_override("separation", 16)
	vb.add_child(UiKit.label("游戏设置", 24, UiKit.PINK_600, 600))

	vb.add_child(_volume_card("volume-2", "音效", 75))
	vb.add_child(_volume_card("music", "音乐", 60))
	vb.add_child(_quality_card())
	vb.add_child(_notify_card())
	vb.add_child(_speed_card())
	vb.add_child(_version_card())


func _volume_card(icon_name: String, title: String, initial: int) -> PanelContainer:
	var c := UiKit.card()
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
	s.value_changed.connect(func(v: float) -> void: val.text = "%d%%" % int(v))
	row.add_child(s)
	row.add_child(val)
	cv.add_child(row)
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c


func _quality_card() -> PanelContainer:
	var c := UiKit.card()
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
		row.add_child(UiKit.seg_button(q[1], quality_group, q[0] == "high"))
	cv.add_child(row)
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c


func _notify_card() -> PanelContainer:
	var c := UiKit.card()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var left := HBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(UiKit.icon_rect("bell", 20, UiKit.PINK_500))
	left.add_child(UiKit.label("推送通知", 16, UiKit.PINK_700, 600))
	row.add_child(left)
	row.add_child(_make_switch(true))
	c.add_child(UiKit.margin_wrap(row, 16))
	return c


func _speed_card() -> PanelContainer:
	var c := UiKit.card()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 12)
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 12)
	ch.add_child(UiKit.icon_rect("clock", 20, UiKit.PINK_500))
	ch.add_child(UiKit.label("时间调速", 16, UiKit.PINK_700, 600))
	cv.add_child(ch)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var speeds := [[0.5, "0.5x"], [1.0, "1x"], [2.0, "2x"], [5.0, "5x"], [10.0, "10x"]]
	for opt in speeds:
		var b := UiKit.seg_button(opt[1], speed_group, is_equal_approx(opt[0], 1.0))
		b.pressed.connect(_on_speed_changed.bind(opt[0]))
		row.add_child(b)
	cv.add_child(row)

	speed_caption = UiKit.label("当前游戏时间流速: 1倍", 12, UiKit.PINK_400)
	cv.add_child(speed_caption)
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c


func _version_card() -> PanelContainer:
	var c := UiKit.card()
	var vv := VBoxContainer.new()
	vv.alignment = BoxContainer.ALIGNMENT_CENTER
	vv.add_theme_constant_override("separation", 4)
	vv.add_child(UiKit.label("修仙模拟器", 14, UiKit.PINK_600, 400, HORIZONTAL_ALIGNMENT_CENTER))
	vv.add_child(UiKit.label("版本 v1.0.0", 12, UiKit.PINK_400, 400, HORIZONTAL_ALIGNMENT_CENTER))
	c.add_child(UiKit.margin_wrap(vv, 16))
	return c


func _on_speed_changed(value: float) -> void:
	var shown := "0.5" if is_equal_approx(value, 0.5) else str(int(value))
	speed_caption.text = "当前游戏时间流速: %s倍" % shown


## iOS 风格开关（48x24 滑块）
func _make_switch(initial: bool) -> Button:
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
	b.toggled.connect(func(on_now: bool) -> void: knob.position.x = 26.0 if on_now else 2.0)
	return b
