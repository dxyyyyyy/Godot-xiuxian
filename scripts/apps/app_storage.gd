extends "res://scripts/apps/app_base.gd"
## 库房：灶库＋库房（4 列背包网格）。数量来自 GameState 真实库存，收获即更新。

var _count_labels := {}  # item_id -> Label
var _tiles := {}         # item_id -> 网格单元（数量为 0 时隐藏）


func _build_content(vb: VBoxContainer) -> void:
	vb.add_theme_constant_override("separation", 16)
	vb.add_child(UiKit.label("灶库 · 库房", 24, UiKit.PINK_600, 600))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	for id in GameState.ITEM_ORDER:
		grid.add_child(_item_tile(id))
	vb.add_child(grid)
	GameState.inventory_changed.connect(_refresh_counts)
	_refresh_counts()


func _refresh_counts() -> void:
	for id in _count_labels:
		var count: int = GameState.get_item_count(id)
		_count_labels[id].text = "x%d" % count
		_tiles[id].visible = count > 0


func _item_tile(id: String) -> VBoxContainer:
	var def: Dictionary = GameState.ITEMS[id]
	var tile := VBoxContainer.new()
	tile.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_theme_constant_override("separation", 4)

	var sq := UiKit.gradient_panel(Color(def.from), Color(def.to), 12, true)
	sq.custom_minimum_size = Vector2(64, 64)
	sq.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var tc := CenterContainer.new()
	tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tc.add_child(UiKit.label(def.icon, 24, UiKit.PINK_700))
	sq.add_child(tc)
	tile.add_child(sq)

	var name_l := UiKit.label(def.name, 12, UiKit.PINK_700, 600, HORIZONTAL_ALIGNMENT_CENTER)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.custom_minimum_size = Vector2(80, 0)
	tile.add_child(name_l)
	var count_l := UiKit.label("", 12, UiKit.PINK_500, 500, HORIZONTAL_ALIGNMENT_CENTER)
	_count_labels[id] = count_l
	_tiles[id] = tile
	tile.add_child(count_l)
	var attr := UiKit.label(def.attribute, 12, UiKit.PINK_400, 400, HORIZONTAL_ALIGNMENT_CENTER)
	attr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	attr.custom_minimum_size = Vector2(80, 0)
	tile.add_child(attr)
	return tile
