extends "res://scripts/screen_base.gd"
## 名录页：缘分名册 —— 按派系(identity)折叠分组，每组一行四个：
## 分层纸娃娃头像/名字/身份/境界/好感，点标题行收起/展开；
## 点击头像弹出详情弹层（性格/口味/外观/萌点/冷却 + 专注/解契）。
## 灰盒六态好感(陌生→道侣 · 0-1000)、首遇制；未相逢者留白「传闻中的面孔」。

const Portrait := preload("res://scripts/portrait.gd")

const TAG_CN := {"zuidu": "嘴毒", "ruanruo": "软糯", "guayan": "寡言", "xinruan": "心软", "manre": "慢热", "zilaishu": "自来熟", "qinkuai": "勤快", "lansan": "懒散", "jiaozhen": "较真", "zhiqui": "直球", "kouyan": "口嫌", "xishui": "细水"}
const ID_NAME_FALLBACK := {"baimenzong": "百味宗弟子", "tongming": "仙门修士", "jianpai": "剑修", "yoududao": "散修(来历不明)", "shanshen": "山神庙祝", "huizu": "妖族商贩", "wenmai": "说书人", "fangshi": "坊市散修"}

var _content: VBoxContainer
var _rebuild_pending := false
var _detail: Node             # 详情弹层（CanvasLayer 全屏对话框）
var _detail_chron: Button     # 详情弹层里的「纪事」按钮（纪事子层开着时置蓝）
var _follow_warn := ""        # 关注名单满员提示（渲染一次即清）
var _npc_chron: Node          # 纪事子弹层（从详情打开, 叠在详情之上）
var _open_key := ""           # 当前弹层展示的 NPC（重建后保持）
var _folded := {}             # 派系折叠状态（跨重建保持）: identity -> bool


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

	# 按派系(identity)分组: 组序随首现次序, 组内保持上面的入册次序
	var groups: Dictionary = {}
	var gorder: Array = []
	for k in ordered:
		var fac := String(Game._npc_faction(String(k)))
		if not groups.has(fac):
			groups[fac] = []
			gorder.append(fac)
		groups[fac].append(String(k))

	for fac in gorder:
		var keys: Array = groups[fac]
		var grid := GridContainer.new()
		grid.columns = 4
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 12)
		var met_in := 0
		for k in keys:
			if bool(Game.run.npcs[String(k)].get("met", false)):
				met_in += 1
			grid.add_child(_npc_tile(String(k), Game.run.npcs[String(k)]))
		var rumor_in: int = keys.size() - met_in
		var badge := "%d 人" % keys.size() if rumor_in == 0 else "相识 %d · 传闻 %d" % [met_in, rumor_in]
		_content.add_child(_fold_section(_faction_title(String(fac)), String(fac), grid, badge))

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


# ================= 派系折叠区块 =================

## 派系展示名: 沿用身份中文表(散修(来历不明)等), 无表可查的旧档/新派系露出原键, 空身份归「无门无派」。
func _faction_title(fac: String) -> String:
	if fac == "":
		return "无门无派"
	return String(ID_NAME_FALLBACK.get(fac, fac))


## 可折叠派系区块: 标题行整行可点收起/展开(状态记在 _folded, 跨重建保持)。
func _fold_section(title: String, key: String, body: Control, badge := "") -> PanelContainer:
	var c := UiKit.card()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	var folded: bool = bool(_folded.get(key, false))
	body.visible = not folded

	var header := Button.new()
	header.focus_mode = Control.FOCUS_NONE
	header.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	header.custom_minimum_size = Vector2(0, 28)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		header.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(UiKit.label(title, 15, UiKit.PINK_700, 700))
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
		var now: bool = not bool(_folded.get(key, false))
		_folded[key] = now
		body.visible = not now
		chevron.flip_v = not now
	)
	cv.add_child(header)
	cv.add_child(body)
	c.add_child(UiKit.margin_wrap(cv, 10))
	return c


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

	# 名字行(「喜欢」的 NPC 名旁带 ♥, 仅关注的带 👁)
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 3)
	name_row.add_child(UiKit.label(display_name, 13, UiKit.PINK_700, 600, HORIZONTAL_ALIGNMENT_CENTER))
	if String(Game.run.get("focus", "")) == key:
		name_row.add_child(UiKit.icon_rect("heart_filled", 13, UiKit.RED_400))
	elif Game.is_followed(key):
		name_row.add_child(UiKit.icon_rect("eye", 13, UiKit.PINK_500))
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
	aff_row.add_child(UiKit.label("友%.0f" % float(npc.aff), 10, _friend_color(float(npc.aff)), 600))
	if float(npc.get("love", 0.0)) > 0.0:   # 情值 0 不显示 —— 同性 NPC 恒 0 恒隐
		aff_row.add_child(UiKit.label("情%.0f" % float(npc.love), 10, _love_color(float(npc.love)), 600))
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


## 双值配色(拍板): 友情值绿 · 感情值粉 · 负值一律红
func _friend_color(v: float) -> Color:
	return UiKit.RED_400 if v < 0.0 else UiKit.GREEN_500


func _love_color(v: float) -> Color:
	return UiKit.RED_400 if v < 0.0 else UiKit.PINK_500


# ================= 详情弹层 =================

func _open_detail(key: String) -> void:
	_close_detail()
	_open_key = key
	var npc: Dictionary = Game.run.npcs.get(key, {})
	var pool_view := false
	if npc.is_empty():
		npc = (Game.run.get("world_npcs", {}) as Dictionary).get(key, {})
		pool_view = not npc.is_empty()   # 世界池未识者: 仅供测试·人物一览查看(无好感/操作)
	if npc.is_empty() and not Game.npc_arch(key).is_empty():
		npc = {"met": false, "aff": 0.0, "love": 0.0, "hidden": 0.0, "stage": 0, "gate": 0, "talk_cd": 0, "gift_q": 0}   # 固定 NPC 未首遇(仅季忘川开局在册): 临时只读骨架, 不回写 run.npcs
	if npc.is_empty():
		_open_key = ""
		return
	if not bool(npc.get("met", false)):
		pool_view = true   # 未入册(关系区灰显格/人物一览未相逢固定 NPC): 只读基础档案, 不给操作

	var dlg := UiKit.dialog_layer(self, 348.0)
	_detail = dlg.layer
	UiKit.dim_click_close(dlg.dim, _close_detail)

	var cv: VBoxContainer = dlg.vb
	var arch := Game.npc_arch(key)
	var stage := int(npc.get("stage", 0))
	var stage_name := String(Game.tune("aff_stages", ["陌生", "相识", "相熟", "心动", "相恋", "道侣"])[clampi(stage, 0, 5)])

	# 头部：头像 + 名字(♥=喜欢 👁=关注) + 身份 + 性别/段位
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
	elif Game.is_followed(key):
		name_row.add_child(UiKit.icon_rect("eye", 15, UiKit.PINK_500))
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

	# 好感双轨: 友情条(aff · 人人有) + 情条(love · 仅异性可涨, 为 0 整行不显)
	var aff_row := HBoxContainer.new()
	aff_row.add_theme_constant_override("separation", 8)
	aff_row.add_child(UiKit.label("友", 12, _friend_color(float(npc.get("aff", 0.0))), 600))
	aff_row.add_child(UiKit.progress(float(npc.get("aff", 0.0)) / 1000.0, _stage_color(stage)))
	var aff_lb := UiKit.label("%.0f" % float(npc.get("aff", 0.0)), 12, _friend_color(float(npc.get("aff", 0.0))), 600)
	aff_lb.custom_minimum_size = Vector2(40, 0)
	aff_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	aff_row.add_child(aff_lb)
	cv.add_child(aff_row)
	if float(npc.get("love", 0.0)) > 0.0:
		var love_row := HBoxContainer.new()
		love_row.add_theme_constant_override("separation", 8)
		love_row.add_child(UiKit.label("情", 12, _love_color(float(npc.love)), 600))
		love_row.add_child(UiKit.progress(float(npc.love) / 1000.0, UiKit.PINK_400))
		var love_lb := UiKit.label("%.0f" % float(npc.love), 12, _love_color(float(npc.love)), 600)
		love_lb.custom_minimum_size = Vector2(40, 0)
		love_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		love_row.add_child(love_lb)
		cv.add_child(love_row)
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

	cv.add_child(_relation_box(key))

	if String(Game.run.get("focus", "")) == key:
		cv.add_child(UiKit.label("♥ 喜欢中 —— 他人好感将随岁月转淡，留意故人心思", 12, UiKit.RED_400))
	elif Game.is_followed(key):
		cv.add_child(UiKit.label("👁 已关注 —— Ta 的事会记上日程页「一世纪事」", 12, UiKit.PINK_500))

	# 操作栏(喜欢/关注/解契仅入册者 · 纪事人人可看 —— 世间事不因未见而不发生)
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 6)
	var focused := String(Game.run.get("focus", "")) == key
	var followed := Game.is_followed(key)
	_detail_chron = _mini_button("纪事", func() -> void: _open_npc_chron(key))
	acts.add_child(_detail_chron)
	if not pool_view:
		acts.add_child(_mini_button("取消喜欢" if focused else "喜欢", func() -> void:
			Game.set_focus("" if focused else key)
			_open_detail(key)
		))
		acts.add_child(_mini_button("取消关注" if followed else "关注", func() -> void:
			if followed:
				Game.set_follow(key, false)
			elif not Game.set_follow(key, true):
				_follow_warn = "关注已满(%d/%d) —— 先取消一位再关注" % [Game.follows().size(), Game.FOLLOW_MAX]
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
	if _follow_warn != "":
		cv.add_child(UiKit.label(_follow_warn, 12, UiKit.RED_400))
		_follow_warn = ""   # 只提示一次


func _close_detail() -> void:
	_open_key = ""
	_close_npc_chron()
	if _detail != null:
		_detail.queue_free()
		_detail = null
	_detail_chron = null


## 关纪子弹层并还原「纪事」按钮样式(按钮本体随详情弹层管, 这里不清引用)。
func _close_npc_chron() -> void:
	if _npc_chron != null:
		_npc_chron.queue_free()
		_npc_chron = null
	if _detail_chron != null:
		_detail_chron.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.PINK_50, 8))
		_detail_chron.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.PINK_100, 8))


## 纪事子弹层: 此人相关的纪事(最新在前), 数据走 Game.chronicle_of —— 认日志里的【名字】,
## 月末汇总行已拆条只剩提及 Ta 的条目。列表限高约八成屏, 超长滚动。
func _open_npc_chron(key: String) -> void:
	_close_npc_chron()
	var entries: Array = Game.chronicle_of(key)
	var dlg := UiKit.dialog_layer(self, 348.0)
	_npc_chron = dlg.layer
	UiKit.dim_click_close(dlg.dim, _close_npc_chron)
	if _detail_chron != null:   # 详情里的「纪事」按钮置选中态, 关闭时还原
		_detail_chron.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.PINK_100, 8))
		_detail_chron.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.PINK_100, 8))

	var cv: VBoxContainer = dlg.vb
	# 头部: 头像 + 「纪事 · 名字」 + 条数
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	top.add_child(Portrait.build_for(key, 40))
	var name_vb := VBoxContainer.new()
	name_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	name_vb.add_theme_constant_override("separation", 1)
	name_vb.add_child(UiKit.label("纪事 · %s" % Game.npc_name(key), 15, UiKit.PINK_700, 600))
	name_vb.add_child(UiKit.label("Ta 在岁月里留下的痕迹", 10, UiKit.PINK_400))
	top.add_child(name_vb)
	top.add_child(UiKit.expander())
	top.add_child(UiKit.pill("%d 条" % entries.size(), UiKit.WHITE, UiKit.PINK_500, 11, 600))
	cv.add_child(top)

	if entries.is_empty():
		var empty := UiKit.label("还没有关于 Ta 的纪事 —— 故事正在路上。", 12, UiKit.PINK_400)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(empty)
	else:
		# 估算正文高: 超出屏高约六成则限高滚动(行高按字号粗估, 348 宽下每行约 18 字)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sv := VBoxContainer.new()
		sv.custom_minimum_size = Vector2(316, 0)   # 滚动内容须显式横向展开, 否则只拿到子节点最小宽
		sv.add_theme_constant_override("separation", 10)
		var est := 0.0
		for e in entries:
			var lb := UiKit.label(String((e as Dictionary).get("text", "")), 12, UiKit.PINK_700)
			lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var row := VBoxContainer.new()
			row.add_theme_constant_override("separation", 2)
			row.add_child(UiKit.label(String((e as Dictionary).get("day", "")), 10, UiKit.PINK_400, 500))
			row.add_child(lb)
			sv.add_child(row)
			est += 20.0 + ceilf(float(String((e as Dictionary).get("text", "")).length()) / 18.0) * 18.0
		scroll.add_child(sv)
		var cap := float(get_viewport_rect().size.y) * 0.55
		if est > cap:
			scroll.custom_minimum_size = Vector2(0, cap)
		cv.add_child(scroll)

	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 6)
	acts.add_child(UiKit.expander())
	acts.add_child(_mini_button("关闭", _close_npc_chron))
	cv.add_child(acts)


# ================= 关系（详情弹层） =================

## NPC 详情里的「关系」区: Ta 的全部关系边 —— 对方头像 + 姓名 + 友情值(边亲疏) + 关系名称(+恋爱对加情值), 点击格子弹出该人详情。无关系则返回隐藏控件。
## 未识者一并列出(头像灰显): 关系是世间真情, 不因玩家是否认识而遮蔽 —— 如季忘川开局在册而其故交均未入册。
## 情值(恋爱边 aff 0~1000)仅恋爱对显示; 同性/无恋爱边者情值恒 0 无来源, 不占行。
func _relation_box(key: String) -> Control:
	var items: Array = Game.npc_relations(key)
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
		var nl := UiKit.label(Game.npc_name(peer), 10, UiKit.PINK_600 if peer_met else UiKit.GRAY_400, 500, HORIZONTAL_ALIGNMENT_CENTER)
		nl.custom_minimum_size = Vector2(44, 0)
		nl.clip_text = true
		item.add_child(nl)
		item.add_child(UiKit.label("友 %+d" % int(v), 11, _friend_color(v), 600, HORIZONTAL_ALIGNMENT_CENTER))
		var tag_lb := UiKit.label(String(r.get("tag", "")) if String(r.get("tag", "")) != "" else "相识", 10, _relation_color(v), 500, HORIZONTAL_ALIGNMENT_CENTER)
		tag_lb.custom_minimum_size = Vector2(44, 0)
		tag_lb.clip_text = true
		item.add_child(tag_lb)
		if r.has("aff"):   # 恋爱对独享: 情值逐月涨好感、争风吃醋会扣, 恋爱态已在 tag 冠名
			item.add_child(UiKit.label("情 %.0f" % float(r.get("aff", 0.0)), 10, _love_color(float(r.get("aff", 0.0))), 600, HORIZONTAL_ALIGNMENT_CENTER))
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
