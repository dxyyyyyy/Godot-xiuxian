extends Node
## 世界 NPC 池回归冒烟: 50人池+动态关系边全链路(池/边/入册/情面/再遇/老档迁移/新固定NPC进网)。
## ⚠ 会 Game.new_game() 清档重写 user:// 存档 —— 跑前先备份存档目录, 跑完还原。

var _fails := 0


func _chk(name: String, ok: bool) -> void:
	print(("PASS: " if ok else "FAIL: ") + name)
	if not ok:
		_fails += 1


func _ready() -> void:
	Game.new_game()
	var pool: Dictionary = Game.run.world_npcs
	var rels: Array = Game.run.world_rels
	_chk("池=50", pool.size() == 50)
	_chk("边数≥50", rels.size() >= 50)
	var fixed_keys := {}
	for nd in DataManager.npcs:
		fixed_keys[String(nd.key)] = true
	var bad_ep := 0
	var dupes := 0
	var seen := {}
	for e in rels:
		var a := String(e.get("a", "")); var b := String(e.get("b", ""))
		if not (pool.has(a) or fixed_keys.has(a)) or not (pool.has(b) or fixed_keys.has(b)):
			bad_ep += 1
		var pair := a + "|" + b if a < b else b + "|" + a
		if seen.has(pair):
			dupes += 1
		seen[pair] = true
	_chk("边端点都存在", bad_ep == 0)
	_chk("无重复边", dupes == 0)
	_chk("池不进名录", pool.keys().filter(func(k): return Game.run.npcs.has(String(k))).is_empty())
	_chk("边有 tag 与 note", not String(rels[0].get("tag", "")).is_empty() and String(rels[0].get("note", "")).length() > 4)
	var e0: Dictionary = rels[0]
	_chk("relation_between 命中动态边", not Game.relation_between(String(e0.a), String(e0.b)).is_empty())
	# 反向查表不得把查询者自己当 peer(2026-09-20 修: 关系区曾显示自己)
	var self_leak := false
	for probe in ["jianshu", String(rels[0].get("a", "")), String(rels[0].get("b", ""))]:
		for r in Game.npc_relations(String(probe)):
			if String(r.get("peer", "")) == String(probe):
				self_leak = true
	_chk("关系表无自指", not self_leak)
	# 情面: 给已入册的 jianshu 刷满好感, 确定性造一条 jianshu↔池内人 的正边 → 入册应带初见好感
	Game.run.npcs["jianshu"].aff = 1000.0
	var pool_keys: Array = pool.keys()
	var k := String(pool_keys[0])
	Game.run.world_rels.append({"a": "jianshu", "b": k, "tag": "酒友", "val": 60.0, "note": "冒烟造边。"})
	Game._enroll_pool_npc(k)
	_chk("入册且带情面好感", Game.run.npcs.has(k) and bool(Game.run.npcs[k].met) and float(Game.run.npcs[k].aff) > 0.0)
	_chk("入册后移出池", not pool.has(k))
	var pk := Game._pick_pool_npc()
	_chk("抽人非空", pk != "" and pool.has(pk))
	_chk("抽人不删池", Game._pick_pool_npc() != "" and pool.size() == 49)
	# 老档迁移: 抹掉池键 → _ensure_run 补回
	Game.run.erase("world_npcs")
	Game.run.erase("world_rels")
	Game._ensure_run()
	_chk("老档补池", Game.run.world_npcs.size() == 50 and Game.run.world_rels.size() >= 50)
	# 未来固定 NPC(掌门): 新世自动进网
	DataManager.npcs.append({"key": "testzhang", "name": "测试掌门", "identity": "jianpai", "enrolled": "meet"})
	Game.new_game()
	var touches := false
	for e in Game.run.world_rels:
		if String(e.get("a", "")) == "testzhang" or String(e.get("b", "")) == "testzhang":
			touches = true
			break
	_chk("新固定NPC自动进关系网", touches)
	DataManager.npcs.pop_back()
	print("WORLD_POOL_SMOKE %s" % ("PASS" if _fails == 0 else "FAIL(%d)" % _fails))
	get_tree().quit()
