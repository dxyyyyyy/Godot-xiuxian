extends "res://scripts/apps/app_base.gd"
## 图鉴：灵植／菜谱两栏浏览（发现制：未发现为剪影「？」）。
## 灵植 24 种（seeds.json）· 菜谱 40 道（recipes.json，含暗谱）；发现集存 GameState。

var kind_group := ButtonGroup.new()
var _mode := "recipes"
var _grid: GridContainer
var _detail: CanvasLayer = null          # 菜谱详情弹窗层（同仓库弹窗，打开时暂停时间）
var _detail_speed_prev := 0


func _build_content(vb: VBoxContainer) -> void:
	vb.add_child(bleed_head("图鉴", "灵植与菜谱，发现制。"))

	var section := bleed_section()
	var sv := VBoxContainer.new()
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_theme_constant_override("separation", 12)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var rb := UiKit.seg_button("菜谱", kind_group, _mode == "recipes")
	rb.pressed.connect(_set_mode.bind("recipes"))
	row.add_child(rb)
	var ib := UiKit.seg_button("灵植", kind_group, _mode == "items")
	ib.pressed.connect(_set_mode.bind("items"))
	row.add_child(ib)
	sv.add_child(row)

	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	sv.add_child(_grid)
	section.add_child(UiKit.margin_wrap(sv, 12))
	vb.add_child(section)
	Game.changed.connect(_schedule_rebuild)
	_rebuild()


var _rebuild_pending := false

func _schedule_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	_rebuild.call_deferred()


func _set_mode(mode: String) -> void:
	if _mode == mode:
		return
	_mode = mode
	_rebuild()


func _rebuild() -> void:
	_rebuild_pending = false
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	if _mode == "recipes":
		for r in DataManager.recipes:
			var found: bool = GameState.discovered_recipes.has(String(r.id)) or int(Game.run.get("realm", 0)) >= int(r.get("min_realm", 0))
			_grid.add_child(_recipe_tile(r, found))
	else:
		for s in DataManager.seeds:
			_grid.add_child(_item_tile(s, GameState.discovered_items.has(String(s.id))))


## 图鉴瓦片: 固定 98×146 格心(紧凑, 一行四个), 名称≤2行/效果≤2行(超出省略号)。
const TILE_W := 98.0
const TILE_H := 146.0
const TILE_IMG := 56.0


func _tile_shell() -> VBoxContainer:
	var tile := VBoxContainer.new()
	tile.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_theme_constant_override("separation", 2)
	tile.custom_minimum_size = Vector2(TILE_W, TILE_H)
	return tile


## 行数受限标签: 不用 max_lines_visible(autowrap 下会把最小高塌成 1px), 改显式最小高 + clip 裁切。
func _clip_label(text: String, px: int, color: Color, weight: int, lines: int) -> Label:
	var lb := UiKit.label(text, px, color, weight, HORIZONTAL_ALIGNMENT_CENTER)
	lb.custom_minimum_size = Vector2(TILE_W - 8, float(lines * (px + 5)))
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lb.clip_text = true
	lb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return lb


func _recipe_tile(r: Dictionary, found: bool) -> Control:
	var tile := _tile_shell()
	if found:
		var img := UiKit.sprite("res://assets/sprites/recipes/%s.svg" % String(r.id), int(TILE_IMG))
		if img:
			tile.add_child(img)
		tile.add_child(_clip_label(String(r.name), 12, UiKit.PINK_700, 600, 2))
		var tier := String(r.tier)
		var tier_cn: String = {"low": "低阶", "mid": "中阶", "high": "仙膳", "dark": "暗谱"}.get(tier, tier)
		tile.add_child(UiKit.pill(String(tier_cn), UiKit.WHITE, _tier_color(tier), 10))
		tile.add_child(_clip_label(String(r.get("effect", "")), 11, UiKit.PINK_400, 400, 2))
		return _tappable(tile, _open_recipe_detail.bind(r))
	else:
		tile.add_child(_silhouette("res://assets/sprites/recipes/%s.svg" % String(r.id)))
		tile.add_child(_clip_label("？？？", 12, UiKit.GRAY_400, 600, 1))
		return _tappable(tile, _open_locked_recipe.bind(r))
	return tile


## 可点瓦片壳: 瓦片内容 + 全幅透明点击层（悬停微透提示可点，点开详情弹窗）。
func _tappable(content: Control, cb: Callable) -> Control:
	var shell := Control.new()
	shell.custom_minimum_size = Vector2(TILE_W, TILE_H)
	UiKit.tree_mouse_ignore(content)
	shell.add_child(content)
	var hit := Button.new()
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		hit.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	hit.mouse_entered.connect(func() -> void: content.modulate = Color(1, 1, 1, 0.7))
	hit.mouse_exited.connect(func() -> void: content.modulate = Color.WHITE)
	hit.pressed.connect(cb)
	shell.add_child(hit)
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return shell


func _item_tile(s: Dictionary, found: bool) -> Control:
	var tile := _tile_shell()
	if found:
		var img := UiKit.sprite("res://assets/sprites/seeds/%s.svg" % String(s.id), int(TILE_IMG))
		if img:
			tile.add_child(img)
		tile.add_child(_clip_label(String(s.name), 12, UiKit.PINK_700, 600, 2))
		var type_cn: String = {"food": "食材", "herb": "灵药", "flower": "奇花"}.get(String(s.type), String(s.type))
		tile.add_child(UiKit.pill("%s · %s品" % [String(type_cn), String(s.grade)], UiKit.WHITE, _type_color(String(s.type)), 10))
		tile.add_child(_clip_label(String(s.get("note", "")), 11, UiKit.PINK_400, 400, 2))
		return _tappable(tile, _open_item_detail.bind(s))
	else:
		tile.add_child(_silhouette("res://assets/sprites/seeds/%s.svg" % String(s.id)))
		tile.add_child(_clip_label("？？？", 12, UiKit.GRAY_400, 600, 1))
		return _tappable(tile, _open_locked_item.bind(s))
	return tile


func _tier_color(tier: String) -> Color:
	match tier:
		"low": return UiKit.GREEN_500
		"mid": return UiKit.BLUE_500
		"high": return UiKit.GOLD_500
		"dark": return UiKit.INK
		_: return UiKit.GRAY_400
	return UiKit.GRAY_400


func _type_color(type: String) -> Color:
	match type:
		"food": return UiKit.GREEN_500
		"herb": return UiKit.JADE_500
		"flower": return UiKit.PINK_400
		_: return UiKit.GRAY_400
	return UiKit.GRAY_400


## 未发现剪影：有图谱则显示暗色剪影, 缺图回退灰底「？」占位。
func _silhouette(sprite_path := "") -> Control:
	var img := UiKit.sprite(sprite_path, 72)
	if img:
		img.modulate = Color(0.2, 0.18, 0.24, 0.9)
		return img
	var sq := UiKit.gradient_panel(UiKit.GRAY_200, UiKit.GRAY_300, 12, false)
	sq.custom_minimum_size = Vector2(TILE_IMG, TILE_IMG)
	sq.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var tc := CenterContainer.new()
	tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tc.add_child(UiKit.label("？", 20, UiKit.GRAY_400, 700))
	sq.add_child(tc)
	return sq


## ---- 菜谱详情弹窗（点击已解锁瓦片）：图谱 + 阶品/口味 + 效果/获取/札记 + 所需灵植属性 ----

func _open_recipe_detail(r: Dictionary) -> void:
	_close_detail()
	if Game.speed > 0:
		_detail_speed_prev = Game.speed
		Game.set_speed(0)
	var dlg := UiKit.dialog_layer(self, 300.0)
	_detail = dlg.layer
	UiKit.dim_click_close(dlg.dim, _close_detail)
	var cv: VBoxContainer = dlg.vb

	# 头部: 图谱 + 名称 + 阶品与口味标签
	var tier := String(r.tier)
	var tier_cn: String = {"low": "低阶", "mid": "中阶", "high": "仙膳", "dark": "暗谱"}.get(tier, tier)
	var img: Control = UiKit.sprite("res://assets/sprites/recipes/%s.svg" % String(r.id), 72)
	if img == null:
		img = UiKit.circle(72, UiKit.PINK_100, UiKit.PINK_200, "package", 26, UiKit.PINK_400)
	cv.add_child(img)
	cv.add_child(UiKit.label(String(r.name), 18, UiKit.PINK_700, 600, HORIZONTAL_ALIGNMENT_CENTER))
	var pills := HBoxContainer.new()
	pills.alignment = BoxContainer.ALIGNMENT_CENTER
	pills.add_theme_constant_override("separation", 6)
	pills.add_child(UiKit.pill(tier_cn, UiKit.WHITE, _tier_color(tier), 11, 600))
	for t in r.get("tags", []):
		pills.add_child(UiKit.pill(String(t), UiKit.PINK_600, UiKit.PINK_100, 11))
	cv.add_child(pills)

	# 属性区: 效果 / 获取 / 札记
	cv.add_child(UiKit.vspace(2))
	cv.add_child(_detail_line("效果", String(r.get("effect", "无"))))
	var acquire := String(r.get("acquire", ""))
	if acquire != "":
		cv.add_child(_detail_line("获取", acquire))
	var note := String(r.get("note", ""))
	if note != "":
		cv.add_child(_detail_line("札记", note))

	# 所需灵植: 名称×数量 + 灵植自身属性(类属 · 品阶 · 亲和 · 坊市价)
	cv.add_child(UiKit.vspace(2))
	cv.add_child(UiKit.label("所需灵植", 13, UiKit.PINK_600, 600))
	for m in r.get("mats", []):
		cv.add_child(_mat_row(String(m.seed), int(m.n)))

	cv.add_child(UiKit.vspace(4))
	cv.add_child(_mini_button("关闭"))


func _close_detail() -> void:
	if _detail != null:
		_detail.queue_free()
		_detail = null
	if _detail_speed_prev > 0:
		Game.set_speed(_detail_speed_prev)
		_detail_speed_prev = 0


## 未解锁菜谱: 只给剪影 + 获得方式提示, 不剧透名称/材料/效果。
func _open_locked_recipe(r: Dictionary) -> void:
	_close_detail()
	if Game.speed > 0:
		_detail_speed_prev = Game.speed
		Game.set_speed(0)
	var dlg := UiKit.dialog_layer(self, 300.0)
	_detail = dlg.layer
	UiKit.dim_click_close(dlg.dim, _close_detail)
	var cv: VBoxContainer = dlg.vb

	var img: Control = UiKit.sprite("res://assets/sprites/recipes/%s.svg" % String(r.id), 72)
	if img == null:
		img = UiKit.circle(72, UiKit.GRAY_200, UiKit.GRAY_300, "package", 26, UiKit.GRAY_400)
	else:
		img.modulate = Color(0.2, 0.18, 0.24, 0.9)
	cv.add_child(img)
	cv.add_child(UiKit.label("？？？", 18, UiKit.GRAY_400, 600, HORIZONTAL_ALIGNMENT_CENTER))
	var pills := HBoxContainer.new()
	pills.alignment = BoxContainer.ALIGNMENT_CENTER
	pills.add_child(UiKit.pill("未解锁", UiKit.WHITE, UiKit.GRAY_400, 11, 600))
	cv.add_child(pills)

	cv.add_child(UiKit.vspace(2))
	cv.add_child(UiKit.label("获得方式", 13, UiKit.PINK_600, 600))
	var min_realm := int(r.get("min_realm", 0))
	if min_realm >= 0:
		cv.add_child(UiKit.label("· 境界升至%s后自动入册" % _realm_label(min_realm), 12, UiKit.INK))
	var acquire := String(r.get("acquire", ""))
	if acquire != "":
		cv.add_child(UiKit.label("· " + acquire, 12, UiKit.INK))

	cv.add_child(UiKit.vspace(4))
	cv.add_child(_mini_button("关闭"))


## 未解锁灵植: 只给剪影 + 获得方式提示, 不剧透名称/属性。
func _open_locked_item(s: Dictionary) -> void:
	_close_detail()
	if Game.speed > 0:
		_detail_speed_prev = Game.speed
		Game.set_speed(0)
	var dlg := UiKit.dialog_layer(self, 300.0)
	_detail = dlg.layer
	UiKit.dim_click_close(dlg.dim, _close_detail)
	var cv: VBoxContainer = dlg.vb

	var img: Control = UiKit.sprite("res://assets/sprites/seeds/%s.svg" % String(s.id), 72)
	if img == null:
		img = UiKit.circle(72, UiKit.GRAY_200, UiKit.GRAY_300, "package", 26, UiKit.GRAY_400)
	else:
		img.modulate = Color(0.2, 0.18, 0.24, 0.9)
	cv.add_child(img)
	cv.add_child(UiKit.label("？？？", 18, UiKit.GRAY_400, 600, HORIZONTAL_ALIGNMENT_CENTER))
	var pills := HBoxContainer.new()
	pills.alignment = BoxContainer.ALIGNMENT_CENTER
	pills.add_child(UiKit.pill("未解锁", UiKit.WHITE, UiKit.GRAY_400, 11, 600))
	cv.add_child(pills)

	cv.add_child(UiKit.vspace(2))
	cv.add_child(UiKit.label("获得方式", 13, UiKit.PINK_600, 600))
	for line in _seed_acquire(s):
		cv.add_child(UiKit.label("· " + String(line), 12, UiKit.INK))

	cv.add_child(UiKit.vspace(4))
	cv.add_child(_mini_button("关闭"))


## 属性行: 左侧字段名固定宽 + 右侧说明文字自动换行。
func _detail_line(k: String, v: String, kw := 36) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var kl := UiKit.label(k, 12, UiKit.PINK_400, 600)
	kl.custom_minimum_size = Vector2(kw, 0)
	hb.add_child(kl)
	var vl := UiKit.label(v, 12, UiKit.INK)
	vl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vl)
	return hb


## 所需灵植行: 图谱 + 「名称 ×数量」+ 属性小字；占位料(any/winter_any/flower_any/millennium)无灵植数据, 只显名。
func _mat_row(seed_id: String, n: int) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var s: Dictionary = DataManager.seed(seed_id)
	var icon: Control = UiKit.sprite("res://assets/sprites/seeds/%s.svg" % seed_id, 28)
	if icon == null:
		icon = UiKit.circle(28, UiKit.PINK_100, UiKit.PINK_200, "package", 13, UiKit.PINK_400)
	hb.add_child(icon)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 0)
	vb.add_child(UiKit.label("%s ×%d" % [Game.mat_name(seed_id), n], 13, UiKit.PINK_700, 600))
	if not s.is_empty():
		var type_cn: String = {"food": "食材", "herb": "灵药", "flower": "奇花"}.get(String(s.type), String(s.type))
		vb.add_child(UiKit.label("%s · %s品 · %s亲和 · 坊市 %d 灵石/株" % [type_cn, String(s.grade), String(s.affinity), int(s.price)], 11, UiKit.PINK_400))
	hb.add_child(vb)
	return hb


## 弹窗底部小按钮（同仓库弹窗风格）。
func _mini_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
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
	b.pressed.connect(_close_detail)
	return b


## ---- 灵植详情弹窗（点击已解锁灵植瓦片）：属性 + 特性 + 获取渠道 ----

func _open_item_detail(s: Dictionary) -> void:
	_close_detail()
	if Game.speed > 0:
		_detail_speed_prev = Game.speed
		Game.set_speed(0)
	var dlg := UiKit.dialog_layer(self, 300.0)
	_detail = dlg.layer
	UiKit.dim_click_close(dlg.dim, _close_detail)
	var cv: VBoxContainer = dlg.vb

	# 头部: 图谱 + 名称 + 类属/品阶
	var type_cn: String = {"food": "食材", "herb": "灵药", "flower": "奇花"}.get(String(s.type), String(s.type))
	var img: Control = UiKit.sprite("res://assets/sprites/seeds/%s.svg" % String(s.id), 72)
	if img == null:
		img = UiKit.circle(72, UiKit.PINK_100, UiKit.PINK_200, "package", 26, UiKit.PINK_400)
	cv.add_child(img)
	cv.add_child(UiKit.label(String(s.name), 18, UiKit.PINK_700, 600, HORIZONTAL_ALIGNMENT_CENTER))
	var pills := HBoxContainer.new()
	pills.alignment = BoxContainer.ALIGNMENT_CENTER
	pills.add_theme_constant_override("separation", 6)
	pills.add_child(UiKit.pill("%s · %s品" % [type_cn, String(s.grade)], UiKit.WHITE, _type_color(String(s.type)), 11, 600))
	var seasons: Array = s.get("seasons", [])
	pills.add_child(UiKit.pill("四季" if seasons.is_empty() else " · ".join(seasons), UiKit.PINK_600, UiKit.PINK_100, 11))
	cv.add_child(pills)

	# 属性区: 生长期 / 亲和 / 收获 / 坊市价
	cv.add_child(UiKit.vspace(2))
	cv.add_child(_detail_line("生长期", "%d 月" % int(s.get("months", 0)), 44))
	cv.add_child(_detail_line("五行", String(s.get("affinity", "无")) + "亲和", 44))
	cv.add_child(_detail_line("收获", "每次 %d 株" % int(s.get("yield", 0)), 44))
	cv.add_child(_detail_line("坊市价", "%d 灵石/株" % int(s.get("price", 0)), 44))
	var note := String(s.get("note", ""))
	if note != "":
		cv.add_child(_detail_line("特性", note, 44))

	# 获取渠道
	cv.add_child(UiKit.vspace(2))
	cv.add_child(UiKit.label("获取渠道", 13, UiKit.PINK_600, 600))
	for line in _seed_acquire(s):
		cv.add_child(UiKit.label("· " + String(line), 12, UiKit.INK))

	cv.add_child(UiKit.vspace(4))
	cv.add_child(_mini_button("关闭"))


## 灵植获取渠道: 游历采获(所在地图风物池) / 坊市购种(仅上品) / NPC 赠礼 / 初始家底。
func _seed_acquire(s: Dictionary) -> Array:
	var sid := String(s.id)
	var lines: Array = []
	var maps: Array = []
	for k in Game.TRAVEL_MAPS:
		var info: Dictionary = Game.TRAVEL_MAPS[k]
		if info.get("flora", []).has(sid):
			var idx := Game.map_unlock_realm(String(k))
			maps.append("%s(%s)" % [String(info.name), "开局可采" if idx == 0 else "%s期起" % _realm_label(idx)])
	if not maps.is_empty():
		lines.append("寻道采获: %s" % "、".join(maps))
	if String(s.grade) == "上":
		lines.append("坊市购种: 稀有种子 %d 灵石(首株高价购入, 之后收获自留)" % Game.seed_buy_cost(s))
	lines.append("NPC 赠礼: 好感深厚者偶赠花木")
	if sid == "chunjiu":
		lines.append("初始家底: 入世自带 ×10")
	return lines


## 境界序号 → 境界名(realms.json: 0=炼气 1=筑基 2=金丹…)。
func _realm_label(ord: int) -> String:
	if ord >= 0 and ord < DataManager.realms.size():
		return String(DataManager.realms[ord].get("name", "境界%d" % ord))
	return "境界%d" % ord
