extends Node
## 主角名字冒烟(姓/名分栏): 默认 沈/知味; _ensure_run 老档拆分(单字段 name→首字姓+余名, 无则默认);
## set_player_name_parts 往返; 两栏皆空显示回退「主角」; 捏脸工坊两输入框预填+提交(皆空=不修改, 允许只填其一)。
## 安全: 不调 new_game/_start_life(会写盘!), 不碰真实存档 —— run 副本 + 停时钟。

var _fails := 0


func _chk(name: String, ok: bool) -> void:
	print(("PASS: " if ok else "FAIL: ") + name)
	if not ok:
		_fails += 1


func _ready() -> void:
	Game.set_process(false)   # 停时钟: 无 tick、无自动存盘
	Game.run = Game.run.duplicate(true)

	# ① 默认姓/名
	_chk("默认姓=沈", Game.DEFAULT_PLAYER_SURNAME == "沈")
	_chk("默认名=知味", Game.DEFAULT_PLAYER_GIVEN == "知味")

	# ② _ensure_run 老档拆分: 单字段 name=沈知味 → 姓沈/名知味
	Game.run.erase("surname")
	Game.run.erase("given")
	Game.run["name"] = "沈知味"
	Game._ensure_run()
	_chk("老档name拆姓首字", Game.player_surname() == "沈" and Game.player_given() == "知味")
	# 无 name 老档 → 默认
	Game.run.erase("surname")
	Game.run.erase("given")
	Game.run.erase("name")
	Game._ensure_run()
	_chk("无名老档补默认", Game.player_surname() == "沈" and Game.player_given() == "知味")

	# ③ set/get 往返
	Game.set_player_name_parts("顾", "知微")
	_chk("两栏往返", Game.player_name() == "顾知微")

	# ④ 两栏皆空 → 显示回退「主角」(directory_screen._player_display_name)
	Game.run.surname = ""
	Game.run.given = ""
	var scr := Control.new()
	scr.set_script(load("res://scripts/directory_screen.gd"))
	add_child(scr)
	await get_tree().process_frame
	_chk("空名回退主角", String(scr._player_display_name()) == "主角")
	Game.set_player_name_parts("沈", "知味")
	_chk("有名显示名", String(scr._player_display_name()) == "沈知味")
	scr.queue_free()
	await get_tree().process_frame

	# ⑤ 捏脸工坊: 姓/名两框预填当前姓/名; _commit 提交; 皆空=不修改; 只填名可提交
	var face := Control.new()
	face.set_script(load("res://scripts/apps/app_face.gd"))
	add_child(face)
	await get_tree().process_frame
	await get_tree().process_frame
	var se: LineEdit = face.get("_sur_edit") as LineEdit
	var ge: LineEdit = face.get("_giv_edit") as LineEdit
	_chk("捏脸有姓/名输入框", se != null and ge != null)
	_chk("两框已挂进场景树", se != null and se.get_parent() != null and ge != null and ge.get_parent() != null)
	_chk("两框预填当前姓/名", se != null and ge != null and String(se.text) == "沈" and String(ge.text) == "知味")
	if se != null and ge != null:
		se.text = "欧 阳"   # 半角空格应被实时剔除
		se.text_changed.emit("欧 阳")   # 程序化赋值不发信号(真实键入会发), 手动触发净化
		_chk("输入禁止空格", String(se.text) == "欧阳")
		se.text = "陆"
		ge.text = "朝餐"
		face._commit()
		_chk("提交落两字段", Game.player_name() == "陆朝餐")
		se.text = ""
		ge.text = "   "
		face._commit()
		_chk("两栏皆空不修改", Game.player_name() == "陆朝餐")
		se.text = ""
		ge.text = "单名"
		face._commit()
		_chk("只填名可提交", Game.player_name() == "单名")
	face.queue_free()

	print("FACE_NAME " + ("PASS" if _fails == 0 else "FAIL(%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)
