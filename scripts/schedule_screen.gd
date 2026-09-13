extends "res://scripts/screen_base.gd"
## 日程页：人物资料卡（读 GameState，含「行动方案」选择）+ 一世纪事（预留区块，待接入）。
## 纪事数据层已在 GameState.chronicle 就绪（玉牌·纪事 app 同源），接入时替换预留位即可。

var plan_group := ButtonGroup.new()

func _build(vb: VBoxContainer) -> void:
	var profile := UiKit.card()
	profile.add_child(UiKit.margin_wrap(_profile_card(), 24))
	vb.add_child(profile)

	var chron := UiKit.card()
	chron.add_child(UiKit.margin_wrap(_chronicle_card(), 24))
	vb.add_child(chron)


func _profile_card() -> VBoxContainer:
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 16)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	top.add_child(UiKit.circle(80, UiKit.PINK_300, UiKit.PINK_400, "users", 40, UiKit.WHITE, true))
	var name_vb := VBoxContainer.new()
	name_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	name_vb.add_theme_constant_override("separation", 2)
	name_vb.add_child(UiKit.label(GameState.player_name, 20, UiKit.PINK_700, 600))
	name_vb.add_child(UiKit.label(GameState.player_title, 12, UiKit.PINK_400))
	top.add_child(name_vb)
	top.add_child(UiKit.expander())
	top.add_child(_plan_panel())
	pv.add_child(top)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.add_child(_stat_text("年纪", "%d岁" % int(GameState.age)))
	grid.add_child(_stat_bar("灵力", GameState.spirit_pct / 100.0, str(GameState.spirit)))
	grid.add_child(_stat_bar("生命", GameState.health_pct / 100.0, "%d%%" % int(GameState.health_pct)))
	grid.add_child(_stat_text("突破率", "%d%%" % int(GameState.breakthrough_pct)))
	pv.add_child(grid)
	return pv


func _stat_text(caption: String, value: String) -> PanelContainer:
	var box := UiKit.padded(UiKit.pink_box(), 12)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.add_child(UiKit.label(caption, 12, UiKit.PINK_400))
	vb.add_child(UiKit.label(value, 18, UiKit.PINK_600, 600))
	box.add_child(vb)
	return box


func _stat_bar(caption: String, frac: float, value: String) -> PanelContainer:
	var box := UiKit.padded(UiKit.pink_box(), 12)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.add_child(UiKit.label(caption, 12, UiKit.PINK_400))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UiKit.progress(frac, UiKit.PINK_500))
	var val := UiKit.label(value, 14, UiKit.PINK_600, 600)
	val.custom_minimum_size = Vector2(36, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	vb.add_child(row)
	box.add_child(vb)
	return box


## 行动方案：四选一（GameState.action_plan 持久化；机制待接入）。
func _plan_panel() -> PanelContainer:
	var panel := UiKit.padded(UiKit.pink_box(), 12)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 8)
	pv.add_child(UiKit.label("行动方案", 13, UiKit.PINK_700, 600))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var plans := [
		["cultivate", "认真修炼"],
		["farm", "照顾灵田"],
		["cook", "做饭"],
		["travel", "出门游历"],
		["romance", "情缘来往"],
		["explore", "寻道探索"],
	]
	for p in plans:
		var b := _plan_button(String(p[1]), String(p[0]) == GameState.action_plan)
		var pid: String = p[0]
		b.pressed.connect(func() -> void: GameState.action_plan = pid)
		grid.add_child(b)
	pv.add_child(grid)
	panel.add_child(pv)
	return panel


func _plan_button(text: String, is_on: bool) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = plan_group
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 30)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_override("font", UiKit.font(500))
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", UiKit.PINK_600)
	b.add_theme_color_override("font_hover_color", UiKit.PINK_600)
	b.add_theme_color_override("font_focus_color", UiKit.PINK_600)
	b.add_theme_color_override("font_pressed_color", UiKit.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", UiKit.WHITE)
	var off := UiKit.stylebox(UiKit.PINK_100, 8)
	var on := UiKit.stylebox(UiKit.PINK_500, 8)
	for sb in [off, on]:
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
	b.add_theme_stylebox_override("normal", off)
	b.add_theme_stylebox_override("hover", off)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.set_pressed_no_signal(is_on)
	return b


## 一世纪事：内容先预留，接入前以留白占位。
func _chronicle_card() -> VBoxContainer:
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 16)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiKit.icon_rect("calendar", 20, UiKit.PINK_700))
	head.add_child(UiKit.label("一世纪事", 18, UiKit.PINK_700, 600))
	sv.add_child(head)

	var slot := UiKit.pink_box()
	slot.custom_minimum_size = Vector2(0, 120)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var slot_vb := VBoxContainer.new()
	slot_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_vb.add_theme_constant_override("separation", 6)
	slot_vb.add_child(UiKit.label("此间留白，待日子来填。", 14, UiKit.PINK_600, 500, HORIZONTAL_ALIGNMENT_CENTER))
	slot_vb.add_child(UiKit.label("一世纪事 · 内容待接入", 12, UiKit.PINK_400, 400, HORIZONTAL_ALIGNMENT_CENTER))
	slot.add_child(UiKit.margin_wrap(slot_vb, 16))
	sv.add_child(slot)
	return sv
