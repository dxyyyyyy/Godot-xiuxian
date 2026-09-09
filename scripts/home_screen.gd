extends "res://scripts/screen_base.gd"
## 家园页：标题 + 两个可折叠区块（灵食烹饪 / 灵田种植）

var farmlands := [
	{"level": 3, "plant": "灵稻", "quantity": 50, "progress": 75, "totalTime": "4小时", "remainingTime": "1小时"},
	{"level": 5, "plant": "仙草", "quantity": 30, "progress": 40, "totalTime": "6小时", "remainingTime": "3.6小时"},
	{"level": 2, "plant": "灵芝", "quantity": 20, "progress": 90, "totalTime": "8小时", "remainingTime": "0.8小时"},
	{"level": 4, "plant": "天莲", "quantity": 15, "progress": 60, "totalTime": "10小时", "remainingTime": "4小时"},
	{"locked": true, "unlockLevel": 15},
	{"locked": true, "unlockLevel": 20},
	{"locked": true, "unlockLevel": 25},
	{"locked": true, "unlockLevel": 30},
]
var cooking_stoves := [
	{"food": "灵气糕点", "level": 3, "remainingTime": "30分钟", "progress": 60},
	{"empty": true},
	{"food": "养魂汤", "level": 5, "remainingTime": "1.5小时", "progress": 25},
	{"empty": true},
	{"locked": true, "unlockLevel": 10},
	{"locked": true, "unlockLevel": 15},
	{"locked": true, "unlockLevel": 20},
	{"locked": true, "unlockLevel": 25},
]


func _build(vb: VBoxContainer) -> void:
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	head.add_child(UiKit.label("灵田家园", 24, UiKit.PINK_600, 700, HORIZONTAL_ALIGNMENT_CENTER))
	head.add_child(UiKit.label("辛勤耕耘，收获仙缘", 14, UiKit.PINK_400, 400, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(head)

	vb.add_child(_section("🍳 灵食烹饪", _build_cooking_grid()))
	vb.add_child(_section("🌾 灵田种植", _build_farm_grid()))


## 折叠区块：标题按钮 + 内容网格
func _section(title: String, body: Control) -> PanelContainer:
	var card := UiKit.card()
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	card.add_child(outer)

	var head_btn := Button.new()
	head_btn.focus_mode = Control.FOCUS_NONE
	head_btn.custom_minimum_size = Vector2(0, 56)
	var normal_sb := UiKit.stylebox(UiKit.WHITE, 16)
	normal_sb.corner_radius_bottom_left = 0
	normal_sb.corner_radius_bottom_right = 0
	var hover_sb := UiKit.stylebox(UiKit.PINK_50, 16)
	hover_sb.corner_radius_bottom_left = 0
	hover_sb.corner_radius_bottom_right = 0
	head_btn.add_theme_stylebox_override("normal", normal_sb)
	head_btn.add_theme_stylebox_override("hover", hover_sb)
	head_btn.add_theme_stylebox_override("pressed", hover_sb)
	head_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(UiKit.label(title, 18, UiKit.PINK_700, 600))
	hb.add_child(UiKit.expander())
	var chevron := UiKit.icon_rect("chevron-down", 20, UiKit.PINK_500)
	chevron.flip_v = true  # 展开时箭头朝上
	hb.add_child(chevron)
	var head_wrap := UiKit.margin_wrap(hb, 16)
	head_wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	head_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_btn.add_child(head_wrap)
	outer.add_child(head_btn)

	var body_wrap := UiKit.margin_wrap(body, 16)
	body_wrap.add_theme_constant_override("margin_top", 0)
	outer.add_child(body_wrap)

	head_btn.pressed.connect(func() -> void:
		var will_show: bool = not body_wrap.visible
		body_wrap.visible = will_show
		chevron.flip_v = will_show
	)
	return card


func _build_cooking_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	for s in cooking_stoves:
		grid.add_child(_stove_tile(s))
	return grid


func _build_farm_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	for land in farmlands:
		grid.add_child(_land_tile(land))
	return grid


func _locked_content(sub: String) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 4)
	vb.custom_minimum_size = Vector2(0, 140)
	var circ := UiKit.circle(64, UiKit.GRAY_200, Color.TRANSPARENT, "lock", 32, UiKit.GRAY_400)
	circ.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(circ)
	vb.add_child(UiKit.label("未解锁", 14, UiKit.GRAY_400, 400, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(UiKit.label(sub, 12, UiKit.GRAY_400, 400, HORIZONTAL_ALIGNMENT_CENTER))
	return vb


func _stove_tile(s: Dictionary) -> PanelContainer:
	var box := UiKit.padded(UiKit.pink_box(), 12)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if s.get("locked", false):
		box.add_child(_locked_content("Lv.%d解锁" % int(s.unlockLevel)))
		return box
	if s.get("empty", false):
		var ec := VBoxContainer.new()
		ec.alignment = BoxContainer.ALIGNMENT_CENTER
		ec.add_theme_constant_override("separation", 4)
		ec.custom_minimum_size = Vector2(0, 140)
		var circ := UiKit.circle(64, UiKit.GRAY_200, UiKit.GRAY_300, "flame", 32, UiKit.GRAY_400)
		circ.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ec.add_child(circ)
		ec.add_child(UiKit.label("空闲中", 14, UiKit.GRAY_400, 400, HORIZONTAL_ALIGNMENT_CENTER))
		box.add_child(ec)
		return box

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	var tile := UiKit.gradient_panel(UiKit.ORANGE_200, UiKit.ORANGE_300, 8)
	tile.custom_minimum_size = Vector2(0, 80)
	var tc := CenterContainer.new()
	tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tv := VBoxContainer.new()
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", 2)
	tv.add_child(UiKit.icon_rect("flame", 32, UiKit.ORANGE_500))
	tv.add_child(UiKit.label("🍲", 20, UiKit.PINK_700))
	tc.add_child(tv)
	tile.add_child(tc)
	vb.add_child(tile)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.add_child(UiKit.label(s.food, 14, UiKit.PINK_700, 600))
	name_row.add_child(UiKit.expander())
	name_row.add_child(UiKit.pill("Lv.%d" % int(s.level), UiKit.PINK_600, UiKit.WHITE, 12, 600))
	vb.add_child(name_row)
	vb.add_child(_progress_block("烹饪进度", int(s.progress), UiKit.ORANGE_500, s.remainingTime))
	box.add_child(vb)
	return box


func _land_tile(land: Dictionary) -> PanelContainer:
	var box := UiKit.padded(UiKit.pink_box(), 12)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if land.get("locked", false):
		box.add_child(_locked_content("Lv.%d解锁" % int(land.unlockLevel)))
		return box

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.add_child(UiKit.pill("Lv.%d 土地" % int(land.level), UiKit.PINK_600, UiKit.WHITE, 12, 600))
	top.add_child(UiKit.expander())
	top.add_child(UiKit.label(land.totalTime, 12, UiKit.PINK_400))
	vb.add_child(top)

	var tile := UiKit.gradient_panel(UiKit.AMBER_100, UiKit.GREEN_100, 8)
	tile.custom_minimum_size = Vector2(0, 60)
	var tc := CenterContainer.new()
	tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tv := VBoxContainer.new()
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", 2)
	tv.add_child(UiKit.label("🌾", 20, UiKit.PINK_700))
	tv.add_child(UiKit.label(land.plant, 12, UiKit.GREEN_700, 600))
	tc.add_child(tv)
	tile.add_child(tc)
	vb.add_child(tile)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.add_child(UiKit.label(land.plant, 14, UiKit.PINK_700, 600))
	name_row.add_child(UiKit.expander())
	name_row.add_child(UiKit.label("x%d" % int(land.quantity), 14, UiKit.PINK_500, 500))
	vb.add_child(name_row)
	vb.add_child(_progress_block("成熟进度", int(land.progress), UiKit.GREEN_500, land.remainingTime))
	box.add_child(vb)
	return box


func _progress_block(caption: String, pct: int, fill: Color, remaining: String) -> VBoxContainer:
	var prog := VBoxContainer.new()
	prog.add_theme_constant_override("separation", 4)
	var prow := HBoxContainer.new()
	prow.add_child(UiKit.label(caption, 12, UiKit.PINK_400))
	prow.add_child(UiKit.expander())
	prow.add_child(UiKit.label("%d%%" % pct, 12, UiKit.PINK_400))
	prog.add_child(prow)
	prog.add_child(UiKit.progress(pct / 100.0, fill))
	prog.add_child(UiKit.label("剩余 " + remaining, 12, UiKit.PINK_400, 400, HORIZONTAL_ALIGNMENT_RIGHT))
	return prog
