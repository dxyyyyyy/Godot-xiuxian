extends "res://scripts/apps/app_base.gd"
## 图鉴：菜谱／物品两栏浏览，按发现记录显隐（未发现为剪影「？？？」）。

var kind_group := ButtonGroup.new()
var _mode := "recipes"
var _grid: GridContainer


func _build_content(vb: VBoxContainer) -> void:
	vb.add_theme_constant_override("separation", 16)
	vb.add_child(UiKit.label("图鉴", 24, UiKit.PINK_600, 600))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var rb := UiKit.seg_button("菜谱", kind_group, _mode == "recipes")
	rb.pressed.connect(_set_mode.bind("recipes"))
	row.add_child(rb)
	var ib := UiKit.seg_button("物品", kind_group, _mode == "items")
	ib.pressed.connect(_set_mode.bind("items"))
	row.add_child(ib)
	vb.add_child(row)

	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 16)
	vb.add_child(_grid)
	GameState.inventory_changed.connect(_rebuild)
	_rebuild()


func _set_mode(mode: String) -> void:
	if _mode == mode:
		return
	_mode = mode
	_rebuild()


func _rebuild() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	if _mode == "recipes":
		for id in GameState.RECIPES:
			var rid := String(id)
			_grid.add_child(_recipe_tile(rid, bool(GameState.discovered_recipes.get(rid, false))))
	else:
		for id in GameState.ITEM_ORDER:
			var iid := String(id)
			_grid.add_child(_item_tile(iid, bool(GameState.discovered_items.get(iid, false))))


func _recipe_tile(id: String, found: bool) -> VBoxContainer:
	var tile := VBoxContainer.new()
	tile.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_theme_constant_override("separation", 4)
	if found:
		var def: Dictionary = GameState.RECIPES[id]
		var out_def: Dictionary = GameState.ITEMS[String(def.item)]
		var sq := UiKit.gradient_panel(Color(out_def.from), Color(out_def.to), 12, true)
		sq.custom_minimum_size = Vector2(64, 64)
		sq.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var tc := CenterContainer.new()
		tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tc.add_child(UiKit.label(def.icon, 24, UiKit.PINK_700))
		sq.add_child(tc)
		tile.add_child(sq)
		var name_l := UiKit.label(String(def.name), 12, UiKit.PINK_700, 600, HORIZONTAL_ALIGNMENT_CENTER)
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_l.custom_minimum_size = Vector2(80, 0)
		tile.add_child(name_l)
		var kind_text := "灵田" if String(def.kind) == "plot" else "灶台"
		tile.add_child(UiKit.pill("%s · 产×%d" % [kind_text, int(def.output)], UiKit.PINK_600, UiKit.PINK_100, 11))
	else:
		tile.add_child(_silhouette())
		var name_l := UiKit.label("？？？" , 12, UiKit.GRAY_400, 600, HORIZONTAL_ALIGNMENT_CENTER)
		name_l.custom_minimum_size = Vector2(80, 0)
		tile.add_child(name_l)
	return tile


func _item_tile(id: String, found: bool) -> VBoxContainer:
	var tile := VBoxContainer.new()
	tile.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_theme_constant_override("separation", 4)
	if found:
		var def: Dictionary = GameState.ITEMS[id]
		var sq := UiKit.gradient_panel(Color(def.from), Color(def.to), 12, true)
		sq.custom_minimum_size = Vector2(64, 64)
		sq.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var tc := CenterContainer.new()
		tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tc.add_child(UiKit.label(def.icon, 24, UiKit.PINK_700))
		sq.add_child(tc)
		tile.add_child(sq)
		var name_l := UiKit.label(String(def.name), 12, UiKit.PINK_700, 600, HORIZONTAL_ALIGNMENT_CENTER)
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_l.custom_minimum_size = Vector2(80, 0)
		tile.add_child(name_l)
		var attr := UiKit.label(String(def.attribute), 12, UiKit.PINK_400, 400, HORIZONTAL_ALIGNMENT_CENTER)
		attr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		attr.custom_minimum_size = Vector2(80, 0)
		tile.add_child(attr)
	else:
		tile.add_child(_silhouette())
		var name_l := UiKit.label("？？?", 12, UiKit.GRAY_400, 600, HORIZONTAL_ALIGNMENT_CENTER)
		name_l.custom_minimum_size = Vector2(80, 0)
		tile.add_child(name_l)
	return tile


## 未发现剪影：灰底 + 「？」
func _silhouette() -> PanelContainer:
	var sq := UiKit.gradient_panel(UiKit.GRAY_200, UiKit.GRAY_300, 12, false)
	sq.custom_minimum_size = Vector2(64, 64)
	sq.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var tc := CenterContainer.new()
	tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tc.add_child(UiKit.label("？", 22, UiKit.GRAY_400, 700))
	sq.add_child(tc)
	return sq
