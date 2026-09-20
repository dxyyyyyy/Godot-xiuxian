extends Control
## 玉牌 app 页基类：玉色标题栏（返回桌面 / 相邻 app 快切）+ app 自带皮肤内容区。
## 子类重写 _build_content(vb)；tablet_screen 负责注入身份（setup）并连接信号。

signal back_pressed
signal open_app(app_id: String)
signal exit_app   # 请求离开玉牌、回到游戏主界面（由 tablet_screen 上抛给 main）

const UiKit := preload("res://scripts/ui_kit.gd")

var app_id := ""
var app_title := ""
var app_order: Array = []   # 玉牌桌面上的 app 顺序，供 ‹ › 快切
var content_vb: VBoxContainer
var _back_btn: Button = null
var _switcher: HBoxContainer = null
## 通栏开关（默认开）：内容区去左右/下边距、块间距归零、隐藏滚动条、白底层铺满；
## 页面内容用 bleed_head/bleed_section 拼装（纪事同款），不想通栏的子类在 _init 里置 false。
var full_bleed := true


## 通栏页头：标题 + 副题，铺在白底上，内部 16px 留白。
func bleed_head(title: String, subtitle := "") -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.add_child(UiKit.label(title, 24, UiKit.PINK_600, 600))
	if subtitle != "":
		vb.add_child(UiKit.label(subtitle, 12, UiKit.PINK_400))
	var wrap := UiKit.margin_wrap(vb, 16)
	wrap.add_theme_constant_override("margin_top", 12)
	wrap.add_theme_constant_override("margin_bottom", 12)
	return wrap


## 通栏区块：白底直角铺满屏宽，块与块之间以 1px 分隔线相接；内容用 UiKit.margin_wrap(cv, 16) 填入。
func bleed_section() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiKit.stylebox(UiKit.WHITE, 0)
	sb.border_width_bottom = 1
	sb.border_color = UiKit.PINK_100
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func setup(id: String, title: String, order: Array) -> void:
	app_id = id
	app_title = title
	app_order = order


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_chrome()
	_build_content(content_vb)


## 子类重写：往内容 VBox 搭页面（app 内页保持各自皮肤）。
func _build_content(_vb: VBoxContainer) -> void:
	pass


func _build_chrome() -> void:
	# app 皮肤底：粉色渐变（玉牌只管壳，app 自带皮肤）
	var bg := TextureRect.new()
	bg.texture = UiKit.gradient_texture(UiKit.PINK_50, UiKit.PINK_100, "v")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(_title_bar())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var mc := MarginContainer.new()
	if full_bleed:
		# 通栏：白底层垫在滚动层背后铺满整个内容区（内容不足一屏也填满）；
		# 滚动内容须显式横向展开，否则 ScrollContainer 只给子节点最小宽（实测 188px）；
		# 竖向滚动条隐藏（SHOW_NEVER，滚动照常），免得占掉右侧 8px 不铺满。
		var host := Control.new()
		host.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root.add_child(host)
		var page_bg := PanelContainer.new()
		page_bg.add_theme_stylebox_override("panel", UiKit.stylebox(UiKit.WHITE, 0))
		page_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(page_bg)
		scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		host.add_child(scroll)
		mc.add_theme_constant_override("margin_left", 0)
		mc.add_theme_constant_override("margin_right", 0)
		mc.add_theme_constant_override("margin_top", 8)
		mc.add_theme_constant_override("margin_bottom", 80)   # 让位主界面底部导航条(悬浮 80px), 末行不再被遮
		mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root.add_child(scroll)
		mc.add_theme_constant_override("margin_left", 24)
		mc.add_theme_constant_override("margin_right", 24)
		mc.add_theme_constant_override("margin_top", 16)
		mc.add_theme_constant_override("margin_bottom", 24)
	scroll.add_child(mc)
	content_vb = VBoxContainer.new()
	content_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vb.add_theme_constant_override("separation", 0 if full_bleed else 24)
	mc.add_child(content_vb)


func _title_bar() -> PanelContainer:
	var bar := PanelContainer.new()
	var sb := UiKit.stylebox(UiKit.JADE_100, 0)
	sb.border_width_bottom = 2
	sb.border_color = UiKit.JADE_200
	bar.add_theme_stylebox_override("panel", sb)
	bar.custom_minimum_size = Vector2(0, 52)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	bar.add_child(hb)
	_back_btn = _title_btn("返回", true)   # 返回桌面
	hb.add_child(_back_btn)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(UiKit.label(app_title, 17, UiKit.JADE_800, 600, HORIZONTAL_ALIGNMENT_CENTER))
	hb.add_child(center)
	_switcher = HBoxContainer.new()
	_switcher.add_theme_constant_override("separation", 4)
	_switcher.add_child(_title_btn("‹", false))
	_switcher.add_child(_title_btn("›", false))
	hb.add_child(_switcher)
	return bar


## 锁定态(开局/转世)收走标题栏跳转: ‹› 快切一律藏, 三生石连「返回」也藏(捏脸页留返回→三生石)。
## 页面是常驻实例, 每次 _open 由 tablet_screen 按当前状态重设。
func set_nav_locked(no_switch: bool, no_back: bool) -> void:
	if _switcher != null:
		_switcher.visible = not no_switch
	if _back_btn != null:
		_back_btn.visible = not no_back


## 标题栏文字按钮：返回 = 「返回」文字；快切 prev = ‹、next = ›（不依赖贴图旋转，方向一眼可辨）。
func _title_btn(glyph: String, is_back: bool) -> Button:
	var b := Button.new()
	b.text = glyph
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(60, 44) if is_back else Vector2(32, 44)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.add_theme_font_override("font", UiKit.font(600))
	b.add_theme_font_size_override("font_size", 15 if is_back else 26)
	b.add_theme_color_override("font_color", UiKit.JADE_700)
	b.add_theme_color_override("font_hover_color", UiKit.JADE_900)
	b.add_theme_color_override("font_pressed_color", UiKit.JADE_900)
	if is_back:
		b.pressed.connect(func() -> void: back_pressed.emit())
	elif glyph == "‹":
		b.pressed.connect(_go_neighbor.bind(-1))
	else:
		b.pressed.connect(_go_neighbor.bind(1))
	return b


func _go_neighbor(dir: int) -> void:
	var idx := app_order.find(app_id)
	if idx == -1 or app_order.is_empty():
		return
	var next_id: String = app_order[(idx + dir + app_order.size()) % app_order.size()]
	open_app.emit(next_id)
