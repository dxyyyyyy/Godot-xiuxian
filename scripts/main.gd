extends Control
## 主界面：背景渐变 + 四页签屏幕（日程/家园/名录/玉牌）+ 底部导航栏。
## 玉牌为全屏层（自管边距），收纳闲话壁/纪事/三生石/库房/图鉴/设置。
## 全局层：灰盒事件打断弹窗（Game.interrupted → 选项 → resolve_option）+ 结局落幕弹窗。

const UiKit := preload("res://scripts/ui_kit.gd")

const SCREEN_SCRIPTS := {
	"schedule": preload("res://scripts/schedule_screen.gd"),
	"home": preload("res://scripts/home_screen.gd"),
	"directory": preload("res://scripts/directory_screen.gd"),
	"tablet": preload("res://scripts/tablet_screen.gd"),
}
const NAV_ITEMS := [
	{"id": "schedule", "label": "日程", "icon": "calendar"},
	{"id": "home", "label": "家园", "icon": "home"},
	{"id": "directory", "label": "名录", "icon": "users"},
	{"id": "tablet", "label": "玉牌", "icon": "jade_tablet"},
]

var _screens := {}
var _nav_refs := {}
var _nav_bar: Control
var _active := "schedule"   # 开始界面进入游戏 → 落在日程页

# ---- 全局弹窗层 ----
var _event_layer: Control
var _event_title: Label
var _event_body: Label
var _event_options: VBoxContainer
var _event_cd: Label
var _event_timer: Timer
var _afk_left := 0
var _afk_default := 1
var _afk_default_text := "放下"

## 挂机兜底: 弹框挂起 AFK_AUTO_SEC 秒未抉择 → 默认选第二项(多为「放下/错过」, 零损失)
const AFK_AUTO_SEC := 60
var _event_scroll: ScrollContainer
var _end_layer: Control
var _end_body: Label


func _ready() -> void:
	theme = UiKit.base_theme()
	_build_background()
	_build_screens()
	_build_nav_bar()
	_build_event_layer()
	_build_end_layer()
	GameState.tablet_unread_changed.connect(_refresh_tablet_badge)
	GameState.npc_detail_requested.connect(_on_npc_detail_requested)
	_screens["tablet"].leave_requested.connect(_on_tablet_leave)
	Game.interrupted.connect(_on_interrupted)
	Game.ended.connect(_on_ended)
	_switch_to(_active)
	_refresh_tablet_badge()
	if GameState.fresh_start or bool(Game.run.get("ended", false)):
		_nav_bar.visible = false   # 入世/转世流程不显底栏(读档遇到未转世的死亡档同样锁在玉牌)
		_switch_to("tablet")   # 新开一世 → 三生石选属性 + 捏脸
		_screens["tablet"].open_app("lifestone")


func _build_background() -> void:
	var bg := TextureRect.new()
	bg.name = "Background"
	bg.texture = UiKit.gradient_texture(UiKit.PINK_50, UiKit.PINK_100, "v")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


func _build_screens() -> void:
	var wrap := MarginContainer.new()
	wrap.name = "Screens"
	wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrap.add_theme_constant_override("margin_left", 24)
	wrap.add_theme_constant_override("margin_right", 24)
	wrap.add_theme_constant_override("margin_top", 24)
	wrap.add_theme_constant_override("margin_bottom", 104)  # 底栏 80 + 内容底部留白 24
	add_child(wrap)
	for id in SCREEN_SCRIPTS:
		var screen: Control = SCREEN_SCRIPTS[id].new()
		screen.name = id
		if id == "tablet":
			screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			add_child(screen)  # 玉牌全屏铺满，自管留白
		else:
			wrap.add_child(screen)
		_screens[id] = screen


func _build_nav_bar() -> void:
	var bar := PanelContainer.new()
	bar.name = "NavBar"
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -80.0
	var sb := UiKit.stylebox(UiKit.WHITE, 0)
	sb.border_width_top = 2
	sb.border_color = UiKit.PINK_200
	sb.shadow_color = Color(0, 0, 0, 0.10)
	sb.shadow_size = 8
	bar.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 0)
	bar.add_child(hb)
	for item in NAV_ITEMS:
		hb.add_child(_make_nav_button(item))
	add_child(bar)
	_nav_bar = bar


func _make_nav_button(item: Dictionary) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 78)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_wrap := Control.new()
	icon_wrap.custom_minimum_size = Vector2(24, 24)
	icon_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := UiKit.icon_rect(item.icon, 24, UiKit.GRAY_400)
	icon_wrap.add_child(ic)
	if item.id == "tablet":
		icon_wrap.add_child(_make_badge())
	vb.add_child(icon_wrap)
	var lb := UiKit.label(item.label, 12, UiKit.GRAY_400, 500, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(lb)
	center.add_child(vb)
	b.add_child(center)
	b.pressed.connect(_switch_to.bind(item.id))
	_nav_refs[item.id] = {"icon": ic, "label": lb}
	return b


## 玉牌按钮角标：任一 app 有未读即亮，数字封顶 999+（玉牌界面文档 §6）。鎏金阵纹风见 UiKit.make_badge。
func _make_badge() -> PanelContainer:
	var badge := UiKit.make_badge()
	badge.panel.position = Vector2(16, -6)
	_nav_refs["tablet_badge"] = badge
	return badge.panel


func _refresh_tablet_badge() -> void:
	var badge: Dictionary = _nav_refs.get("tablet_badge", {})
	if badge.is_empty():
		return
	UiKit.badge_set(badge, GameState.unread_total())


func _switch_to(id: String) -> void:
	if id == "tablet" and _active == "tablet":
		_screens["tablet"].back_to_desktop()  # 再点玉牌即收起
		return
	_active = id
	for key in _screens:
		_screens[key].visible = key == id
	for key in _nav_refs:
		if key == "tablet_badge":
			continue
		var active: bool = key == id
		var tint: Color = UiKit.PINK_500 if active else UiKit.GRAY_400
		_nav_refs[key].icon.modulate = tint
		_nav_refs[key].label.add_theme_color_override("font_color", tint)


# ---- 全局弹窗层（CanvasLayer 20 置顶，压过玉牌 App 弹层 layer 10）----

## 事件打断弹窗：greybox 打断即自动暂停时速，决策后自动恢复，这里只管呈现。
func _build_event_layer() -> void:
	var host := CanvasLayer.new()
	host.layer = 20
	add_child(host)
	_event_layer = Control.new()
	_event_layer.name = "EventLayer"
	_event_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_event_layer.visible = false
	host.add_child(_event_layer)

	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.05, 0.1, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_event_layer.add_child(dim)

	# 卡片:固定尺寸 + 固定位置(顶部 56 / 底部留 28 / 左右 24) —— 每次事件同一位置;
	# 正文与选项放在内部 ScrollContainer, 超长内容滚动查看
	var card := UiKit.card()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb: StyleBoxFlat = card.get_theme_stylebox("panel")
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	card.anchor_left = 0.0
	card.anchor_right = 1.0
	card.anchor_top = 0.0
	card.anchor_bottom = 1.0
	card.offset_left = 24
	card.offset_right = -24
	card.offset_top = 56
	card.offset_bottom = -28
	_event_layer.add_child(card)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_event_scroll = scroll
	card.add_child(scroll)

	var cv := VBoxContainer.new()
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cv.add_theme_constant_override("separation", 10)
	scroll.add_child(cv)
	_event_title = UiKit.label("", 18, UiKit.PINK_700, 600)
	_event_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(_event_title)
	_event_body = UiKit.label("", 14, UiKit.PINK_600)
	_event_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(_event_body)
	_event_options = VBoxContainer.new()
	_event_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_event_options.add_theme_constant_override("separation", 8)
	cv.add_child(_event_options)
	_event_cd = UiKit.label("", 11, UiKit.PINK_400)
	_event_cd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(_event_cd)
	_event_timer = Timer.new()
	_event_timer.wait_time = 1.0
	_event_timer.one_shot = false
	_event_timer.timeout.connect(_on_event_tick)
	add_child(_event_timer)


func _on_interrupted(ev: Dictionary) -> void:
	_event_title.text = String(ev.get("title", "机缘"))
	_event_body.text = String(ev.get("text", ""))
	for c in _event_options.get_children():
		_event_options.remove_child(c)
		c.queue_free()
	var opts: Array = ev.get("options", [])
	for i in opts.size():
		_event_options.add_child(_event_option_button(i, opts[i]))
	# 挂机兜底倒计时: 默认取第二项(单选项事件则取第一项)
	_afk_default = mini(1, maxi(0, opts.size() - 1))
	_afk_default_text = String((opts[_afk_default] as Dictionary).get("t", "放下")) if opts.size() > 0 else "放下"
	_afk_left = AFK_AUTO_SEC
	_update_event_cd()
	_event_timer.start()
	_event_scroll.scroll_vertical = 0   # 每次弹出回到顶部
	_event_layer.visible = true


func _update_event_cd() -> void:
	if _event_cd == null:
		return
	_event_cd.text = "%d 秒未抉择 → 默认「%s」" % [_afk_left, _afk_default_text]


func _on_event_tick() -> void:
	if not _event_layer.visible:
		_event_timer.stop()
		return
	_afk_left -= 1
	if _afk_left <= 0:
		_event_timer.stop()
		_event_layer.visible = false
		if not Game.pending.is_empty():
			Game.resolve_option(_afk_default)   # 收尾会复位时速并 emit changed
		return
	_update_event_cd()


## 选项条：主文案 + 「need / result」小注（自动换行，内容驱动高度，不溢出）。
func _event_option_button(i: int, opt: Dictionary) -> PanelContainer:
	var note := String(opt.get("need", ""))
	var result := String(opt.get("result", ""))
	var parts := PackedStringArray()
	if note != "":
		parts.append(note)
	if result != "":
		parts.append(result)
	var sub := " · ".join(parts)
	return UiKit.text_option_button(String(opt.get("t", "…")), sub, func() -> void:
		_event_timer.stop()
		_event_layer.visible = false
		Game.resolve_option(i)
	, bool(opt.get("disabled", false)))


## 结局落幕弹窗：飞升/隐退/陨落/坐化 → 展示道韵结算，去三生石转世。
func _build_end_layer() -> void:
	var host := CanvasLayer.new()
	host.layer = 20
	add_child(host)
	_end_layer = Control.new()
	_end_layer.name = "EndLayer"
	_end_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_end_layer.visible = false
	host.add_child(_end_layer)

	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.04, 0.1, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_end_layer.add_child(dim)

	var card := UiKit.card()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb: StyleBoxFlat = card.get_theme_stylebox("panel")
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(card)
	_end_layer.add_child(cc)

	var cv := VBoxContainer.new()
	cv.custom_minimum_size = Vector2(320, 0)
	cv.add_theme_constant_override("separation", 14)
	card.add_child(cv)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiKit.icon_rect("heart", 22, UiKit.PINK_500))
	head.add_child(UiKit.label("一世落幕", 20, UiKit.PINK_700, 600))
	cv.add_child(head)
	_end_body = UiKit.label("", 14, UiKit.PINK_600)
	_end_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(_end_body)
	var go := Button.new()
	go.text = "去三生石 · 转世再来"
	go.focus_mode = Control.FOCUS_NONE
	go.custom_minimum_size = Vector2(0, 42)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.add_theme_font_override("font", UiKit.font(600))
	go.add_theme_font_size_override("font_size", 15)
	go.add_theme_color_override("font_color", UiKit.WHITE)
	go.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.PINK_500, 10))
	go.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.PINK_600, 10))
	go.add_theme_stylebox_override("pressed", UiKit.stylebox(UiKit.PINK_600, 10))
	go.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	go.pressed.connect(func() -> void:
		_end_layer.visible = false
		_switch_to("tablet")
		_screens["tablet"].open_app("lifestone")
	)
	cv.add_child(go)


## 人物一览等处的「查看某 NPC 详情」请求: 不切屏, 直接弹层(CanvasLayer 不随目录页隐藏)。
func _on_npc_detail_requested(key: String) -> void:
	_screens["directory"]._open_detail(key)


func _on_tablet_leave() -> void:
	# 开局捏人/上世已了未转世: 游戏界面锁住, 只能经三生石「入世/转世」按钮入局
	if GameState.fresh_start or bool(Game.run.get("ended", false)):
		return
	_nav_bar.visible = true   # 恢复底栏
	_switch_to("schedule")   # 玉牌 app 退出（如捏脸应用容貌）→ 回游戏主界面


func _on_ended(summary: Dictionary) -> void:
	_nav_bar.visible = false   # 转世前锁底栏: 结局弹窗 → 三生石, 只能经「转世」入局
	_end_body.text = "【%s】\n享年 %d 岁 · 止步%s · 出身%s\n道韵 +%d（累计 %d）· 印记羁绊 %d · 决策 %d 次\n\n玉牌三生石可炼灵根、铸体、纳眷顾，转世再来。" % [
		String(summary.get("kind", "落幕")), int(summary.get("years", 0)), String(summary.get("realm", "?")),
		String(summary.get("origin", "?")), int(summary.get("dao", 0)), int(summary.get("total_dao", 0)),
		int(summary.get("bonds", 0)), int(summary.get("decisions", 0)),
	]
	_end_layer.visible = true
