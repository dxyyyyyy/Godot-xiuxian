extends "res://scripts/apps/app_base.gd"
## 三生石：轮回页（灰盒转世 Meta 循环）——道韵总账/结局史 + 炼灵根(五→单, 每炼去一行更贵) + 先天特质 + 转世。
## 五行持有改五围图(root_radar)交互选择: 顶点=一行, 点击切换。

const RootRadar := preload("res://scripts/root_radar.gd")
## 出身设定已废(一律宗门弟子), 只剩风味文本; 灵根 = 行数(道韵) + 自择五行(免费)。

var _content: VBoxContainer
var _rebuild_pending := false
var _root_n := 5                      # 身负行数: 5/4/3/2/1(五行俱全免费)
var _root_els: Array = ["金", "木", "水", "火", "土"]   # 持有哪几行(自择, 不超过 _root_n)
var _traits_sel: Array[String] = []   # 已订先天特质 id(一世, 多选)


func _build_content(vb: VBoxContainer) -> void:
	vb.add_child(bleed_head("三生石", "宗门后山那块石头，拓的是「自家的那一份」。"))
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
	var meta: Dictionary = Game.meta
	if meta.is_empty():
		return

	# —— 道韵总账(紧凑单行) ——
	var total := bleed_section()
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.add_child(UiKit.icon_rect("heart", 14, UiKit.PINK_500))
	head.add_child(UiKit.label("道韵总账", 13, UiKit.PINK_700, 600))
	head.add_child(UiKit.expander())
	head.add_child(UiKit.label("累计 %d 韵 · %d 世 · 最佳 %s · 魂印 %d" % [int(meta.get("dao", 0)), int(meta.get("lives", 0)), String(meta.get("best_name", "无")), int(meta.get("bonds", 0))], 12, UiKit.PINK_600, 600))
	tv.add_child(head)
	var endings: Dictionary = meta.get("endings", {})
	if not endings.is_empty():
		var parts := PackedStringArray()
		for k in endings:
			parts.append("%s×%d" % [String(k), int(endings[k])])
		var el := UiKit.label("结局史：%s" % " · ".join(parts), 11, UiKit.PINK_400)
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(el)
	total.add_child(UiKit.margin_wrap(tv, 10))
	_content.add_child(total)

	# —— 此世状态 / 转世操作 ——
	if Game.run.is_empty():
		return
	if not bool(Game.run.get("ended", false)):
		var live := bleed_section()
		var lv := VBoxContainer.new()
		lv.add_theme_constant_override("separation", 6)
		lv.add_child(UiKit.label("此世未了", 16, UiKit.PINK_700, 600))
		var lb := UiKit.label("第 %d 世（%s · %s）仍在途上 —— 寿尽、飞升、陨落或隐退后，三生石自会亮起转世之途。" % [int(Game.run.get("life", 1)), String(Game.run.get("origin", "?")), String(Game.run.get("end_kind", "进行中"))], 13, UiKit.PINK_600)
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lv.add_child(lb)
		if float(meta.get("bless_pct", 0.0)) > 0.0:
			lv.add_child(UiKit.label("天道眷顾：冲关率永久 +%.0f%%" % (float(meta.bless_pct) * 100.0), 12, UiKit.GOLD_600))
		live.add_child(UiKit.margin_wrap(lv, 16))
		_content.add_child(live)
		return

	# 此世已了 → 出身 / 遗产 / 转世
	_content.add_child(_rebirth_card(meta))


func _rebirth_card(meta: Dictionary) -> PanelContainer:
	var dao := int(meta.get("dao", 0))
	var c := bleed_section()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 12)

	# —— 炼灵根: 默认五行俱全(五灵根)免费, 每炼去一行更贵(30/80/150/240 累计); 持有哪几行免费自择 ——
	cv.add_child(UiKit.label("转世 · 炼灵根", 16, UiKit.PINK_700, 600))
	var n_group := ButtonGroup.new()
	var n_cns := {5: "五", 4: "四", 3: "三", 2: "二", 1: "单"}
	# 档位按钮竖排在左, 五围图占右侧
	var pick_row := HBoxContainer.new()
	pick_row.add_theme_constant_override("separation", 12)
	var ncol := VBoxContainer.new()
	ncol.custom_minimum_size = Vector2(92, 0)
	ncol.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ncol.add_theme_constant_override("separation", 4)
	for i in Game.ROOT_COUNTS.size():
		var cnt := int(Game.ROOT_COUNTS[i])
		var price := int(Game.ROOT_TRIM_COST.get(cnt, 0))
		var nb := UiKit.seg_button("%s灵根%s" % [String(n_cns.get(cnt, "?")), ("%d韵" % price) if price > 0 else "免费"], n_group, cnt == _root_n)
		nb.add_theme_font_size_override("font_size", 11)
		nb.pressed.connect(_set_root_n.bind(cnt))
		ncol.add_child(nb)
	pick_row.add_child(ncol)
	var radar := RootRadar.new()
	radar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	radar.setup(PackedStringArray(Game.ELEMENTS), PackedStringArray(_root_els), "")
	radar.toggled.connect(_toggle_root_el)
	pick_row.add_child(radar)
	cv.add_child(pick_row)
	var cn := String(n_cns.get(_root_n, "?"))
	var rnote_txt := "五行俱全（杂灵根）免费：亲和覆盖全五行，聚灵系数垫底（×%.2f）；出身一律宗门弟子。" % Game.root_coef_preview(_root_n, 0)
	if _root_n < 5:
		rnote_txt = "炼至 %s灵根：聚灵系数 ×%.2f，亲和覆盖面换强度 —— 缺的那行灵植不吃 −1 月/升品 ×2，水火不同身则无「上品封锁」。" % [cn, Game.root_coef_preview(_root_n, 0)]
	var rnote := UiKit.label(rnote_txt, 12, UiKit.PINK_400)
	rnote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(rnote)
	var owned: String = "·".join(PackedStringArray(_root_els))
	var plabel := UiKit.label("下世灵根 ≈ ×%.2f · %s灵根·%s（%d/%d 行）" % [Game.root_coef_preview(_root_n, 0), cn, owned, _root_els.size(), _root_n], 12, UiKit.GOLD_600, 600)
	plabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(plabel)

	# —— 先天特质(一世): 转世时道韵买断的胎里禀赋, 每世重购、不带到下下世; 一行两格 ——
	cv.add_child(UiKit.label("先天特质（一世）", 16, UiKit.PINK_700, 600))
	var tgrid := GridContainer.new()
	tgrid.columns = 2
	tgrid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tgrid.add_theme_constant_override("h_separation", 8)
	tgrid.add_theme_constant_override("v_separation", 6)
	for t in DataManager.traits:
		var id := String(t.get("id", ""))
		var sel: bool = id in _traits_sel
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var nvb := VBoxContainer.new()
		nvb.add_theme_constant_override("separation", 1)
		nvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nvb.add_child(UiKit.label("%s%s" % [String(t.get("name", id)), " ✓" if sel else ""], 13, UiKit.PINK_600 if sel else UiKit.PINK_400, 600))
		var nl := UiKit.label(String(t.get("note", "")), 11, UiKit.PINK_400)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nvb.add_child(nl)
		row.add_child(nvb)
		row.add_child(UiKit.pill("%d 韵" % int(t.get("cost", 0)), UiKit.WHITE, UiKit.GOLD_500 if not sel else UiKit.PINK_500, 11, 600))
		tgrid.add_child(UiKit.tappable_row(row, _toggle_trait.bind(id)))
	cv.add_child(tgrid)

	var spend := _root_cost() + _traits_cost()
	var budget := UiKit.label("合计 %d / %d 道韵%s" % [spend, dao, "（超支，减一减）" if spend > dao else ""])
	budget.add_theme_color_override("font_color", UiKit.RED_400 if spend > dao else UiKit.PINK_400)
	cv.add_child(budget)

	var go := Button.new()
	go.text = "转世 · 入第 %d 世" % (int(meta.get("lives", 0)) + 1)
	go.focus_mode = Control.FOCUS_NONE
	go.custom_minimum_size = Vector2(0, 44)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.add_theme_font_override("font", UiKit.font(600))
	go.add_theme_font_size_override("font_size", 15)
	go.add_theme_color_override("font_color", UiKit.WHITE)
	go.add_theme_color_override("font_disabled_color", UiKit.WHITE)
	go.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.PINK_500, 10))
	go.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.PINK_600, 10))
	go.add_theme_stylebox_override("pressed", UiKit.stylebox(UiKit.PINK_600, 10))
	go.add_theme_stylebox_override("disabled", UiKit.stylebox(UiKit.GRAY_400, 10))
	go.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	go.disabled = spend > dao
	go.pressed.connect(func() -> void:
		Game.rebirth({}, 0, 0, {"n": _root_n, "els": _root_els}, _traits_sel.duplicate())   # 出身传空: 取默认宗门弟子
		_traits_sel.clear()
		open_app.emit("face")   # 新世落地 → 先进捏脸工坊定容
	)
	cv.add_child(go)
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c


## 行数变更(档位按钮): 持有截断/补齐到恰好 n 行
func _set_root_n(n: int) -> void:
	_root_n = n
	while _root_els.size() > n:
		_root_els.pop_back()
	if _root_els.size() < n:
		for e in Game.ELEMENTS:   # 缺位按五行序补齐(不重复)
			if _root_els.size() >= n:
				break
			if not (_root_els.has(String(e))):
				_root_els.append(String(e))
	_rebuild()


## 雷达点顶点: 点掉一行 → 档位自动跳到对应的 N 灵根(费用随行数降); 点回一行 → 档位同步回升(至多五行)
func _toggle_root_el(es: String) -> void:
	if _root_els.has(es):
		if _root_els.size() > 1:   # 至少留一行(单灵根保底)
			_root_els.erase(es)
			_root_n = _root_els.size()
	else:
		_root_els.append(es)
		_root_n = _root_els.size()
	_rebuild()


func _root_cost() -> int:
	return int(Game.ROOT_TRIM_COST.get(_root_n, 0))


func _traits_cost() -> int:
	var s := 0
	for tid in _traits_sel:
		s += int(DataManager.traits_def(String(tid)).get("cost", 0))
	return s


## 特质多选: 点击行切换订购(预算不足由 go.disabled 兜底显示)
func _toggle_trait(id: String) -> void:
	if _traits_sel.has(id):
		_traits_sel.erase(id)
	else:
		_traits_sel.append(id)
	_rebuild()
