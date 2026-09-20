extends Control
## 传讯玉牌：仙皮手机桌面——七个 app 的收纳壳。
## 纯 UI 层：开合不暂停、不加速、不参与任何结算（玉牌界面文档 §1/§3）。

const UiKit := preload("res://scripts/ui_kit.gd")

const APPS := [
	{"id": "gossip", "title": "闲话壁", "icon": "bell"},
	{"id": "chronicle", "title": "纪事", "icon": "calendar"},
	{"id": "lifestone", "title": "三生石", "icon": "heart"},
	{"id": "face", "title": "捏脸", "icon": "users", "hidden": true},
	{"id": "npcface", "title": "捏脸 · 他人", "icon": "users", "hidden": true},
	{"id": "kidface", "title": "幼儿捏脸", "icon": "users", "hidden": true},
	{"id": "oldface", "title": "老年捏脸", "icon": "users", "hidden": true},
	{"id": "storage", "title": "库房", "icon": "package"},
	{"id": "cave", "title": "洞府", "icon": "home"},
	{"id": "market", "title": "坊市", "icon": "coins"},
	{"id": "codex", "title": "图鉴", "icon": "eye"},
	{"id": "settings", "title": "设置", "icon": "settings"},
	{"id": "test", "title": "测试", "icon": "eye"},
]
const APP_SCRIPTS := {
	"gossip": preload("res://scripts/apps/app_gossip.gd"),
	"chronicle": preload("res://scripts/apps/app_chronicle.gd"),
	"lifestone": preload("res://scripts/apps/app_lifestone.gd"),
	"face": preload("res://scripts/apps/app_face.gd"),
	"npcface": preload("res://scripts/apps/app_face_npc.gd"),
	"kidface": preload("res://scripts/apps/app_face_age.gd"),
	"oldface": preload("res://scripts/apps/app_face_age.gd"),
	"storage": preload("res://scripts/apps/app_storage.gd"),
	"cave": preload("res://scripts/apps/app_cave.gd"),
	"market": preload("res://scripts/apps/app_market.gd"),
	"codex": preload("res://scripts/apps/app_codex.gd"),
	"settings": preload("res://scripts/apps/app_settings.gd"),
	"test": preload("res://scripts/apps/app_test.gd"),
}

var _desktop: Control
var _pages := {}          # app_id -> app 页
var _badges := {}         # app_id -> 角标（PanelContainer + Label）
var _clock: Label
var _clock_cache := ""
var _current := ""        # "" = 桌面


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_wallpaper()
	_build_desktop()
	_build_pages()
	GameState.tablet_unread_changed.connect(_refresh_badges)
	_refresh_badges()


func _process(_delta: float) -> void:
	if _clock == null:
		return
	var txt := Game.calendar()
	if txt != _clock_cache:
		_clock_cache = txt
		_clock.text = txt


## 供全局层跳转（结局弹窗 → 三生石）。
func open_app(app_id: String) -> void:
	_open(app_id)


## app 请求退出玉牌回游戏主界面（如捏脸应用容貌后）——收起页面并上抛给 main。
signal leave_requested


func _on_app_exit() -> void:
	if GameState.face_returning:
		GameState.face_returning = false
		_open("lifestone")   # 新开一世捏脸毕 → 回三生石
		return
	back_to_desktop()
	leave_requested.emit()


## 主页再点一次「玉牌」即收起（回到桌面层）。
## 开局/转世态下返回只到桌面，不进游戏——入局唯一通道是三生石的「入世/转世」按钮(main 侧兜底)。
func back_to_desktop() -> void:
	if GameState.face_returning:
		GameState.face_returning = false
		_open("lifestone")   # 捏脸返回 → 回三生石(未应用容貌)
		return
	if GameState.fresh_start or bool(Game.run.get("ended", false)):
		_open("lifestone")   # 锁定态: 桌面也不露, 只回三生石
		return
	_current = ""
	for k in _pages:
		_pages[k].visible = false
	if _desktop != null:
		_desktop.visible = true


func _open(app_id: String) -> void:
	GameState.mark_app_opened(app_id)
	_current = app_id
	_desktop.visible = false
	for k in _pages:
		_pages[k].visible = k == app_id
	# 锁定态(开局/转世): ‹› 快切全藏; 三生石连「返回」也藏, 只剩「入世/转世」一条路
	var locked := GameState.fresh_start or bool(Game.run.get("ended", false))
	_pages[app_id].set_nav_locked(locked, locked and app_id == "lifestone")
	_refresh_badges()


# ---- 桌面（青玉壁纸 + 阵纹装饰 + 状态栏 + app 网格）----

func _build_wallpaper() -> void:
	var bg := TextureRect.new()
	bg.texture = UiKit.gradient_texture(UiKit.JADE_50, UiKit.JADE_100, "v")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# 两圈淡金阵纹装饰（玉牌上依稀可辨的刻痕）
	add_child(_ring(Vector2(316, 48), 190, Color(UiKit.GOLD_500, 0.18)))
	add_child(_ring(Vector2(-52, 700), 240, Color(UiKit.JADE_400, 0.20)))


func _ring(pos: Vector2, d: float, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiKit.stylebox(Color.TRANSPARENT, 999)
	sb.set_border_width_all(2)
	sb.border_color = color
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(d, d)
	p.position = pos
	p.size = Vector2(d, d)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _build_desktop() -> void:
	_desktop = MarginContainer.new()
	_desktop.name = "Desktop"
	_desktop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_desktop.add_theme_constant_override("margin_left", 24)
	_desktop.add_theme_constant_override("margin_right", 24)
	_desktop.add_theme_constant_override("margin_top", 20)
	_desktop.add_theme_constant_override("margin_bottom", 104)  # 底栏 80 + 留白 24
	add_child(_desktop)

	var vb := VBoxContainer.new()
	_desktop.add_child(vb)

	# 状态栏：归属 · 游戏内时间
	var status := HBoxContainer.new()
	status.add_child(UiKit.label("百味宗 · 杂役院", 12, UiKit.JADE_600, 500))
	status.add_child(UiKit.expander())
	_clock = UiKit.label(Game.calendar(), 12, UiKit.JADE_700, 600)
	status.add_child(_clock)
	vb.add_child(status)

	vb.add_child(UiKit.vspace(28))
	vb.add_child(UiKit.label("传讯玉牌", 26, UiKit.INK, 700))
	vb.add_child(UiKit.label("后勤堂制 · 阵纹八枚", 12, UiKit.JADE_500))
	vb.add_child(UiKit.vspace(24))

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 22)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for app in APPS:
		if app.get("hidden", false):
			continue   # 桌面不摆阵纹(如捏脸, 入口在测试页), 页面实例保留供跳转
		grid.add_child(_app_tile(app))
	vb.add_child(grid)

	vb.add_child(UiKit.expander())
	vb.add_child(UiKit.label("阵纹即入口 · 面板间可快切", 11, UiKit.JADE_400, 400, HORIZONTAL_ALIGNMENT_CENTER))


func _app_tile(app: Dictionary) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(78, 96)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 阵纹图标：白玉圆底 + 金色阵纹 + 细玉环，红点角标叠右上
	var icon_wrap := Control.new()
	icon_wrap.custom_minimum_size = Vector2(66, 66)
	icon_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var disc := PanelContainer.new()
	var sb := UiKit.stylebox(UiKit.WHITE, 999, true)
	sb.set_border_width_all(2)
	sb.border_color = UiKit.JADE_200
	disc.add_theme_stylebox_override("panel", sb)
	disc.custom_minimum_size = Vector2(64, 64)
	disc.position = Vector2(1, 1)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tc := CenterContainer.new()
	tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tc.add_child(UiKit.icon_rect(app.icon, 26, UiKit.GOLD_600))
	disc.add_child(tc)
	icon_wrap.add_child(disc)

	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UiKit.stylebox(UiKit.RED_400, 999))
	badge.custom_minimum_size = Vector2(18, 18)
	badge.position = Vector2(48, -2)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bl := UiKit.label("", 10, UiKit.WHITE, 700, HORIZONTAL_ALIGNMENT_CENTER)
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(bl)
	icon_wrap.add_child(badge)
	_badges[app.id] = {"panel": badge, "label": bl}

	vb.add_child(icon_wrap)
	var lb := UiKit.label(app.title, 13, UiKit.INK, 500, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(lb)
	center.add_child(vb)
	b.add_child(center)
	b.pressed.connect(_open.bind(app.id))
	return b


func _refresh_badges() -> void:
	for app in APPS:
		if not _badges.has(app.id):
			continue   # 隐藏入口的 app 没有桌面阵纹
		var n: int = GameState.app_unread(String(app.id))
		var badge: PanelContainer = _badges[app.id].panel
		var bl: Label = _badges[app.id].label
		badge.visible = n > 0
		bl.text = "9+" if n > 9 else str(n)


# ---- app 页（常驻实例，显隐切换）----

func _build_pages() -> void:
	var order: Array = []
	for app in APPS:
		order.append(String(app.id))
	for app in APPS:
		var page: Control = APP_SCRIPTS[String(app.id)].new()
		page.name = String(app.id)
		page.setup(String(app.id), String(app.title), order)
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page.visible = false
		page.back_pressed.connect(back_to_desktop)
		page.open_app.connect(_open)
		page.exit_app.connect(_on_app_exit)
		add_child(page)
		_pages[String(app.id)] = page
