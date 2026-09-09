extends "res://scripts/screen_base.gd"
## 日程页：人物资料卡 + 今日行程列表

var schedules := [
	{"time": "06:00", "activity": "晨练", "status": "completed", "desc": "修炼基础功法"},
	{"time": "09:00", "activity": "采集灵草", "status": "completed", "desc": "后山采集药材"},
	{"time": "12:00", "activity": "炼丹", "status": "current", "desc": "炼制回灵丹"},
	{"time": "15:00", "activity": "闭关修炼", "status": "pending", "desc": "冲击筑基期"},
	{"time": "18:00", "activity": "拜访师尊", "status": "pending", "desc": "请教修炼心得"},
]


func _build(vb: VBoxContainer) -> void:
	var profile := UiKit.card()
	profile.add_child(UiKit.margin_wrap(_profile_card(), 24))
	vb.add_child(profile)

	var sched := UiKit.card()
	sched.add_child(UiKit.margin_wrap(_schedule_card(), 24))
	vb.add_child(sched)


func _profile_card() -> VBoxContainer:
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 16)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	top.add_child(UiKit.circle(80, UiKit.PINK_300, UiKit.PINK_400, "users", 40, UiKit.WHITE, true))
	var name_vb := VBoxContainer.new()
	name_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	name_vb.add_theme_constant_override("separation", 2)
	name_vb.add_child(UiKit.label("修仙者", 20, UiKit.PINK_700, 600))
	name_vb.add_child(UiKit.label("初入仙途", 12, UiKit.PINK_400))
	top.add_child(name_vb)
	pv.add_child(top)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.add_child(_stat_text("年纪", "18岁"))
	grid.add_child(_stat_bar("灵力", 0.75, "750"))
	grid.add_child(_stat_bar("生命", 0.90, "90%"))
	grid.add_child(_stat_text("突破率", "45%"))
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


func _schedule_card() -> VBoxContainer:
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 16)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiKit.icon_rect("calendar", 20, UiKit.PINK_700))
	head.add_child(UiKit.label("今日行程", 18, UiKit.PINK_700, 600))
	sv.add_child(head)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	for s in schedules:
		list.add_child(_schedule_row(s))
	sv.add_child(list)
	return sv


func _schedule_row(s: Dictionary) -> PanelContainer:
	var bg := UiKit.PINK_50
	var border := 0
	if s.status == "completed":
		bg = Color(UiKit.PINK_50, 0.6)
	elif s.status == "current":
		border = 2
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.stylebox(bg, 12, false, border, UiKit.PINK_300))
	UiKit.padded(p, 12)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var time_vb := VBoxContainer.new()
	time_vb.custom_minimum_size = Vector2(60, 0)
	time_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	time_vb.add_child(UiKit.label("时间", 12, UiKit.PINK_400, 400, HORIZONTAL_ALIGNMENT_CENTER))
	time_vb.add_child(UiKit.label(s.time, 14, UiKit.PINK_600, 600, HORIZONTAL_ALIGNMENT_CENTER))
	row.add_child(time_vb)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 2)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	title_row.add_child(UiKit.label(s.activity, 14, UiKit.PINK_700, 600))
	if s.status == "completed":
		title_row.add_child(UiKit.pill("已完成", UiKit.PINK_600, UiKit.PINK_200))
	elif s.status == "current":
		title_row.add_child(UiKit.pill("进行中", UiKit.WHITE, UiKit.PINK_400))
	info.add_child(title_row)
	info.add_child(UiKit.label(s.desc, 12, UiKit.PINK_400))
	row.add_child(info)

	p.add_child(row)
	return p
