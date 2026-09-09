extends "res://scripts/screen_base.gd"
## 人物页：4 列角色关系网格

var characters := [
	{"name": "云梦瑶", "level": 25, "gender": "female", "friendship": 85, "love": 60},
	{"name": "剑无痕", "level": 30, "gender": "male", "friendship": 70, "love": 45},
	{"name": "月灵儿", "level": 22, "gender": "female", "friendship": 90, "love": 75},
	{"name": "风逍遥", "level": 28, "gender": "male", "friendship": 65, "love": 30},
	{"name": "花千骨", "level": 24, "gender": "female", "friendship": 80, "love": 55},
	{"name": "叶青云", "level": 32, "gender": "male", "friendship": 75, "love": 40},
	{"name": "紫霞仙子", "level": 26, "gender": "female", "friendship": 95, "love": 85},
	{"name": "白云飞", "level": 29, "gender": "male", "friendship": 60, "love": 25},
]


func _build(vb: VBoxContainer) -> void:
	vb.add_theme_constant_override("separation", 16)
	vb.add_child(UiKit.label("人物关系", 24, UiKit.PINK_600, 600))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	for c in characters:
		grid.add_child(_character_tile(c))
	vb.add_child(grid)


func _character_tile(c: Dictionary) -> VBoxContainer:
	var tile := VBoxContainer.new()
	tile.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_theme_constant_override("separation", 8)

	# 头像 + 性别角标（角标定位在头像右上角，需要普通 Control 手动摆位）
	var avatar_wrap := Control.new()
	avatar_wrap.custom_minimum_size = Vector2(68, 68)
	avatar_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var avatar := UiKit.circle(64, UiKit.PINK_300, UiKit.PINK_400, "users", 28, UiKit.WHITE, true)
	avatar_wrap.add_child(avatar)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UiKit.stylebox(
		UiKit.PINK_500 if c.gender == "female" else UiKit.BLUE_500, 999))
	badge.custom_minimum_size = Vector2(22, 22)
	var bl := UiKit.label("♀" if c.gender == "female" else "♂", 12, UiKit.WHITE, 700, HORIZONTAL_ALIGNMENT_CENTER)
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(bl)
	badge.position = Vector2(48, -4)
	avatar_wrap.add_child(badge)
	tile.add_child(avatar_wrap)

	var name_vb := VBoxContainer.new()
	name_vb.add_theme_constant_override("separation", 1)
	name_vb.add_child(UiKit.label(c.name, 12, UiKit.PINK_700, 600, HORIZONTAL_ALIGNMENT_CENTER))
	name_vb.add_child(UiKit.label("Lv.%d" % int(c.level), 12, UiKit.PINK_400, 400, HORIZONTAL_ALIGNMENT_CENTER))
	tile.add_child(name_vb)

	var hearts := HBoxContainer.new()
	hearts.alignment = BoxContainer.ALIGNMENT_CENTER
	hearts.add_theme_constant_override("separation", 8)
	hearts.add_child(_heart_stat(UiKit.YELLOW_400, int(c.friendship)))
	hearts.add_child(_heart_stat(UiKit.RED_400, int(c.love)))
	tile.add_child(hearts)
	return tile


func _heart_stat(tint: Color, value: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	h.add_child(UiKit.icon_rect("heart_filled", 12, tint))
	h.add_child(UiKit.label(str(value), 12, UiKit.PINK_600, 500))
	return h
