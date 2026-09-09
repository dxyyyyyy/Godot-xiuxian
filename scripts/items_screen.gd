extends "res://scripts/screen_base.gd"
## 物品页：4 列背包网格，图标为渐变方块 + emoji

var items := [
	{"name": "回灵丹", "quantity": 25, "attribute": "恢复灵力", "icon": "💊", "from": Color("93c5fd"), "to": Color("60a5fa")},
	{"name": "疗伤药", "quantity": 18, "attribute": "恢复生命", "icon": "🩹", "from": Color("fca5a5"), "to": Color("f87171")},
	{"name": "聚灵石", "quantity": 50, "attribute": "提升修为", "icon": "💎", "from": Color("d8b4fe"), "to": Color("c084fc")},
	{"name": "破境丹", "quantity": 3, "attribute": "突破境界", "icon": "⭐", "from": Color("fde047"), "to": Color("facc15")},
	{"name": "灵草", "quantity": 120, "attribute": "炼丹材料", "icon": "🌿", "from": Color("86efac"), "to": Color("4ade80")},
	{"name": "仙剑", "quantity": 1, "attribute": "攻击+500", "icon": "⚔️", "from": Color("d1d5db"), "to": Color("9ca3af")},
	{"name": "护身符", "quantity": 8, "attribute": "防御+300", "icon": "🛡️", "from": Color("fdba74"), "to": Color("fb923c")},
	{"name": "传送符", "quantity": 15, "attribute": "瞬间移动", "icon": "📜", "from": Color("f9a8d4"), "to": Color("f472b6")},
	{"name": "灵兽蛋", "quantity": 2, "attribute": "孵化灵兽", "icon": "🥚", "from": Color("fcd34d"), "to": Color("fbbf24")},
	{"name": "仙露", "quantity": 30, "attribute": "增加寿命", "icon": "💧", "from": Color("67e8f9"), "to": Color("22d3ee")},
	{"name": "法宝碎片", "quantity": 45, "attribute": "合成法宝", "icon": "✨", "from": Color("a5b4fc"), "to": Color("818cf8")},
	{"name": "秘籍", "quantity": 5, "attribute": "学习技能", "icon": "📖", "from": Color("fda4af"), "to": Color("fb7185")},
	{"name": "灵石", "quantity": 9, "attribute": "货币", "icon": "🪙", "from": Color("d6dffcff"), "to": Color("e1c7e2ff")}
]


func _build(vb: VBoxContainer) -> void:
	vb.add_theme_constant_override("separation", 16)
	vb.add_child(UiKit.label("物品背包", 24, UiKit.PINK_600, 600))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	for it in items:
		grid.add_child(_item_tile(it))
	vb.add_child(grid)


func _item_tile(it: Dictionary) -> VBoxContainer:
	var tile := VBoxContainer.new()
	tile.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_theme_constant_override("separation", 4)

	var sq := UiKit.gradient_panel(it.from, it.to, 12, true)
	sq.custom_minimum_size = Vector2(64, 64)
	sq.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var tc := CenterContainer.new()
	tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tc.add_child(UiKit.label(it.icon, 24, UiKit.PINK_700))
	sq.add_child(tc)
	tile.add_child(sq)

	var name_l := UiKit.label(it.name, 12, UiKit.PINK_700, 600, HORIZONTAL_ALIGNMENT_CENTER)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.custom_minimum_size = Vector2(80, 0)
	tile.add_child(name_l)
	tile.add_child(UiKit.label("x%d" % int(it.quantity), 12, UiKit.PINK_500, 500, HORIZONTAL_ALIGNMENT_CENTER))
	var attr := UiKit.label(it.attribute, 12, UiKit.PINK_400, 400, HORIZONTAL_ALIGNMENT_CENTER)
	attr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	attr.custom_minimum_size = Vector2(80, 0)
	tile.add_child(attr)
	return tile
