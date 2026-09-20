extends Control
## 开始界面：标题 + 存档摘要 + 继续/新开。选毕切主场景（res://scenes/main.tscn）。
## 「继续修行」直接进主界面；「新开一世」清双层存档 → Game.new_game() 起第 1 世 →
## 主界面自动落到玉牌三生石（GameState.fresh_start），只能经「入世/转世」按钮入局。

const UiKit := preload("res://scripts/ui_kit.gd")
const MAIN_SCENE := "res://scenes/main.tscn"

var _dlg: Node = null
var _saved: Dictionary = {}   # 已存的当前一世(空=无存档)


func _ready() -> void:
	theme = UiKit.base_theme()
	_saved = SaveSystem.load_open_run()
	_build()


func _build() -> void:
	var bg := TextureRect.new()
	bg.texture = UiKit.gradient_texture(UiKit.PINK_50, UiKit.PINK_100, "v")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var wrap := MarginContainer.new()
	wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrap.add_theme_constant_override("margin_left", 32)
	wrap.add_theme_constant_override("margin_right", 32)
	wrap.add_theme_constant_override("margin_top", 56)
	wrap.add_theme_constant_override("margin_bottom", 40)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	wrap.add_child(vb)

	vb.add_child(UiKit.expander())

	# —— 标题 ——
	var ic := CenterContainer.new()
	ic.add_child(UiKit.icon_rect("jade_tablet", 72, UiKit.GOLD_600))
	vb.add_child(ic)
	vb.add_child(_center_label("百味长生", 34, UiKit.PINK_700, 700))
	vb.add_child(_center_label("宗门杂役院 · 一饭一修行", 13, UiKit.JADE_600))
	vb.add_child(UiKit.vspace(20))
	vb.add_child(_save_card())
	vb.add_child(UiKit.vspace(28))

	# —— 入口 ——
	var has_save := not _saved.is_empty()
	vb.add_child(_big_button("继续修行" if has_save else "入世修行", _enter_main))
	vb.add_child(UiKit.vspace(10))
	vb.add_child(_ghost_button("新开一世（清档重来）", _confirm_new))

	vb.add_child(UiKit.expander())
	vb.add_child(_center_label("玉牌随身 · 岁月自走", 11, UiKit.PINK_400))


func _save_card() -> Control:
	var box := UiKit.padded(UiKit.pink_box(), 14)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	if _saved.is_empty():
		vb.add_child(_center_label("尚无存档", 11, UiKit.PINK_400, 600))
		vb.add_child(_center_label("新开一世，即入百味宗门墙", 14, UiKit.PINK_700, 600))
	else:
		var life := int(_saved.get("life", 1))
		var realm_name := String(Game.realm().get("name", "?"))
		vb.add_child(_center_label("存 档", 11, UiKit.PINK_400, 600))
		vb.add_child(_center_label("第 %d 世 · %s" % [life, realm_name], 15, UiKit.PINK_700, 600))
		vb.add_child(_center_label("道韵 %d · 历世 %d · 最佳 %s" % [
			int(Game.meta.get("dao", 0)), int(Game.meta.get("lives", 0)), String(Game.meta.get("best_name", "无")),
		], 12, UiKit.PINK_500))
	box.add_child(vb)
	return box


func _center_label(text: String, size: int, color: Color, weight := 400) -> Label:
	var l := UiKit.label(text, size, color, weight, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


# ---- 入口动作 ----

func _enter_main() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)


## 新开一世：清双层存档 + UI 档 → 起第 1 世 → 主界面先落捏脸。
func _new_game() -> void:
	SaveSystem.clear_all()
	GameState.reset_all()
	Game.new_game()
	GameState.fresh_start = true
	get_tree().change_scene_to_file(MAIN_SCENE)


func _confirm_new() -> void:
	_close_dialog()
	var dlg := UiKit.dialog_layer(self, 320.0)
	_dlg = dlg.layer
	UiKit.dim_click_close(dlg.dim, _close_dialog)
	var vb: VBoxContainer = dlg.vb
	vb.add_child(UiKit.label("新开一世？", 17, UiKit.PINK_700, 600))
	var note := UiKit.label("清空全部存档：道韵、历世、当前一世与纪事图鉴一并归零，从第 1 世重修 —— 不可撤销。", 12, UiKit.PINK_400)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_ghost_button("再想想", _close_dialog))
	row.add_child(_big_button("确认清空", func() -> void:
		_close_dialog()
		_new_game()
	))
	vb.add_child(row)


func _close_dialog() -> void:
	if _dlg != null:
		_dlg.queue_free()
		_dlg = null


# ---- 按钮 ----

func _big_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 46)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_override("font", UiKit.font(600))
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", UiKit.WHITE)
	b.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.PINK_500, 10))
	b.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.PINK_600, 10))
	b.add_theme_stylebox_override("pressed", UiKit.stylebox(UiKit.PINK_600, 10))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b


func _ghost_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 42)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_override("font", UiKit.font(500))
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", UiKit.PINK_500)
	b.add_theme_color_override("font_hover_color", UiKit.PINK_700)
	b.add_theme_color_override("font_pressed_color", UiKit.PINK_700)
	b.add_theme_stylebox_override("normal", UiKit.stylebox(Color(0, 0, 0, 0), 10, false, 1, UiKit.PINK_300))
	b.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.PINK_50, 10, false, 1, UiKit.PINK_400))
	b.add_theme_stylebox_override("pressed", UiKit.stylebox(UiKit.PINK_100, 10, false, 1, UiKit.PINK_500))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b
