extends "res://scripts/apps/app_base.gd"
## 库房：洞府仓库（灰盒）——坊市（灵石/清货）+ 菜肴 + 灵植三层品质。
## 菜肴/灵植均为「一排五个」图文格（图谱来自 assets/sprites），点击格子弹出操作（吃/送/卖出/服用/赠礼）。

var _content: VBoxContainer
var _rebuild_pending := false
var _folded := {}   # 区块折叠状态（跨重建保持）：dishes / herbs
var _picker: CanvasLayer
var _picker_speed_prev := 0


func _build_content(vb: VBoxContainer) -> void:
	vb.add_child(bleed_head("库房", "洞府仓库 · 菜入仓，药入库。"))
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

	# —— 功法 · 藏经(残页→合成→研习→装备, GDD §5.3; run.tech 随装备功法变活)——可折叠 ——
	_content.add_child(_fold_section("功法 · 藏经", "gongfa", _gongfa_section(), _gongfa_badge()))

	# —— 菜肴（一排五个图文格，点击吃/送）——可折叠 ——
	var dishes: Dictionary = f.get("dishes", {})
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 8)
	var dish_n := 0
	if dishes.is_empty():
		dv.add_child(UiKit.label("灶上还没有成菜入库 —— 去家园点灶开烹，或选「做饭」方案。", 13, UiKit.PINK_400))
	else:
		var dgrid := _item_grid()
		for r in DataManager.recipes:
			var rid := String(r.id)
			var n := int(dishes.get(rid, 0))
			if n <= 0:
				continue
			dish_n += 1
			dgrid.add_child(_dish_cell(rid, r, n))
		dv.add_child(dgrid)
	_content.add_child(_fold_section("菜肴 · 仓库", "dishes", dv, "" if dish_n == 0 else "%d 种" % dish_n))

	# —— 灵植（一排五个图文格，点击服用/赠礼/卖出）——可折叠 ——
	var inv: Dictionary = f.get("inv", {})
	var millennium := int(f.get("millennium", 0))
	var yaodan := int(f.get("yaodan", 0))
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 8)
	var herb_n := 0
	if millennium > 0:
		var mrow := HBoxContainer.new()
		mrow.add_theme_constant_override("separation", 6)
		mrow.add_child(UiKit.pill("千年灵植 ×%d" % millennium, UiKit.WHITE, UiKit.GOLD_500, 12, 600))
		mrow.add_child(UiKit.expander())
		mrow.add_child(_mini_button("卖出", func() -> void: Game.farm_sell_millennium()))
		mrow.add_child(_mini_button("赠礼+80", func() -> void: Game.farm_gift_millennium()))
		hv.add_child(mrow)
	if yaodan > 0:
		var yrow := HBoxContainer.new()
		yrow.add_theme_constant_override("separation", 6)
		yrow.add_child(UiKit.pill("妖丹 ×%d" % yaodan, UiKit.WHITE, UiKit.PINK_600, 12, 600))
		yrow.add_child(UiKit.expander())
		yrow.add_child(_mini_button("卖出", func() -> void: Game.farm_sell_yaodan()))
		yrow.add_child(_mini_button("赠礼+60", func() -> void: Game.farm_gift_yaodan()))
		hv.add_child(yrow)
	var any := false
	var hgrid := _item_grid()
	for s in DataManager.seeds:
		var sid := String(s.id)
		if not inv.has(sid):
			continue
		var total := 0
		for g in inv[sid]:
			total += int(inv[sid][g])
		if total <= 0:
			continue
		any = true
		herb_n += 1
		hgrid.add_child(_herb_cell(sid, s, inv[sid], total))
	if not any and millennium <= 0 and yaodan <= 0:
		hv.add_child(UiKit.label("仓廪尚虚 —— 灵田收获后会自己入这里的格。", 13, UiKit.PINK_400))
	else:
		hv.add_child(hgrid)
	var herb_badge := ""
	if herb_n > 0:
		herb_badge = "%d 种" % herb_n
	if millennium > 0:
		herb_badge = ("· " if herb_badge != "" else "") + "千年 ×%d" % millennium
	if yaodan > 0:
		herb_badge = ("· " if herb_badge != "" else "") + "妖丹 ×%d" % yaodan
	_content.add_child(_fold_section("灵植 · 仓库", "herbs", hv, herb_badge))


## 可折叠通栏区块：标题行整行可点，收起/展开 body（状态记在 _folded，跨月报重建保持）。
func _fold_section(title: String, key: String, body: VBoxContainer, badge := "") -> PanelContainer:
	var c := bleed_section()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	var folded: bool = _folded.get(key, false)
	body.visible = not folded

	var header := Button.new()
	header.focus_mode = Control.FOCUS_NONE
	header.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	header.custom_minimum_size = Vector2(0, 28)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		header.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(UiKit.label(title, 16, UiKit.PINK_700, 600))
	hb.add_child(UiKit.expander())
	if badge != "":
		hb.add_child(UiKit.label(badge, 11, UiKit.PINK_400, 500))
		hb.add_child(UiKit.hspace(6))
	var chevron := UiKit.icon_rect("chevron-down", 15, UiKit.PINK_500)
	chevron.flip_v = not folded   # 展开时箭头朝上
	hb.add_child(chevron)
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	header.add_child(hb)
	header.pressed.connect(func() -> void:
		var now: bool = not _folded.get(key, false)
		_folded[key] = now
		body.visible = not now
		chevron.flip_v = not now
	)
	cv.add_child(header)
	cv.add_child(body)
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c


## 坊市已迁至独立 App(app_market); 本页管功法藏经与仓库两栏。


# ---- 功法 · 藏经(详解卷 5.3): 残页合成 / 藏经阁研习 / 装备主功法 ----

func _gongfa_section() -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	if Game.run.is_empty() or not Game.run.has("gongfa"):
		vb.add_child(UiKit.label("功法档案待开世建立。", 13, UiKit.PINK_400))
		return vb
	var g: Dictionary = Game.gongfa()
	var studying := String(g.get("studying", ""))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.add_child(UiKit.pill("功法残页 ×%d" % int(g.get("pages", 0)), UiKit.WHITE, UiKit.GOLD_500, 12, 600))
	if studying != "":
		head.add_child(UiKit.pill("研席·%s" % Game.gongfa_name(studying), UiKit.WHITE, UiKit.JADE_500, 12, 600))
	head.add_child(UiKit.expander())
	vb.add_child(head)
	for def in DataManager.gongfa:
		vb.add_child(_gongfa_row(def))
	var hint := UiKit.label("残页四源: 坊市/地摊购入 · 秘境大获 · 秋期论道 · 道侣赠礼; 藏经阁与悟性料理提研速 —— 研通方可装备, 装备位唯一、切换免费。", 11, UiKit.PINK_400)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hint)
	return vb


func _gongfa_badge() -> String:
	if Game.run.is_empty() or not Game.run.has("gongfa"):
		return ""
	var g: Dictionary = Game.gongfa()
	var owned_n := Array(g.get("owned", [])).size()
	var badge := "%d 部" % owned_n if owned_n > 0 else ""
	var pages := int(g.get("pages", 0))
	if pages > 0:
		badge = (("残页 ×%d · " % pages) + badge) if badge != "" else ("残页 ×%d" % pages)
	return badge


func _gongfa_row(def: Dictionary) -> Control:
	var id := String(def.id)
	var g: Dictionary = Game.gongfa()
	var owned: bool = id in Array(g.get("owned", []))
	var mastered := Game.gongfa_mastered(id)
	var equipped: bool = String(g.get("equipped", "")) == id
	var studying: bool = String(g.get("studying", "")) == id
	var mult := float(def.get("mult", 1.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	name_row.add_child(UiKit.label(String(def.name), 14, UiKit.PINK_700 if owned else UiKit.GRAY_400, 600))
	name_row.add_child(UiKit.label("×%.2f" % mult, 12, UiKit.GOLD_600, 600))
	if equipped:
		name_row.add_child(UiKit.pill("装备中", UiKit.WHITE, UiKit.GREEN_500, 11, 600))
	elif mastered:
		name_row.add_child(UiKit.pill("研通", UiKit.WHITE, UiKit.JADE_500, 11, 600))
	elif studying:
		name_row.add_child(UiKit.pill("研习中", UiKit.WHITE, UiKit.JADE_400, 11, 600))
	info.add_child(name_row)
	var state := ""
	if owned and not mastered:
		state = "%s · 研满 %d 有效研月可装备" % [Game.gongfa_prog_txt(id), int(def.get("research", 0))]
	elif owned:
		state = "研通 · 聚灵 ×%.2f · 武力 +%.0f%%" % [mult, (mult - 1.0) * 100.0]
	else:
		state = "%s · 合成需残页 %d 页%s" % [String(def.get("desc", "")), int(def.get("pages", 0)), " · 坊市有售" if bool(def.get("market", false)) else " · 仅残页合成"]
	var sl := UiKit.label(state, 11, UiKit.PINK_400 if owned else UiKit.GRAY_400)
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(sl)
	row.add_child(info)
	if equipped:
		row.add_child(UiKit.pill("主功法", UiKit.WHITE, UiKit.GREEN_500, 12, 600))
	elif owned and not mastered:
		row.add_child(_mini_button("收卷" if studying else "研习",
			func() -> void:
				if studying:
					Game.gongfa_stop_study()
				else:
					Game.gongfa_study(id)))
	elif owned:
		row.add_child(_mini_button("装备", func() -> void: Game.gongfa_equip(id)))
	else:
		var need := int(def.get("pages", 0))
		var syn := _mini_button("合成 %d页" % need, func() -> void: Game.gongfa_synthesize(id))
		syn.disabled = int(g.get("pages", 0)) < need
		row.add_child(syn)
	return row


## 物品网格：一排五个。
func _item_grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 5
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	return g


## 菜肴格：图谱 + 名称 + ×数量。
func _dish_cell(rid: String, r: Dictionary, n: int) -> Control:
	return _cell(_cell_content("res://assets/sprites/recipes/%s.svg" % rid, String(r.name), n),
		func() -> void: _open_item_actions(String(r.name),
			[String(r.get("effect", "")), "档位 %s · 库存 ×%d" % [
				String({"low": "低阶", "mid": "中阶", "high": "仙膳", "dark": "暗谱"}.get(String(r.tier), String(r.tier))), n]],
			[["吃", _act_and_close(func() -> void: Game.kitchen_eat(rid))],
				["送", _act_and_close(func() -> void: Game.kitchen_gift(rid))]]))


## 操作后关闭弹窗: 吃/送/服用/赠礼/卖出 统一「执行一次 + 收起」。
func _act_and_close(cb: Callable) -> Callable:
	return func() -> void:
		_close_picker()
		cb.call()


## 灵植格：图谱 + 名称 + ×总数。
func _herb_cell(sid: String, s: Dictionary, grades: Dictionary, total: int) -> Control:
	return _cell(_cell_content("res://assets/sprites/seeds/%s.svg" % sid, String(s.name), total),
		func() -> void:
			var acts: Array = []
			var use: Array = s.get("use", [])
			if use.has("tonic"):
				acts.append(["服用", _act_and_close(func() -> void: Game.farm_tonic(sid))])
			if use.has("gift"):
				acts.append(["赠礼", _act_and_close(func() -> void: Game.farm_gift(sid))])
			if use.has("market"):
				acts.append(["卖出", _act_and_close(func() -> void: Game.farm_sell(sid))])
			_open_item_actions(String(s.name),
				["%s · 凡%d 灵%d 上%d" % [String(s.type), int(grades.get("凡", 0)), int(grades.get("灵", 0)), int(grades.get("上", 0))],
				 "%d 灵石/株 · 库存 ×%d" % [Game.seed_stock_value(sid), total]], acts))


## 格子内容（图/名/数）与可点格壳（粉底 + 全幅透明按钮）。
func _cell_content(path: String, item_name: String, count: int) -> Control:
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	var img: Control = UiKit.sprite(path, 52)
	if img == null:
		img = UiKit.circle(52, UiKit.PINK_100, UiKit.PINK_200, "package", 22, UiKit.PINK_400)
	vb.add_child(img)
	var name_l := UiKit.label(item_name, 10, UiKit.PINK_700, 600, HORIZONTAL_ALIGNMENT_CENTER)
	name_l.clip_text = true
	vb.add_child(name_l)
	vb.add_child(UiKit.label("×%d" % count, 11, UiKit.GOLD_600, 600, HORIZONTAL_ALIGNMENT_CENTER))
	return vb


func _cell(content: Control, cb: Callable) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.stylebox(UiKit.PINK_50, 10))
	p.custom_minimum_size = Vector2(72, 96)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(content)
	var hit := Button.new()
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		hit.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	hit.pressed.connect(cb)
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.add_child(hit)
	return p


## 物品操作弹窗：图谱名 + 信息行 + 操作按钮（打开时暂停时间流逝，同选种弹窗）。
func _open_item_actions(title: String, lines: Array, actions: Array) -> void:
	_close_picker()
	if Game.speed > 0:
		_picker_speed_prev = Game.speed
		Game.set_speed(0)
	var dlg := UiKit.dialog_layer(self, 300.0)
	_picker = dlg.layer
	UiKit.dim_click_close(dlg.dim, _close_picker)
	var cv: VBoxContainer = dlg.vb
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiKit.label(title, 16, UiKit.PINK_700, 600))
	head.add_child(UiKit.expander())
	cv.add_child(head)
	for l in lines:
		var lb := UiKit.label(String(l), 12, UiKit.PINK_500)
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(lb)
	for a in actions:
		cv.add_child(_mini_button(String(a[0]), a[1]))
	cv.add_child(_mini_button("关闭", _close_picker))


func _close_picker() -> void:
	if _picker != null:
		_picker.queue_free()
		_picker = null
	if _picker_speed_prev > 0:
		Game.set_speed(_picker_speed_prev)
		_picker_speed_prev = 0


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
