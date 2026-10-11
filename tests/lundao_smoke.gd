extends Node
## 大比论道 + 名望冒烟(GDD §3.2 第 7 方案 / 8.4 §12): 方案注册/十年一届大会/deterministic 静默结算/
## 名望三源(大比+司膳+话本帖)/老档兜底/照壁补帖与事件帖/名望 App 渲染。
## ⚠ 会 new_game() 清档 —— 经 tools/run_tests.sh 隔离跑。

var _fails := 0

func _chk(name: String, ok: bool) -> void:
	print(("PASS: " if ok else "FAIL: ") + name)
	if not ok:
		_fails += 1

func _goto(year: int, month: int) -> void:
	# 直接拨钟到指定年月(年=1 起): age_m = START_AGE_M + (年-1)*12 + (月-1), tick 后落在下一个月初 —— 故回拨一月
	Game.run.age_m = Game.START_AGE_M + (year - 1) * 12 + (month - 1) - 1

func _wall_ids() -> Dictionary:
	var ids := {}
	for p in (Game.run.wall.posts as Array):
		ids[String((p as Dictionary).get("id", ""))] = true
	return ids

func _ready() -> void:
	const TG := preload("res://tests/test_guard.gd")
	if not TG.ensure_isolated("LUNDAO_SMOKE"):
		get_tree().quit(2)
		return
	Game.debug_seed(11)
	Game.new_game()

	# ═══ 1. 数据完整性 ═══
	var lundao_plan := {}
	for p in DataManager.plans:
		if String(p.get("id", "")) == "lundao":
			lundao_plan = p
	_chk("1a plans.json 第 7 方案 lundao ×0.8", not lundao_plan.is_empty() and float(lundao_plan.get("mult", 0)) == 0.8)
	var fac_ids := {}
	var fac_ok := DataManager.factions.size() == 9
	for f in DataManager.factions:
		var fid := String(f.get("id", ""))
		fac_ids[fid] = true
		if fid == "" or String(f.get("name", "")) == "" or String(f.get("taste", "")) == "" or String(f.get("seat", "")) == "":
			fac_ok = false
	for fid in ["baimenzong", "xianmeng", "tongming", "jianpai", "yoududao", "shanshen", "huizu", "wenmai", "fangshi"]:
		if not fac_ids.has(fid):
			fac_ok = false
	_chk("1b factions.json 九家齐且档案字段全", fac_ok)
	var wall_by_id := {}
	var rotate_factions := {}
	for w in DataManager.wall:
		wall_by_id[String(w.get("id", ""))] = w
		var t: Dictionary = w.get("trigger", {})
		if String(t.get("type", "")) == "faction_rotate" and String(t.get("faction", "")) != "":
			rotate_factions[String(t.get("faction", ""))] = true
	var rotate_needed := ["tongming", "jianpai", "xianmeng", "yoududao", "shanshen", "huizu", "wenmai", "fangshi"]
	var covered := true
	for rf in rotate_needed:
		if not rotate_factions.has(rf):
			covered = false
	_chk("1c 照壁 55 帖且势力轮换池覆盖八家外围势力", DataManager.wall.size() == 55 and covered)
	var ev_ok := true
	for ev in ["lundao_win", "lundao_up", "lundao_misc", "huaben"]:
		var found := false
		for w in DataManager.wall:
			var t2: Dictionary = w.get("trigger", {})
			if String(t2.get("type", "")) == "event" and String(t2.get("event", "")) == ev:
				found = true
		if not found:
			ev_ok = false
	_chk("1d 大会三帖+话本帖事件钩齐", ev_ok)

	# ═══ 2. 方案切换与备赛 ═══
	Game.set_plan("lundao")
	_chk("2a 方案可切换且倍率 0.8", String(Game.run.plan) == "lundao" and absf(Game.plan_mult() - 0.8) < 0.001)
	var aff_sum0 := 0.0
	for k in Game.run.npcs:
		if bool(Game.run.npcs[k].get("met", false)):
			aff_sum0 += float(Game.run.npcs[k].get("aff", 0.0))
	var spar_fired := false
	for _i in 30:
		Game._lundao_plan_tick()
		var aff_sum1 := 0.0
		for k2 in Game.run.npcs:
			if bool(Game.run.npcs[k2].get("met", false)):
				aff_sum1 += float(Game.run.npcs[k2].get("aff", 0.0))
		if aff_sum1 > aff_sum0:
			spar_fired = true
			break
	_chk("2b 备赛切磋: 在册 NPC 好感落账(开局在册仅季忘川)", spar_fired)

	# ═══ 3. 非大会年 9 月不触发 ═══
	Game.new_game()
	Game.set_plan("lundao")
	Game.deterministic = true
	_goto(3, 9)
	Game.tick_month()
	_chk("3a 第 3 年 9 月无大会(lundao.last 未动)", Game.pending.is_empty() and int(Game.run.lundao.get("last", -1)) == -1)
	Game.new_game()
	Game.set_plan("travel")
	_goto(10, 9)
	Game.tick_month()
	_chk("3b 大比年但非大比方案: 不赴会", Game.pending.is_empty() and int(Game.run.lundao.get("last", -1)) == -1)

	# ═══ 4. 大会年 9 月: deterministic 静默结算一届 ═══
	Game.new_game()
	Game.set_plan("lundao")
	Game.deterministic = true
	Game.run.farm.dishes = {"suchaochunjiu": 2}   # 带菜候选(低阶)
	_goto(10, 9)
	Game.tick_month()
	_chk("4a 届月自动结算(deterministic 首选项=带菜)", Game.pending.is_empty() and int(Game.run.lundao.get("last", -1)) == 10)
	_chk("4b 名望落账且 best∈1..3", int(Game.run.get("repute", 0)) > 0 and int(Game.run.lundao.get("best", 0)) >= 1 and int(Game.run.lundao.get("best", 0)) <= 3)
	var rep4 := int(Game.run.get("repute", 0))
	_chk("4c 名望流水留档", not (Game.run.get("repute_log", []) as Array).is_empty())
	_goto(10, 10)
	var lundao_post := false
	for _i in 3:
		Game.tick_month()
		var ids4 := _wall_ids()
		if ids4.has("wall_053") or ids4.has("wall_054") or ids4.has("wall_055"):
			lundao_post = true
			break
	_chk("4d 大会结果帖次月上壁(队列 FIFO 容忍同月世界帖)", lundao_post)
	_goto(20, 9)
	Game.tick_month()
	_chk("4e 下届(第 20 年)再开且再结算", int(Game.run.lundao.get("last", -1)) == 20 and int(Game.run.get("repute", 0)) > rep4)
	Game.deterministic = false

	# ═══ 5. 名望三源: 司膳好评 + 话本帖(§10.2 门槛) ═══
	Game.new_game()
	Game.set_plan("cook")
	Game.run.farm.dishes = {"huanyangxianyan": 1}
	Game.run.farm.cook = 1
	_goto(2, 9)
	Game.tick_month()
	var rep5 := int(Game.run.get("repute", 0))
	_chk("5a 司膳好评: 库房有菜 9 月 +1(无方案门槛)", rep5 == int(Game.tune("lundao_shishan_repute", 1)) and int(Game.run.get("shishan_last", 0)) == 2)
	_goto(4, 9)
	Game.tick_month()
	_chk("5b 司膳一年一评不重复", int(Game.run.get("repute", 0)) == rep5 + int(Game.tune("lundao_shishan_repute", 1)))
	Game._add_repute(int(Game.tune("repute_huaben", 20)), "测试直加")
	var queued := false
	for q in (Game.run.wall.queue as Array):
		if String((q as Dictionary).get("ev", "")) == "huaben":
			queued = true
	_chk("5c 名望破 20 入话本帖队列", queued)
	var huaben_post := false
	for _i in 3:
		Game.tick_month()
		if _wall_ids().has("wall_056"):
			huaben_post = true
			break
	_chk("5d 话本帖(wall_056)上壁(队列 FIFO 容忍同月世界帖)", huaben_post)

	# ═══ 6. 带菜候选: 高阶优先 ═══
	Game.run.farm.dishes = {"suchaochunjiu": 1, "huanyangxianyan": 1}
	Game.debug_seed(3)
	var dish: Dictionary = Game._lundao_best_dish()
	_chk("6a 带菜择优取高阶", String(dish.get("id", "")) == "huanyangxianyan")
	Game.run.farm.dishes = {}
	_chk("6b 空库返回空(只留空手项)", Game._lundao_best_dish().is_empty())

	# ═══ 7. 老档兜底(不 bump SCHEMA) ═══
	Game.run.erase("lundao")
	Game.run.erase("repute")
	Game.run.erase("repute_log")
	Game.run.erase("shishan_last")
	Game._ensure_run()
	_chk("7a 老档补齐 lundao/repute/shishan 账本", Game.run.has("lundao") and int(Game.run.lundao.get("last", -9)) == -1 and int(Game.run.get("repute", -9)) == 0 and Game.run.has("shishan_last"))

	# ═══ 8. 名望 App headless 渲染 ═══
	Game.new_game()
	Game._add_repute(7, "测试流水")
	var ui := Control.new()
	ui.set_script(load("res://scripts/apps/app_repute.gd"))
	add_child(ui)
	await get_tree().process_frame
	await get_tree().process_frame
	var labels := _collect_labels(ui)
	var joined := "\n".join(labels)
	_chk("8a 名望 App: 值+流水+话本门槛线", joined.contains("名望流水") and joined.contains("测试流水") and joined.contains("仙盟官账"))
	var fac_all := true
	for fname in ["百味宗", "扶摇仙盟", "通明宫", "掬霜剑派", "幽都道", "山君神系", "青丘狐族", "文脉", "青梧城坊市"]:
		if not joined.contains(fname):
			fac_all = false
	_chk("8b 九家势力档案卡全部渲染(点名只在名望 App)", fac_all and joined.contains("大比戏台"))
	ui.queue_free()

	print("LUNDAO_SMOKE %s" % ("PASS" if _fails == 0 else "FAIL(%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)

func _collect_labels(node: Node) -> Array:
	var out: Array = []
	if node == null or not is_instance_valid(node):
		return out
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
			if c is Label:
				out.append((c as Label).text)
	return out
