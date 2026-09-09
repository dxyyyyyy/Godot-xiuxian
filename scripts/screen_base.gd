extends Control
## 屏幕基类：整屏滚动容器 + 内容 VBox，子类重写 _build。

const UiKit := preload("res://scripts/ui_kit.gd")


func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 24)
	scroll.add_child(vb)
	_build(vb)


func _build(_vb: VBoxContainer) -> void:
	pass
