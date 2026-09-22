extends Node
## 名录派系折叠冒烟: 按 identity 分组/组内瓦片归属/标题计数/点标题收起/重建后保持折叠。
## 安全起见: 不调 new_game、不碰真实存档 —— 读档后在 Game.run 的副本上合成名册并停时钟。

var _fails := 0


func _chk(name: String, ok: bool) -> void:
	print(("PASS: " if ok else "FAIL: ") + name)
	if not ok:
		_fails += 1


func _ready() -> void:
	Game.set_process(false)   # 停时钟: 无 tick、无自动存盘
	Game.run = Game.run.duplicate(true)
	# 合成: 两个不同派系的随机入册者 + 一个未识固定骨架(莫休·有都道; 真实档里已有则跳过)
	var gen := Game.npc_generator
	for fid in ["fangshi", "tongming"]:
		var g: Dictionary = gen.generate(Game.rng, Game.run.npcs, [fid])
		var e := Game._npc_init()
		e.merge(g, true)
		e.met = true
		Game.run.npcs[String(e.key)] = e
	if not Game.run.npcs.has("moxiu"):
		Game.run.npcs["moxiu"] = {"met": false, "aff": 0.0, "love": 0.0, "hidden": 0.0, "stage": 0, "gate": 0, "talk_cd": 0, "gift_q": 0}

	var scr := Control.new()
	scr.set_script(load("res://scripts/directory_screen.gd"))
	add_child(scr)
	await get_tree().process_frame
	await get_tree().process_frame

	# —— 结构断言: 期望的分组(与页面同口径: 固定档案序 → rand 入册序) ——
	var ordered: Array = []
	for n in DataManager.npcs:
		var k := String(n.key)
		if Game.run.npcs.has(k):
			ordered.append(k)
	for k in Game.run.npcs:
		if String(k).begins_with("rand_"):
			ordered.append(String(k))
	var want_facs: Array = []
	var want_n := {}
	for k in ordered:
		var fac := String(Game._npc_faction(String(k)))
		if not want_n.has(fac):
			want_facs.append(fac)
			want_n[fac] = 0
		want_n[fac] += 1

	var secs: Array = []
	for c in scr._content.get_children():
		if c is PanelContainer:
			secs.append(c)
	_chk("区块数=派系数(%d)" % want_facs.size(), secs.size() == want_facs.size())
	var got_titles: Array = []
	var grids: Array = []
	for s in secs:
		var cv := ((s as PanelContainer).get_child(0) as MarginContainer).get_child(0) as VBoxContainer
		got_titles.append((cv.get_child(0).get_child(0) as HBoxContainer).get_child(0).text)
		grids.append(cv.get_child(1))
	var exp_titles: Array = []
	for fac in want_facs:
		exp_titles.append(scr._faction_title(String(fac)))
	_chk("组序=派系首现序", got_titles == exp_titles)
	var tiles_ok := true
	for i in secs.size():
		if (grids[i] as GridContainer).get_child_count() != int(want_n[want_facs[i]]):
			tiles_ok = false
	_chk("组内瓦片数=派系人数", tiles_ok)

	# —— 折叠交互: 收起任一带传闻的组, 再触发整页重建, 折叠须保持 ——
	var pick := 0
	for i in secs.size():
		if int(want_n[want_facs[i]]) > 1 or String(want_facs[i]) == "yoududao":
			pick = i
			break
	var head_btn := ((secs[pick] as PanelContainer).get_child(0) as MarginContainer).get_child(0).get_child(0) as Button
	_chk("收起前可见", grids[pick].visible)
	head_btn.pressed.emit()
	await get_tree().process_frame
	_chk("点标题可收起", not grids[pick].visible)
	Game.changed.emit()   # 模拟月末数据变更整页重建
	await get_tree().process_frame
	await get_tree().process_frame
	var secs2: Array = []
	for c in scr._content.get_children():
		if c is PanelContainer:
			secs2.append(c)
	_chk("重建后区块数不变", secs2.size() == secs.size())
	var g2 := ((secs2[pick] as PanelContainer).get_child(0) as MarginContainer).get_child(0).get_child(1)
	var g_other := ((secs2[(pick + 1) % secs2.size()] as PanelContainer).get_child(0) as MarginContainer).get_child(0).get_child(1)
	_chk("重建后折叠保持·他组展开", not g2.visible and g_other.visible)

	print("DIRECTORY_FOLD " + ("PASS" if _fails == 0 else "FAIL(%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)
