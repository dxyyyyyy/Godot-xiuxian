extends "res://scripts/apps/app_base.gd"
## 三生石：轮回页（灰盒转世 Meta 循环）——道韵总账/结局史 + 炼灵根(五→单, 每炼去一行更贵) + 先天特质 + 转世。
## 五行持有改五围图(root_radar)交互选择: 顶点=一行, 点击切换。

const RootRadar := preload("res://scripts/root_radar.gd")
const Portrait := preload("res://scripts/portrait.gd")
const NGScript := preload("res://sim/NpcGenerator.gd")
## 出身设定已废(一律宗门弟子), 只剩风味文本; 灵根 = 行数(道韵) + 自择五行(免费)。

var _content: VBoxContainer
var _rebuild_pending := false
var _root_n := 5                      # 身负行数: 5/4/3/2/1(五行俱全免费)
var _root_els: Array = ["金", "木", "水", "火", "土"]   # 持有哪几行(自择, 不超过 _root_n)
var _traits_sel: Array[String] = []   # 已订先天特质 id(一世, 多选)
var _sur_edit: LineEdit = null        # 姓输入(卡片随交互重建, 文本走 _sur/_giv_pending 保持)
var _giv_edit: LineEdit = null        # 名输入
var _sur_pending := ""                # 姓暂存: 新开局预填默认姓, 转世预填上世姓
var _giv_pending := ""                # 名暂存
var _name_dirty := false              # 本张卡上用户动过键盘 → 重建保留暂存; 未动过 → 回读 run
var _name_refocus := false            # 重建前输入框有焦点 → 重建后找回


func _build_content(vb: VBoxContainer) -> void:
	_sur_pending = Game.player_surname()   # 开页预填: 新开局=默认(沈/知味), 转世=上一世
	_giv_pending = Game.player_given()
	_name_dirty = false
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
	# 未动过键盘 → 每次重建都回读当前姓/名(转世=上一世, 新开局=默认);
	# 动过则保留暂存, 不打断正在输入的名字(月 tick/炼灵根重建同卡)。
	if not _name_dirty:
		_sur_pending = Game.player_surname()
		_giv_pending = Game.player_given()
	_name_refocus = _sur_edit != null and is_instance_valid(_sur_edit) and _sur_edit.has_focus()
	_sur_edit = null
	_giv_edit = null
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	var meta: Dictionary = Game.meta
	if meta.is_empty():
		return

	# —— 历世烙印者名录(GDD §16 三生石含此账; 重逢实装 GDD §13-①): 旧名·身份·世次·强度·今世寻回与否 ——
	# (旧版「标题+道韵总账」hdr 构造从未挂树=死代码, v2.8 清除; 道韵总账在转世卡/此世状态块显示, App 外层标题栏已有「三生石」)
	var seals: Array = meta.get("seals", [])
	if not seals.is_empty():
		var ts: Dictionary = DataManager.reunion_texts
		var lf: Dictionary = ts.get("lifestone", {})
		var reg_sec := bleed_section()
		var reg_vb := UiKit.margin_wrap(VBoxContainer.new(), 16)
		reg_vb.add_theme_constant_override("separation", 2)
		reg_sec.add_child(reg_vb)
		reg_vb.add_child(UiKit.label(String(lf.get("title", "历世烙印者名录")), 11, UiKit.PINK_600))
		for rec in seals:
			var strength := Game._seal_strength(rec)
			var tier: int = Game._seal_tier(strength)
			var tiers: Array = ts.get("tiers", [])
			var tname := String((tiers[tier] as Dictionary).get("name", "")) if tiers.size() > tier else ""
			var found := false
			if String(rec.get("fixed", "")) != "":
				found = bool(Game.run.get("npcs", {}).get(String(rec.fixed), {}).get("reunion", false))
			else:
				for nk in Game.run.get("npcs", {}):
					var ne: Dictionary = Game.run.npcs[nk]
					if bool(ne.get("reunion", false)) and String(ne.get("name", "")) == String(rec.get("name", "")):
						found = true
						break
			var row := String(lf.get("row", "【{name}】 {id} · 第{life}世 · 强度{strength} · {found}"))
			row = row.replace("{name}", String(rec.get("name", ""))).replace("{id}", String(NGScript.ID_NAMES.get(String(rec.get("identity", "")), "散修")))
			row = row.replace("{life}", String.num_int64(int(rec.get("seal_life", 0)))).replace("{strength}", String.num_int64(int(strength)))
			row = row.replace("{found}", ("今世已寻回 · " + tname) if found else ("转世在世 · 待重逢" if String(rec.get("fixed", "")) == "" else "旧人在世 · 待重逢"))
			reg_vb.add_child(UiKit.label(row, 10, UiKit.GRAY_400))
		_content.add_child(reg_sec)

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

	# —— 名字(新开局默认名 / 转世上世名, 均可改) ——
	cv.add_child(_name_row())

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
	go.pressed.connect(_enter_world)
	cv.add_child(go)
	c.add_child(UiKit.margin_wrap(cv, 10))
	return c


## 名字行(姓/名分栏, UiKit.name_row 共用样式): 文本走 _sur/_giv_pending(随交互重建保持); 重建前有焦点则找回。
func _name_row() -> Control:
	var built := UiKit.name_row(_sur_pending, _giv_pending, Game.DEFAULT_PLAYER_SURNAME, Game.DEFAULT_PLAYER_GIVEN)
	_sur_edit = built.sur
	_giv_edit = built.giv
	_sur_edit.text_changed.connect(func(t: String) -> void: _sur_pending = t; _name_dirty = true)
	_giv_edit.text_changed.connect(func(t: String) -> void: _giv_pending = t; _name_dirty = true)
	if _name_refocus:
		_name_refocus = false
		_sur_edit.grab_focus()
	return built.row


## 入世/转世: 姓/名两栏皆空=不修改; 任一非空即落(允许只填其一), 再 rebirth(keep_name=true 带进新世)。
func _enter_world() -> void:
	var sur := _sur_pending.strip_edges()
	var giv := _giv_pending.strip_edges()
	if sur != "" or giv != "":
		Game.set_player_name_parts(sur, giv)
	# 只 rebirth: meta 已由开始界面 new_game 重置, 这里再 new_game 会白起一世、开局志重复入纪事
	Game.rebirth({}, 0, 0, {"n": _root_n, "els": _root_els}, _traits_sel.duplicate())
	_traits_sel.clear()
	_name_dirty = false   # 已提交 → 下张卡重新回读 run
	GameState.fresh_start = false
	exit_app.emit()


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
