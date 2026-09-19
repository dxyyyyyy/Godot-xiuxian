extends "res://scripts/apps/app_base.gd"
## 坊市：灵石总账 + 清空余货 + 稀有种子高价购种（自库房迁出, 独立成页）。
## 购种走 Game.seed_buy（价 × seed_buy_mult, 入库为「凡」品留种）; 上品播种需仓库留种 1 株。

var _content: VBoxContainer
var _rebuild_pending := false


func _build_content(vb: VBoxContainer) -> void:
	vb.add_child(bleed_head("坊市", "余货换灵石 · 稀有种子高价购入。"))
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
	var f: Dictionary = Game.farm()

	# —— 灵石总账 + 清货 ——
	var c := bleed_section()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiKit.icon_rect("coins", 18, UiKit.GOLD_600))
	head.add_child(UiKit.label("灵石", 16, UiKit.PINK_700, 600))
	head.add_child(UiKit.expander())
	head.add_child(UiKit.label("%d" % int(f.stones), 22, UiKit.GOLD_600, 600))
	cv.add_child(head)
	cv.add_child(_mini_button("清空余货换灵石", func() -> void: Game.farm_sell_all()))
	var hint := UiKit.label("收获都自动入仓; 灵植点库房物品格卖出。余货一键清仓, 换成灵石购种修行。", 11, UiKit.PINK_400)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(hint)
	c.add_child(UiKit.margin_wrap(cv, 16))
	_content.add_child(c)

	# —— 稀有种子 · 购种（上品灵植, 价昂; 购得入库为「凡」品留种）——
	var sc := bleed_section()
	var scv := VBoxContainer.new()
	scv.add_theme_constant_override("separation", 8)
	scv.add_child(UiKit.label("稀有种子 · 购种", 16, UiKit.PINK_700, 600))
	for s in DataManager.seeds:
		if not Game.seed_gated(s):
			continue
		var sid := String(s.id)
		var cost := Game.seed_buy_cost(s)
		var srow := HBoxContainer.new()
		srow.add_theme_constant_override("separation", 8)
		var img := UiKit.sprite("res://assets/sprites/seeds/%s.svg" % sid, 36)
		if img:
			srow.add_child(img)
		var nv := VBoxContainer.new()
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nv.add_theme_constant_override("separation", 1)
		nv.add_child(UiKit.label(String(s.name), 14, UiKit.PINK_700, 600))
		var stock := Game._inv_seed_total(sid)
		nv.add_child(UiKit.label("留种 ×%d" % stock if stock > 0 else "未持有 · 播种需留种 1 株", 11, UiKit.PINK_400))
		srow.add_child(nv)
		srow.add_child(UiKit.label("%d 灵石" % cost, 13, UiKit.GOLD_600, 600))
		var b := _mini_button("购种", func() -> void: Game.seed_buy(sid))
		b.disabled = int(f.stones) < cost
		srow.add_child(b)
		scv.add_child(srow)
	scv.add_child(UiKit.label("上品种子播种消耗仓库留种 1 株 —— 首株在此高价购入, 之后靠收获自留。", 11, UiKit.PINK_400))
	sc.add_child(UiKit.margin_wrap(scv, 16))
	_content.add_child(sc)


func _mini_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 30)
	b.add_theme_font_override("font", UiKit.font(500))
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", UiKit.PINK_600)
	b.add_theme_color_override("font_hover_color", UiKit.PINK_600)
	b.add_theme_color_override("font_pressed_color", UiKit.WHITE)
	b.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.PINK_50, 8))
	b.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.PINK_100, 8))
	b.add_theme_stylebox_override("pressed", UiKit.stylebox(UiKit.PINK_500, 8))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b
