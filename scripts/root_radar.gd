extends Control
## 五围图: 灵根选择的五行雷达盘 —— 顶点自正上方顺时针 = 金/木/水/火/土。
## 实心尖角 = 身负该行, 空心内收 = 缺行; 点顶点(或其标签)切换持有, 中心字给出下世预览。
## 纯呈现 + 命中判定: 选择状态与行数约束由调用方(三生石)持有, 本控件只发 toggled 信号。

signal toggled(el: String)

const UiKit := preload("res://scripts/ui_kit.gd")

const LABEL_MARGIN := 24.0      # 顶点标签外扩距离, 同时充当点击半径
const INSET := 0.14             # 缺行顶点的内收比例(不为 0: 雷达保持五角轮廓)

var elements: PackedStringArray = PackedStringArray(["金", "木", "水", "火", "土"])
var owned: PackedStringArray = PackedStringArray()
var center_text := ""


func setup(els: PackedStringArray, owns: PackedStringArray, text: String) -> void:
	elements = els
	owned = owns
	center_text = text
	queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(244, 236)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _angle(i: int) -> float:
	return -PI / 2.0 + TAU * float(i) / float(elements.size())


func _center() -> Vector2:
	return Vector2(size.x / 2.0, size.y / 2.0 + 6.0)


func _radius() -> float:
	return maxf(40.0, minf(size.x, size.y) / 2.0 - LABEL_MARGIN)


func vertex_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var c := _center()
	var R := _radius()
	for i in elements.size():
		pts.append(c + Vector2(cos(_angle(i)), sin(_angle(i))) * R)
	return pts


## 点击命中: 顶点或其标签附近 → 返回对应五行, 否则空串
func el_at_point(p: Vector2) -> String:
	var pts := vertex_points()
	for i in pts.size():
		var label_pt := pts[i] + (pts[i] - _center()).normalized() * LABEL_MARGIN
		if p.distance_to(pts[i]) <= 20.0 or p.distance_to(label_pt) <= 22.0:
			return String(elements[i])
	return ""


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var hit := el_at_point(e.position)
		if hit != "":
			accept_event()
			toggled.emit(hit)


func _draw() -> void:
	var c := _center()
	var pts := vertex_points()
	# 同心五边形网格(三圈) + 轴线
	for lv in [0.34, 0.67, 1.0]:
		var ring := PackedVector2Array()
		for i in pts.size():
			ring.append(c + (pts[i] - c) * lv)
		ring.append(ring[0])
		draw_polyline(ring, UiKit.PINK_200 if lv < 1.0 else UiKit.PINK_300, 1.0)
	for i in pts.size():
		draw_line(c, pts[i], UiKit.PINK_100, 1.0)
	# 持有多边形: 实顶点全径, 缺行内收
	var shape := PackedVector2Array()
	for i in elements.size():
		var k := 1.0 if owned.has(String(elements[i])) else INSET
		shape.append(c + (pts[i] - c) * k)
	draw_colored_polygon(shape, Color(UiKit.PINK_500, 0.25))
	var outline := shape.duplicate()
	outline.append(shape[0])
	draw_polyline(outline, UiKit.PINK_500, 2.0)
	# 顶点与标签
	var f := UiKit.font(400)
	var fb := UiKit.font(600)
	for i in elements.size():
		var on: bool = owned.has(String(elements[i]))
		var v := pts[i]
		if on:
			draw_circle(v, 5.5, UiKit.PINK_500)
		else:
			draw_circle(v, 4.5, UiKit.WHITE)
			draw_arc(v, 4.5, 0, TAU, 20, UiKit.PINK_400, 1.5)
		var lp := v + (v - c).normalized() * LABEL_MARGIN
		var txt := String(elements[i])
		draw_string(fb if on else f, Vector2(lp.x - 20, lp.y + 5), txt, HORIZONTAL_ALIGNMENT_CENTER, 40, 13, UiKit.PINK_700 if on else UiKit.PINK_300)
	if center_text != "":
		draw_string(fb, Vector2(0, c.y + 5), center_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 13, UiKit.GOLD_600)
