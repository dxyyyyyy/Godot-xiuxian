extends "res://scripts/apps/app_base.gd"
## 测试：灰盒调试旋钮——高倍速时速 + 主动隐退重开（无境界限制）+ 人物一览（世界池调试视图）。
## 自日程页迁入；不影响铁律（一切结算仍只走 tick_month 唯一入口）。

const Portrait := preload("res://scripts/portrait.gd")

var _content: VBoxContainer
var _rebuild_pending := false
var _item_dlg: Node = null   # 添加灵植的二级弹层
var _stage := "main"         # main=测试旋钮页 / npcs=人物一览页(两段式, 仿捏脸·他人)


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
	if Game.run.is_empty():
		return
	if _stage == "npcs":
		_content.add_child(_npcs_page())
		return
	_content.add_child(_face_card())      # 捏脸入口(桌面无阵纹, 自测试页进)
	_content.add_child(_npc_face_card())  # 他人捏脸: 固定 NPC 容貌编辑
	_content.add_child(_age_face_card("kidface", "幼儿捏脸", "编辑本世孩子的容貌（born_m 且未满 12 岁）。写入本世快照，一世位、转世即散。"))
	_content.add_child(_age_face_card("oldface", "老年捏脸", "编辑老世辈的容貌（花甲之年的孩子、或化神以上境界者）。同样只写本世快照。"))
	_content.add_child(_npcs_card())
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


## 幼儿/老年捏脸入口: 共用 app_face_age 编辑器(按 app_id 分模式), 只写本世 run 快照。
func _age_face_card(app: String, title: String, desc: String) -> PanelContainer:
	var c := bleed_section()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	cv.add_child(UiKit.label(title, 16, UiKit.PINK_700, 600))
	var d := UiKit.label(desc, 12, UiKit.PINK_400)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(d)
	cv.add_child(_action_button("进入" + title, func() -> void: open_app.emit(app), true))
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c


## 人物一览入口(调试): 本世所有已生成 NPC —— 已入册 / 世界池(未识) / 未遇固定, 点按钮进二级页。
## 池内未识者仅此页可见(名录与详情弹层仍不露脸), 供验证世界池生成与关系网。
func _npcs_card() -> PanelContainer:
	var c := bleed_section()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	cv.add_child(UiKit.label("人物一览", 16, UiKit.PINK_700, 600))
	cv.add_child(UiKit.label(_npcs_caption(), 11, UiKit.PINK_400))
	cv.add_child(_action_button("进入人物一览", func() -> void:
		_stage = "npcs"
		_rebuild()
	))
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c


func _npcs_caption() -> String:
	var pool: Dictionary = Game.run.get("world_npcs", {})
	var rels: Array = Game.run.get("world_rels", [])
	var enrolled := 0
	for k in Game.run.npcs:
		if bool(Game.run.npcs[k].get("met", false)):
			enrolled += 1
	return "已入册 %d · 世界池 %d · 关系边 %d 条 —— 未识者仅此页露脸" % [enrolled, pool.size(), rels.size()]


## 人物一览二级页: 返回行 + 5 列方格墙(整页随玉牌滚动); 点格子弹详情, 本页保持打开。
func _npcs_page() -> PanelContainer:
	var c := bleed_section()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var back := _cheat_button("‹ 返回测试", func() -> void:
		_stage = "main"
		_rebuild()
	)
	back.custom_minimum_size = Vector2(96, 30)
	head.add_child(back)
	head.add_child(UiKit.label("人物一览", 16, UiKit.PINK_700, 600))
	cv.add_child(head)
	var cap := UiKit.label(_npcs_caption(), 11, UiKit.PINK_400)
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(cap)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 8)
	cv.add_child(grid)
	var pool: Dictionary = Game.run.get("world_npcs", {})
	# 关系数预聚合(静态+动态边一次扫完, 56 格不重复遍历)
	var rel_count := {}
	for e in DataManager.relations:
		rel_count[String(e.get("a", ""))] = int(rel_count.get(String(e.get("a", "")), 0)) + 1
		rel_count[String(e.get("b", ""))] = int(rel_count.get(String(e.get("b", "")), 0)) + 1
	for e in Game.run.get("world_rels", []):
		rel_count[String(e.get("a", ""))] = int(rel_count.get(String(e.get("a", "")), 0)) + 1
		rel_count[String(e.get("b", ""))] = int(rel_count.get(String(e.get("b", "")), 0)) + 1
	for k in Game.run.npcs:
		if bool(Game.run.npcs[k].get("met", false)):
			grid.add_child(_npc_cell(String(k), Game.run.npcs[k], "入册" + ("·幼年" if Game._npc_is_minor(String(k)) else ""), int(rel_count.get(String(k), 0))))
	for k in pool:
		grid.add_child(_npc_cell(String(k), pool[k] as Dictionary, "池中" + ("·幼年" if Game._npc_is_minor(String(k)) else ""), int(rel_count.get(String(k), 0))))
	for n in DataManager.npcs:
		var fk := String(n.key)
		if not Game.run.npcs.has(fk):
			grid.add_child(_npc_cell(fk, n, "未遇", int(rel_count.get(fk, 0))))
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c


## 一览方格: 头像 + 姓名 + 状态 + 关系数, 点击跳该人详情弹层(池内未识者亦可查看)。
func _npc_cell(key: String, d: Dictionary, state: String, rel_n := 0) -> Control:
	var cell := PanelContainer.new()
	cell.add_theme_stylebox_override("panel", UiKit.stylebox(Color(0, 0, 0, 0), 10))
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	var av := CenterContainer.new()
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av.add_child(Portrait.build_for(key, 48))
	vb.add_child(av)
	var nl := UiKit.label(Game.npc_name(key), 11, UiKit.PINK_700, 600, HORIZONTAL_ALIGNMENT_CENTER)
	nl.custom_minimum_size = Vector2(64, 0)
	nl.clip_text = true
	vb.add_child(nl)
	vb.add_child(UiKit.label(state, 9, UiKit.PINK_400 if state == "入册" else UiKit.GRAY_400, 500, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(UiKit.label("关系 %d" % rel_n, 9, UiKit.JADE_600, 500, HORIZONTAL_ALIGNMENT_CENTER))
	cell.add_child(vb)
	var hit := Button.new()
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		hit.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	hit.pressed.connect(GameState.request_npc_detail.bind(key))
	cell.add_child(hit)
	return cell


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
