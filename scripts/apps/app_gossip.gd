extends "res://scripts/apps/app_base.gd"
## 闲话壁：百话楼照壁帖串（论坛体，四型分类色，回帖恰 2 条）+「壁讯」订阅开关。
## 数据来自 Game.run.wall.posts × DataManager.wall（灰盒闲话壁系统：永不弹窗，红点未读）。

const FAMILY_CN := {
	"force": {"name": "势力", "color_ref": "jade"},
	"npc": {"name": "人情", "color_ref": "pink"},
	"strange": {"name": "怪谈", "color_ref": "gold"},
	"mortal": {"name": "凡尘", "color_ref": "gray"},
	"protagonist": {"name": "主角", "color_ref": "red"},
}

var _list_vb: VBoxContainer


func _build_content(vb: VBoxContainer) -> void:
	vb.add_child(bleed_head("闲话壁", "百话楼照壁 · 一世一壁，帖是当世的。"))
	_list_vb = VBoxContainer.new()
	_list_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_vb.add_theme_constant_override("separation", 0)
	vb.add_child(_list_vb)
	Game.changed.connect(_schedule_rebuild)
	_rebuild()


var _rebuild_pending := false

func _schedule_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_pending = false
	for c in _list_vb.get_children():
		_list_vb.remove_child(c)
		c.queue_free()
	if Game.run.is_empty() or not Game.run.has("wall"):
		return
	var posts: Array = Game.run.wall.get("posts", [])
	if posts.is_empty():
		var empty := UiKit.label("壁上无帖 —— 照壁也在等新鲜事。", 13, UiKit.PINK_400)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var empty_wrap := UiKit.margin_wrap(empty, 16)
		empty_wrap.add_theme_constant_override("margin_top", 24)
		_list_vb.add_child(empty_wrap)
		return
	# 最新帖在最上
	for i in range(posts.size() - 1, -1, -1):
		var p: Dictionary = posts[i]
		var post: Dictionary = DataManager.wall_post(String(p.get("id", "")))
		if post.is_empty():
			continue
		_list_vb.add_child(_post_card(post, int(p.get("year", 0)), int(p.get("month", 1)), p.get("sub", {})))


## 事件帖占位替换: "{npc}" → 帖子记录里的人名等
func _sub(line: String, sub: Dictionary) -> String:
	for k in sub:
		line = line.replace("{%s}" % k, String(sub[k]))
	return line


func _post_card(post: Dictionary, year: int, month: int, sub: Dictionary = {}) -> PanelContainer:
	var c := bleed_section()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	c.add_child(UiKit.margin_wrap(cv, 16))

	var fam := String(post.get("family", "mortal"))
	var meta: Dictionary = FAMILY_CN.get(fam, {"name": fam, "color_ref": "gray"})
	cv.add_child(UiKit.pill(String(meta.name), UiKit.WHITE, _family_color(String(meta.color_ref)), 11, 600))

	var title := UiKit.label(_sub(String(post.get("title", "")), sub), 15, UiKit.PINK_700, 600)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(title)

	var op: Dictionary = post.get("op", {})
	var op_head := HBoxContainer.new()
	op_head.add_theme_constant_override("separation", 6)
	op_head.add_child(UiKit.label("1楼 · %s" % _sub(String(op.get("poster_id", "匿名")), sub), 11, UiKit.PINK_400, 500))
	op_head.add_child(UiKit.expander())
	op_head.add_child(UiKit.label("入世第%d年·%d月" % [year, month], 10, UiKit.PINK_300))
	cv.add_child(op_head)
	cv.add_child(_body_label(_sub(String(op.get("text", "")), sub)))

	# op_extra 在 JSON 里多为 null(get 的默认值对「键存在但值为 null」不生效, 须显式判空)
	var extra_v: Variant = post.get("op_extra")
	var extra := "" if extra_v == null else _sub(String(extra_v), sub)
	if extra != "":
		var el := UiKit.label(extra, 11, UiKit.GOLD_600)
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(el)

	var replies: Array = post.get("replies", [])
	for i in replies.size():
		var r: Dictionary = replies[i]
		var rl := UiKit.label("%d楼 · %s：%s" % [i + 2, _sub(String(r.get("poster_id", "匿名")), sub), _sub(String(r.get("text", "")), sub)], 12, UiKit.PINK_600)
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(rl)
	return c


func _body_label(text: String) -> Label:
	var l := UiKit.label(text, 13, UiKit.PINK_700)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _family_color(ref: String) -> Color:
	match ref:
		"jade": return UiKit.JADE_500
		"pink": return UiKit.PINK_500
		"gold": return UiKit.GOLD_500
		"red": return UiKit.RED_400
		_: return UiKit.GRAY_400
	return UiKit.GRAY_400
