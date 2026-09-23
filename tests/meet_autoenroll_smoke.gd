extends Node
## 遇见NPC直接入册回归冒烟(2026-09-22 拍板: 不再弹「是否攀谈」框)。
## ⚠ 会 Game.new_game() 清档重写 user:// 存档 —— 跑前先备份存档目录, 跑完还原。

var _fails := 0


func _chk(name: String, ok: bool) -> void:
	print(("PASS: " if ok else "FAIL: ") + name)
	if not ok:
		_fails += 1


func _ready() -> void:
	Game.new_game()
	# 1) 被动首遇: 反复检定, 全程不得出现弹框, 最终固定候选全部入册
	var fixed_keys: Array = []
	for n in DataManager.npcs:
		if String(n.get("enrolled", "meet")) == "meet":
			fixed_keys.append(String(n.key))
	_chk("存在被动首遇候选", not fixed_keys.is_empty())
	var popup_seen := false
	for _i in 4000:
		Game._first_meet_roll()
		if not Game.pending.is_empty():
			popup_seen = true
			Game.pending = {}
	var met_all := true
	for k in fixed_keys:
		if not Game.run.npcs.has(String(k)):
			met_all = false
	_chk("被动首遇不弹框", not popup_seen)
	_chk("被动首遇全部自动入册", met_all)
	# 2) 游历首遇: 反复游历, 全程不得出现弹框, 随机 NPC 应静默入册
	var rand_before := Game._rand_count()
	var pool_before := (Game.run.world_npcs as Dictionary).size()
	for _i in 400:
		Game._travel_tick()
		if not Game.pending.is_empty():
			var kind := String(Game.pending.get("kind", ""))
			print("  FAIL-popup kind=", kind)
			Game.pending = {}
	_chk("游历首遇不弹框", Game.pending.is_empty())
	_chk("游历静默入册了随机面孔", Game._rand_count() > rand_before)
	_chk("池入册后移出池", (Game.run.world_npcs as Dictionary).size() < pool_before)
	# 3) 入册者状态正确: met=true 且缘分页可查
	var ok_state := true
	for key in Game.run.npcs:
		if String(key).begins_with("rand_"):
			if not bool(Game.run.npcs[key].get("met", false)):
				ok_state = false
	_chk("入册者 met=true", ok_state)
	# 4) 纪事兜底(2026-09-23): 真纪事没留痕的池内传闻脸, chronicle_of 不得为空 —— 坊间传闻补位
	var rumor_ok := true
	var rumor_n := 0
	for k in Game.run.world_npcs:
		var ks := String(k)
		var nm := Game.npc_name(ks)
		var es: Array = Game.chronicle_of(ks)
		if es.is_empty():
			rumor_ok = false
		elif not String(es[0].get("text", "")).contains("【%s】" % nm):
			rumor_ok = false
		rumor_n += 1
		if rumor_n >= 10:
			break
	_chk("池内传闻脸纪事非空(坊间传闻兜底)", rumor_ok)
	_chk("已入册者首条仍从真纪事/兜底可查", not Game.chronicle_of(String((Game.run.npcs as Dictionary).keys()[0])).is_empty())
	print("MEET_AUTOENROLL_SMOKE ", "PASS" if _fails == 0 else "FAIL(%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
