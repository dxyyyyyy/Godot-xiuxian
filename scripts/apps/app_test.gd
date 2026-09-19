extends "res://scripts/apps/app_base.gd"
## 测试：灰盒调试旋钮——高倍速时速 + 主动隐退重开（无境界限制）。
## 自日程页迁入；不影响铁律（一切结算仍只走 tick_month 唯一入口）。

var _content: VBoxContainer
var _rebuild_pending := false
var _item_dlg: Node = null   # 添加灵植的二级弹层


func _notification(what: int) -> void:
	# 切走页面时收起二级弹层（CanvasLayer 不随屏幕隐藏）
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_close_item_dialog()


func _build_content(vb: VBoxContainer) -> void:
	vb.add_child(bleed_head("测试", "数值验证用旋钮 —— 日常试玩用不着这里。"))
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 0)
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
	_content.add_child(_face_card())      # 捏脸入口(桌面无阵纹, 自测试页进)
	_content.add_child(_npc_face_card())  # 他人捏脸: 固定 NPC 容貌编辑
	if Game.run.is_empty():
		return
	_content.add_child(_speed_card())
	_content.add_child(_cheat_card())
	_content.add_child(_retire_card())


## 捏脸 · 他人入口: 给六位固定 NPC 捏脸(改写 data/npcs.json, 跨世生效)。
func _npc_face_card() -> PanelContainer:
	var c := bleed_section()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	cv.add_child(UiKit.label("捏脸 · 他人", 16, UiKit.PINK_700, 600))
	var desc := UiKit.label("给六位固定 NPC 捏脸：选人 → 换部件/配色 → 应用。写入 data/npcs.json，跨世生效（性别锁档案值）。", 12, UiKit.PINK_400)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(desc)
	cv.add_child(_action_button("进入他人捏脸", func() -> void: open_app.emit("npcface"), true))
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c


## 捏脸工坊入口: 主角容貌编辑页自玉牌桌面移入测试页(转世流程仍会自动跳入捏脸页)。
func _face_card() -> PanelContainer:
	var c := bleed_section()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	cv.add_child(UiKit.label("捏脸工坊", 16, UiKit.PINK_700, 600))
	var desc := UiKit.label("编辑主角容貌：性别、七件部件、发色瞳色；应用后写入本世并更新日程人物卡头像。", 12, UiKit.PINK_400)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(desc)
	cv.add_child(_action_button("进入捏脸工坊", func() -> void: open_app.emit("face"), true))
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c


## 高倍速档(自日程页移入): 10×~100×。常规档(暂停/1×/2×/5×)仍在日程页。
func _speed_card() -> PanelContainer:
	var c := bleed_section()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	cv.add_child(UiKit.label("时间流速 · 高倍速", 16, UiKit.PINK_700, 600))

	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	var group := ButtonGroup.new()
	for v in [0, 10, 25, 50, 100]:
		var b := UiKit.seg_button("暂停" if v == 0 else "%d×" % v, group, Game.speed == v)
		b.pressed.connect(func() -> void: Game.set_speed(v))
		grid.add_child(b)
	cv.add_child(grid)

	var speed_txt := ("%d×" % Game.speed) if Game.speed > 0 else "暂停"
	var cap := UiKit.label("当前时速: %s · %s（常规档在日程页）" % [speed_txt, Game.calendar()], 12, UiKit.PINK_400)
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(cap)
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c


## 修改器: 加修为 / 加灵石 / 加仓库物品（都是即时生效的内存改写, 随存档持久化）。
func _cheat_card() -> PanelContainer:
	var c := bleed_section()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	cv.add_child(UiKit.label("修改器", 16, UiKit.PINK_700, 600))

	# 主角修为
	var cvv1 := UiKit.label("主角修为", 13, UiKit.PINK_600, 500)
	cv.add_child(cvv1)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	for opt in [["+1万", 10000.0], ["+10万", 100000.0], ["+100万", 1000000.0]]:
		var amt: float = opt[1]
		row1.add_child(_cheat_button(String(opt[0]), func() -> void: Game._add_cult(amt)))
	row1.add_child(_cheat_button("修为灌满", func() -> void: Game.run.cult = Game.layer_need()))
	cv.add_child(row1)

	# 灵石
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	row2.add_child(UiKit.label("灵石", 13, UiKit.PINK_600, 500))
	row2.add_child(UiKit.expander())
	row2.add_child(_cheat_button("+100", func() -> void: Game.farm().stones = int(Game.farm().stones) + 100))
	row2.add_child(_cheat_button("+1000", func() -> void: Game.farm().stones = int(Game.farm().stones) + 1000))
	cv.add_child(row2)

	# 仓库物品
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 6)
	row3.add_child(UiKit.label("仓库", 13, UiKit.PINK_600, 500))
	row3.add_child(UiKit.expander())
	row3.add_child(_cheat_button("千年灵植 +1", func() -> void:
		Game.farm().millennium = int(Game.farm().millennium) + 1
		Game.changed.emit()
	))
	row3.add_child(_cheat_button("添加灵植 ×10…", _open_item_dialog))
	cv.add_child(row3)

	var hint := UiKit.label("改动即时生效并入档；修为灌满后下一次结算自动冲关。", 11, UiKit.PINK_400)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(hint)
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c


## 添加灵植二级弹层: 3 列种子格, 点击入库凡品 ×10。
func _open_item_dialog() -> void:
	_close_item_dialog()
	var dlg := UiKit.dialog_layer(self, 352.0)
	_item_dlg = dlg.layer
	UiKit.dim_click_close(dlg.dim, _close_item_dialog)
	var cv: VBoxContainer = dlg.vb
	cv.add_child(UiKit.label("添加灵植（凡品 ×10）", 16, UiKit.PINK_700, 600))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 430)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	cv.add_child(scroll)

	for s in DataManager.seeds:
		var sid := String(s.id)
		grid.add_child(UiKit.tappable_row(_item_cell(s), func() -> void:
			Game._inv_add(sid, "凡", 10)
			Game.changed.emit()
			_close_item_dialog()
		))

	cv.add_child(_mini_close_button("关闭", _close_item_dialog))


func _item_cell(s: Dictionary) -> Control:
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	var name_l := UiKit.label(String(s.name), 13, UiKit.PINK_700, 600, HORIZONTAL_ALIGNMENT_CENTER)
	name_l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	vb.add_child(name_l)
	var pills := HBoxContainer.new()
	pills.alignment = BoxContainer.ALIGNMENT_CENTER
	pills.add_theme_constant_override("separation", 3)
	pills.add_child(UiKit.pill("%s·%s" % [_type_cn(String(s.type)), String(s.grade)], UiKit.WHITE, _type_color(String(s.type)), 9))
	vb.add_child(pills)
	vb.add_child(UiKit.label("入库 ×10", 10, UiKit.GOLD_600, 500, HORIZONTAL_ALIGNMENT_CENTER))
	return vb


func _close_item_dialog() -> void:
	if _item_dlg != null:
		_item_dlg.queue_free()
		_item_dlg = null


func _cheat_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 30)
	b.add_theme_font_override("font", UiKit.font(500))
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", UiKit.PINK_600)
	b.add_theme_color_override("font_hover_color", UiKit.PINK_600)
	b.add_theme_color_override("font_pressed_color", UiKit.WHITE)
	b.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.WHITE, 8))
	b.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.PINK_100, 8))
	b.add_theme_stylebox_override("pressed", UiKit.stylebox(UiKit.PINK_500, 8))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b


func _type_cn(t: String) -> String:
	var cn: String = {"food": "食材", "herb": "灵药", "flower": "奇花"}.get(t, t)
	return cn


func _type_color(t: String) -> Color:
	match t:
		"food": return UiKit.GREEN_500
		"herb": return UiKit.JADE_500
		"flower": return UiKit.PINK_400
		_: return UiKit.GRAY_400
	return UiKit.GRAY_400


func _mini_close_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_override("font", UiKit.font(500))
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", UiKit.PINK_600)
	b.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.PINK_50, 8))
	b.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.PINK_100, 8))
	b.add_theme_stylebox_override("pressed", UiKit.stylebox(UiKit.PINK_500, 8))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b


## 主动隐退(测试): 无境界限制 —— 随时可直接落幕重开, 按「圆满隐退」结算(道韵 ×1.2)。
func _retire_card() -> PanelContainer:
	var c := bleed_section()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	cv.add_child(UiKit.label("主动隐退 · 重开", 16, UiKit.PINK_700, 600))
	var desc := UiKit.label("立即结束此世, 按「圆满隐退」结算（道韵 ×1.2）—— 无境界限制, 随时可重开。", 12, UiKit.PINK_400)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(desc)
	cv.add_child(_action_button("就此隐退 · 重开一世", func() -> void: Game._ending("圆满隐退"), not Game.is_ended(), "此世已了"))
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c


func _action_button(text: String, cb: Callable, enabled := true, disabled_hint := "") -> Button:
	var b := Button.new()
	b.text = text if enabled or disabled_hint == "" else "%s（%s）" % [text, disabled_hint]
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 40)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.disabled = not enabled
	b.add_theme_font_override("font", UiKit.font(600))
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", UiKit.WHITE)
	b.add_theme_color_override("font_disabled_color", UiKit.WHITE)
	b.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.PINK_500, 10))
	b.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.PINK_600, 10))
	b.add_theme_stylebox_override("pressed", UiKit.stylebox(UiKit.PINK_600, 10))
	b.add_theme_stylebox_override("disabled", UiKit.stylebox(UiKit.GRAY_400, 10))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b
