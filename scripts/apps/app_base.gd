extends Control
## 玉牌 app 页基类：玉色标题栏（返回桌面 / 相邻 app 快切）+ app 自带皮肤内容区。
## 子类重写 _build_content(vb)；tablet_screen 负责注入身份（setup）并连接信号。

signal back_pressed
signal open_app(app_id: String)

const UiKit := preload("res://scripts/ui_kit.gd")

var app_id := ""
var app_title := ""
var app_order: Array = []   # 玉牌桌面上的 app 顺序，供 ‹ › 快切
var content_vb: VBoxContainer


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
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 24)
	mc.add_theme_constant_override("margin_right", 24)
	mc.add_theme_constant_override("margin_top", 16)
	mc.add_theme_constant_override("margin_bottom", 24)
	scroll.add_child(mc)
	content_vb = VBoxContainer.new()
	content_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vb.add_theme_constant_override("separation", 24)
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
	hb.add_child(_chevron_button("back", 90))   # ‹ 返回桌面
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(UiKit.label(app_title, 17, UiKit.JADE_800, 600, HORIZONTAL_ALIGNMENT_CENTER))
	hb.add_child(center)
	var switcher := HBoxContainer.new()
	switcher.add_theme_constant_override("separation", 4)
	switcher.add_child(_chevron_button("prev", 90))
	switcher.add_child(_chevron_button("next", -90))
	hb.add_child(switcher)
	return bar


## 标题栏箭头按钮：kind = back/prev（‹）或 next（›），由 chevron-down 旋转而来。
func _chevron_button(kind: String, rot_deg: float) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(56, 44) if kind == "back" else Vector2(28, 44)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var tr := TextureRect.new()
	tr.texture = UiKit.icon("chevron-down")
	tr.custom_minimum_size = Vector2(20, 20)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.modulate = UiKit.JADE_700
	tr.rotation_degrees = rot_deg
	tr.pivot_offset = Vector2(10, 10)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(CenterContainer.new())
	(b.get_child(0) as CenterContainer).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	(b.get_child(0) as CenterContainer).mouse_filter = Control.MOUSE_FILTER_IGNORE
	(b.get_child(0) as CenterContainer).add_child(tr)
	match kind:
		"back":
			b.pressed.connect(func() -> void: back_pressed.emit())
		"prev":
			b.pressed.connect(_go_neighbor.bind(-1))
		"next":
			b.pressed.connect(_go_neighbor.bind(1))
	return b


func _go_neighbor(dir: int) -> void:
	var idx := app_order.find(app_id)
	if idx == -1 or app_order.is_empty():
		return
	var next_id: String = app_order[(idx + dir + app_order.size()) % app_order.size()]
	open_app.emit(next_id)
