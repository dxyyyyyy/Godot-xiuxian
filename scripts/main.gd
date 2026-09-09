extends Control
## 主界面：背景渐变 + 五个页签屏幕 + 底部导航栏。

const UiKit := preload("res://scripts/ui_kit.gd")

const SCREEN_SCRIPTS := {
	"schedule": preload("res://scripts/schedule_screen.gd"),
	"character": preload("res://scripts/character_screen.gd"),
	"home": preload("res://scripts/home_screen.gd"),
	"items": preload("res://scripts/items_screen.gd"),
	"settings": preload("res://scripts/settings_screen.gd"),
}
const NAV_ITEMS := [
	{"id": "schedule", "label": "日程", "icon": "calendar"},
	{"id": "character", "label": "人物", "icon": "users"},
	{"id": "home", "label": "家园", "icon": "home"},
	{"id": "items", "label": "物品", "icon": "package"},
	{"id": "settings", "label": "设置", "icon": "settings"},
]

var _screens := {}
var _nav_refs := {}
var _active := "home"


func _ready() -> void:
	theme = UiKit.base_theme()
	_build_background()
	_build_screens()
	_build_nav_bar()
	_switch_to(_active)


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
	var ic := UiKit.icon_rect(item.icon, 24, UiKit.GRAY_400)
	vb.add_child(ic)
	var lb := UiKit.label(item.label, 12, UiKit.GRAY_400, 500, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(lb)
	center.add_child(vb)
	b.add_child(center)
	b.pressed.connect(_switch_to.bind(item.id))
	_nav_refs[item.id] = {"icon": ic, "label": lb}
	return b


func _switch_to(id: String) -> void:
	_active = id
	for key in _screens:
		_screens[key].visible = key == id
	for key in _nav_refs:
		var active: bool = key == id
		var tint: Color = UiKit.PINK_500 if active else UiKit.GRAY_400
		_nav_refs[key].icon.modulate = tint
		_nav_refs[key].label.add_theme_color_override("font_color", tint)
