extends "res://scripts/apps/app_base.gd"
## 纪事：一世纪事日志（逐日分组，最新在上）。数据由 GameState.log_chronicle 维护。

var _list_vb: VBoxContainer


func _build_content(vb: VBoxContainer) -> void:
	vb.add_theme_constant_override("separation", 16)
	vb.add_child(UiKit.label("一世纪事", 24, UiKit.PINK_600, 600))
	vb.add_child(UiKit.label("日子一笔一笔记。", 12, UiKit.PINK_400))
	_list_vb = VBoxContainer.new()
	_list_vb.add_theme_constant_override("separation", 12)
	vb.add_child(_list_vb)
	GameState.chronicle_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for c in _list_vb.get_children():
		_list_vb.remove_child(c)
		c.queue_free()
	if GameState.chronicle.is_empty():
		var empty := UiKit.label("纪事未启——日子还长。", 13, UiKit.PINK_400)
		_list_vb.add_child(empty)
		return
	# 倒序扫描：最新一天在最上，同日条目聚为一组
	var groups: Array = []
	for i in range(GameState.chronicle.size() - 1, -1, -1):
		var e: Dictionary = GameState.chronicle[i]
		var day := int(e.day)
		if groups.is_empty() or int(groups.back().day) != day:
			groups.append({"day": day, "lines": []})
		groups.back().lines.append(String(e.text))
	for g in groups:
		_list_vb.add_child(_day_card(int(g.day), g.lines))


func _day_card(day: int, lines: Array) -> PanelContainer:
	var c := UiKit.card()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	cv.add_child(UiKit.pill("第 %d 天" % day, UiKit.WHITE, UiKit.PINK_500, 12, 600))
	for line in lines:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(UiKit.label("·", 14, UiKit.PINK_300, 700))
		var lb := UiKit.label(String(line), 14, UiKit.PINK_700)
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lb)
		cv.add_child(row)
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c
