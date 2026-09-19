extends "res://scripts/apps/app_base.gd"
## 洞府：设施升级（聚灵阵/灵泉/藏经阁/待客厅院）——自家园页迁入玉牌。
## 灵石换长久：等级一世受用，上限随境界解锁；升级走 Game.cave_upgrade 唯一入口。

var _content: VBoxContainer
var _rebuild_pending := false


func _build_content(vb: VBoxContainer) -> void:
	vb.add_child(bleed_head("洞府", "灵石换长久 —— 设施升级，此世受用。"))
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
	if Game.run.is_empty() or not Game.run.has("farm"):
		return
	var card := bleed_section()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiKit.label("洞府设施", 16, UiKit.PINK_700, 600))
	head.add_child(UiKit.expander())
	head.add_child(UiKit.label("境界上限 %d 级 · 灵石 %d" % [Game.facility_cap(), int(Game.farm().stones)], 12, UiKit.GOLD_600, 600))
	cv.add_child(head)
	for f in DataManager.facilities:
		cv.add_child(_facility_row(f))
	var hint := UiKit.label("等级上限随境界解锁（练气1/筑基2/金丹3）；升级即时生效，转世重置。", 11, UiKit.PINK_400)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(hint)
	card.add_child(UiKit.margin_wrap(cv, 16))
	_content.add_child(card)


func _facility_row(f: Dictionary) -> Control:
	var fid := String(f.id)
	var lv := Game.facility_level(fid)
	var costs: Array = f.get("costs", [])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	name_row.add_child(UiKit.label(String(f.name), 14, UiKit.PINK_700, 600))
	name_row.add_child(UiKit.label("Lv.%d/3" % lv, 12, UiKit.PINK_500, 600))
	info.add_child(name_row)
	info.add_child(UiKit.label(_facility_bonus(f, lv), 11, UiKit.GOLD_600, 600))
	var desc := UiKit.label(String(f.get("desc", "")), 11, UiKit.PINK_400)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc)
	row.add_child(info)
	if lv >= costs.size():
		row.add_child(UiKit.pill("圆满", UiKit.WHITE, UiKit.GREEN_500, 12, 600))
	elif lv >= Game.facility_cap():
		row.add_child(UiKit.pill("境界锁", UiKit.GRAY_400, UiKit.GRAY_200, 12))
	else:
		var cost := int(costs[lv])
		var b := _mini_button("升级 %d" % cost, func() -> void: Game.cave_upgrade(fid))
		b.disabled = int(Game.farm().stones) < cost
		row.add_child(b)
	return row


## 设施当前加成: 按当前等级直读 levels, 各设施换算成直读文案。
func _facility_bonus(f: Dictionary, lv: int) -> String:
	var levels: Array = f.get("levels", [])
	var v: float = float(levels[clampi(lv, 0, levels.size() - 1)]) if levels.size() > 0 else 0.0
	match String(f.id):
		"julingzhen":
			return "当前加成: 聚灵效率 +%d%% · 冲关率 +%d%%" % [int(round(v * 100.0)), lv * 2]
		"lingquan":
			return "当前加成: 收获产量 +%d%% · 品质升档 +%dpp" % [int(round(v * 100.0)), int(round(v * 100.0))]
		"cangjingge":
			var pp: Array = [0.0, 2.0, 3.0, 4.5]
			return "当前加成: 研速 ×%.2f · 顿悟 +%.1fpp" % [1.0 + v, float(pp[clampi(lv, 0, pp.size() - 1)])]
		"daiketingyuan":
			return "当前加成: 并行约会 %d 人" % int(v)
	return ""


func _mini_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 32)
	b.add_theme_font_override("font", UiKit.font(600))
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", UiKit.PINK_600)
	b.add_theme_color_override("font_disabled_color", UiKit.GRAY_400)
	b.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.PINK_100, 8))
	b.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.PINK_200, 8))
	b.add_theme_stylebox_override("pressed", UiKit.stylebox(UiKit.PINK_500, 8))
	b.add_theme_stylebox_override("disabled", UiKit.stylebox(UiKit.GRAY_200, 8))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b
