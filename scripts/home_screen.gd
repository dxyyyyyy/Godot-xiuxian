extends "res://scripts/screen_base.gd"
## 家园页：灵田（9 地块/选种/虫害变异）+ 伙房（四小灶）。
## 坊市/库存已迁入玉牌 · 库房 App，洞府设施已迁入玉牌 · 洞府 App，这里只留灵石余额指示。
## 灰盒月度结算：生长/收获/巡视按月自动进行，本页只做显示 + 转发；
## 选种/选菜弹层打开时自动暂停时速，关闭恢复（greybox 模式）。

var _content: VBoxContainer
var _rebuild_pending := false
var _picker: Node            # 选种/选菜弹层（CanvasLayer 全屏对话框）
var _mode_speed_prev := 0      # 进入弹层前的时速档（退出恢复）


func _notification(what: int) -> void:
	# 切走页面时收起弹层（CanvasLayer 不随屏幕隐藏）
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_close_picker()


func _build(vb: VBoxContainer) -> void:
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	head.add_child(UiKit.label("洞府家园", 24, UiKit.PINK_600, 700, HORIZONTAL_ALIGNMENT_CENTER))
	head.add_child(UiKit.label("灵田 · 伙房 —— 岁月按月走", 13, UiKit.PINK_400, 400, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(head)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 16)
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
	_content.add_child(_farm_card())
	_content.add_child(_kitchen_card())


# ================= 灵田 =================

func _farm_card() -> PanelContainer:
	var f: Dictionary = Game.farm()
	var c := UiKit.card()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiKit.label("灵田", 18, UiKit.PINK_700, 600))
	head.add_child(UiKit.expander())
	head.add_child(UiKit.label("灵石 %d" % int(f.stones), 14, UiKit.GOLD_600, 600))
	head.add_child(UiKit.hspace(8))
	head.add_child(UiKit.label("%d/%d 块（随境界扩）" % [Game.farm_open_count(), Game.farm_cap()], 12, UiKit.PINK_400))
	cv.add_child(head)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var plots: Array = f.plots
	for i in plots.size():
		grid.add_child(_plot_tile(plots[i], i))
	cv.add_child(grid)

	var hint := UiKit.label("播种/开垦点地块；生长·收获·虫害·变异按月自动结算，收成自动入仓。卖出/服用/赠礼见玉牌 · 库房 · 坊市。方案「照顾灵田」=自动选种除虫+变异检定。", 11, UiKit.PINK_400)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(hint)
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c


func _plot_tile(p: Dictionary, idx: int) -> PanelContainer:
	var tile := UiKit.padded(UiKit.pink_box(), 10)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)

	if not bool(p.open):
		var cost := Game.farm_reclaim_cost()
		var can := cost > 0 and Game.farm_open_count() < Game.farm_cap()
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_child(UiKit.circle(40, UiKit.GRAY_200, UiKit.GRAY_300, "lock", 18, UiKit.GRAY_400))
		if can:
			vb.add_child(UiKit.label("荒地 · 开垦", 12, UiKit.PINK_600, 600, HORIZONTAL_ALIGNMENT_CENTER))
			vb.add_child(UiKit.label("%d 灵石" % cost, 11, UiKit.GOLD_600, 500, HORIZONTAL_ALIGNMENT_CENTER))
		else:
			vb.add_child(UiKit.label("未开垦", 12, UiKit.GRAY_400, 400, HORIZONTAL_ALIGNMENT_CENTER))
			vb.add_child(UiKit.label("突破扩地", 11, UiKit.GRAY_400, 400, HORIZONTAL_ALIGNMENT_CENTER))
		tile.add_child(vb)
		_ignore_mouse(vb)
		if can:
			_tile_click(tile, func() -> void: Game.farm_reclaim())
		return tile

	if String(p.seed) == "":
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_child(UiKit.label("🌱", 22, UiKit.PINK_500, 400, HORIZONTAL_ALIGNMENT_CENTER))
		vb.add_child(UiKit.label("空地 · 点选种", 12, UiKit.PINK_600, 600, HORIZONTAL_ALIGNMENT_CENTER))
		tile.add_child(vb)
		_ignore_mouse(vb)
		_tile_click(tile, func() -> void: _open_seed_picker(idx))
		return tile

	var s: Dictionary = DataManager.seed(String(p.seed))
	var eff := Game.seed_eff_months(s)
	# 作物图标占主视觉: 放大到 72px 并居中
	var img := UiKit.sprite("res://assets/sprites/seeds/%s.svg" % String(p.seed), 72)
	if img:
		var ic := CenterContainer.new()
		ic.custom_minimum_size = Vector2(0, 72)
		ic.add_child(img)
		vb.add_child(ic)
	# 名字与亲和同栏
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	var nl := UiKit.label(String(s.name), 13, UiKit.PINK_700, 600)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_row.add_child(nl)
	name_row.add_child(UiKit.pill(String(s.affinity) + "亲和", UiKit.WHITE, UiKit.GREEN_400, 10))
	vb.add_child(name_row)
	var months_row := HBoxContainer.new()
	months_row.add_theme_constant_override("separation", 6)
	months_row.add_child(UiKit.progress(float(int(p.age)) / float(eff), UiKit.GREEN_500))
	months_row.add_child(UiKit.label("%d/%d月" % [int(p.age), eff], 11, UiKit.PINK_500, 500))
	vb.add_child(months_row)
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 4)
	if bool(p.pest):
		tags.add_child(UiKit.pill("虫害!", UiKit.WHITE, UiKit.RED_400, 10, 600))
	if bool(p.get("mutated", false)):
		tags.add_child(UiKit.pill("变异!", UiKit.INK, UiKit.GOLD_400, 10, 600))
	if tags.get_child_count() > 0:
		vb.add_child(tags)
	tile.add_child(vb)
	return tile


## 地块/行级点击层：内容整体设为鼠标穿透后，透明按钮以最后子节点（最顶层）盖在地块上负责点击。
func _tile_click(tile: PanelContainer, cb: Callable) -> void:
	var hit := Button.new()
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		hit.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	hit.pressed.connect(cb)
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tile.add_child(hit)


## 递归把整棵子树的鼠标过滤设为 IGNORE（点击层在其上，事件必须一路穿透到 hit 按钮）。
func _ignore_mouse(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in c.get_children():
		if ch is Control:
			_ignore_mouse(ch)


# ================= 伙房 =================

func _kitchen_card() -> PanelContainer:
	var c := UiKit.card()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiKit.label("伙房 · 四小灶", 18, UiKit.PINK_700, 600))
	head.add_child(UiKit.expander())
	head.add_child(UiKit.label("已点亮 %d 灶" % Game.stove_open_count(), 12, UiKit.PINK_400))
	cv.add_child(head)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var stoves: Array = Game._stoves()
	for i in Game.STOVE_TOTAL:
		grid.add_child(_stove_tile(stoves, i))
	cv.add_child(grid)

	var hint := UiKit.label("手动烹一道即成（点「收取」入洞府仓库）；方案「做饭」每月自动烹一道低/中阶谱入库。吃/送去玉牌 · 库房。", 11, UiKit.PINK_400)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(hint)
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c


func _stove_tile(stoves: Array, i: int) -> PanelContainer:
	var tile := UiKit.padded(UiKit.pink_box(), 10)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)

	if i >= Game.stove_open_count():
		var realm_name := String(Game.stove_unlock_realm(i + 1).get("name", "?"))
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_child(UiKit.circle(36, UiKit.GRAY_200, UiKit.GRAY_300, "flame", 16, UiKit.GRAY_400))
		vb.add_child(UiKit.label("灶 %d · 未点亮" % (i + 1), 12, UiKit.GRAY_400, 400, HORIZONTAL_ALIGNMENT_CENTER))
		vb.add_child(UiKit.label("%s点亮" % realm_name, 11, UiKit.GRAY_400, 400, HORIZONTAL_ALIGNMENT_CENTER))
		tile.add_child(vb)
		return tile

	var dish: Dictionary = Game._stove_dish(i)
	if dish.is_empty():
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_child(UiKit.label("🔥", 20, UiKit.ORANGE_500, 400, HORIZONTAL_ALIGNMENT_CENTER))
		vb.add_child(UiKit.label("灶 %d · 空灶" % (i + 1), 13, UiKit.PINK_600, 600, HORIZONTAL_ALIGNMENT_CENTER))
		vb.add_child(UiKit.label("点击开烹", 11, UiKit.PINK_400, 400, HORIZONTAL_ALIGNMENT_CENTER))
		tile.add_child(vb)
		_ignore_mouse(vb)
		_tile_click(tile, func() -> void: _open_cook_picker(i))
		return tile

	# 食物图标占主视觉: 放大到 72px 并居中
	var img := UiKit.sprite("res://assets/sprites/recipes/%s.svg" % String(dish.get("id", "")), 72)
	if img:
		if not Game.stove_done(i):
			img.modulate = Color(1, 1, 1, 0.55)   # 烹制中半透明, 出锅全彩
		var ic := CenterContainer.new()
		ic.custom_minimum_size = Vector2(0, 72)
		ic.add_child(img)
		vb.add_child(ic)
	# 名字与阶级同栏
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	var nl := UiKit.label(String(dish.name), 13, UiKit.PINK_700, 600)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_row.add_child(nl)
	name_row.add_child(UiKit.pill(_tier_cn(String(dish.tier)), UiKit.WHITE, _tier_color(String(dish.tier)), 10))
	vb.add_child(name_row)
	if not Game.stove_done(i):
		# 烹制中: 进度条 + 还需月数, 不可收取/不可再开
		var needed := Game.cook_months(dish)
		var age := int(stoves[i].get("age", 0))
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 6)
		prow.add_child(UiKit.progress(float(age) / float(needed), UiKit.ORANGE_500))
		var pv := UiKit.label("%d/%d月" % [age, needed], 11, UiKit.ORANGE_500, 600)
		pv.custom_minimum_size = Vector2(40, 0)
		prow.add_child(pv)
		vb.add_child(prow)
		tile.add_child(vb)
		return tile

	# 已出锅: 效果 + 收取
	var eff := UiKit.label(String(dish.get("effect", "")), 11, UiKit.PINK_400)
	eff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(eff)
	vb.add_child(_mini_button("收取入库", func() -> void: Game.kitchen_collect(i)))
	tile.add_child(vb)
	return tile


# ================= 弹层（选种/选菜） =================

func _open_seed_picker(slot_idx: int) -> void:
	var season := _season_name()
	var opts := []
	var in_season := []
	var off_season := []
	for s in DataManager.seeds:
		if Game.seed_in_season(s, season):
			in_season.append(s)
		else:
			off_season.append(s)
	in_season.sort_custom(func(a, b): return Game.seed_value(a, season) > Game.seed_value(b, season))
	opts.append_array(in_season)
	opts.append_array(off_season)
	var rows := []
	for s in opts:
		var ok := Game.seed_in_season(s, season)
		var gated := Game.seed_gated(s)
		var stock := Game._inv_seed_total(String(s.id))
		var need_buy := gated and stock < 1
		var stones := int(Game.farm().stones)
		var disabled: bool
		if not ok:
			disabled = true
		elif stock > 0:
			disabled = false   # 已有留种: 播种免费, 不看灵石
		elif need_buy:
			disabled = stones < Game.seed_buy_cost(s)   # 买不起种 → 置灰
		else:
			disabled = stones < Game.seed_plant_cost(s)   # 播种费不够 → 置灰
		var sid := String(s.id)
		rows.append({
			"content": _seed_cell_content(s, ok, gated, stock, need_buy),
			"disabled": disabled,
			"cb": func() -> void: _pick_seed(slot_idx, sid),
		})
	_open_picker("选种 · 第%d格（%s季 · 当季优先）" % [slot_idx + 1, season], rows, 3)


## 种子单元格（一行三个）：名称 + 类型品质/稀有标签 / 月份亲和 / 产量 / 费用与留种状态。
## 上品稀有种子：需仓库留种 1 株（播种消耗）；无留种时点击 = 坊市购种入库。
func _seed_cell_content(s: Dictionary, ok: bool, gated: bool, stock: int, need_buy: bool) -> Control:
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 3)
	var name_l := UiKit.label(String(s.name), 14, UiKit.GRAY_400 if not ok else UiKit.PINK_700, 600, HORIZONTAL_ALIGNMENT_CENTER)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(name_l)
	var pills := HBoxContainer.new()
	pills.alignment = BoxContainer.ALIGNMENT_CENTER
	pills.add_theme_constant_override("separation", 3)
	pills.add_child(UiKit.pill("%s·%s" % [_type_cn(String(s.type)), String(s.grade)], UiKit.WHITE, _type_color(String(s.type)), 9))
	if gated:
		pills.add_child(UiKit.pill("稀有", UiKit.WHITE, UiKit.GOLD_500, 9, 600))
	vb.add_child(pills)
	vb.add_child(UiKit.label("%d月熟·%s亲和" % [Game.seed_eff_months(s), String(s.affinity)], 11, UiKit.PINK_600, 400, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(UiKit.label("产×%d" % int(s.yield), 11, UiKit.PINK_600, 400, HORIZONTAL_ALIGNMENT_CENTER))
	var cost_txt := "耗留种×1·免费" if stock > 0 else (("购种%d灵石" % Game.seed_buy_cost(s)) if need_buy else ("播种%d灵石" % Game.seed_plant_cost(s)))
	vb.add_child(UiKit.label(cost_txt, 11, UiKit.GOLD_600 if stock <= 0 else UiKit.GREEN_700, 600, HORIZONTAL_ALIGNMENT_CENTER))
	var state := ""
	var state_c := UiKit.PINK_400
	if not ok:
		state = "非当季"
		state_c = UiKit.GRAY_400
	elif need_buy:
		state = "点击购种入库"
		state_c = UiKit.GOLD_600
	elif gated:
		state = "留种×%d" % stock
	elif stock > 0:
		state = "库存播种"
	if state != "":
		vb.add_child(UiKit.label(state, 10, state_c, 500, HORIZONTAL_ALIGNMENT_CENTER))
	return vb


func _pick_seed(slot_idx: int, seed_id: String) -> void:
	var s: Dictionary = DataManager.seed(seed_id)
	if Game.seed_gated(s) and Game._inv_seed_total(seed_id) < 1:
		if Game.seed_buy(seed_id):
			_open_seed_picker(slot_idx)   # 购种入库后刷新本层：再次点击即播种
		return
	Game.farm_plant(slot_idx, seed_id)
	_close_picker()


func _open_cook_picker(stove_idx: int) -> void:
	var rows := []
	for r in DataManager.recipes:
		if String(r.tier) == "dark":
			continue
		var learned := int(Game.run.realm) >= int(r.get("min_realm", 0))
		var missing := Game.recipe_missing(r)
		rows.append({
			"content": _cook_cell_content(r, learned, missing),
			"disabled": missing != "" or not learned,
			"cb": func() -> void: _pick_cook(stove_idx, String(r.id)),
		})
	_open_picker("灶 %d · 开烹（已习得且足料可烹）" % (stove_idx + 1), rows, 3)


## 菜谱单元格（一行三个）：名称 + 阶层/门槛标签 / 效果 / 用料 / 状态。
func _cook_cell_content(r: Dictionary, learned: bool, missing: String) -> Control:
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 3)
	var name_l := UiKit.label(String(r.name), 14, UiKit.GRAY_400 if not learned else UiKit.PINK_700, 600, HORIZONTAL_ALIGNMENT_CENTER)
	name_l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY   # 任意断行: 窄格里长菜名/效果不再撑破画幅
	vb.add_child(name_l)
	var pills := HBoxContainer.new()
	pills.alignment = BoxContainer.ALIGNMENT_CENTER
	pills.add_theme_constant_override("separation", 3)
	pills.add_child(UiKit.pill(_tier_cn(String(r.tier)), UiKit.WHITE, _tier_color(String(r.tier)), 9))
	if int(r.get("min_realm", 0)) > 0:
		pills.add_child(UiKit.pill("%s习得" % String(DataManager.realm(int(r.get("min_realm", 0))).get("name", "?")), UiKit.WHITE, UiKit.GRAY_400, 9))
	vb.add_child(pills)
	var eff := UiKit.label(String(r.get("effect", "")), 11, UiKit.PINK_600, 400, HORIZONTAL_ALIGNMENT_CENTER)
	eff.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	vb.add_child(eff)

	var mats := PackedStringArray()
	for m in r.get("mats", []):
		mats.append("%s×%d" % [Game.mat_name(String(m.seed)), int(m.n)])
	var mats_l := UiKit.label("用料:%s" % "、".join(mats), 10, UiKit.PINK_500, 400, HORIZONTAL_ALIGNMENT_CENTER)
	mats_l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	vb.add_child(mats_l)

	var state := ""
	var state_c := UiKit.PINK_400
	if missing != "":
		state = "缺:%s" % missing
		state_c = UiKit.RED_400
	elif not learned:
		state = "尚未习得"
		state_c = UiKit.GRAY_400
	if state != "":
		var state_l := UiKit.label(state, 10, state_c, 500, HORIZONTAL_ALIGNMENT_CENTER)
		state_l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		vb.add_child(state_l)
	return vb


func _pick_cook(stove_idx: int, recipe_id: String) -> void:
	Game.kitchen_cook(stove_idx, recipe_id)
	_close_picker()


## 弹层骨架：全屏对话框（CanvasLayer 置顶 + 遮罩 + 居中卡片，可滚动选项 + 取消）。
## 打开即暂停时速，关闭恢复；点遮罩或「取消」关闭。columns > 1 时选项按网格排布。
func _open_picker(title: String, rows: Array, columns := 1) -> void:
	_close_picker()
	if Game.speed > 0 and Game.pending.is_empty():
		_mode_speed_prev = Game.speed
		Game.set_speed(0)

	var dlg := UiKit.dialog_layer(self, 352.0)
	_picker = dlg.layer
	UiKit.dim_click_close(dlg.dim, _close_picker)

	var cv: VBoxContainer = dlg.vb
	cv.add_child(UiKit.label(title, 17, UiKit.PINK_700, 600))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 430)
	var holder: Container
	if columns > 1:
		var grid := GridContainer.new()
		grid.columns = columns
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		holder = grid
	else:
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 6)
		holder = list
	scroll.add_child(holder)
	cv.add_child(scroll)

	for row in rows:
		holder.add_child(UiKit.tappable_row(row.content, row.cb, row.disabled))

	var cancel := _mini_button("取消", _close_picker)
	cancel.custom_minimum_size = Vector2(0, 36)
	cv.add_child(cancel)


func _close_picker() -> void:
	if _picker != null:
		_picker.queue_free()
		_picker = null
	if _mode_speed_prev > 0:
		Game.set_speed(_mode_speed_prev)
		_mode_speed_prev = 0


# ================= 小件 =================

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
	b.add_theme_color_override("font_disabled_color", UiKit.GRAY_400)
	b.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.WHITE, 8))
	b.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.PINK_100, 8))
	b.add_theme_stylebox_override("pressed", UiKit.stylebox(UiKit.PINK_500, 8))
	b.add_theme_stylebox_override("disabled", UiKit.stylebox(UiKit.GRAY_200, 8))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b


func _season_name() -> String:
	var m := (int(Game.run.age_m) % 12) + 1
	if m >= 3 and m <= 5:
		return "春"
	if m >= 6 and m <= 8:
		return "夏"
	if m >= 9 and m <= 11:
		return "秋"
	return "冬"


func _type_cn(t: String) -> String:
	var cn: String = {"food": "食材", "herb": "灵药", "flower": "奇花"}.get(t, t)
	return cn


func _type_color(t: String) -> Color:
	match t:
		"food": return UiKit.GREEN_500
		"herb": return UiKit.JADE_500
		"flower": return UiKit.PINK_400
		_: return UiKit.GRAY_400
	return UiKit.GRAY_400


func _tier_cn(t: String) -> String:
	var cn: String = {"low": "低阶", "mid": "中阶", "high": "仙膳"}.get(t, t)
	return cn


func _tier_color(t: String) -> Color:
	match t:
		"low": return UiKit.GREEN_500
		"mid": return UiKit.BLUE_500
		"high": return UiKit.GOLD_500
		_: return UiKit.GRAY_400
	return UiKit.GRAY_400
