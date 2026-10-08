extends Node
const TestGuard := preload("res://tests/test_guard.gd")
## 转世命名冒烟(姓/名分栏): 转世沿用两字段; 新开一世回默认拆分;
## 三生石两栏预填/挂树/入世提交/皆空不修改/卡片再现身回读(脏标记竞态回归)。
## 安全: rebirth/_start_life/new_game 都会落盘 —— 本测必须配 APPDATA 隔离目录运行!

var _fails := 0


func _chk(name: String, ok: bool) -> void:
	print(("PASS: " if ok else "FAIL: ") + name)
	if not ok:
		_fails += 1


func _ready() -> void:
	if not TestGuard.ensure_isolated("REBIRTH_NAME_SMOKE"):
		get_tree().quit(2)
		return
	Game.set_process(false)
	# ① 转世沿用两字段
	Game.set_player_name_parts("陆", "朝餐")
	Game.rebirth({}, 0, 0)
	_chk("转世沿用姓", Game.player_surname() == "陆")
	_chk("转世沿用名", Game.player_given() == "朝餐")

	# ② 新开一世 → 回默认拆分
	Game.new_game()
	_chk("新开一世回默认", Game.player_name() == "沈知味")

	# ③ 三生石两栏: 预填默认 → 改名入世
	GameState.fresh_start = true
	var stone := Control.new()
	stone.set_script(load("res://scripts/apps/app_lifestone.gd"))
	add_child(stone)
	await get_tree().process_frame
	await get_tree().process_frame
	var se: LineEdit = stone.get("_sur_edit") as LineEdit
	var ge: LineEdit = stone.get("_giv_edit") as LineEdit
	_chk("三生石有姓/名输入框", se != null and ge != null)
	_chk("两框已挂进场景树", se != null and se.get_parent() != null and ge != null and ge.get_parent() != null)
	_chk("三生石预填默认姓/名", se != null and ge != null and String(se.text) == "沈" and String(ge.text) == "知味")
	if se != null and ge != null:
		se.text = "云"
		ge.text = "朝雨"
		se.text_changed.emit("云")   # 程序化赋值未必发信号, 补发保 pending/dirty 同步
		ge.text_changed.emit("朝雨")
		stone._enter_world()
		_chk("三生石命名入世", Game.player_name() == "云朝雨")

	# ④ 皆空提交=不修改; 死亡再现身回读当前姓/名
	stone._sur_pending = "  "
	stone._giv_pending = ""
	stone._enter_world()
	_chk("皆空提交不修改", Game.player_name() == "云朝雨")
	Game.run.ended = true
	Game.changed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var se2: LineEdit = stone.get("_sur_edit") as LineEdit
	var ge2: LineEdit = stone.get("_giv_edit") as LineEdit
	_chk("卡片再现身回读姓", se2 != null and String(se2.text) == "云")
	_chk("卡片再现身回读名", ge2 != null and String(ge2.text) == "朝雨")
	stone.queue_free()

	print("REBIRTH_NAME " + ("PASS" if _fails == 0 else "FAIL(%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)
