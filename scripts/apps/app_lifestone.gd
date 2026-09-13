extends "res://scripts/apps/app_base.gd"
## 三生石：跨世图鉴占位——尘缘未启（烙印/词条/回看皆留白，归 GDD §13 P2）。


func _build_content(vb: VBoxContainer) -> void:
	vb.add_theme_constant_override("separation", 16)
	vb.add_child(UiKit.label("三生石", 24, UiKit.PINK_600, 600))
	vb.add_child(_hero_card())
	vb.add_child(_blank_card())
	var foot := UiKit.label("牌是宗门财产，跟着「百味一世」世系传下来。", 12, UiKit.PINK_400)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(foot)


func _hero_card() -> PanelContainer:
	var c := UiKit.card()
	var cv := VBoxContainer.new()
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_theme_constant_override("separation", 12)
	cv.add_child(UiKit.circle(64, UiKit.PINK_200, UiKit.PINK_400, "heart", 28, UiKit.WHITE, true))
	cv.add_child(UiKit.label("尘缘未启", 16, UiKit.PINK_700, 600, HORIZONTAL_ALIGNMENT_CENTER))
	var body := UiKit.label(
		"宗门后山有块石头，刻满了名字，长老们也说不清刻的什么。\n玉牌里这枚阵拓的是「自家的那一份」——只是拓片上还什么都没有。",
		13, UiKit.PINK_600, 400, HORIZONTAL_ALIGNMENT_CENTER)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(body)
	c.add_child(UiKit.margin_wrap(cv, 20))
	return c


func _blank_card() -> PanelContainer:
	var c := UiKit.card()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 12)
	for row in [["历世烙印者"], ["暗线词条"], ["重逢回看"]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		h.add_child(UiKit.label(String(row[0]), 14, UiKit.PINK_700, 600))
		var exp := UiKit.expander()
		h.add_child(exp)
		h.add_child(UiKit.label("——", 14, UiKit.PINK_300))
		cv.add_child(h)
	c.add_child(UiKit.margin_wrap(cv, 16))
	return c
