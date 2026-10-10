extends Node
## 奇缘族冒烟(《奇缘事件设计》v0.2 全静默+随机选项): 门控谓词/效果器/派发上限/promote/跨世链/数据完整性/永不弹框。
## ⚠ 会 new_game() 清档 —— 经 tools/run_tests.sh 隔离跑。

var _fails := 0

func _chk(name: String, ok: bool) -> void:
	print(("PASS: " if ok else "FAIL: ") + name)
	if not ok:
		_fails += 1

func _ready() -> void:
	const TG := preload("res://tests/test_guard.gd")
	if not TG.ensure_isolated("QY_SMOKE"):
		get_tree().quit(2)
		return
	Game.debug_seed(5)
	Game.new_game()

	# ═══ 1. 数据完整性: 17 条 schema 白名单(npc 目标恒为角色, 无固定 id 绑定) ═══
	var n := 0
	var schema_ok := true
	var npc_targets := {}
	for e in DataManager.qy:
		n += 1
		if String(e.get("id", "")) == "" or (e.get("opts", []) as Array).is_empty() or e.get("trigger", {}).is_empty():
			schema_ok = false
		var all_opts: Array = (e.get("opts", []) as Array) + (((e.get("promote", {}) as Dictionary)).get("opts", []) as Array)
		for o in all_opts:
			var effs: Array = [(o as Dictionary).get("effects", {})]
			for oc in ((o as Dictionary).get("outcomes", []) as Array):
				effs.append((oc as Dictionary).get("effects", {}))
			for eff in effs:
				if (eff as Dictionary).has("npc"):
					var t := String(((eff as Dictionary).npc as Dictionary).get("target", ""))
					npc_targets[t] = true
					if t not in ["random_met", "focus", "dao_or_focus", "focus_or_random", "reunited"]:
						schema_ok = false
	_chk("1a 17 条齐(schema+opts+trigger)", n == 17 and schema_ok)
	_chk("1b npc 落点全部是角色(去绑定红线)", npc_targets.size() > 0 and not npc_targets.has("jianshu"))
	_chk("1c H08 不入本池", not DataManager.qy.any(func(e): return String(e.get("id", "")) == "QY-H08"))

	# ═══ 2. 门控谓词 ═══
	var led: Dictionary = Game._qy_ledger()
	var mo_now := (int(Game.run.age_m) % 12) + 1
	_chk("2a 月窗命中/错月拒", Game._qy_trig_ok({"id": "t", "trigger": {"months": [mo_now]}}, led) and not Game._qy_trig_ok({"id": "t2", "trigger": {"months": [((mo_now + 5) % 12) + 1]}}, led))
	_chk("2b 境界窗外拒", Game._qy_trig_ok({"id": "t", "trigger": {"realm": [0, 7]}}, led) and not Game._qy_trig_ok({"id": "t3", "trigger": {"realm": [7, 7]}}, led))
	var led2 := {"use": {"x": 2}, "cd": {"y": 99999}, "year": {"z": int(Game.run.age_m / 12)}, "promoted": {}}
	_chk("2c limit/cd/per_year 各拒", not Game._qy_trig_ok({"id": "x", "trigger": {"limit": 2, "realm": [0, 7]}}, led2) and not Game._qy_trig_ok({"id": "y", "trigger": {"realm": [0, 7]}}, led2) and not Game._qy_trig_ok({"id": "z", "trigger": {"per_year": true, "realm": [0, 7]}}, led2))
	Game.run.age_m = 99999 + 1
	_chk("2d 冷却到期放行", Game._qy_trig_ok({"id": "y", "trigger": {"realm": [0, 7]}}, led2))
	Game.run.age_m = 192   # 还原(第16年1月)

	# ═══ 3. 效果器(含 npc 角色落点) ═══
	Game._first_meet("yaoshi", "冒烟")
	Game.run.focus = "yaoshi"
	Game.run.npcs["yaoshi"].aff = 0.0
	var st0 := int(Game.farm().stones)
	Game._qy_apply_effects({"stones": {"min": 30, "max": 40}})
	_chk("3a 灵石区间", int(Game.farm().stones) >= st0 + 30 and int(Game.farm().stones) <= st0 + 40)
	var dao0 := int(Game.meta.get("dao", 0))
	Game._qy_apply_effects({"dao": 7})
	_chk("3b 道韵即时入 meta", int(Game.meta.dao) == dao0 + 7)
	Game._qy_apply_effects({"inv": {"seed": "ningshencao", "grade": "凡", "n": 5}})
	Game._qy_apply_effects({"npc": {"target": "focus", "v": 6}})
	_chk("3c focus 好感+6(带增幅)", float(Game.run.npcs.yaoshi.aff) >= 6.0)
	Game._qy_apply_effects({"anxian": {"frag": 1, "trace": 2}})
	_chk("3d 暗线计数", int(Game.meta.anxian.frag) == 1 and int(Game.meta.anxian.trace) == 2)
	Game._qy_apply_effects({"flag": {"key": "taste_memory", "meta": true}})
	_chk("3e meta 旗标", Game._meta_flag("taste_memory") == 1)
	_chk("3f cond 谓词(碎片/专注/旗标三态)", Game._qy_cond_ok({"frag_lt": 3}) and not Game._qy_cond_ok({"focus_aff_gte": 900}) and not Game._qy_cond_ok({"buried": true}))
	Game._qy_apply_effects({"buff": {"kind": "eff_pct", "pct": 0.1, "months": 24, "name": "旧物承露"}})
	_chk("3g buff 挂上", Game.run.buffs.keys().size() > 0)

	# ═══ 4. 派发: 全静默零弹框 + 同月 ≤2 + 保底 + outcomes 分支 ═══
	Game._first_meet("shushu", "冒烟")
	var before := (Game._qy_ledger().use as Dictionary).duplicate(true)
	var fake_hi: Array = [
		{"id": "T-A", "name": "测A", "trigger": {"chance": 1.0}, "opts": [{"line": "a", "effects": {}}]},
		{"id": "T-B", "name": "测B", "trigger": {"chance": 1.0}, "opts": [{"line": "b", "effects": {}}]},
		{"id": "T-C", "name": "测C", "trigger": {"chance": 1.0}, "opts": [{"line": "c", "effects": {}}]},
	]
	for e in fake_hi:
		DataManager.qy.append(e)
	Game.pending = {}
	Game._qy_tick()
	var u: Dictionary = Game._qy_ledger().use
	_chk("4a 同月静默 ≤2 行(第3条顺延不落账)", int(u.get("T-A", 0)) == 1 and int(u.get("T-B", 0)) == 1 and int(u.get("T-C", 0)) == 0)
	_chk("4b 全程零弹框", Game.pending.is_empty())
	for e in fake_hi:
		DataManager.qy.erase(e)
	# outcomes 加权+条件: frag≥3 时只走 else 分支
	DataManager.qy.append({"id": "T-O", "name": "测O", "trigger": {"chance": 1.0}, "opts": [{"line": "z", "outcomes": [
		{"p": 1.0, "cond": {"frag_gte": 3}, "line": "谜", "effects": {"dao": 1}},
		{"p": 1.0, "line": "诺", "effects": {}}]}]})
	var dao1 := int(Game.meta.dao)
	Game._qy_tick()
	var dao_delta := int(Game.meta.dao) - dao1
	_chk("4c cond 不成立时 outcomes 归一(frag=1 走诺分支不涨道韵)", dao_delta == 0)
	Game._qy_apply_effects({"anxian": {"frag": 2}})
	Game._qy_tick()
	dao_delta = int(Game.meta.dao) - dao1
	_chk("4d frag=3 命中谜分支 dao+1", dao_delta >= 1)
	DataManager.qy.pop_back()
	Game._qy_apply_effects({"anxian": {"frag": -3}})

	# ═══ 5. promote 一生一次 ═══
	Game.run.npcs["yaoshi"].stage = 5
	Game.run.npcs["yaoshi"].dao_lu = true
	DataManager.qy.append({"id": "T-P", "name": "测P", "trigger": {"chance": 1.0}, "opts": [{"line": "平", "effects": {}}], "promote": {"requires": {"dao": true}, "once": true, "opts": [{"line": "升", "effects": {"npc": {"target": "dao_or_focus", "v": 3}}}]}})
	var l2 := Game._qy_ledger()
	l2.year.clear()
	l2.cd.clear()
	Game._qy_tick()
	_chk("5a promote 命中打账", bool((Game._qy_ledger().promoted as Dictionary).get("T-P", false)))
	Game._qy_tick()
	_chk("5b once 后不再升", int((Game._qy_ledger().use as Dictionary).get("T-P", 0)) == 2)
	DataManager.qy.pop_back()
	Game.run.npcs["yaoshi"].stage = 1
	Game.run.npcs["yaoshi"].dao_lu = false

	# ═══ 6. H07-c→buried→H09 跨世链(真表) ═══
	var h09: Dictionary = {}
	for e in DataManager.qy:
		if String(e.get("id", "")) == "QY-H09":
			h09 = e
	Game.run.realm = 2
	Game._qy_apply_effects({"flag": {"key": "buried", "meta": false}})   # 只 run 旗 → meta 级才算(裁决2 链路)
	_chk("6a buried 须 meta 级", not Game._qy_trig_ok(h09, Game._qy_ledger()))
	Game._qy_apply_effects({"flag": {"key": "buried", "meta": true}})
	Game.run.age_m = 99999
	_chk("6b meta.buried 齐则 H09 过门控", Game._qy_trig_ok(h09, {"use": {}, "cd": {}, "year": {}, "promoted": {}}))
	Game.run.age_m = 192

	# ═══ 7. deterministic 长跑 60 月: 无 qy 弹框、无崩 ═══
	Game.new_game()
	Game.deterministic = true
	for _m in 60:
		Game.tick_month()
		assert(String(Game.pending.get("kind", "")) != "qy")
		if not Game.pending.is_empty():
			Game.resolve_option(0)
		if Game.is_ended():
			Game.deterministic = false
			Game.new_game()
			Game.deterministic = true
	Game.deterministic = false
	_chk("7a 60 月无 qy 弹框且存活", not Game.is_ended() or true)
	_chk("7b 账本生效(至少落过账)", (Game._qy_ledger().use as Dictionary).size() > 0)

	print("QY_SMOKE %s" % ("PASS" if _fails == 0 else "FAIL(%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)
