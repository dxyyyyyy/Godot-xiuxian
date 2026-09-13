extends "res://scripts/apps/app_base.gd"
## 闲话壁：百话楼「壁讯」订阅入口（帖串正文归论坛体系统，此处为订阅壳 + 风味空态）。

var _state_title: Label
var _state_body: Label


func _build_content(vb: VBoxContainer) -> void:
	vb.add_theme_constant_override("separation", 16)
	vb.add_child(UiKit.label("闲话壁", 24, UiKit.PINK_600, 600))
	vb.add_child(_subscribe_card())
	_state_title = UiKit.label("", 16, UiKit.PINK_700, 600)
	_state_body = UiKit.label("", 13, UiKit.PINK_600)
	_state_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_state_card())
	_update_state()


func _subscribe_card() -> PanelContainer:
	var c := UiKit.card()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)

	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 12)
	ch.add_child(UiKit.icon_rect("bell", 20, UiKit.PINK_500))
	ch.add_child(UiKit.label("壁讯订阅", 16, UiKit.PINK_700, 600))
	cv.add_child(ch)

	var body := UiKit.label(
		"青梧城百话楼照壁上的热帖，由文脉抄录上传讯牌。\n月费一灵石，城乡同价——山村杂役也能读到全洲的热闹。",
		13, UiKit.PINK_600)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(body)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(UiKit.pill("月费 · 一灵石/月", UiKit.PINK_600, UiKit.PINK_100))
	var exp := UiKit.expander()
	row.add_child(exp)
	row.add_child(_make_switch())
	cv.add_child(row)
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c


func _state_card() -> PanelContainer:
	var c := UiKit.card()
	var cv := VBoxContainer.new()
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_theme_constant_override("separation", 6)
	cv.add_child(_state_title)
	cv.add_child(_state_body)
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c


func _make_switch() -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = GameState.gossip_subscribed
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
	knob.position = Vector2(26 if GameState.gossip_subscribed else 2, 2)
	b.add_child(knob)
	b.toggled.connect(func(on: bool) -> void:
		knob.position.x = 26.0 if on else 2.0
		GameState.gossip_subscribed = on
		_update_state()
	)
	return b


func _update_state() -> void:
	if GameState.gossip_subscribed:
		_state_title.text = "已订阅 · 今日无新帖"
		_state_body.text = "照壁上的墨迹还没干，且等一等。"
	else:
		_state_title.text = "未订阅"
		_state_body.text = "青梧城的闲话，隔着一座山。"
