extends Node
## 主角关系冒烟: 已相识 NPC 的详情关系区首位列主角格(友=好感原值/情行)、未相逢者不列主角格;
## 点主角格开主角详情弹层; 主角详情关系区列相识众人(按好感从深到浅)且点格跳回 NPC 详情; 重建后还原。
## 安全起见: 不调 new_game、不碰真实存档 —— 读档后在 Game.run 的副本上合成名册并停时钟。

var _fails := 0


func _chk(name: String, ok: bool) -> void:
	print(("PASS: " if ok else "FAIL: ") + name)
	if not ok:
		_fails += 1


## 关系区(box)里的流式格子容器: pink_box > margin_wrap > VBox > [head, flow]
func _flow_of(box: Control) -> HFlowContainer:
	if box.get_child_count() == 0:
		return null
	return box.get_child(0).get_child(0).get_child(1) as HFlowContainer


## 关系格首 Label = 名字行
func _cell_name(cell: Node) -> String:
	for c in (cell.get_child(0) as VBoxContainer).get_children():
		if c is Label:
			return (c as Label).text
	return ""


## 关系格内全部文本(名字/友/称谓/情)
func _cell_texts(cell: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for c in (cell.get_child(0) as VBoxContainer).get_children():
		if c is Label:
			out.append((c as Label).text)
	return out


func _cell_hit(cell: Node) -> Button:
	return cell.get_child(cell.get_child_count() - 1) as Button


func _ready() -> void:
	Game.set_process(false)   # 停时钟: 无 tick、无自动存盘
	Game.run = Game.run.duplicate(true)
	# 合成: 两个相识随机 NPC(好感 520/100, 一位带情缘) + 一名强制未识的固定 NPC(防玩家进度干扰)
	var gen := Game.npc_generator
	var e := Game._npc_init()
	e.merge(gen.generate(Game.rng, Game.run.npcs, ["fangshi"]), true)
	e.met = true
	e.aff = 520.0
	e.love = 130.0
	e.stage = 2
	var rand_key := String(e.key)
	Game.run.npcs[rand_key] = e
	Game._npc_vitals_backfill(e, rand_key)
	var e2 := Game._npc_init()
	e2.merge(gen.generate(Game.rng, Game.run.npcs, ["tongming"]), true)
	e2.met = true
	e2.aff = 100.0
	var rand_key2 := String(e2.key)
	Game.run.npcs[rand_key2] = e2
	Game._npc_vitals_backfill(e2, rand_key2)
	# 未相逢固定骨架: 取档案首位固定 NPC 强制未识态(run 副本上改, 不回存档) —— 防玩家进度里此君已相逢
	var unmet_key := String((DataManager.npcs[0] as Dictionary).get("key", ""))
	if Game.run.npcs.has(unmet_key):
		Game.run.npcs[unmet_key].met = false
		Game.run.npcs[unmet_key].dead = false
	else:
		Game.run.npcs[unmet_key] = {"met": false, "aff": 0.0, "love": 0.0, "hidden": 0.0, "stage": 0, "gate": 0, "talk_cd": 0, "gift_q": 0}

	var scr := Control.new()
	scr.set_script(load("res://scripts/directory_screen.gd"))
	add_child(scr)
	await get_tree().process_frame
	await get_tree().process_frame

	# ① 相识 NPC 详情的关系区: 首位=主角格(显示名=run.name, 空则「主角」), 友值=好感原值, 带情行
	var pname := Game.player_name()
	if pname == "":
		pname = "主角"
	var box: Control = scr._relation_box(rand_key)
	var flow := _flow_of(box)
	_chk("相识者关系区有内容", flow != null and flow.get_child_count() > 0)
	var first := flow.get_child(0)
	_chk("关系首位=主角格", _cell_name(first) == pname)
	var texts := _cell_texts(first)
	_chk("主角格友值=好感原值", "友 520" in texts)
	_chk("主角格带情行", "情 130" in texts)

	# ② 未相逢者关系区: 无主角格(有无 NPC 边皆可, 只看主角格缺席)
	var mbox: Control = scr._relation_box(unmet_key)
	var mflow := _flow_of(mbox)
	var has_player := false
	if mflow != null:
		for c in mflow.get_children():
			if _cell_name(c) == pname:
				has_player = true
	_chk("未相逢者关系区无主角格", not has_player)

	# ③ 点主角格 → 开主角详情弹层
	_cell_hit(first).pressed.emit()
	_chk("点主角格开主角详情", scr._open_key == scr.PLAYER_KEY and scr._detail != null)

	# ④ 主角详情的关系区: 列相识众人(含合成两位), 不列未相逢者, 且按好感从深到浅
	var pbox: Control = scr._player_relation_box()
	var pflow := _flow_of(pbox)
	_chk("主角关系区有内容", pflow != null and pflow.get_child_count() > 0)
	var names := PackedStringArray()
	for c in pflow.get_children():
		names.append(_cell_name(c))
	_chk("主角关系列相识者", Game.npc_name(rand_key) in names and Game.npc_name(rand_key2) in names)
	_chk("主角关系不列未相逢者", not (Game.npc_name(unmet_key) in names))
	_chk("主角关系按好感从深到浅", names.find(Game.npc_name(rand_key)) < names.find(Game.npc_name(rand_key2)))

	# ⑤ 点主角关系区里的 NPC 格 → 跳回该 NPC 详情
	var jump: Node = null
	for c in pflow.get_children():
		if _cell_name(c) == Game.npc_name(rand_key):
			jump = c
			break
	if jump == null:
		_chk("点主角关系格跳回NPC详情(找到格)", false)
	else:
		_cell_hit(jump).pressed.emit()
		_chk("点主角关系格跳回NPC详情", scr._open_key == rand_key and scr._detail != null)

	# ⑥ 整页重建(如月末变更)后还原主角详情弹层
	scr._open_key = scr.PLAYER_KEY
	scr._rebuild()
	await get_tree().process_frame
	_chk("重建后还原主角详情", scr._open_key == scr.PLAYER_KEY and scr._detail != null)

	scr._close_detail()
	print("PLAYER_RELATION " + ("PASS" if _fails == 0 else "FAIL(%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)
