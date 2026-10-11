extends "res://scripts/apps/app_base.gd"
## 坊市：灵石总账 + 清仓余货 + 稀有种子购种 + 书卷功法 + 突破丹（自库房迁出, 独立成页; GDD 留位货架 v2.9.6 补齐, 「灵材」货架同日拍板下架）。
## 购种走 Game.seed_buy（价 × seed_buy_mult, 入库为「凡」品留种）; 上品播种需仓库留种 1 株。
## 开垦吃自种灵植(Game.farm_reclaim, §6.1.1); 突破丹走 Game.pill_buy（价随境界水涨, 不限购可叠加）。

var _content: VBoxContainer
var _rebuild_pending := false
var _folded := {}   # 区块折叠态(键=区块 id): 页面常驻实例, Game.changed 整页重建后仍保持


func _build_content(vb: VBoxContainer) -> void:
	vb.add_child(bleed_head("坊市", "余货换灵石 · 种子书卷突破丹有售。"))
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

	# —— 灵石总账 + 清货(头行右侧常显灵石数) ——
	var c := bleed_section()
	_content.add_child(c)
	var cv := _section_head(c, "ledger", "灵石 · 总账", UiKit.label("%d" % int(f.stones), 22, UiKit.GOLD_600, 600))
	cv.add_child(_mini_button("清空余货换灵石", func() -> void: Game.farm_sell_all()))
	var hint := UiKit.label("收获都自动入仓; 灵植点库房物品格卖出。余货一键清仓, 换成灵石购种修行。", 11, UiKit.PINK_400)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(hint)

	# —— 稀有种子 · 购种（上品灵植, 价昂; 购得入库为「凡」品留种）——
	var sc := bleed_section()
	_content.add_child(sc)
	var scv := _section_head(sc, "seeds", "稀有种子 · 购种")
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
		var sdesc := UiKit.label("留种 ×%d" % stock if stock > 0 else "未持有 · 播种需留种 1 株", 11, UiKit.PINK_400)
		sdesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nv.add_child(sdesc)
		srow.add_child(nv)
		srow.add_child(UiKit.label("%d 灵石" % cost, 13, UiKit.GOLD_600, 600))
		var b := _mini_button("购种", func() -> void: Game.seed_buy(sid))
		b.disabled = int(f.stones) < cost
		srow.add_child(b)
		scv.add_child(srow)
	scv.add_child(UiKit.label("上品种子播种消耗仓库留种 1 株 —— 首株在此高价购入, 之后靠收获自留。", 11, UiKit.PINK_400))

	# —— 书卷 · 功法（残页常供 + 上架功法整卷, GDD §5.3 坊市位）——
	var gc := bleed_section()
	_content.add_child(gc)
	var gcv := _section_head(gc, "scroll", "书卷 · 功法")
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 8)
	var pv := VBoxContainer.new()
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv.add_theme_constant_override("separation", 1)
	pv.add_child(UiKit.label("功法残页", 14, UiKit.PINK_700, 600))
	var pdesc := UiKit.label("存 %d 页 · 地摊价随境界水涨, 坊市常供翻倍" % int(Game.gongfa().get("pages", 0)), 11, UiKit.PINK_400)
	pdesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv.add_child(pdesc)
	prow.add_child(pv)
	prow.add_child(UiKit.label("%d 灵石" % Game.gongfa_page_price(), 13, UiKit.GOLD_600, 600))
	var pb := _mini_button("购一页", func() -> void: Game.gongfa_page_buy())
	pb.disabled = int(f.stones) < Game.gongfa_page_price()
	prow.add_child(pb)
	gcv.add_child(prow)
	for def in DataManager.gongfa:
		if not bool(def.get("market", false)):
			continue
		gcv.add_child(_gongfa_row(def))
	var ghint := UiKit.label("整卷购入即残卷态, 与残页合成同 —— 研通后方可装备; 未上架的六部只能攒残页合成。", 11, UiKit.PINK_400)
	ghint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gcv.add_child(ghint)

	# —— 丹药 · 突破丹（坊市购入不限量: 价随境界水涨, +10% 一次性冲关加成, §6.0.4/§6.4.2）——
	var pc := bleed_section()
	_content.add_child(pc)
	var pcv := _section_head(pc, "pill", "丹药 · 突破丹")
	var pill_row := HBoxContainer.new()
	pill_row.add_theme_constant_override("separation", 8)
	var pill_v := VBoxContainer.new()
	pill_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pill_v.add_theme_constant_override("separation", 1)
	pill_v.add_child(UiKit.label("突破丹", 14, UiKit.PINK_700, 600))
	var cb := Game._buff_pct("check_pct")
	var ptxt := "每枚冲关成功率 +%.0f%%, 可叠加 —— 未冲关不消散, 破境方消" % (float(Game.econ("pill_bonus", 0.10)) * 100.0)
	if cb > 0.0:
		ptxt += " · 已加持 %+.0f%%检定" % (cb * 100.0)
	var plabel := UiKit.label(ptxt, 11, UiKit.PINK_400)
	plabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pill_v.add_child(plabel)
	pill_row.add_child(pill_v)
	pill_row.add_child(UiKit.label("%d 灵石" % Game.pill_price(), 13, UiKit.GOLD_600, 600))
	var pbuy := _mini_button("购丹", func() -> void: Game.pill_buy())
	pbuy.disabled = int(f.stones) < Game.pill_price()
	pill_row.add_child(pbuy)
	pcv.add_child(pill_row)
	var phint := UiKit.label("不限购, 价随境界水涨, 多购同叠 —— 冲关是硬仗, 丹是备而不赖的保险(§6.0.4)。", 11, UiKit.PINK_400)
	phint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pcv.add_child(phint)


## 折叠区块头: 「▾/▸ 标题」点击头 + 可选右侧常显控件(灵石数等); 返回内容体 VBox, 折叠即整块隐藏。
## 折叠态记 _folded[key] —— Game.changed 每次变动都整页重建, 折叠态挂在成员上才不会弹回展开。
func _section_head(section: PanelContainer, key: String, title: String, right: Control = null) -> VBoxContainer:
	var folded: bool = bool(_folded.get(key, false))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var btn := Button.new()
	btn.text = ("▸ " if folded else "▾ ") + title
	btn.focus_mode = Control.FOCUS_NONE
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for st in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	btn.add_theme_font_override("font", UiKit.font(600))
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", UiKit.PINK_700)
	btn.add_theme_color_override("font_hover_color", UiKit.PINK_600)
	btn.add_theme_color_override("font_pressed_color", UiKit.PINK_500)
	btn.pressed.connect(_toggle_fold.bind(key))
	head.add_child(btn)
	if right != null:
		head.add_child(right)
	cv.add_child(head)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.visible = not folded
	cv.add_child(body)
	section.add_child(UiKit.margin_wrap(cv, 16))
	return body


func _toggle_fold(key: String) -> void:
	_folded[key] = not bool(_folded.get(key, false))
	_rebuild()


## 上架功法行: 已持有置灰, 未持有可整卷购入(残卷态, 藏经阁研通才生效)
func _gongfa_row(def: Dictionary) -> Control:
	var id := String(def.id)
	var owned: bool = id in Array(Game.gongfa().get("owned", []))
	var cost := int(def.get("price", 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_theme_constant_override("separation", 1)
	nv.add_child(UiKit.label("%s ×%.2f" % [String(def.name), float(def.get("mult", 1.0))], 14, UiKit.PINK_700 if not owned else UiKit.GRAY_400, 600))
	var desc := UiKit.label(String(def.get("desc", "")), 11, UiKit.PINK_400)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nv.add_child(desc)
	row.add_child(nv)
	if owned:
		row.add_child(UiKit.pill("已持有", UiKit.WHITE, UiKit.GRAY_300, 12, 600))
	else:
		row.add_child(UiKit.label("%d 灵石" % cost, 13, UiKit.GOLD_600, 600))
		var b := _mini_button("购入", func() -> void: Game.gongfa_market_buy(id))
		b.disabled = int(Game.farm().stones) < cost
		row.add_child(b)
	return row


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
