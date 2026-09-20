extends "res://scripts/apps/app_base.gd"
## 三生石：轮回页（灰盒转世 Meta 循环）——道韵总账/结局史 + 炼灵根(五→单, 每炼去一行更贵) + 先天特质 + 转世。
## 五行持有改五围图(root_radar)交互选择: 顶点=一行, 点击切换。

const RootRadar := preload("res://scripts/root_radar.gd")
const Portrait := preload("res://scripts/portrait.gd")
## 出身设定已废(一律宗门弟子), 只剩风味文本; 灵根 = 行数(道韵) + 自择五行(免费)。

var _content: VBoxContainer
var _rebuild_pending := false
var _root_n := 5                      # 身负行数: 5/4/3/2/1(五行俱全免费)
var _root_els: Array = ["金", "木", "水", "火", "土"]   # 持有哪几行(自择, 不超过 _root_n)
var _traits_sel: Array[String] = []   # 已订先天特质 id(一世, 多选)


func _build_content(vb: VBoxContainer) -> void:
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

	# —— 标题 + 道韵总账(合并紧凑) ——
	var hdr := bleed_head("三生石")
	hdr.add_theme_constant_override("margin_top", 6)
	hdr.add_theme_constant_override("margin_bottom", 4)
	var hdr_vb := hdr.get_child(0)   # 内部 VBox
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 4)
	stats.add_child(UiKit.label("%d 韵 · %d 世 · 最佳 %s · 魂印 %d" % [int(meta.get("dao", 0)), int(meta.get("lives", 0)), String(meta.get("best_name", "无")), int(meta.get("bonds", 0))], 11, UiKit.PINK_500))
	hdr_vb.add_child(stats)

	# —— 此世状态 / 转世操作 ——
	if GameState.fresh_start:
		_content.add_child(_rebirth_card(meta))
		return
	if Game.run.is_empty():
		return
	if not bool(Game.run.get("ended", false)):
		var live := bleed_section()
		var lv := VBoxContainer.new()
		lv.add_theme_constant_override("separation", 4)
		lv.add_child(UiKit.label("此世未了", 14, UiKit.PINK_700, 600))
		var lb := UiKit.label("第 %d 世（%s · %s）仍在途上 —— 寿尽、飞升、陨落或隐退后，三生石自会亮起转世之途。" % [int(Game.run.get("life", 1)), String(Game.run.get("origin", "?")), String(Game.run.get("end_kind", "进行中"))], 12, UiKit.PINK_600)
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lv.add_child(lb)
		if float(meta.get("bless_pct", 0.0)) > 0.0:
			lv.add_child(UiKit.label("天道眷顾：冲关率永久 +%.0f%%" % (float(meta.bless_pct) * 100.0), 11, UiKit.GOLD_600))
		live.add_child(UiKit.margin_wrap(lv, 10))
		_content.add_child(live)
		return

	# 此世已了 → 出身 / 遗产 / 转世
	_content.add_child(_rebirth_card(meta))


func _rebirth_card(meta: Dictionary) -> PanelContainer:
	var dao := int(meta.get("dao", 0))
	var c := bleed_section()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)

	# —— 容貌 + 五维图(同行) ——
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 6)
	top_row.custom_minimum_size = Vector2(0, 200)
	top_row.add_child(_face_portrait())
	var radar := RootRadar.new()
	radar.custom_minimum_size = Vector2(170, 184)
	radar.setup(PackedStringArray(Game.ELEMENTS), PackedStringArray(_root_els), "")
	radar.toggled.connect(_toggle_root_el)
	var radar_center := CenterContainer.new()
	radar_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	radar_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	radar_center.add_child(radar)
	top_row.add_child(radar_center)
	cv.add_child(top_row)

	# —— 炼灵根(下拉) ——
	var n_cns := {5: "五", 4: "四", 3: "三", 2: "二", 1: "单"}
	var root_drop := OptionButton.new()
	for i in Game.ROOT_COUNTS.size():
		var cnt := int(Game.ROOT_COUNTS[i])
		var price := int(Game.ROOT_TRIM_COST.get(cnt, 0))
		root_drop.add_item("%s灵根 · %s" % [String(n_cns.get(cnt, "?")), ("%d韵" % price) if price > 0 else "免费"], i)
	root_drop.select(Game.ROOT_COUNTS.find(_root_n))
	root_drop.item_selected.connect(func(idx: int) -> void: _set_root_n(int(Game.ROOT_COUNTS[idx])))
	root_drop.add_theme_font_override("font", UiKit.font(600))
	root_drop.add_theme_font_size_override("font_size", 13)
	root_drop.add_theme_color_override("font_color", UiKit.PINK_700)
	root_drop.add_theme_color_override("font_hover_color", UiKit.PINK_700)
	root_drop.add_theme_color_override("font_pressed_color", UiKit.PINK_700)
	root_drop.add_theme_color_override("font_disabled_color", UiKit.GRAY_400)
	root_drop.custom_minimum_size = Vector2(0, 36)
	root_drop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_drop.focus_mode = Control.FOCUS_NONE
	var drop_normal := UiKit.stylebox(UiKit.PINK_50, 8, false, 1, UiKit.PINK_300)
	drop_normal.content_margin_left = 10
	drop_normal.content_margin_right = 28
	var drop_hover := UiKit.stylebox(UiKit.PINK_100, 8, false, 1, UiKit.PINK_400)
	drop_hover.content_margin_left = 10
	drop_hover.content_margin_right = 28
	var drop_pressed := UiKit.stylebox(UiKit.PINK_200, 8, false, 2, UiKit.PINK_500)
	drop_pressed.content_margin_left = 10
	drop_pressed.content_margin_right = 28
	var drop_focus := UiKit.stylebox(UiKit.PINK_50, 8, false, 2, UiKit.PINK_400)
	drop_focus.content_margin_left = 10
	drop_focus.content_margin_right = 28
	root_drop.add_theme_stylebox_override("normal", drop_normal)
	root_drop.add_theme_stylebox_override("hover", drop_hover)
	root_drop.add_theme_stylebox_override("pressed", drop_pressed)
	root_drop.add_theme_stylebox_override("focus", drop_focus)
	root_drop.add_theme_stylebox_override("disabled", UiKit.stylebox(Color(UiKit.GRAY_200, 0.4), 8, false, 1, UiKit.GRAY_300))
	cv.add_child(root_drop)
	var cn := String(n_cns.get(_root_n, "?"))
	var rnote_txt := "五行俱全免费 · 聚灵 ×%.2f" % Game.root_coef_preview(_root_n, 0)
	if _root_n < 5:
		rnote_txt = "%s灵根 · 聚灵 ×%.2f · 缺行灵植 −1 月/升品" % [cn, Game.root_coef_preview(_root_n, 0)]
	var rnote := UiKit.label(rnote_txt, 11, UiKit.PINK_400)
	rnote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(rnote)

	# —— 先天特质(一世) ——
	cv.add_child(UiKit.label("先天特质", 14, UiKit.PINK_700, 600))
	var tgrid := GridContainer.new()
	tgrid.columns = 2
	tgrid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tgrid.add_theme_constant_override("h_separation", 8)
	tgrid.add_theme_constant_override("v_separation", 4)
	for t in DataManager.traits:
		var id := String(t.get("id", ""))
		var sel: bool = id in _traits_sel
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var nvb := VBoxContainer.new()
		nvb.add_theme_constant_override("separation", 1)
		nvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nvb.add_child(UiKit.label("%s%s" % [String(t.get("name", id)), " ✓" if sel else ""], 12, UiKit.PINK_600 if sel else UiKit.PINK_400, 600))
		var nl := UiKit.label(String(t.get("note", "")), 10, UiKit.PINK_400)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nvb.add_child(nl)
		row.add_child(nvb)
		row.add_child(UiKit.pill("%d韵" % int(t.get("cost", 0)), UiKit.WHITE, UiKit.GOLD_500 if not sel else UiKit.PINK_500, 10, 600))
		tgrid.add_child(UiKit.tappable_row(row, _toggle_trait.bind(id)))
	cv.add_child(tgrid)

	var spend := _root_cost() + _traits_cost()
	var budget := UiKit.label("合计 %d / %d 道韵%s" % [spend, dao, "（超支）" if spend > dao else ""])
	budget.add_theme_color_override("font_color", UiKit.RED_400 if spend > dao else UiKit.PINK_400)
	cv.add_child(budget)

	var go := Button.new()
	if GameState.fresh_start:
		go.text = "入世 · 第 1 世"
	else:
		go.text = "转世 · 入第 %d 世" % (int(meta.get("lives", 0)) + 1)
	go.focus_mode = Control.FOCUS_NONE
	go.custom_minimum_size = Vector2(0, 38)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.add_theme_font_override("font", UiKit.font(600))
	go.add_theme_font_size_override("font_size", 14)
	go.add_theme_color_override("font_color", UiKit.WHITE)
	go.add_theme_color_override("font_disabled_color", UiKit.WHITE)
	go.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.PINK_500, 10))
	go.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.PINK_600, 10))
	go.add_theme_stylebox_override("pressed", UiKit.stylebox(UiKit.PINK_600, 10))
	go.add_theme_stylebox_override("disabled", UiKit.stylebox(UiKit.GRAY_400, 10))
	go.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	go.disabled = spend > dao
	go.pressed.connect(func() -> void:
		if GameState.fresh_start:
			Game.new_game()
		Game.rebirth({}, 0, 0, {"n": _root_n, "els": _root_els}, _traits_sel.duplicate())
		_traits_sel.clear()
		GameState.fresh_start = false
		exit_app.emit()
	)
	cv.add_child(go)
	c.add_child(UiKit.margin_wrap(cv, 10))
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


## 容貌预览：玉阵头像框(UiKit.jade_frame) + portrait，点击进入捏脸工坊。
func _face_portrait() -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(180, 180)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())

	var look := Game.player_look()
	var male := String(look.get("gender", "female")) == "male"
	btn.add_child(UiKit.jade_frame(Portrait.build_from(look, 132, male), UiKit.aura_tint(String(look.get("aura", "")))))

	btn.pressed.connect(func() -> void:
		GameState.face_returning = true
		open_app.emit("face")
	)
	vb.add_child(btn)

	var hint := UiKit.pill("✦ 点击调整容貌", UiKit.PINK_600, Color(UiKit.PINK_200, 0.6), 10, 500)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hint)

	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = Vector2(180, 190)
	wrap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	wrap.add_child(vb)
	return wrap
