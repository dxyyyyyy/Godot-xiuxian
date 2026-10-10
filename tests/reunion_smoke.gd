extends Node
## 魂印跨世重逢冒烟: 快照落盘/转世体入池/优先抽脸/三档认出/H08 三选/迟来对视/迟疑甜补/开局特例/旧档兼容。
## ⚠ 会 new_game() 清档重写 user:// —— 经 tools/run_tests.sh 隔离跑。

var _fails := 0
var _logs: Array = []

func _chk(name: String, ok: bool) -> void:
	print(("PASS: " if ok else "FAIL: ") + name)
	if not ok:
		_fails += 1

func _on_logged(t: String, _d: String) -> void:
	_logs.append(t)


func _ready() -> void:
	const TG := preload("res://tests/test_guard.gd")
	if not TG.ensure_isolated("REUNION_SMOKE"):
		get_tree().quit(2)
		return
	Game.debug_seed(7)
	Game.logged.connect(_on_logged)

	# ═══ A. 固定 NPC 烙印: 快照落 meta.seals, _ending 盖 end_kind ═══
	Game.new_game()
	Game._first_meet("yaoshi", "冒烟入册")
	Game.run.npcs["yaoshi"].hidden = 8000.0
	Game.pending = {"title": "t", "text": "", "options": [{"t": "烙印"}, {"t": "不"}], "kind": "seal", "data": {"key": "yaoshi"}}
	Game.resolve_option(0)
	var seals: Array = Game.meta.get("seals", [])
	_chk("A1 烙印写快照(fixed=yaoshi)", seals.size() == 1 and String(seals[0].get("fixed", "")) == "yaoshi")
	_chk("A2 快照带身份字段", String(seals[0].get("name", "")) == "温半夏" and String(seals[0].get("gender", "")) == "male" and float(seals[0].get("hidden", 0.0)) == 8000.0)
	Game._ending("飞升")
	_chk("A3 结局盖章 end_kind", String(seals[0].get("end_kind", "")) == "飞升")
	_chk("A4 强度=隐藏×飞升1.0", absf(Game._seal_strength(seals[0]) - 8000.0) < 1e-4)
	# 转世: 固定者不做转世体(人本在世)
	Game.rebirth({}, 0, 0)
	var marks_a := 0
	for k in Game.run.world_npcs:
		if bool((Game.run.world_npcs[k] as Dictionary).get("soulmark", false)):
			marks_a += 1
	_chk("A5 固定烙印不造转世体", marks_a == 0)
	_chk("A6 强度分档 tier2(8000>6600)", Game._seal_tier(8000.0) == 2 and Game._seal_tier(5000.0) == 1 and Game._seal_tier(1000.0) == 0)

	# ═══ B. 随机人烙印 → 转世体入池 → 优先抽出 → a 唤醒全额保留 ═══
	Game.debug_seed(11)
	var pk := Game._pick_pool_npc()
	Game._enroll_pool_npc(pk)
	var old_name := String(Game.run.npcs[pk].get("name", ""))
	var old_identity := String(Game.run.npcs[pk].get("identity", ""))
	Game.run.npcs[pk].hidden = 4000.0
	Game.pending = {"title": "t", "text": "", "options": [{"t": "烙印"}, {"t": "不"}], "kind": "seal", "data": {"key": pk}}
	Game.resolve_option(0)
	Game._ending("圆满隐退")
	var rec_b: Dictionary = (Game.meta.get("seals", []) as Array).back()
	_chk("B1 隐退继承率强度=3200", absf(Game._seal_strength(rec_b) - 3200.0) < 1e-4)
	Game.rebirth({}, 0, 0)
	var reborn_key := ""
	var reborn: Dictionary = {}
	for k in Game.run.world_npcs:
		var e: Dictionary = Game.run.world_npcs[k]
		if bool(e.get("soulmark", false)):
			reborn_key = String(k)
			reborn = e
	_chk("B2 转世体入池", reborn_key != "")
	_chk("B3 同名同 identity(性别随魂)", String(reborn.get("name", "")) == old_name and String(reborn.get("identity", "")) == old_identity and String(reborn.get("gender", "")) == String(rec_b.get("gender", "male")))
	_chk("B4 抽池优先印脸", Game._pick_pool_npc() == reborn_key)
	var chance0 = Game.tune("reunion_month_chance", 0.06)
	DataManager.tuning["reunion_month_chance"] = 1.0
	Game._reunion_tick()
	_chk("B5 H08 擦肩弹窗 kind=reunion", Game.pending.get("kind", "") == "reunion")
	Game.resolve_option(0)   # a 唤住
	_chk("B6 a 唤醒入册且情深许保留", Game.run.npcs.has(reborn_key) and absf(float(Game.run.npcs[reborn_key].aff) - 1000.0) < 1e-4 and int(Game.run.npcs[reborn_key].stage) == 4)
	_chk("B7 唤醒上照壁队列", (Game.run.wall.queue as Array).any(func(q): return String(q.get("ev", "")) == "reunion"))
	_logs.clear()
	DataManager.tuning["reunion_month_chance"] = chance0

	# ═══ C. b 迟来对视 → 档一演出+升档旗; c 迟疑 → 甜补不崩 ═══
	Game.debug_seed(23)
	Game.rebirth({}, 0, 0)   # 上世烙印已寻回复位? reunion 标记随世消亡, 转世体再生(印记每世投胎)
	reborn_key = ""
	for k in Game.run.world_npcs:
		if bool((Game.run.world_npcs[k] as Dictionary).get("soulmark", false)):
			reborn_key = String(k)
	if reborn_key == "":
		_chk("C0 转世体每世投胎", false)
	else:
		DataManager.tuning["reunion_month_chance"] = 1.0
		Game._reunion_tick()
		Game.resolve_option(1)   # b 远望
		_chk("C1 b 留池挂迟来回视", Game.run.world_npcs.has(reborn_key) and bool((Game.run.world_npcs[reborn_key] as Dictionary).get("reunion_wait", false)))
		Game._enroll_pool_npc(reborn_key)
		var npc_c: Dictionary = Game.run.npcs[reborn_key]
		_chk("C2 迟来者先演档一并留升档旗", bool(npc_c.get("reunion", false)) and int(npc_c.get("reunion_tier", -1)) == 0 and bool(npc_c.get("reunion_upgrade", false)) and absf(float(npc_c.aff) - 1000.0) < 1e-4)
		var chance1 = DataManager.tuning["reunion_month_chance"]
		DataManager.tuning["reunion_month_chance"] = 1.0
		Game._reunion_tick()   # 池里已无 mark → 不再弹(候选检查兜空)
		_chk("C3 无候选不弹框", String(Game.pending.get("kind", "")) != "reunion")
		DataManager.tuning["reunion_month_chance"] = chance1

	# ═══ D. 季忘川(开局在册)带旧印 → 首月 opening 演出 ═══
	Game.debug_seed(31)
	Game.new_game()
	Game.meta.bonds = int(Game.meta.get("bonds", 0)) + 1
	if not Game.meta.has("seals"):
		Game.meta.seals = []
	(Game.meta.seals as Array).append({"name": "季忘川", "gender": "male", "identity": "baimenzong", "persona": {}, "moe": "", "appearance": {}, "taste_base": "", "taste_final": "", "hidden": 9000.0, "seal_life": 0, "end_kind": "渡劫陨落", "fixed": "jianshu"})
	Game.rebirth({}, 0, 0)
	_chk("D1 开局挂 reunion_pending", bool(Game.run.npcs.jianshu.get("reunion_pending", false)))
	_logs.clear()
	Game.deterministic = true
	Game.tick_month()
	Game.deterministic = false
	_chk("D2 首月认出(剑先认出 opening)", bool(Game.run.npcs.jianshu.get("reunion", false)) and _logs.any(func(s): return s.contains("上一次见你")))
	_chk("D3 陨落后强度 4500→档一但演出走 opening", Game._seal_tier(9000.0 * 0.5) == 1)

	# ═══ E. 旧档兼容: bonds>0 无 seals → 不转世不崩 ═══
	Game.new_game()
	Game.meta.bonds = 3
	Game.meta.erase("seals")
	Game.deterministic = true
	Game.tick_month()
	Game.deterministic = false
	var marks_e := 0
	for k in Game.run.world_npcs:
		if bool((Game.run.world_npcs[k] as Dictionary).get("soulmark", false)):
			marks_e += 1
	_chk("E1 旧 bonds 无快照=降级纪念不转世", marks_e == 0 and Game.run.get("npcs", {}).size() >= 1)
	# 重逢实装前印记者不报错, 三生石名录空态不画行
	_chk("E2 seals 空读安全", (Game.meta.get("seals", []) as Array).is_empty())

	# ═══ F. 三生石名录非空路径: 渲染不崩且含历世烙印者行 ═══
	Game.meta.seals = [{"name": "温半夏", "gender": "male", "identity": "fangshi", "persona": {}, "moe": "", "appearance": {}, "taste_base": "", "taste_final": "", "hidden": 7000.0, "seal_life": 1, "end_kind": "飞升", "fixed": "yaoshi"}]
	GameState.fresh_start = true
	var stone := Control.new()
	stone.set_script(load("res://scripts/apps/app_lifestone.gd"))
	add_child(stone)
	await get_tree().process_frame
	await get_tree().process_frame
	var has_row := false
	for l in stone.find_children("*", "Label", true, false):
		if String((l as Label).text).contains("温半夏"):
			has_row = true
	_chk("F1 三生石名录含烙印者行(强度7000·飞升)", has_row)
	GameState.fresh_start = false

	print("REUNION_SMOKE %s" % ("PASS" if _fails == 0 else "FAIL(%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)
