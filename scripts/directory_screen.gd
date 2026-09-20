extends "res://scripts/screen_base.gd"
## 名录页：缘分名册 —— 头像网格（一行四个：分层纸娃娃头像/名字/身份/境界/好感），
## 点击头像弹出详情弹层（性格/口味/外观/萌点/冷却 + 专注/解契）。
## 灰盒六态好感(陌生→道侣 · 0-1000)、首遇制；未相逢者留白「传闻中的面孔」。

const Portrait := preload("res://scripts/portrait.gd")

const TAG_CN := {"zuidu": "嘴毒", "ruanruo": "软糯", "guayan": "寡言", "xinruan": "心软", "manre": "慢热", "zilaishu": "自来熟", "qinkuai": "勤快", "lansan": "懒散", "jiaozhen": "较真", "zhiqui": "直球", "kouyan": "口嫌", "xishui": "细水"}
const ID_NAME_FALLBACK := {"baimenzong": "百味宗弟子", "tongming": "仙门修士", "jianpai": "剑修", "yoududao": "散修(来历不明)", "shanshen": "山神庙祝", "huizu": "妖族商贩", "wenmai": "说书人", "fangshi": "坊市散修"}

var _content: VBoxContainer
var _rebuild_pending := false
var _detail: Node             # 详情弹层（CanvasLayer 全屏对话框）
var _open_key := ""           # 当前弹层展示的 NPC（重建后保持）


func _notification(what: int) -> void:
	# 切走页面时收起弹层（CanvasLayer 不随屏幕隐藏）
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_close_detail()


func _build(vb: VBoxContainer) -> void:
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
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
	if Game.run.is_empty() or not Game.run.has("npcs"):
		return

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiKit.label("名录 · 缘分", 24, UiKit.PINK_600, 700))
	head.add_child(UiKit.expander())
	head.add_child(UiKit.label("相识不加好感，攀谈才入册", 12, UiKit.PINK_400))
	_content.add_child(head)

	# 固定 NPC 按档案序、随机 NPC 按入册序
	var ordered: Array = []
	for n in DataManager.npcs:
		var k := String(n.key)
		if Game.run.npcs.has(k):
			ordered.append(k)
	for k in Game.run.npcs:
		if String(k).begins_with("rand_"):
			ordered.append(String(k))

	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 12)
	for k in ordered:
		grid.add_child(_npc_tile(String(k), Game.run.npcs[k]))
	_content.add_child(grid)

	var met_n := 0
	var rumor_n := 0
	for k in ordered:
		if bool(Game.run.npcs[k].get("met", false)):
			met_n += 1
		else:
			rumor_n += 1
	var stat := UiKit.label("在册 %d · 传闻 %d —— 游历与市井之间，缘分自会来敲门。" % [met_n, rumor_n], 12, UiKit.PINK_400)
	stat.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(stat)

	if _open_key != "" and Game.run.npcs.has(_open_key):
		_open_detail(_open_key)


# ================= 头像瓦片 =================

func _npc_tile(key: String, npc: Dictionary) -> Control:
	# 外层用 PanelContainer(子节点自动铺满整格),点击层才能盖住头像区;VBox 会把按钮排成 0×0
	var tile := PanelContainer.new()
	var tile_sb := UiKit.stylebox(Color.TRANSPARENT, 12)
	tile.add_theme_stylebox_override("panel", tile_sb)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if not bool(npc.get("met", false)):
		# 未入册：传闻留白（不可点）
		tile.custom_minimum_size = Vector2(0, 128)
		vb.add_child(UiKit.circle(48, UiKit.GRAY_200, UiKit.GRAY_300, "lock", 20, UiKit.GRAY_400, true))
		var lb := UiKit.label("传闻中的面孔", 11, UiKit.GRAY_400, 400, HORIZONTAL_ALIGNMENT_CENTER)
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(lb)
		tile.add_child(vb)
		return tile

	var display_name := Game.npc_name(key)

	# 主角同款玉阵头像框(按该 NPC 气质染色; 52px 头像等比缩框, 外框约 71)
	var k := 52.0 / 132.0
	var outer := 180.0 * k
	var avatar_wrap := Control.new()
	avatar_wrap.custom_minimum_size = Vector2(outer, outer)
	avatar_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	avatar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_wrap.add_child(UiKit.jade_frame(Portrait.build_for(key, 52), UiKit.aura_tint(String(Game.npc_look(key).get("aura", ""))), k))
	# 性别徽章(左上角)
	var male := Game.npc_male(key)
	var gbadge := UiKit.pill("♂" if male else "♀", UiKit.WHITE, UiKit.BLUE_500 if male else UiKit.PINK_400, 10, 600)
	gbadge.position = Vector2(2, 2)
	avatar_wrap.add_child(gbadge)
	if bool(npc.get("dao_lu", false)):
		var ring := UiKit.pill("道侣", UiKit.WHITE, UiKit.RED_400, 9, 600)
		ring.position = Vector2(outer - 34, 0)
		avatar_wrap.add_child(ring)
	vb.add_child(avatar_wrap)

	# 名字行(特别关注的 NPC 名旁带 ♥)
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 3)
	name_row.add_child(UiKit.label(display_name, 13, UiKit.PINK_700, 600, HORIZONTAL_ALIGNMENT_CENTER))
	if String(Game.run.get("focus", "")) == key:
		name_row.add_child(UiKit.icon_rect("heart_filled", 13, UiKit.RED_400))
	vb.add_child(name_row)
	var id_lb := UiKit.label(_identity_name(key, npc), 10, UiKit.PINK_400, 400, HORIZONTAL_ALIGNMENT_CENTER)
	id_lb.clip_text = true
	id_lb.custom_minimum_size = Vector2(84, 0)
	vb.add_child(id_lb)

	var pill_row := HBoxContainer.new()
	pill_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pill_row.add_child(UiKit.pill(_npc_realm(key, npc), UiKit.WHITE, _realm_color(_npc_realm_ord(key, npc)), 10, 600))
	vb.add_child(pill_row)

	var aff_row := HBoxContainer.new()
	aff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	aff_row.add_theme_constant_override("separation", 3)
	aff_row.add_child(UiKit.icon_rect("heart_filled", 11, UiKit.RED_400))
	aff_row.add_child(UiKit.label("%.0f" % float(npc.aff), 11, UiKit.PINK_600, 600))
	vb.add_child(aff_row)

	tile.add_child(vb)

	# 命中层最后添加（PanelContainer 铺满整格）+ 悬停变色
	var hit := Button.new()
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		hit.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	hit.pressed.connect(func() -> void: _open_detail(key))
	hit.mouse_entered.connect(func() -> void:
		tile.add_theme_stylebox_override("panel", UiKit.stylebox(UiKit.PINK_50, 12))
	)
	hit.mouse_exited.connect(func() -> void:
		tile.add_theme_stylebox_override("panel", tile_sb)
	)
	tile.add_child(hit)
	return tile


# ================= 关系（共用小件, 供详情弹层） =================

func _is_met(key: String) -> bool:
	return Game.run.npcs.has(key) and bool(Game.run.npcs[key].get("met", false))


## 亲疏配色: 亲近(≥35)粉红 · 交好青玉 · 交恶靛蓝(喜剧化, 不用警示色) · 素无往来灰
func _relation_color(v: float) -> Color:
	if v >= float(Game.tune("rel_close_min", 35.0)):
		return UiKit.PINK_500
	if v > 0.0:
		return UiKit.JADE_500
	if v < 0.0:
		return UiKit.BLUE_500
	return UiKit.GRAY_400


# ================= 详情弹层 =================

func _open_detail(key: String) -> void:
	_close_detail()
	_open_key = key
	var npc: Dictionary = Game.run.npcs.get(key, {})
	var pool_view := false
	if npc.is_empty():
		npc = (Game.run.get("world_npcs", {}) as Dictionary).get(key, {})
		pool_view = not npc.is_empty()   # 世界池未识者: 仅供测试·人物一览查看(无好感/操作)
	if npc.is_empty() or (not pool_view and not bool(npc.get("met", false))):
		_open_key = ""
		return

	var dlg := UiKit.dialog_layer(self, 348.0)
	_detail = dlg.layer
	UiKit.dim_click_close(dlg.dim, _close_detail)

	var cv: VBoxContainer = dlg.vb
	var arch := Game.npc_arch(key)
	var stage := int(npc.get("stage", 0))
	var stage_name := String(Game.tune("aff_stages", ["陌生", "相识", "相熟", "心动", "相恋", "道侣"])[clampi(stage, 0, 5)])

	# 头部：头像 + 名字(♥=特别关注) + 身份 + 性别/段位
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	top.add_child(Portrait.build_for(key, 52))
	var name_vb := VBoxContainer.new()
	name_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	name_vb.add_theme_constant_override("separation", 1)
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 4)
	name_row.add_child(UiKit.label(Game.npc_name(key), 17, UiKit.PINK_700, 600))
	if String(Game.run.get("focus", "")) == key:
		name_row.add_child(UiKit.icon_rect("heart_filled", 15, UiKit.RED_400))
	name_vb.add_child(name_row)
	var sub := PackedStringArray()
	if key.begins_with("rand_") and String(npc.get("alias", "")) != "":
		sub.append(String(npc.alias))
	sub.append(_identity_name(key, npc))
	name_vb.add_child(UiKit.label(" · ".join(sub), 11, UiKit.PINK_400))
	top.add_child(name_vb)
	top.add_child(UiKit.expander())
	top.add_child(UiKit.pill("♂" if Game.npc_male(key) else "♀", UiKit.WHITE, UiKit.BLUE_500 if Game.npc_male(key) else UiKit.PINK_400, 12, 600))
	top.add_child(UiKit.pill(stage_name, UiKit.WHITE, _stage_color(stage), 12, 600))
	cv.add_child(top)

	# 好感
	var aff_row := HBoxContainer.new()
	aff_row.add_theme_constant_override("separation", 8)
	aff_row.add_child(UiKit.progress(float(npc.get("aff", 0.0)) / 1000.0, _stage_color(stage)))
	var aff_lb := UiKit.label("%.0f" % float(npc.get("aff", 0.0)), 12, UiKit.PINK_600, 600)
	aff_lb.custom_minimum_size = Vector2(40, 0)
	aff_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	aff_row.add_child(aff_lb)
	cv.add_child(aff_row)
	if float(npc.get("hidden", 0.0)) > 0.0:
		cv.add_child(UiKit.label("情深许 %.0f（溢出好感化作此间牵系）" % float(npc.hidden), 11, UiKit.RED_400))

	# 详情行
	var persona: Dictionary = arch.get("persona", npc.get("persona", {}))
	var ptxt := "%s·%s·%s·%s" % [
		String(TAG_CN.get(String(persona.get("biaoda", "")), "—")),
		String(TAG_CN.get(String(persona.get("dairen", "")), "—")),
		String(TAG_CN.get(String(persona.get("xingshi", "")), "—")),
		String(TAG_CN.get(String(persona.get("dongxin", "")), "—")),
	]
	var appr: Dictionary = arch.get("appearance", npc.get("appearance", {}))
	var realm_line := "境界：%s" % _npc_realm(key, npc)
	if npc.has("cult") and int(npc.get("realm_ord", -1)) >= 0:
		var nneed: float = float(Game.tune("layer_need_base", 100.0)) * pow(float(Game.tune("layer_growth", 1.55)), float(DataManager.layer_offset(int(npc.get("realm_ord", 0))) + int(npc.get("nlayer", 0))))
		realm_line += "（修为 %d%%）" % clampi(int(float(npc.get("cult", 0.0)) / nneed * 100.0), 0, 100)
	var brk := Game.npc_break_chance(key)
	if brk >= 0.0:
		realm_line += " · 突破率 %d%%" % int(round(brk * 100.0))
	var detail := UiKit.pink_box()
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 4)
	for line in [
		"性格：%s" % ptxt,
		"口味：%s（投喜菜谱好感翻倍）" % Game.npc_taste_base(key),
		realm_line,
		"缘分：%s" % ("可谈恋爱 · 可结道侣" if Game.npc_male(key) else "红颜知己 · 止步相熟"),
		"外观：%s · %s · %s%s" % [String(appr.get("face", "—")), String(appr.get("hair", "—")), String(appr.get("aura", "—")), Game.aura_npc_hint(key)],
		"萌点：%s" % String(arch.get("moe", npc.get("moe", "—"))),
		"交谈冷却 %d 月 · 赠礼本季 %d 次 · 时光闸 %d 月" % [int(npc.get("talk_cd", 0)), int(npc.get("gift_q", 0)), int(npc.get("gate", 0))],
		String(arch.get("blurb", npc.get("blurb", ""))),
	]:
		var lb := UiKit.label(String(line), 12, UiKit.PINK_600)
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dv.add_child(lb)
	detail.add_child(UiKit.margin_wrap(dv, 10))
	cv.add_child(detail)

	cv.add_child(_relation_box(key, pool_view))

	if String(Game.run.get("focus", "")) == key:
		cv.add_child(UiKit.label("♥ 特别关注中 —— 他人好感将随岁月转淡，留意故人心思", 12, UiKit.RED_400))

	# 操作
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 6)
	var focused := String(Game.run.get("focus", "")) == key
	if not pool_view:
		acts.add_child(_mini_button("取消特别关注" if focused else "特别关注", func() -> void:
			Game.set_focus("" if focused else key)
			_open_detail(key)
		))
		if bool(npc.get("dao_lu", false)):
			acts.add_child(_mini_button("解契", func() -> void:
				Game.dao_cancel(key)
				_open_detail(key)
			))
	acts.add_child(UiKit.expander())
	acts.add_child(_mini_button("关闭", _close_detail))
	cv.add_child(acts)


func _close_detail() -> void:
	_open_key = ""
	if _detail != null:
		_detail.queue_free()
		_detail = null


# ================= 关系（详情弹层） =================

## NPC 详情里的「关系」区: Ta 与在册众人的关系 —— 对方头像 + 姓名 + 亲密度, 点击格子弹出该人详情。无关系则返回隐藏控件。
## show_all(人物一览的池内视图)= 不过滤已识: 列出其全部关系(含其他未识者, 灰显+「未识」标); 常规名录仍只列已识者。
func _relation_box(key: String, show_all := false) -> Control:
	var items: Array = []
	for r in Game.npc_relations(key):
		var peer := String(r.get("peer", ""))
		if not show_all and not _is_met(peer):
			continue
		items.append(r)
	if items.is_empty():
		var none := Control.new()
		none.visible = false
		return none

	var box := UiKit.pink_box()
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.add_child(UiKit.label("关系", 12, UiKit.PINK_700, 600))
	head.add_child(UiKit.expander())
	head.add_child(UiKit.label("%d 段" % items.size(), 11, UiKit.PINK_400))
	bv.add_child(head)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 8)
	for r in items:
		var peer := String(r.get("peer", ""))
		var v := float(r.get("val", 0.0))
		var peer_met := _is_met(peer)
		var cell := PanelContainer.new()
		cell.add_theme_stylebox_override("panel", UiKit.stylebox(Color(0, 0, 0, 0), 8))
		var item := VBoxContainer.new()
		item.add_theme_constant_override("separation", 2)
		var av := CenterContainer.new()
		av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var portrait := Portrait.build_for(peer, 40)
		if not peer_met:
			portrait.modulate = Color(1, 1, 1, 0.45)   # 未识者: 灰显
		av.add_child(portrait)
		item.add_child(av)
		var nl := UiKit.label(Game.npc_name(peer) + ("" if peer_met else "·未识"), 10, UiKit.PINK_600 if peer_met else UiKit.GRAY_400, 500, HORIZONTAL_ALIGNMENT_CENTER)
		nl.custom_minimum_size = Vector2(44, 0)
		nl.clip_text = true
		item.add_child(nl)
		item.add_child(UiKit.label("%+d" % int(v), 11, _relation_color(v), 600, HORIZONTAL_ALIGNMENT_CENTER))
		cell.add_child(item)
		# 命中层(铺满格): 点击跳转到该人详情弹层
		var hit := Button.new()
		hit.focus_mode = Control.FOCUS_NONE
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			hit.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		hit.pressed.connect(_open_detail.bind(peer))
		cell.add_child(hit)
		flow.add_child(cell)
	bv.add_child(flow)
	box.add_child(UiKit.margin_wrap(bv, 10))
	return box


# ================= 小件 =================

func _identity_name(key: String, npc: Dictionary) -> String:
	var arch := Game.npc_arch(key)
	var idv: Variant = arch.get("identity", npc.get("identity", ""))
	if idv == null or String(idv) == "":
		return "路人"
	var id_name := String(arch.get("id_name", npc.get("id_name", "")))
	if id_name != "":
		return id_name
	return String(ID_NAME_FALLBACK.get(String(idv), "路人"))


## 境界显示: 固定 NPC 用档案标签(渡劫后期/金丹/话本成精…), 随机 NPC 按 ordinal 反查 realms.json
func _npc_realm(key: String, npc: Dictionary) -> String:
	if Game._npc_is_minor(key):
		return "幼年"
	# 破境后的 run 侧标签优先(随修炼推进), 否则用 GDD 档案标签
	var npc_lbl := String(npc.get("realm", ""))
	if npc_lbl != "":
		return npc_lbl
	var arch := Game.npc_arch(key)
	var lbl := String(arch.get("realm", ""))
	if lbl != "":
		return lbl
	var ord := _npc_realm_ord(key, npc)
	if ord < 0:
		return "凡人"
	return String(DataManager.realm(ord).get("name", "?"))


func _npc_realm_ord(key: String, npc: Dictionary) -> int:
	# run 侧 realm_ord 随突破推进, 优先于档案初值
	var npc_ord: Variant = npc.get("realm_ord", null)
	if npc_ord != null:
		return int(npc_ord)
	var arch := Game.npc_arch(key)
	var v: Variant = arch.get("realm_ord", -1)
	return int(v)


func _realm_color(ord: int) -> Color:
	match clampi(ord, -1, 7):
		-1: return UiKit.GRAY_400
		0: return UiKit.GRAY_400
		1: return UiKit.BLUE_500
		2: return UiKit.GOLD_500
		3: return UiKit.GREEN_500
		4: return UiKit.JADE_500
		5: return UiKit.PINK_400
		6: return UiKit.ORANGE_500
		7: return UiKit.RED_400
	return UiKit.GRAY_400


func _stage_color(stage: int) -> Color:
	match clampi(stage, 0, 5):
		0: return UiKit.GRAY_400
		1: return UiKit.BLUE_500
		2: return UiKit.GREEN_500
		3: return UiKit.GOLD_500
		4: return UiKit.PINK_400
		_: return UiKit.RED_400
	return UiKit.GRAY_400


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
