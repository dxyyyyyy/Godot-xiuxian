extends "res://scripts/apps/app_base.gd"
## 纪事：一世纪事日志（按年归档，最新在上；通栏铺满）。数据来自 GameState.chronicle，
## 由 Game.logged（灰盒月度结算流水 + 抉择）实时汇入；分组键取自时间标签「第X世 · 第Y年」。

var _list_vb: VBoxContainer
var _folded := {}   # 年份卷标 -> 是否收起（跨重建保持，仅本会话）
var _name_keys := {}   # 姓名 -> npc key，反查表见 UiKit.npc_name_keys


func _build_content(vb: VBoxContainer) -> void:
	vb.add_child(bleed_head("一世纪事", "日子一笔一笔记，一年一卷。"))
	_list_vb = VBoxContainer.new()
	_list_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_vb.add_theme_constant_override("separation", 0)
	vb.add_child(_list_vb)
	GameState.chronicle_changed.connect(_schedule_rebuild)
	_rebuild()


var _rebuild_pending := false

func _schedule_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_pending = false
	_name_keys = UiKit.npc_name_keys()
	for c in _list_vb.get_children():
		_list_vb.remove_child(c)
		c.queue_free()
	if GameState.chronicle.is_empty():
		var empty := UiKit.label("纪事未启——日子还长。", 13, UiKit.PINK_400)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var empty_wrap := UiKit.margin_wrap(empty, 16)
		empty_wrap.add_theme_constant_override("margin_top", 24)
		_list_vb.add_child(empty_wrap)
		return
	# 倒序扫描：最新一年在最上，同年条目聚为一卷
	var groups: Array = []
	for i in range(GameState.chronicle.size() - 1, -1, -1):
		var e: Dictionary = GameState.chronicle[i]
		var year := _year_label(String(e.day))
		if groups.is_empty() or String(groups.back().year) != year:
			groups.append({"year": year, "lines": []})
		groups.back().lines.append(String(e.text))
	for g in groups:
		_list_vb.add_child(_year_card(String(g.year), g.lines))


## 从时间标签「第X世 · 第Y年 · M月」提取年份卷标；异常标签（旧档迁移等）原样归卷。
func _year_label(day: String) -> String:
	var parts := day.split("·")
	if parts.size() >= 2:
		return "%s · %s" % [String(parts[0]).strip_edges(), String(parts[1]).strip_edges()]
	return day


## 年卷通栏块：白底铺满屏幕宽，块间以 1px 分隔线相接，内部 16px 留白。
## 点年卷头部收起/展开该年条目（头部显示条数与箭头）。
func _year_card(year: String, lines: Array) -> PanelContainer:
	var c := bleed_section()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)

	var folded: bool = _folded.get(year, false)

	# 条目行（先建,头部按钮的切换回调要引用它）
	var lines_vb := VBoxContainer.new()
	lines_vb.visible = not folded
	lines_vb.add_theme_constant_override("separation", 10)
	for line in lines:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(UiKit.label("·", 14, UiKit.PINK_300, 700))
		row.add_child(UiKit.chronicle_line(String(line), _name_keys))
		lines_vb.add_child(row)

	# 年卷头部（整行可点,收起/展开）
	var chevron := UiKit.icon_rect("chevron-down", 16, UiKit.PINK_500)
	chevron.flip_v = not folded   # 展开时箭头朝上
	var head_btn := Button.new()
	head_btn.focus_mode = Control.FOCUS_NONE
	head_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	head_btn.custom_minimum_size = Vector2(0, 28)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		head_btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	head_btn.pressed.connect(func() -> void:
		var now: bool = not _folded.get(year, false)
		_folded[year] = now
		lines_vb.visible = not now
		chevron.flip_v = not now
	)
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(UiKit.pill(year, UiKit.WHITE, UiKit.PINK_500, 12, 600))
	hb.add_child(UiKit.expander())
	hb.add_child(UiKit.label("%d 条" % lines.size(), 11, UiKit.PINK_400))
	hb.add_child(UiKit.hspace(6))
	hb.add_child(chevron)
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	head_btn.add_child(hb)
	cv.add_child(head_btn)
	cv.add_child(lines_vb)

	c.add_child(UiKit.margin_wrap(cv, 16))
	return c
