class_name RecipePicker
extends Control
## 配方选择弹窗：点击已解锁的空闲槽位（灶台/灵田）后弹出，按 kind 列出对应配方，
## 展示成熟时间、产量与材料需求（拥有/需求），选中可行配方后调用
## GameState.slot_start() 扣材料并开始生产。全部代码构建，复用 UiKit 配色。
## 用法：var p := RecipePicker.new(); p.kind = "plot"; p.slot_idx = i; add_child(p)

const UiKit := preload("res://scripts/ui_kit.gd")

## "plot" 种植 / "stove" 烹饪 —— 须在 add_child 前赋值
var kind := "plot"
## 槽位下标（对应 kind 的 farmland/stoves 数组）—— 须在 add_child 前赋值
var slot_idx := 0

var _selected := ""          # 当前高亮配方 id（"" = 未选中）
var _rows := {}              # recipe id -> {panel, hit, def, cost_labels, affordable}
var _confirm_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_build_mask())
	add_child(_build_card())
	_refresh_costs()


## 槽位字典（farmland/stoves 按 kind 取）
func _slot() -> Dictionary:
	var slots: Array = GameState.farmland if kind == "plot" else GameState.stoves
	return slots[slot_idx]


# ---- 遮罩与骨架 ----

## 全屏半透明遮罩：点击空白处 = 取消关闭
func _build_mask() -> ColorRect:
	var mask := ColorRect.new()
	mask.name = "Mask"
	mask.color = Color(0, 0, 0, 0.45)
	mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mask.mouse_filter = Control.MOUSE_FILTER_STOP
	mask.gui_input.connect(_on_mask_input)
	return mask


func _on_mask_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_close()


## 居中白色圆角卡片：标题行 + 可滚动配方列表 + 底部按钮行。
## 挂在家园页根控件上（全屏 anchors 只覆盖内容区，不遮挡底部导航）。
func _build_card() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS  # 卡片外空白点击透传给遮罩 = 取消
	var recipes: Array = GameState.recipes_of_kind(kind)
	var card := UiKit.padded(UiKit.card(), 16)
	card.custom_minimum_size = Vector2(_card_width(), 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	card.add_child(vb)
	vb.add_child(_build_header())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, _list_height(recipes.size()))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in recipes:
		list.add_child(_recipe_row(String(id)))
	scroll.add_child(list)
	vb.add_child(scroll)
	vb.add_child(_build_footer())

	_default_highlight(recipes)
	center.add_child(card)
	return center


func _build_header() -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := "选择要烹饪的灵食" if kind == "stove" else "选择要种植的灵植"
	hb.add_child(UiKit.label(title, 18, UiKit.PINK_700, 700))
	hb.add_child(UiKit.expander())
	var close := Button.new()
	close.text = "✕"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(36, 36)
	close.add_theme_color_override("font_color", UiKit.GRAY_400)
	close.add_theme_color_override("font_hover_color", UiKit.PINK_700)
	close.add_theme_color_override("font_pressed_color", UiKit.PINK_700)
	close.add_theme_font_size_override("font_size", 16)
	for st in ["normal", "hover", "pressed", "focus"]:
		close.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	close.pressed.connect(_close)
	hb.add_child(close)
	return hb


func _build_footer() -> Control:
	var fb := HBoxContainer.new()
	fb.add_theme_constant_override("separation", 12)
	var cancel := _dialog_button("取消", UiKit.GRAY_200, UiKit.GRAY_400,
			UiKit.GRAY_200, UiKit.GRAY_400, UiKit.GRAY_300)
	cancel.pressed.connect(_close)
	fb.add_child(cancel)
	var confirm_text := "开始烹饪" if kind == "stove" else "开始种植"
	_confirm_btn = _dialog_button(confirm_text, UiKit.PINK_600, UiKit.WHITE,
			UiKit.GRAY_200, UiKit.GRAY_400, UiKit.PINK_500)
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	fb.add_child(_confirm_btn)
	return fb


## 底部通用按钮：等宽、圆角 12、高 44，禁用态灰底灰字。
func _dialog_button(text: String, bg: Color, fg: Color, disabled_bg: Color,
		disabled_fg: Color, hover_bg: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 44)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_override("font", UiKit.font(600))
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", disabled_fg)
	b.add_theme_stylebox_override("normal", UiKit.stylebox(bg, 12))
	b.add_theme_stylebox_override("hover", UiKit.stylebox(hover_bg, 12))
	b.add_theme_stylebox_override("pressed", UiKit.stylebox(hover_bg, 12))
	b.add_theme_stylebox_override("disabled", UiKit.stylebox(disabled_bg, 12))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


# ---- 配方行 ----

## 单项配方卡：图标/名称/成熟时间/产量 + 材料需求行 + 透明点击层。
func _recipe_row(id: String) -> PanelContainer:
	var def: Dictionary = GameState.RECIPES[id]
	var cost_labels := []
	for item_id in def.costs:
		var idef: Dictionary = GameState.ITEMS[String(item_id)]
		var lb := UiKit.label("", 12, UiKit.PINK_500, 500)
		lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cost_labels.append({"label": lb, "item": String(item_id),
				"icon": String(idef.icon), "name": String(idef.name),
				"need": int(def.costs[item_id])})

	var panel := PanelContainer.new()
	panel.name = "Row_%s" % id
	panel.custom_minimum_size = Vector2(0, 88)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(UiKit.margin_wrap(_row_content(def, cost_labels), 10))
	var hit := Button.new()
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		hit.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	hit.pressed.connect(_on_row_pressed.bind(id))
	panel.add_child(hit)
	_rows[id] = {"panel": panel, "hit": hit, "def": def,
			"cost_labels": cost_labels, "affordable": true}
	return panel


func _row_content(def: Dictionary, cost_labels: Array) -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(UiKit.label(String(def.icon), 22, UiKit.PINK_700))
	top.add_child(UiKit.label(String(def.name), 16, UiKit.PINK_700, 600))
	top.add_child(UiKit.expander())
	top.add_child(UiKit.label(_fmt_hours(float(def.hours)) + "成熟", 12, UiKit.PINK_400))
	vb.add_child(top)
	vb.add_child(UiKit.label("产 %d 份" % int(def.output), 12, UiKit.PINK_400))
	var cost_hb := HBoxContainer.new()
	cost_hb.add_theme_constant_override("separation", 10)
	cost_hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for entry in cost_labels:
		cost_hb.add_child(entry.label)
	vb.add_child(cost_hb)
	return vb


# ---- 状态刷新 ----

## 按当前库存重算：材料"拥有/需求"文本、可行性、行高亮/置灰与确认按钮状态。
func _refresh_costs() -> void:
	for id in _rows:
		var row: Dictionary = _rows[id]
		var def: Dictionary = row.def
		var ok := GameState.can_afford(def.costs)
		row.affordable = ok
		for entry in row.cost_labels:
			var have: int = GameState.get_item_count(entry.item)
			entry.label.text = "%s %s %d/%d" % [entry.icon, entry.name, have, entry.need]
			entry.label.add_theme_color_override(
					"font_color", UiKit.PINK_500 if have >= entry.need else UiKit.RED_400)
		var panel: PanelContainer = row.panel
		panel.self_modulate = Color.WHITE if ok else Color(0.62, 0.62, 0.66, 0.95)
		(row.hit as Button).disabled = not ok
		if not ok:
			panel.add_theme_stylebox_override("panel", UiKit.stylebox(UiKit.GRAY_200, 12))
		elif _selected == id:
			panel.add_theme_stylebox_override("panel",
					UiKit.stylebox(UiKit.PINK_100, 12, false, 2, UiKit.PINK_400))
		else:
			panel.add_theme_stylebox_override("panel", UiKit.stylebox(UiKit.PINK_50, 12))
	if _selected != "" and not bool(_rows[_selected].affordable):
		_selected = ""
	_confirm_btn.disabled = _selected == ""


## 默认高亮该槽位 last_recipe（存在、类型匹配且材料足够时）。
## 注意：此时尚未跑过 _refresh_costs，可行性须直接查库存。
func _default_highlight(recipes: Array) -> void:
	var lr: String = String(_slot().get("last_recipe", ""))
	if recipes.has(lr) and _rows.has(lr) \
			and GameState.can_afford(GameState.RECIPES[lr].costs):
		_selected = lr


## 选中某可行配方（材料不足的行走不到这里：hit.disabled）
func _on_row_pressed(id: String) -> void:
	if _selected == id or not bool(_rows[id].affordable):
		return
	_selected = id
	_refresh_costs()


func _on_confirm_pressed() -> void:
	if _selected == "":
		return
	if GameState.slot_start(_slot(), _selected):
		_close()
	else:
		# 竞态（弹窗开着时库存被花掉）：不关闭，刷新材料显示与选中态
		_refresh_costs()


func _close() -> void:
	queue_free()


# ---- 尺寸与文案辅助 ----

## 卡片宽 ≈ 屏宽 80%（夹在 280~380 之间，兼顾小屏与大屏）
func _card_width() -> float:
	return clampf(get_viewport_rect().size.x * 0.8, 280.0, 380.0)


## 列表高度：内容不超高时恰好展开，超高时封顶进入滚动区
func _list_height(n: int) -> float:
	var desired: float = n * 88.0 + maxf(0.0, float(n - 1)) * 8.0
	var cap: float = maxf(140.0, get_viewport_rect().size.y - 260.0)
	return minf(desired, cap)


func _fmt_hours(h: float) -> String:
	if is_equal_approx(h, roundf(h)):
		return "%d 小时" % int(roundf(h))
	return "%.2f 小时" % h
