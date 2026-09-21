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
	# 派系先验: 同派系更易相识(占比远超均匀随机的 1/8≈0.125, 下界取 0.3 抗抽样波动),
	# 且同派系边更亲近(同派系进 rel_close_min 亲近带的比例高于跨派系)。
	var close_min := float(Game.tune("rel_close_min", 35.0))
	var same_n := 0
	var cross_n := 0
	var same_close := 0
	var cross_close := 0
	for e in rels:
		var fa := Game._npc_faction(String(e.get("a", "")))
		var fb := Game._npc_faction(String(e.get("b", "")))
		var v := float(e.get("val", 0.0))
		var same := fa != "" and fa == fb
		if same:
			same_n += 1
			if v >= close_min:
				same_close += 1
		elif fa != "" and fb != "":
			cross_n += 1
			if v >= close_min:
				cross_close += 1
	print("  FACTION same=%d cross=%d same_close=%d cross_close=%d" % [same_n, cross_n, same_close, cross_close])
	_chk("同派系边明显更多", float(same_n) / float(rels.size()) > 0.3)
	_chk("跨派系缘分仍存在", cross_n > 0)
	_chk("同派系更亲近", same_close * cross_n > cross_close * same_n)
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
	# 开局夫妻: 世界池随机婚配存在, 且婚配边高亲疏、展示 tag 覆盖为夫妻
	var rom0: Dictionary = Game.run.get("npc_romance", {})
	var couples := 0
	var couple_ok := true
	for pk2 in rom0:
		var r2: Dictionary = rom0[pk2]
		if not bool(r2.get("married", false)):
			continue
		couples += 1
		var seg2: PackedStringArray = String(pk2).split("|")
		var rel2: Dictionary = Game.relation_between(String(seg2[0]), String(seg2[1]))
		if float(rel2.get("val", 0.0)) < 60.0 or String(rel2.get("tag", "")) != "夫妻":
			print("  COUPLE BAD pk=", pk2, " rel=", rel2)
			couple_ok = false
	_chk("开局有夫妻", couples >= 1)
	_chk("夫妻边高亲疏且显示夫妻", couple_ok)
	# 友情值按月漂移: 只动动态边、亲子不动、带内不越 0
	var before_vals: Array = []
	for e in Game.run.world_rels:
		before_vals.append([String(e.get("tag", "")), float(e.get("val", 0.0))])
	for _d in 80:
		Game._friendship_drift()
	var moved := 0
	var drift_ok := true
	for i in Game.run.world_rels.size():
		var e2: Dictionary = Game.run.world_rels[i]
		var v: float = float(e2.get("val", 0.0))
		var v0: float = float(before_vals[i][1])
		if String(before_vals[i][0]) == "亲子":
			if v != v0:
				print("  DRIFT BAD 亲子动了 idx=", i, " v0=", v0, " v=", v)
				drift_ok = false
		else:
			if v != v0:
				moved += 1
			if v < -100.0 or v > 100.0:
				print("  DRIFT BAD 越界 idx=", i, " v0=", v0, " v=", v)
				drift_ok = false
			if v0 > 0.0 and v < 0.0:
				print("  DRIFT BAD 越0(正→负) idx=", i, " v0=", v0, " v=", v)
				drift_ok = false   # 淡出止于陌生
			if v0 < 0.0 and v > 0.0:
				print("  DRIFT BAD 越0(负→正) idx=", i, " v0=", v0, " v=", v)
				drift_ok = false   # 和解止于陌生
	_chk("友情值随岁月变动", moved > 0)
	_chk("漂移不越界不越0亲子不动", drift_ok)
	# 情面: 给已入册的 jianshu 刷满好感, 确定性造一条 jianshu↔池内人 的正边 → 入册应带初见好感
	Game.run.npcs["jianshu"].aff = 1000.0
	var pool_keys: Array = pool.keys()
	var k := ""
	for pk3 in pool_keys:   # 挑与 jianshu 尚无边的池内人: 保底连线可能已占首键, relation_between 先命中先赢
		var clash := false
		for e in Game.run.world_rels:
			if (String(e.get("a", "")) == "jianshu" and String(e.get("b", "")) == String(pk3)) or (String(e.get("b", "")) == "jianshu" and String(e.get("a", "")) == String(pk3)):
				clash = true
				break
		if not clash:
			k = String(pk3)
			break
	if k == "":
		k = String(pool_keys[0])
	Game.run.world_rels.append({"a": "jianshu", "b": k, "tag": "酒友", "val": 60.0, "note": "冒烟造边。"})
	Game._enroll_pool_npc(k)
	_chk("入册且带情面好感", Game.run.npcs.has(k) and bool(Game.run.npcs[k].met) and float(Game.run.npcs[k].aff) > 0.0)
	_chk("入册后移出池", not pool.has(k))
	# 双轨守卫: 情值仅异性可涨 —— 同性 love 恒 0, 恋爱类行为自动落回友情轨
	var aff_b := float(Game.run.npcs[k].aff)
	Game._bump_aff(k, 100.0, "love")
	var lve := float(Game.run.npcs[k].get("love", 0.0))
	if Game.npc_male(k):
		_chk("情值仅异性可涨", lve > 0.0 and absf(float(Game.run.npcs[k].aff) - aff_b) < 1e-4)
	else:
		_chk("情值仅异性可涨", lve == 0.0 and float(Game.run.npcs[k].aff) > aff_b)
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
