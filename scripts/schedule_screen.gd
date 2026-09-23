extends "res://scripts/screen_base.gd"
## 日程页：修炼面板（境界/修为/气血/寿元/突破率）+ 时速档 + 行动方案 + 游历去向 + 一世纪事预览。
## 数据全部来自 Game autoload（灰盒月度结算），本页只做「显示 + 转发」。
## 整页不滚（page_scrolls=false）：一世纪事卡片吃满剩余屏幕，条目超高时在卡内滚轮滚动。

const Portrait := preload("res://scripts/portrait.gd")

var _content: VBoxContainer
var _rebuild_pending := false
var _chron_scroll: ScrollContainer   ## 一世纪事卡内滚动条(每轮重建会换新实例)
var _map_dlg: CanvasLayer = null     ## 锁定去向弹窗层
var _map_speed_prev := 0


func _init() -> void:
	page_scrolls = false


func _build(vb: VBoxContainer) -> void:
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 16)
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	_chron_scroll = null
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	if Game.run.is_empty():
		return
	_content.add_child(_clock_card())
	_content.add_child(_profile_card())
	_content.add_child(_plan_card())
	_content.add_child(_travel_card())
	_content.add_child(_chronicle_card())


# ---- 时钟 + 时速档(紧凑) ----

func _clock_card() -> PanelContainer:
	var c := UiKit.card()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 5)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.add_child(UiKit.icon_rect("clock", 15, UiKit.PINK_500))
	head.add_child(UiKit.label(Game.calendar(), 13, UiKit.PINK_700, 600))
	if Game.pending.is_empty():
		var season := _season_name()
		head.add_child(UiKit.pill(season, UiKit.WHITE, UiKit.GREEN_500 if season == "春" else UiKit.JADE_500 if season == "夏" else UiKit.GOLD_500 if season == "秋" else UiKit.BLUE_500, 10, 600))
	head.add_child(UiKit.expander())
	# 时速档(紧凑单行): 暂停/1×/2×/5×, 高倍速在玉牌·测试
	var group := ButtonGroup.new()
	for opt in [[0, "暂停"], [1, "1×"], [2, "2×"], [5, "5×"]]:
		var v: int = opt[0]
		var b := _mini_seg(String(opt[1]), group, Game.speed == v)
		b.pressed.connect(func() -> void: Game.set_speed(v))
		head.add_child(b)
	cv.add_child(head)
	if Game.speed > 5:
		cv.add_child(UiKit.label("当前时速 %d× —— 高倍速档在玉牌 · 测试" % Game.speed, 10, UiKit.GOLD_600, 600))
	c.add_child(UiKit.margin_wrap(cv, 10))
	return c


func _season_name() -> String:
	var m := (int(Game.run.age_m) % 12) + 1
	if m >= 3 and m <= 5:
		return "春"
	if m >= 6 and m <= 8:
		return "夏"
	if m >= 9 and m <= 11:
		return "秋"
	return "冬"


## 紧凑分段按钮(高 24 / 字号 10), 时速档与游历去向共用。
func _mini_seg(text: String, group: ButtonGroup, is_on: bool) -> Button:
	var b := UiKit.seg_button(text, group, is_on)
	b.custom_minimum_size = Vector2(0, 24)
	b.add_theme_font_size_override("font_size", 10)
	return b


## 锁定去向分段: 灰底、悬停变亮 + 手型光标提示可点; 不入 ButtonGroup, 点击不影响当前选中态。
func _locked_seg(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 24)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", UiKit.font(500))
	b.add_theme_font_size_override("font_size", 10)
	b.add_theme_color_override("font_color", UiKit.GRAY_400)
	b.add_theme_color_override("font_hover_color", UiKit.INK)
	b.add_theme_color_override("font_pressed_color", UiKit.INK)
	b.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.GRAY_200, 8))
	b.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.GRAY_300, 8))
	b.add_theme_stylebox_override("pressed", UiKit.stylebox(UiKit.GRAY_300, 8))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


# ---- 修炼面板 ----

func _profile_card() -> PanelContainer:
	var c := UiKit.card()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 5)

	# 左: 头像(三生石同款玉阵框, 随气质染色; 框体总高与右侧条目齐平) | 右: 名号 + 修为/气血条; 五维小格在下方通栏
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	var av := CenterContainer.new()
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var look := Game.player_look()
	var k := 132.0 / 180.0
	av.add_child(UiKit.jade_frame(Portrait.build_from(look, 132.0 * k, Game.player_male()), UiKit.aura_tint(String(look.get("aura", ""))), k))
	top.add_child(av)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 5)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 1)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_child(UiKit.label(Game.realm_display(), 14, UiKit.PINK_700, 600))
	var ol := UiKit.label("出身%s · %s · 灵根×%.2f" % [String(Game.run.origin), Game.root_display(), float(Game.run.root)], 10, UiKit.PINK_400)
	ol.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nv.add_child(ol)
	head.add_child(nv)
	if Game.is_ended():
		head.add_child(UiKit.pill("此世已了 · %s" % String(Game.run.get("end_kind", "落幕")), UiKit.WHITE, UiKit.GRAY_400, 10, 600))
	right.add_child(head)
	var need := Game.layer_need()
	var cult := float(Game.run.cult)
	right.add_child(_stat_bar("修为 · %s" % ("圆满 · 自动冲关" if Game.realm_ready() else "%s/%s" % [Game._fmt(cult), Game._fmt(need)]), cult / need if need > 0 else 0.0, "%d%%" % int(round(cult / need * 100.0)) if need > 0 else "100%"))
	right.add_child(_stat_bar("气血", float(Game._qi()) / float(Game.qi_max()), "%d/%d" % [Game._qi(), Game.qi_max()]))
	top.add_child(right)
	cv.add_child(top)

	var infos := GridContainer.new()
	infos.columns = 5
	infos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	infos.add_theme_constant_override("h_separation", 8)
	infos.add_child(_stat_text("寿元", "%d/%d岁" % [int(Game.age_years()), Game.lifespan_cap_years()]))
	infos.add_child(_stat_text("冲关率", "%d%%" % int(round(Game.break_chance() * 100.0))))
	infos.add_child(_stat_text("武力", str(int(round(Game.wu_li())))))
	infos.add_child(_stat_text("月修为", Game._fmt(Game.month_gain())))
	infos.add_child(_stat_text("灵石", str(int(Game.farm().stones))))
	cv.add_child(infos)

	var buff_txt := Game.buffs_summary()
	var foot := UiKit.label("加持：%s" % (buff_txt if buff_txt != "" else "无"), 10, UiKit.PINK_400)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(foot)
	c.add_child(UiKit.margin_wrap(cv, 10))
	return c


func _stat_text(caption: String, value: String) -> PanelContainer:
	var box := UiKit.padded(UiKit.pink_box(), 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	vb.add_child(UiKit.label(caption, 10, UiKit.PINK_400))
	vb.add_child(UiKit.label(value, 12, UiKit.PINK_600, 600))
	box.add_child(vb)
	return box


func _stat_bar(caption: String, frac: float, value: String) -> PanelContainer:
	var box := UiKit.padded(UiKit.pink_box(), 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.add_child(UiKit.label(caption, 10, UiKit.PINK_400))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UiKit.progress(frac, UiKit.PINK_500))
	var val := UiKit.label(value, 11, UiKit.PINK_600, 600)
	val.custom_minimum_size = Vector2(30, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	vb.add_child(row)
	box.add_child(vb)
	return box


# ---- 行动方案 ----

func _plan_card() -> PanelContainer:
	var c := UiKit.card()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.add_child(UiKit.label("行动方案", 13, UiKit.PINK_700, 600))
	head.add_child(UiKit.expander())
	if Game.recover_months() > 0:
		head.add_child(UiKit.pill("闭关注养 · 余 %d 月" % Game.recover_months(), UiKit.WHITE, UiKit.GOLD_500, 10, 600))
	else:
		head.add_child(UiKit.label("自下一月生效", 10, UiKit.PINK_400))
	cv.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var group := ButtonGroup.new()
	for p in DataManager.plans:
		var pid := String(p.id)
		var b := _mini_seg("%s ×%.2f" % [String(p.name), float(p.mult)], group, String(Game.run.plan) == pid)
		b.disabled = Game.recover_months() > 0 and pid != "pure"   # 闭关封存: 只锁不灰当前生效项
		b.pressed.connect(func() -> void: Game.set_plan(pid))
		grid.add_child(b)
	cv.add_child(grid)
	var note := String(DataManager.plan(String(Game.run.plan)).get("note", ""))
	if note != "":
		var nl := UiKit.label(note, 10, UiKit.PINK_400)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(nl)
	c.add_child(UiKit.margin_wrap(cv, 10))
	return c


# ---- 游历去向（方案「出门游历」时生效）----

func _travel_card() -> PanelContainer:
	var c := UiKit.card()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 5)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.add_child(UiKit.icon_rect("eye", 15, UiKit.PINK_500))
	head.add_child(UiKit.label("游历去向", 13, UiKit.PINK_700, 600))
	head.add_child(UiKit.expander())
	head.add_child(UiKit.label("缘起缘灭，名录自宽", 10, UiKit.PINK_400))
	cv.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var group := ButtonGroup.new()
	var cur := String(Game.run.get("travel_dest", "auto"))
	var auto := _mini_seg("自动轮换", group, cur == "auto")
	auto.pressed.connect(func() -> void: Game.set_travel_dest("auto"))
	grid.add_child(auto)
	for id in Game.TRAVEL_MAPS:
		var info: Dictionary = Game.TRAVEL_MAPS[id]
		var locked := int(Game.run.realm) < Game.map_unlock_realm(String(id))
		var txt := String(info.name) if not locked else "%s·锁" % String(info.name)
		var tid := String(id)
		if locked:
			var lb := _locked_seg(txt)   # 灰底可点分段: 不入 ButtonGroup, 点开解锁条件
			lb.pressed.connect(_open_locked_map.bind(tid, info))
			grid.add_child(lb)
		else:
			var b := _mini_seg(txt, group, cur == String(id))
			b.pressed.connect(func() -> void: Game.set_travel_dest(tid))
			grid.add_child(b)
	cv.add_child(grid)
	c.add_child(UiKit.margin_wrap(cv, 10))
	return c


## 锁定去向弹窗: 锁图标 + 解锁条件（境界名）+ 当地景象预告。点灰色「·锁」分段时弹出。
func _open_locked_map(id: String, info: Dictionary) -> void:
	_close_map_dlg()
	if Game.speed > 0:
		_map_speed_prev = Game.speed
		Game.set_speed(0)
	var dlg := UiKit.dialog_layer(self, 300.0)
	_map_dlg = dlg.layer
	UiKit.dim_click_close(dlg.dim, _close_map_dlg)
	var cv: VBoxContainer = dlg.vb

	var lock := CenterContainer.new()
	lock.add_child(UiKit.icon_rect("lock", 40, UiKit.GRAY_400))
	cv.add_child(lock)
	cv.add_child(UiKit.label(String(info.name), 18, UiKit.PINK_700, 600, HORIZONTAL_ALIGNMENT_CENTER))
	var pills := HBoxContainer.new()
	pills.alignment = BoxContainer.ALIGNMENT_CENTER
	pills.add_child(UiKit.pill("未解锁", UiKit.WHITE, UiKit.GRAY_400, 11, 600))
	cv.add_child(pills)

	cv.add_child(UiKit.vspace(2))
	cv.add_child(UiKit.label("解锁条件", 13, UiKit.PINK_600, 600))
	cv.add_child(UiKit.label("· 境界达到%s期后开放游历" % _realm_name(Game.map_unlock_realm(id)), 12, UiKit.INK))
	var scene := String(info.get("scene", ""))
	if scene != "":
		cv.add_child(UiKit.label("· 当地景象: %s" % scene, 12, UiKit.INK))

	cv.add_child(UiKit.vspace(4))
	cv.add_child(_dialog_close())


func _close_map_dlg() -> void:
	if _map_dlg != null:
		_map_dlg.queue_free()
		_map_dlg = null
	if _map_speed_prev > 0:
		Game.set_speed(_map_speed_prev)
		_map_speed_prev = 0


## 境界索引 → 境界名(realms.json: 0=炼气 1=筑基…)。
func _realm_name(idx: int) -> String:
	if idx >= 0 and idx < DataManager.realms.size():
		return String(DataManager.realms[idx].get("name", "境界%d" % idx))
	return "境界%d" % idx


## 弹窗底部关闭按钮（粉底胶囊, 同图鉴弹窗风格）。
func _dialog_close() -> Button:
	var b := Button.new()
	b.text = "关闭"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 36)
	b.add_theme_font_override("font", UiKit.font(600))
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", UiKit.WHITE)
	b.add_theme_color_override("font_hover_color", UiKit.WHITE)
	b.add_theme_color_override("font_pressed_color", UiKit.WHITE)
	b.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.PINK_500, 10))
	b.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.PINK_600, 10))
	b.add_theme_stylebox_override("pressed", UiKit.stylebox(UiKit.PINK_700, 10))
	b.pressed.connect(_close_map_dlg)
	return b


# ---- 一世纪事预览（全文见玉牌·纪事）----

func _chronicle_card() -> PanelContainer:
	var c := UiKit.card()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL   # 吃掉日程页剩余屏幕
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.add_child(UiKit.icon_rect("bell", 14, UiKit.PINK_500))
	head.add_child(UiKit.label("一世纪事", 13, UiKit.PINK_700, 600))
	head.add_child(UiKit.expander())
	head.add_child(UiKit.label("只叙关注之人 · 全文见玉牌 · 纪事", 10, UiKit.PINK_400))
	cv.add_child(head)

	if GameState.chronicle.is_empty():
		cv.add_child(UiKit.label("纪事未启——日子还长。", 12, UiKit.PINK_400))
	else:
		# 特殊事件只显示选择结果: 抉择行剥去「◇ 抉择」前缀只留结果段; 纯抉择行(无结果段)整行跳过
		var shown: Array = []
		var idx := GameState.chronicle.size() - 1
		while idx >= 0 and shown.size() < 14:
			var e: Dictionary = GameState.chronicle[idx]
			var t := Game.filter_chronicle_for_follows(String(e.text))   # 未关注 NPC 的事不上日程页(玉牌纪事仍有全文)
			if t == "":
				idx -= 1
				continue
			if t.begins_with("◇ 抉择「"):
				var cut := t.find("」")
				t = "" if cut == -1 else t.substr(cut + 1).strip_edges()
				if t.begins_with("——"):
					t = t.substr(2).strip_edges()
			t = _strip_time(t)
			t = _strip_parens(t)
			if t != "":
				shown.push_front({"day": String(e.day), "text": t})
			idx -= 1
		# 列表装进卡内滚动容器: 卡片吃满剩余屏幕, 条目超高时滚轮滚列表, 页面本身不滚
		var name_keys := UiKit.npc_name_keys()   # 【人名】链接反查表(每轮重建一次)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 4)
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(UiKit.expander())   # 弹性空隙: 条目少时沉到卡片底, 多时收紧转为滚动
		# 同月多条只在该月首行挂时间标签: 后续行留 68px 空位保持缩进, 换月处补一点留白做视觉分段
		var last_day := ""
		var first_row := true
		for e in shown:
			var day := String(e.day)
			if not first_row and day != last_day:
				list.add_child(UiKit.vspace(6))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var tag := UiKit.label(_short_when(day) if day != last_day else "", 10, UiKit.PINK_400, 500)
			tag.custom_minimum_size = Vector2(68, 0)
			tag.clip_text = true
			tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN   # 长文本换行时, 日期钉在第一行
			tag.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			row.add_child(tag)
			row.add_child(UiKit.chronicle_line(String(e.text), name_keys, 12, UiKit.PINK_600))   # 长事件完整换行显示, 超出卡片高度由卡内滚轮查看; 【人名】可点开详情
			list.add_child(row)
			last_day = day
			first_row = false
		scroll.add_child(list)
		cv.add_child(scroll)
		_chron_scroll = scroll
		_scroll_to_latest.call_deferred()
	c.add_child(UiKit.margin_wrap(cv, 10))
	return c


## 纪事重建后自动滚到底部看最新一条: 布局排定滚动范围前给不了终值, 故 deferred 且超幅自动钳制。
func _scroll_to_latest() -> void:
	if _chron_scroll == null or not is_instance_valid(_chron_scroll):
		return
	_chron_scroll.scroll_vertical = 1 << 20


## 时间标签缩写: 「第2世 · 第13年 · 5月」→「第13年5月」; 异常标签原样返回
func _short_when(day: String) -> String:
	var parts := day.split("·")
	if parts.size() >= 3:
		var year := String(parts[1]).strip_edges().trim_prefix("第").trim_suffix("年")
		var month := String(parts[2]).strip_edges().trim_suffix("月")
		return "第%s年%d月" % [year, int(month)]
	return day


## 月报行自带「第Y年·M月 · 」时间前缀: 预览左侧标签已显示时间, 剥去重复的日期前缀只留内容。
func _strip_time(t: String) -> String:
	if t.begins_with("第") and t.contains("年·"):
		var parts := t.split(" · ")
		if parts.size() >= 2 and String(parts[0]).contains("年·"):
			parts.remove_at(0)
			return " · ".join(parts)
	return t


## 日程预览瘦身: 去掉括号内的提示细节(全半角括号, 可多层) —— 玉牌纪事可见全文
func _strip_parens(t: String) -> String:
	var rx := RegEx.create_from_string("\\([^()]*\\)|（[^（）]*）")
	var prev := ""
	while prev != t:
		prev = t
		t = rx.sub(t, "", true)
	t = t.strip_edges()
	while t.ends_with("·") or t.ends_with("· ") or t.ends_with(" ·"):
		t = t.strip_edges().trim_suffix("·").strip_edges()
	return t
