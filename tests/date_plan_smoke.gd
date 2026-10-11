extends Node
## 十四景约会·方案执行端到端冒烟: 真跑一次 romance 方案的约会月(不 new_game 不写档) ——
## 验证选景月报主行、与会者差分行、撞破月报与壁帖队列的 {scene} 替换源、约会冷却重置。
## (选景门控/偏好的纯函数校验在 date_scene_smoke; 本档守住 Game._execute_plan 的 romance 接线。)

var _fails := 0

func _chk(name: String, ok: bool) -> void:
	print(("PASS: " if ok else "FAIL: ") + name)
	if not ok:
		_fails += 1

func _ready() -> void:
	Game.set_process(false)   # 停时钟: 无 tick、无自动存盘
	Game.debug_seed(4242)
	Game.run = Game.run.duplicate(true)
	# 合成三名心动段男性 NPC(1 专注 + 2 随好感补足)
	var gen := Game.npc_generator
	for i in range(3):
		var e := Game._npc_init()
		e.merge(gen.generate(Game.rng, Game.run.npcs, ["fangshi", "tongming"]), true)
		e.met = true
		e.gender = "male"
		e.stage = 3
		e.love = 610.0 + 10.0 * (2 - i)
		Game.run.npcs[String(e.key)] = e
		Game._npc_vitals_backfill(e, String(e.key))
	Game.run.plan = "romance"
	Game.run.date_cd = 1
	# 待客庭院拉满(3 级=4 名额) → 验证多人同景与差分行
	Game.run.facilities = {"julingzhen": 0, "lingquan": 0, "cangjingge": 0, "daiketingyuan": 3}
	DataManager.economy["date_found_rate"] = 1.0   # 强制撞破 → 验证火葬场月报与壁帖 {scene} 占位
	var notes_before: int = Game.month_notes.size()
	Game._execute_plan()
	var new_notes := []
	for i in range(notes_before, Game.month_notes.size()):
		new_notes.append(String(Game.month_notes[i]))
	var main_line := ""
	for n in new_notes:
		if n.begins_with("同游「"):
			main_line = n
	_chk("月报含『同游「景名」』主行", main_line != "")
	var scn_id := ""
	if main_line != "":
		var nm: String = main_line.substr(3, main_line.find("」") - 3)
		for s in DataManager.date_scenes:
			if String(s.name) == nm:
				scn_id = String(s.id)
	_chk("景名可在十四景表中找到(%s)" % scn_id, scn_id != "")
	# 差分行从「同游」主行后起算: 交谈台词(chat_texts)同用 "—— " 前缀且先于约会段入报, 不属约会差分
	var flavor := []
	var in_date := false
	for n in new_notes:
		if n.begins_with("同游「"):
			in_date = true
			continue
		if in_date and n.begins_with("—— "):
			flavor.append(n)
	_chk("每位与会者各一条差分行(3 人)", flavor.size() == 3)
	var clean := true
	for n in new_notes:
		if n.contains("{"):
			clean = false
	_chk("月报无残留占位符", clean)
	_chk("约会冷却重置=3", int(Game.run.date_cd) == 3)
	var found_line := ""
	for n in new_notes:
		if n.contains("火葬场了"):
			found_line = n
	_chk("撞破月报带景名", found_line.contains("「") and found_line.contains("火葬场了"))
	var q := (Game.run.wall.get("queue", []) as Array)
	var last: Dictionary = q[q.size() - 1] if q.size() > 0 else {}
	_chk("壁帖队列带 {scene} 替换源", String(last.get("ev", "")) == "huozangchang" and String((last.get("sub", {}) as Dictionary).get("scene", "")) != "")
	print("DATE_PLAN_SMOKE %s" % ("PASS" if _fails == 0 else "FAIL(%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)
