extends "res://scripts/apps/app_base.gd"
## 名望：仙盟官账名望榜 + 九家势力档案卡（GDD 8.4 势力主舞台的玩家侧呈现）。
## 名望三源（8.4 §12.2）= 大比名次（十年一届大比）＋ 司膳好评（秋期例会流水席）＋ 话本传唱（文脉民账）。
## 势力档案全量来自 data/factions.json（单一事实源）；NPC 原型仍隐名，门派点名只在照壁/论道/这里。

const TASTE_COLOR := {
	"温": "pink", "清": "jade", "辛": "red", "猎奇": "gray", "素": "green",
	"鲜": "blue", "甘": "gold", "饱腹": "orange", "—": "gray",
}
const RANK_CN := {1: "陪榜", 2: "上位", 3: "头名"}

var _stat_vb: VBoxContainer
var _log_vb: VBoxContainer
var _fac_vb: VBoxContainer


func _build_content(vb: VBoxContainer) -> void:
	vb.add_child(bleed_head("名望", "扶摇仙盟官账 · 名望榜 —— 大比名次 ＋ 司膳好评 ＋ 话本传唱"))
	_stat_vb = VBoxContainer.new()
	_stat_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stat_vb.add_theme_constant_override("separation", 0)
	vb.add_child(_stat_vb)
	_log_vb = VBoxContainer.new()
	_log_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_vb.add_theme_constant_override("separation", 0)
	vb.add_child(_log_vb)
	_fac_vb = VBoxContainer.new()
	_fac_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fac_vb.add_theme_constant_override("separation", 0)
	vb.add_child(_fac_vb)
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
	for vb in [_stat_vb, _log_vb, _fac_vb]:
		for c in vb.get_children():
			vb.remove_child(c)
			c.queue_free()
	if Game.run.is_empty():
		return
	_build_stat()
	_build_log()
	_build_factions()


## 名望值大字 + 大比最好名次 + 话本资格（名望≥repute_huaben, 8.4 §10.2）
func _build_stat() -> void:
	var c := bleed_section()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	c.add_child(UiKit.margin_wrap(cv, 16))
	var huaben := int(Game.tune("repute_huaben", 20))
	var rep := int(Game.run.get("repute", 0))
	cv.add_child(UiKit.label(str(rep), 42, UiKit.JADE_700, 700))
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", 6)
	sub.add_child(UiKit.label("名望 · 仙盟官账，全洲通用", 12, UiKit.PINK_500))
	sub.add_child(UiKit.expander())
	if rep >= huaben:
		sub.add_child(UiKit.pill("话本资格 · 名望≥%d" % huaben, UiKit.WHITE, UiKit.GOLD_600, 10, 600))
	var best := int(Game.run.get("lundao", {}).get("best", 0))
	sub.add_child(UiKit.label("大比最好名次: %s" % (RANK_CN.get(best, "尚未赴会") if best > 0 else "尚未赴会"), 12, UiKit.PINK_400))
	cv.add_child(sub)
	_stat_vb.add_child(c)


## 名望流水（_add_repute 留档最近 8 条：±n · 缘由 · 年份）
func _build_log() -> void:
	var c := bleed_section()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 4)
	c.add_child(UiKit.margin_wrap(cv, 16))
	cv.add_child(UiKit.label("名望流水", 13, UiKit.JADE_800, 600))
	var entries: Array = Game.run.get("repute_log", [])
	if entries.is_empty():
		var e := UiKit.label("尚无记录 —— 名望从一场大比、一席流水席开始。", 12, UiKit.PINK_400)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(e)
	for r in entries:
		var row: Dictionary = r
		var l := UiKit.label("第%d年 · 名望%+d · %s" % [int(row.get("y", 0)), int(row.get("n", 0)), String(row.get("why", ""))], 12, UiKit.PINK_600)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(l)
	_log_vb.add_child(c)


## 九家势力档案卡（GDD 8.4 §2.1 一句话定位 / §12.1 大比戏台位 / §3.2 与百味宗关系）
func _build_factions() -> void:
	for f in DataManager.factions:
		_fac_vb.add_child(_faction_card(f))


func _faction_card(f: Dictionary) -> PanelContainer:
	var c := bleed_section()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	c.add_child(UiKit.margin_wrap(cv, 16))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiKit.label(String(f.get("name", "?")), 16, UiKit.PINK_700, 600))
	var taste := String(f.get("taste", "—"))
	head.add_child(UiKit.pill("味 · %s" % taste, UiKit.WHITE, _taste_color(taste), 11, 600))
	if String(f.get("id", "")) == "baimenzong":
		head.add_child(UiKit.pill("家门", UiKit.WHITE, UiKit.PINK_400, 11, 600))
	head.add_child(UiKit.expander())
	cv.add_child(head)
	var intro := UiKit.label(String(f.get("intro", "")), 13, UiKit.PINK_700)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(intro)
	var seat := UiKit.label("大比戏台 · %s" % String(f.get("seat", "")), 12, UiKit.JADE_700)
	seat.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(seat)
	var rel := UiKit.label("与百味宗 · %s" % String(f.get("relation", "")), 11, UiKit.PINK_400)
	rel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(rel)
	return c


func _taste_color(t: String) -> Color:
	match TASTE_COLOR.get(t, "gray"):
		"pink": return UiKit.PINK_500
		"jade": return UiKit.JADE_500
		"red": return UiKit.RED_400
		"green": return UiKit.GREEN_500
		"blue": return UiKit.BLUE_500
		"gold": return UiKit.GOLD_500
		"orange": return UiKit.ORANGE_500
		_: return UiKit.GRAY_400
	return UiKit.GRAY_400
