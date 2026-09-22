extends "res://scripts/apps/app_base.gd"
## 幼儿捏脸（测试页入口）：选人 → 改部件/配色 → 应用到该人幼儿相 kid_look（脸A 幼儿套，未成年期间渲染用）。
## 与「捏脸·他人」（改 npcs.json 跨世）不同：本编辑只写本世 run 字典（名录/池中），一世位、转世即散。
## 成年相 appearance 不受影响：孩子成年礼后自动换回性别套。
## 幼儿 = born_m 且未满 npc_adult_years。

const Portrait := preload("res://scripts/portrait.gd")
const NG := preload("res://sim/NpcGenerator.gd")

const SLOTS := ["face", "brows", "eyes", "mouth", "hair_front", "hair_back", "cloth"]
const SLOT_CN := {"face": "脸型", "brows": "眉", "eyes": "眼", "mouth": "嘴", "hair_front": "前发", "hair_back": "后发", "cloth": "服装"}

var _content: VBoxContainer
var _rebuild_pending := false
var _stage := "pick"          # pick=选人 / edit=编辑
var _key := ""
var _work := {}               # 容貌工作台(kid_look 形状)
var _val_labels := {}
var _preview_box: CenterContainer
var _rng := RandomNumberGenerator.new()


func _build_content(vb: VBoxContainer) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiKit.label("幼儿捏脸", 18, UiKit.PINK_600, 600))
	head.add_child(UiKit.label("本世快照 · 一世位", 11, UiKit.PINK_400))
	var hw := UiKit.margin_wrap(head, 16)
	hw.add_theme_constant_override("margin_top", 8)
	hw.add_theme_constant_override("margin_bottom", 4)
	vb.add_child(hw)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 4)
	var cw := UiKit.margin_wrap(_content, 16)
	cw.add_theme_constant_override("margin_top", 0)
	cw.add_theme_constant_override("margin_bottom", 12)
	vb.add_child(cw)
	Game.changed.connect(_schedule_rebuild)
	_rebuild()


func _schedule_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	_rebuild.call_deferred()


## 可编辑对象: 名录+世界池合览, 只留幼儿。
func _candidates() -> Array:
	var out: Array = []
	if Game.run.is_empty():
		return out
	var all: Dictionary = Game.run.npcs.duplicate()
	all.merge(Game.run.world_npcs, true)
	for k in all:
		var e: Dictionary = all[k]
		if e.has("born_m") and Game._npc_age_years(String(k)) < int(Game.tune("npc_adult_years", 12)):
			out.append(String(k))
	return out


func _rebuild() -> void:
	_rebuild_pending = false
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_val_labels.clear()
	if _stage == "edit" and _key != "":
		_build_edit()
		return
	_build_pick()


# ---- 选人页 ----

func _build_pick() -> void:
	var cands := _candidates()
	if cands.is_empty():
		var hint := UiKit.label("暂无符合条件的人（幼儿=本世未满 12 岁的孩子）。", 12, UiKit.PINK_400)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(hint)
		return
	for k in cands:
		var e: Dictionary = Game._npc_entry(String(k))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(Portrait.build_for(String(k), 44))
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_child(UiKit.label(Game.npc_name(String(k)), 14, UiKit.PINK_700, 600))
		var age := "" if not e.has("born_m") else "%d岁 · " % Game._npc_age_years(String(k))
		vb.add_child(UiKit.label("%s%s" % [age, String(e.get("id_name", Game.npc_arch(String(k)).get("identity", "")))], 11, UiKit.PINK_400))
		row.add_child(vb)
		_content.add_child(UiKit.tappable_row(row, _enter_edit.bind(String(k))))


func _enter_edit(key: String) -> void:
	_key = key
	_rng.randomize()
	var e := Game._npc_entry(key)
	_work = (e.get("kid_look", {}) as Dictionary).duplicate(true)
	_work["aura"] = String((e.get("appearance", {}) as Dictionary).get("aura", NG.AURAS[0]))
	_stage = "edit"
	_rebuild()


# ---- 编辑页 ----

func _build_edit() -> void:
	var preview := CenterContainer.new()
	preview.custom_minimum_size = Vector2(0, 190)
	_preview_box = CenterContainer.new()
	_preview_box.add_child(_preview_frame())
	preview.add_child(_preview_box)
	_content.add_child(preview)

	for slot in SLOTS:
		_content.add_child(_row(slot))
	_content.add_child(_aura_row())
	_content.add_child(_slider_row("发色", "hair_hue", 0, 359))
	_content.add_child(_slider_row("瞳色", "eye_hue", 0, 359))

	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 6)
	acts.add_child(_sec_button("‹ 选人", func() -> void:
		_stage = "pick"
		_key = ""
		_rebuild()
	))
	acts.add_child(_sec_button("随机", _randomize_look))
	acts.add_child(_big_button("应用容貌", _apply))
	_content.add_child(acts)


## 随机：全槽部件 + 调色重掷，气质保留(与捏脸工坊同规)
func _randomize_look() -> void:
	var look := NG.random_look_kit(_rng, "kid")
	for k in NG.SLOTS:
		_work[k] = look[k]
	for k in NG.COLOR_IDENTITY:
		_work[k] = look[k]
	_rebuild()


func _preview_frame() -> Control:
	return UiKit.jade_frame(Portrait.build_from_kit(_work, 132, "kid"), UiKit.aura_tint(String(_work.get("aura", ""))))


func _refresh_preview() -> void:
	if _preview_box == null or not is_instance_valid(_preview_box):
		return
	for c in _preview_box.get_children():
		_preview_box.remove_child(c)
		c.queue_free()
	_preview_box.add_child(_preview_frame())


func _cycle(field: String, dir: int) -> void:
	var opts: Array = NG.options_kit("kid", field)
	if opts.is_empty():
		return
	var ids: Array = []
	for o in opts:
		ids.append(String((o as Dictionary).get("id", "")))
	var i := ids.find(String(_work.get(field, "")))
	_work[field] = String(ids[posmod(i + dir, ids.size())])
	if field == "hair_front":
		# 前后发同色约束: 前发换色标时, 后发重挑同色标者(与 random_look 同规)
		var fc := String(NG.entry_kit("kid", "hair_front", String(_work[field])).get("color", ""))
		for o in NG.options_kit("kid", "hair_back"):
			if String((o as Dictionary).get("color", "")) == fc:
				_work["hair_back"] = String((o as Dictionary).get("id", ""))
				break
	for f in _val_labels:
		(_val_labels[f] as Label).text = _disp(String(f))
	_refresh_preview()


func _cycle_aura(dir: int) -> void:
	var i := NG.AURAS.find(String(_work.get("aura", "")))
	_work["aura"] = String(NG.AURAS[posmod(i + dir, NG.AURAS.size())])
	(_val_labels["aura"] as Label).text = _disp("aura")
	_refresh_preview()


func _disp(field: String) -> String:
	if field == "aura":
		return String(_work.get("aura", ""))
	var id := String(_work.get(field, ""))
	var e: Dictionary = NG.entry_kit("kid", field, id)
	return String(e.get("name", id)) if not e.is_empty() else "无"


func _row(field: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var t := UiKit.label(SLOT_CN.get(field, field), 13, UiKit.PINK_700, 600)
	t.custom_minimum_size = Vector2(72, 0)
	row.add_child(t)
	row.add_child(_step_btn("‹", func() -> void: _cycle(field, -1)))
	var val := UiKit.label(_disp(field), 13, UiKit.PINK_600, 600, HORIZONTAL_ALIGNMENT_CENTER)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_val_labels[field] = val
	row.add_child(val)
	row.add_child(_step_btn("›", func() -> void: _cycle(field, 1)))
	return row


func _aura_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var t := UiKit.label("气质", 13, UiKit.PINK_700, 600)
	t.custom_minimum_size = Vector2(72, 0)
	row.add_child(t)
	row.add_child(_step_btn("‹", func() -> void: _cycle_aura(-1)))
	var val := UiKit.label(_disp("aura"), 13, UiKit.PINK_600, 600, HORIZONTAL_ALIGNMENT_CENTER)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_val_labels["aura"] = val
	row.add_child(val)
	row.add_child(_step_btn("›", func() -> void: _cycle_aura(1)))
	return row


func _slider_row(title: String, key: String, vmin: int, vmax: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var t := UiKit.label(title, 13, UiKit.PINK_700, 600)
	t.custom_minimum_size = Vector2(72, 0)
	row.add_child(t)
	var s := HSlider.new()
	s.min_value = vmin
	s.max_value = vmax
	s.step = 1
	s.value = float(int(_work.get(key, 0)))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0, 24)
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(func(v: float) -> void:
		_work[key] = int(v)
		_refresh_preview()
	)
	row.add_child(s)
	var val := UiKit.label("%d°" % int(_work.get(key, 0)), 12, UiKit.PINK_600, 600)
	val.custom_minimum_size = Vector2(44, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	s.value_changed.connect(func(v: float) -> void: val.text = "%d°" % int(v))
	return row


func _apply() -> void:
	var e := Game._npc_entry(_key)
	if e.is_empty():
		return
	var kl: Dictionary = e.get("kid_look", {}) as Dictionary
	kl.merge(_work, true)
	e.kid_look = kl
	Game.changed.emit()
	_stage = "pick"
	_key = ""
	_rebuild()


# ---- 小件(与 app_face 同风格) ----

func _step_btn(glyph: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = glyph
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(32, 28)
	b.add_theme_font_override("font", UiKit.font(600))
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", UiKit.PINK_600)
	b.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.PINK_50, 8))
	b.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.PINK_100, 8))
	b.add_theme_stylebox_override("pressed", UiKit.stylebox(UiKit.PINK_500, 8))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b


func _sec_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_override("font", UiKit.font(600))
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", UiKit.PINK_500)
	b.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.WHITE, 10, false, 2, UiKit.PINK_300))
	b.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.PINK_100, 10, false, 2, UiKit.PINK_400))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b


func _big_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 34)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_override("font", UiKit.font(600))
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", UiKit.WHITE)
	b.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.PINK_500, 10))
	b.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.PINK_600, 10))
	b.add_theme_stylebox_override("pressed", UiKit.stylebox(UiKit.PINK_600, 10))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b
