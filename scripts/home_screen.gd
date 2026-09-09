extends "res://scripts/screen_base.gd"
## 家园页：灵田种植 + 灵食烹饪。
## 数据驱动：槽位状态由 GameState 管理，本页负责渲染 + 点击交互。
## 闭环：空地→点击种植→随游戏时钟生长→可收获→点击收进背包→空地。

var _cook_grid: GridContainer
var _farm_grid: GridContainer
var _tile_refs := []  # {idx, kind, bar, pct, remain}，生产中槽位的进度条引用


func _build(vb: VBoxContainer) -> void:
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	head.add_child(UiKit.label("灵田家园", 24, UiKit.PINK_600, 700, HORIZONTAL_ALIGNMENT_CENTER))
	head.add_child(UiKit.label("辛勤耕耘，收获仙缘", 14, UiKit.PINK_400, 400, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(head)

	_cook_grid = _make_grid()
	vb.add_child(_section("🍳 灵食烹饪", _cook_grid))
	_farm_grid = _make_grid()
	vb.add_child(_section("🌾 灵田种植", _farm_grid))

	GameState.slots_changed.connect(_on_slots_changed)
	_refresh_slots()


func _process(_delta: float) -> void:
	for r in _tile_refs:
		var slots: Array = GameState.farmland if r["kind"] == "plot" else GameState.stoves
		var slot: Dictionary = slots[int(r["idx"])]
		if slot.recipe == "" or GameState.slot_ready(slot):
			continue
		var p := GameState.slot_progress(slot)
		r["bar"].value = p * 100.0
		r["pct"].text = "%d%%" % int(round(p * 100.0))
		r["remain"].text = "剩余 " + _fmt_remaining(slot)


func _make_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	return grid


func _on_slots_changed() -> void:
	# 延迟重建：避免点击回调还在执行栈上时，对应的按钮节点被释放
	_refresh_slots.call_deferred()


func _refresh_slots() -> void:
	_tile_refs.clear()
	_fill_grid(_cook_grid, "stove")
	_fill_grid(_farm_grid, "plot")


func _fill_grid(grid: GridContainer, kind: String) -> void:
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	var slots: Array = GameState.farmland if kind == "plot" else GameState.stoves
	for i in slots.size():
		grid.add_child(_slot_tile(slots[i], kind, i))


func _slot_tile(slot: Dictionary, kind: String, idx: int) -> PanelContainer:
	var tile := UiKit.padded(UiKit.pink_box(), 12)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var content := _slot_content(slot, kind, idx)
	_ignore_mouse(content)
	tile.add_child(content)
	if slot.unlocked:
		tile.add_child(_hit_overlay(tile, kind, idx))
	return tile


func _ignore_mouse(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in c.get_children():
		if ch is Control:
			_ignore_mouse(ch)


## 透明点击层：覆盖整个地块，负责点击与悬停反馈
func _hit_overlay(tile: PanelContainer, kind: String, idx: int) -> Button:
	var hit := Button.new()
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		hit.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	hit.pressed.connect(_on_slot_pressed.bind(kind, idx))
	hit.mouse_entered.connect(func() -> void:
		tile.add_theme_stylebox_override("panel", UiKit.stylebox(UiKit.PINK_100, 12))
	)
	hit.mouse_exited.connect(func() -> void:
		tile.add_theme_stylebox_override("panel", UiKit.stylebox(UiKit.PINK_50, 12))
	)
	return hit


func _on_slot_pressed(kind: String, idx: int) -> void:
	var slots: Array = GameState.farmland if kind == "plot" else GameState.stoves
	var slot: Dictionary = slots[idx]
	if not slot.unlocked:
		return
	if slot.recipe == "":
		# 空闲槽位：弹出配方选择弹窗（确认后由弹窗调用 GameState.slot_start）
		var picker := RecipePicker.new()
		picker.kind = kind
		picker.slot_idx = idx
		add_child(picker)
		return
	GameState.slot_interact(slot)


func _slot_content(slot: Dictionary, kind: String, idx: int) -> Control:
	if not slot.unlocked:
		return _locked_content("Lv.%d解锁" % int(slot.level))
	if slot.recipe == "":
		return _empty_content(slot, kind)
	return _growing_content(slot, kind, idx)


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


func _empty_content(slot: Dictionary, kind: String) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 4)
	vb.custom_minimum_size = Vector2(0, 140)
	var lr: String = slot.get("last_recipe", "")
	var icon_name: String = GameState.RECIPES[lr].icon if GameState.RECIPES.has(lr) else "🌾"
	var circ := UiKit.circle(64, UiKit.GRAY_200, UiKit.GRAY_300)
	var emoji := UiKit.label(icon_name, 24, Color(UiKit.GRAY_400, 0.7))
	emoji.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	circ.add_child(emoji)
	circ.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(circ)
	var hint := "空地 · 点击种植" if kind == "plot" else "空闲中 · 点击烹饪"
	vb.add_child(UiKit.label(hint, 12, UiKit.GRAY_400, 400, HORIZONTAL_ALIGNMENT_CENTER))
	return vb


func _growing_content(slot: Dictionary, kind: String, idx: int) -> Control:
	var ready := GameState.slot_ready(slot)
	var def: Dictionary = GameState.RECIPES[slot.recipe]
	var pct_real := GameState.slot_progress(slot)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)

	var tile: PanelContainer
	if kind == "plot":
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		top.add_child(UiKit.pill("Lv.%d 土地" % int(slot.level), UiKit.PINK_600, UiKit.WHITE, 12, 600))
		top.add_child(UiKit.expander())
		top.add_child(UiKit.label("%d小时" % int(def.hours), 12, UiKit.PINK_400))
		vb.add_child(top)
		tile = UiKit.gradient_panel(UiKit.AMBER_100, UiKit.GREEN_100, 8)
		tile.custom_minimum_size = Vector2(0, 60)
	else:
		tile = UiKit.gradient_panel(UiKit.ORANGE_200, UiKit.ORANGE_300, 8)
		tile.custom_minimum_size = Vector2(0, 80)

	var tc := CenterContainer.new()
	tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tv := VBoxContainer.new()
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", 2)
	if kind == "plot":
		tv.add_child(UiKit.label(def.icon, 20, UiKit.PINK_700))
		tv.add_child(UiKit.label(def.name, 12, UiKit.GREEN_700, 600))
	else:
		tv.add_child(UiKit.icon_rect("flame", 32, UiKit.ORANGE_500))
		tv.add_child(UiKit.label(def.icon, 18, UiKit.PINK_700))
	tc.add_child(tv)
	tile.add_child(tc)
	vb.add_child(tile)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.add_child(UiKit.label(def.name, 14, UiKit.PINK_700, 600))
	name_row.add_child(UiKit.expander())
	if kind == "plot":
		name_row.add_child(UiKit.label("x%d" % int(def.output), 14, UiKit.PINK_500, 500))
	else:
		name_row.add_child(UiKit.pill("Lv.%d" % int(slot.level), UiKit.PINK_600, UiKit.WHITE, 12, 600))
	vb.add_child(name_row)

	var caption: String
	var cap_color := UiKit.PINK_400
	var cap_weight := 400
	if ready:
		caption = "可收获！点击收取" if kind == "plot" else "可收取！点击装盘"
		cap_color = UiKit.GREEN_700
		cap_weight = 600
	else:
		caption = "成熟进度" if kind == "plot" else "烹饪进度"
	var prog := VBoxContainer.new()
	prog.add_theme_constant_override("separation", 4)
	var prow := HBoxContainer.new()
	prow.add_child(UiKit.label(caption, 12, cap_color, cap_weight))
	prow.add_child(UiKit.expander())
	var pct_label := UiKit.label("%d%%" % int(round(pct_real * 100.0)), 12, cap_color, cap_weight)
	prow.add_child(pct_label)
	prog.add_child(prow)
	var fill := UiKit.GREEN_500 if kind == "plot" else UiKit.ORANGE_500
	var bar := UiKit.progress(pct_real, fill)
	prog.add_child(bar)
	var remain := UiKit.label(
		"点击收取" if ready else ("剩余 " + _fmt_remaining(slot)),
		12, cap_color, cap_weight, HORIZONTAL_ALIGNMENT_RIGHT)
	prog.add_child(remain)
	vb.add_child(prog)

	if not ready:
		_tile_refs.append({"idx": idx, "kind": kind, "bar": bar, "pct": pct_label, "remain": remain})
	return vb


func _fmt_remaining(slot: Dictionary) -> String:
	var def: Dictionary = GameState.RECIPES[slot.recipe]
	var left_h: float = maxf(0.0, float(def.hours) * (1.0 - GameState.slot_progress(slot)))
	if left_h >= 1.0:
		return "%.1f小时" % left_h
	return "%d分钟" % int(ceil(left_h * 60.0))


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
