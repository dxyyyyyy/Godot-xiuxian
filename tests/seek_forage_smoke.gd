extends Node
## 寻道采获冒烟: 有获检定按游历去向从风物池采得植物入库(品阶正确) + 灵石随地图位阶增值;
## 去向 auto 时解析到轮换实地的池子。
## 运行: Godot --headless --path . res://tests/seek_forage_smoke.tscn

var _fails := 0


func _ready() -> void:
	Game.debug_seed(11)
	Game._start_life(DataManager.origins[0], 0)
	Game.speed = 0
	Game.run.realm = 9   # 全图解锁, 便于直接测高位阶图

	# 1) 固定去向=清溪村: 采得必在清溪村风物池, 品阶与种子表一致, 灵石 5~15(unlock 0 → ×1)
	Game.run.travel_dest = "qingxicun"
	for i in 6:
		var before: Dictionary = Game.farm().inv.duplicate(true)
		var stones0 := int(Game.farm().stones)
		var loot := Game._seek_forage()
		var gained := int(Game.farm().stones) - stones0
		_check(gained >= 5 and gained <= 15, "清溪村灵石落点 5~15 (实际 %d)" % gained)
		_check(loot.contains("采得"), "月报串含采得: %s" % loot)
		var found: Array = []
		for sid in Game.farm().inv:
			var d0: int = _inv_total(before, String(sid))
			if _inv_total(Game.farm().inv, String(sid)) > d0:
				found.append(String(sid))
		_check(found.size() == 1, "恰入库一株(实际 %d)" % found.size())
		if found.size() == 1:
			var sid := String(found[0])
			var pool: Array = Game.TRAVEL_MAPS.qingxicun.flora
			_check(pool.has(sid), "【%s】在清溪村风物池" % String(DataManager.seed(sid).name))
			var s := DataManager.seed(sid)
			_check(Game.farm().inv[sid][String(s.grade)] == before.get(sid, {"凡": 0, "灵": 0, "上": 0})[String(s.grade)] + 1, "入库品阶=%s" % String(s.grade))

	# 2) 高位阶图(不周山脊 unlock 4): 灵石落点 25~75, 池子含上品
	Game.run.travel_dest = "buzhou"
	var stones1 := int(Game.farm().stones)
	Game._seek_forage()
	var gained1 := int(Game.farm().stones) - stones1
	_check(gained1 >= 25 and gained1 <= 75, "不周山脊灵石落点 25~75 (实际 %d)" % gained1)

	# 3) auto 轮换: 采得植物必属当月轮换图的风物池
	Game.run.travel_dest = "auto"
	for m in [480, 481, 482]:
		Game.run.age_m = m
		var dest := String(Game._travel_dest())
		var loot3 := Game._seek_forage()
		var hit := false
		for e in Game.TRAVEL_MAPS[dest].flora:
			if loot3.contains(String(DataManager.seed(String(e)).name)):
				hit = true
		_check(hit, "auto@%d月→%s 采得在池内: %s" % [m, String(Game.TRAVEL_MAPS[dest].name), loot3])

	print("== seek_forage_smoke: %s (%d FAIL) ==" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _inv_total(inv: Dictionary, sid: String) -> int:
	if not inv.has(sid):
		return 0
	var t := 0
	for g in inv[sid]:
		t += int(inv[sid][g])
	return t


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fails += 1
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
