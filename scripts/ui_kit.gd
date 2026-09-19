extends RefCounted
## UI 工具箱：Tailwind 调色板映射 + 控件工厂函数，用于还原 Figma Make 设计稿。
## 用法：const UiKit := preload("res://scripts/ui_kit.gd")

# ---- Tailwind 调色板（设计稿用到的颜色）----
const PINK_50 := Color("fdf2f8")
const PINK_100 := Color("fce7f3")
const PINK_200 := Color("fbcfe8")
const PINK_300 := Color("f9a8d4")
const PINK_400 := Color("f472b6")
const PINK_500 := Color("ec4899")
const PINK_600 := Color("db2777")
const PINK_700 := Color("be185d")
const GRAY_200 := Color("e5e7eb")
const GRAY_300 := Color("d1d5db")
const GRAY_400 := Color("9ca3af")
const WHITE := Color.WHITE
const ORANGE_200 := Color("fed7aa")
const ORANGE_300 := Color("fdba74")
const ORANGE_500 := Color("f97316")
const AMBER_100 := Color("fef3c7")
const GREEN_100 := Color("dcfce7")
const GREEN_400 := Color("4ade80")
const GREEN_500 := Color("22c55e")
const GREEN_700 := Color("15803d")
const YELLOW_400 := Color("facc15")
const RED_400 := Color("f87171")
const BLUE_500 := Color("3b82f6")

# ---- 玉牌色系（青玉底 + 鎏金阵纹 + 墨色字，传讯玉牌外壳专用）----
const JADE_50 := Color("f0fdfa")
const JADE_100 := Color("ccfbf1")
const JADE_200 := Color("99f6e4")
const JADE_300 := Color("5eead4")
const JADE_400 := Color("2dd4bf")
const JADE_500 := Color("14b8a6")
const JADE_600 := Color("0d9488")
const JADE_700 := Color("0f766e")
const JADE_800 := Color("115e59")
const JADE_900 := Color("134e4a")
const GOLD_200 := Color("fde68a")
const GOLD_400 := Color("fbbf24")
const GOLD_500 := Color("f59e0b")
const GOLD_600 := Color("d97706")
const GOLD_700 := Color("b45309")
const INK := Color("1f2937")

static var _font_cache := {}


## 系统中文字体（发布到其他平台时建议换成打包的字体文件）
static func font(weight := 400) -> SystemFont:
	if not _font_cache.has(weight):
		var f := SystemFont.new()
		f.font_names = PackedStringArray([
			"Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC",
			"Noto Sans CJK SC", "Segoe UI Emoji", "sans-serif",
		])
		if weight >= 600:
			f.font_weight = 700
		_font_cache[weight] = f
	return _font_cache[weight]


static func base_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 14
	return t


static func icon(name: String) -> Texture2D:
	return load("res://assets/icons/%s.svg" % name)


## 白色矢量图标 + modulate 染色（图标源文件统一为白色描边）
static func icon_rect(name: String, size: float, tint: Color) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = icon(name)
	tr.custom_minimum_size = Vector2(size, size)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.modulate = tint
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## 加载 res:// 图片(如 assets/sprites 的种子/菜谱 SVG 图谱)为等比缩放控件;文件缺失返回 null。
static func sprite(path: String, px: float) -> TextureRect:
	if not ResourceLoader.exists(path):
		return null
	var tr := TextureRect.new()
	tr.texture = load(path)
	tr.custom_minimum_size = Vector2(px, px)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## 渐变纹理：mode = "v" 纵向 / "h" 横向 / "diag" 对角线（对应 to-br）
static func gradient_texture(from: Color, to: Color, mode := "v") -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([from, to])
	var t := GradientTexture2D.new()
	t.gradient = g
	match mode:
		"h":
			t.fill_from = Vector2(0, 0.5)
			t.fill_to = Vector2(1, 0.5)
		"diag":
			t.fill_from = Vector2(0, 0)
			t.fill_to = Vector2(1, 1)
		_:
			t.fill_from = Vector2(0, 0)
			t.fill_to = Vector2(0, 1)
	return t


static func stylebox(bg: Color, radius := 12, shadow := false, border := 0, border_color := Color.WHITE) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(radius))
	if shadow:
		sb.shadow_color = Color(0, 0, 0, 0.10)
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0, 2)
	if border > 0:
		sb.set_border_width_all(border)
		sb.border_color = border_color
	return sb


## 白色圆角卡片（rounded-2xl shadow-md）
static func card(bg := WHITE) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", stylebox(bg, 16, true))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## 粉色圆角小盒子（bg-pink-50 rounded-xl）
static func pink_box(bg := PINK_50, radius := 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", stylebox(bg, radius))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## 渐变底板：子节点叠在渐变之上
static func gradient_panel(from: Color, to: Color, radius := 8, shadow := false) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", stylebox(Color.TRANSPARENT, radius, shadow))
	var tr := TextureRect.new()
	tr.texture = gradient_texture(from, to, "diag")
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(tr)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## 渐变圆形底座（头像/图标）
static func circle(d: float, from: Color, to := Color.TRANSPARENT, icon_name := "", icon_size := 0.0, tint := Color.WHITE, shadow := false) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", stylebox(from, 999, shadow))
	p.custom_minimum_size = Vector2(d, d)
	if to.a > 0.0 and to != from:
		var tr := TextureRect.new()
		tr.texture = gradient_texture(from, to, "diag")
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(tr)
	if icon_name != "":
		var center := CenterContainer.new()
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(icon_rect(icon_name, icon_size, tint))
		p.add_child(center)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func label(text: String, size := 14, color := PINK_700, weight := 400, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", int(size))
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 圆角胶囊徽章（rounded-full px-2 py-0.5）
static func pill(text: String, text_color: Color, bg: Color, size := 12, weight := 400) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := stylebox(bg, 999)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(label(text, size, text_color, weight, HORIZONTAL_ALIGNMENT_CENTER))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## 细进度条（h-2 rounded-full）
static func progress(frac: float, fill_color: Color, bg := PINK_200) -> ProgressBar:
	var p := ProgressBar.new()
	p.min_value = 0.0
	p.max_value = 100.0
	p.value = clampf(frac * 100.0, 0.0, 100.0)
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, 8)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_theme_stylebox_override("background", stylebox(bg, 4))
	p.add_theme_stylebox_override("fill", stylebox(fill_color, 4))
	return p


## 音量滑条（音效/音乐设置）
static func slider(value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 100.0
	s.value = value
	s.custom_minimum_size = Vector2(0, 24)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	var track := stylebox(PINK_200, 999)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	s.add_theme_stylebox_override("slider", track)
	var fill_sb := stylebox(PINK_500, 999)
	fill_sb.content_margin_top = 4
	fill_sb.content_margin_bottom = 4
	s.add_theme_stylebox_override("grabber_area", fill_sb)
	s.add_theme_stylebox_override("grabber_area_highlight", fill_sb)
	var grab := icon("slider_grabber")
	s.add_theme_icon_override("grabber", grab)
	s.add_theme_icon_override("grabber_highlight", grab)
	s.add_theme_icon_override("grabber_disabled", grab)
	return s


## 分段选择按钮（画质/时间调速）
static func seg_button(text: String, group: ButtonGroup, is_on: bool) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 36)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_override("font", font(500))
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", PINK_600)
	b.add_theme_color_override("font_hover_color", PINK_600)
	b.add_theme_color_override("font_pressed_color", WHITE)
	b.add_theme_color_override("font_hover_pressed_color", WHITE)
	b.add_theme_color_override("font_focus_color", PINK_600)
	b.add_theme_stylebox_override("normal", stylebox(PINK_100, 8))
	b.add_theme_stylebox_override("hover", stylebox(PINK_100, 8))
	b.add_theme_stylebox_override("pressed", stylebox(PINK_500, 8))
	b.add_theme_stylebox_override("hover_pressed", stylebox(PINK_500, 8))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.set_pressed_no_signal(is_on)
	return b


## 全屏对话框层（CanvasLayer 置顶，盖住整个窗口）：遮罩 + 居中圆角卡片。
## 返回 {layer, root, dim, card, vb}——往 vb 里加内容；关闭时对 layer queue_free。
static func dialog_layer(host: Node, min_width := 340.0) -> Dictionary:
	var layer := CanvasLayer.new()
	layer.layer = 10
	host.add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.05, 0.1, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)
	var card := card()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb: StyleBoxFlat = card.get_theme_stylebox("panel")
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	cc.add_child(card)
	var cv := VBoxContainer.new()
	cv.custom_minimum_size = Vector2(min_width, 0)
	cv.add_theme_constant_override("separation", 10)
	card.add_child(cv)
	return {"layer": layer, "root": root, "dim": dim, "card": card, "vb": cv}


## 带两行文字的选项条（标题 + 小注，均自动换行）。事件弹窗等处使用。
static func text_option_button(title: String, note: String, on_press: Callable, disabled := false) -> PanelContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	var title_l := label(title, 16, GRAY_400 if disabled else PINK_700, 600)
	title_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(title_l)
	if note != "":
		var sub_l := label(note, 12, GRAY_400 if disabled else PINK_400)
		sub_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_child(sub_l)
	return tappable_row(vb, on_press, disabled)


## 可点行：面板 + 调用方自建的内容控件 + 透明点击层（悬停/按下变色，禁用置灰不可点）。
## 内容里所有控件会被统一设为鼠标穿透，由最上层的点击层负责响应。
static func tappable_row(content: Control, on_press: Callable, disabled := false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _opt_sb(GRAY_200 if disabled else PINK_50))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree_mouse_ignore(content)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(content)

	var hit := Button.new()
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not disabled else Control.CURSOR_ARROW
	hit.disabled = disabled
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		hit.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	hit.pressed.connect(on_press)
	if not disabled:
		hit.mouse_entered.connect(func() -> void:
			panel.add_theme_stylebox_override("panel", _opt_sb(PINK_100))
		)
		hit.button_down.connect(func() -> void:
			panel.add_theme_stylebox_override("panel", _opt_sb(PINK_200))
		)
		hit.button_up.connect(func() -> void:
			panel.add_theme_stylebox_override("panel", _opt_sb(PINK_100))
		)
		hit.mouse_exited.connect(func() -> void:
			panel.add_theme_stylebox_override("panel", _opt_sb(PINK_50))
		)
	panel.add_child(hit)
	return panel


## 递归把整棵控件子树的鼠标过滤设为 IGNORE。
static func tree_mouse_ignore(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in c.get_children():
		if ch is Control:
			tree_mouse_ignore(ch)


static func _opt_sb(bg: Color) -> StyleBoxFlat:
	var sb := stylebox(bg, 10)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


## 给控件套满矩形遮罩点击关闭（点遮罩即关）。
static func dim_click_close(dim: ColorRect, on_close: Callable) -> void:
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			on_close.call()
		)


## 给 PanelContainer 的样式加内边距（对应 p-3/p-4/p-6）
static func padded(p: PanelContainer, m: float) -> PanelContainer:
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
	sb.content_margin_left = m
	sb.content_margin_right = m
	sb.content_margin_top = m
	sb.content_margin_bottom = m
	return p


## 外层统一内边距容器
static func margin_wrap(child: Control, m := 16) -> MarginContainer:
	var mc := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(side, int(m))
	mc.add_child(child)
	return mc


static func vspace(px: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, px)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func hspace(px: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(px, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## 占满剩余空间（flex-1）
static func expander() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
