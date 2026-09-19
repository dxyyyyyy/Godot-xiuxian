extends Control
## 屏幕基类：内容 VBox 挂进整屏（默认再套一层滚动容器），子类重写 _build。
## page_scrolls=false 的页（如日程）整页不滚，高内容卡片自管内滚。

const UiKit := preload("res://scripts/ui_kit.gd")

## 整页滚动开关：子类在 _init 里置 false 即可关掉页面级滚轮。
var page_scrolls := true


func _ready() -> void:
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 24)
	if page_scrolls:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(scroll)
		scroll.add_child(vb)
		# 内容最小高 = 视口高: 链路上的容器/卡片设 SIZE_EXPAND_FILL 即可撑满剩余屏幕(如日程一世纪事)
		scroll.resized.connect(func() -> void: vb.custom_minimum_size.y = scroll.size.y)
	else:
		vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(vb)
	_build(vb)


func _build(_vb: VBoxContainer) -> void:
	pass
