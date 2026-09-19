extends Node
## 妖战冒烟: 寻道「其间」档遇妖 —— 胜率随战力极端变化(碾压/不敌)、胜掉灵石+妖丹、
## 败仅气血−30 不弹框; 妖丹卖出/赠礼/闭关守卫; 空池兜底不崩。
## 运行: Godot --headless --path . res://tests/yaoguai_smoke.tscn

var _fails := 0


func _ready() -> void:
	Game.debug_seed(31)
	Game._start_life(DataManager.origins[0], 0)
	Game.speed = 0
	Game.deterministic = false
	Game.run.qi = Game.qi_max()

	# 1) 高战力(功法×5, 满气血): 100 战全胜 —— 灵石逐笔落 [15,40], 妖丹 +100, 全程无弹框
	Game.run.tech = 5.0
	var wins := 0
	var stones_lo := int(Game.econ("yaoguai_stones_lo", 15))
	var stones_hi := int(Game.econ("yaoguai_stones_hi", 40))
	var band_ok := true
	for i in 100:
		var s0 := int(Game.farm().stones)
		var d0 := int(Game.farm().yaodan)
		Game._yaoguai_encounter(20)
		var gained := int(Game.farm().stones) - s0
		if int(Game.farm().yaodan) > d0:
			wins += 1
			if gained < stones_lo or gained > stones_hi:
				band_ok = false
	_check(wins == 100, "高战力 100 战全胜 (实际 %d)" % wins)
	_check(band_ok, "灵石掉落全程落在 [%d,%d]" % [stones_lo, stones_hi])
	_check(int(Game.farm().yaodan) == 100, "妖丹累计 100 枚")
	_check(Game.pending.is_empty(), "妖战胜利不弹框")

	# 2) 低战力(气血见底+心魔): 100 战基本不敌 —— 胜场≤12, 败不弹框, 妖丹不涨
	Game.run.tech = 1.0
	Game.run.inner = 12
	Game.run.qi = 0
	var w2 := 0
	for i in 100:
		var d1 := int(Game.farm().yaodan)
		Game._yaoguai_encounter(20)
		if int(Game.farm().yaodan) > d1:
			w2 += 1
	_check(w2 <= 12, "低战力 100 战胜场 ≤12 (实际 %d)" % w2)
	_check(Game.pending.is_empty(), "妖战失败也不弹框(§5.4 无战败红线, 妖潮档才弹)")
	_check(int(Game.farm().yaodan) == 100 + w2, "败局不掉丹, 妖丹仅随胜场增至 %d" % (100 + w2))
	Game.run.inner = 0
	Game.run.qi = Game.qi_max()

	# 3) 妖丹使用: 卖一枚 +120 灵石 / 赠专注对象好感 +60(每季 1 次) / 闭关拦截
	Game.farm().yaodan = 3
	var st0 := int(Game.farm().stones)
	Game.farm_sell_yaodan()
	_check(int(Game.farm().yaodan) == 2 and int(Game.farm().stones) == st0 + int(Game.econ("yaodan_price", 120)), "卖出: −1 丹 +120 灵石")
	var key := ""
	for k in Game.run.npcs:
		key = String(k)
		break
	Game.run.npcs[key].met = true
	Game.run.npcs[key].stage = 1
	Game.run.npcs[key].gift_q = 0
	Game.run.focus = key
	var aff0 := float(Game.run.npcs[key].aff)
	Game.farm_gift_yaodan()
	_check(int(Game.farm().yaodan) == 1 and absf(float(Game.run.npcs[key].aff) - aff0 - 60.0) < 1e-4, "赠礼: 好感+60 且耗丹")
	Game.run.recover = 10
	Game.run.npcs[key].gift_q = 0
	Game.farm_gift_yaodan()
	_check(int(Game.farm().yaodan) == 1, "闭关注养中赠礼被拦(丹未消耗)")
	Game.run.recover = 0

	# 4) 空池兜底: 数据缺失退回「无功而返」文案, 不崩
	var backup: Array = DataManager.yaoguai
	DataManager.yaoguai = []
	Game._yaoguai_encounter(20)
	DataManager.yaoguai = backup
	_check(true, "空池兜底不崩")

	print("== yaoguai_smoke: %s (%d FAIL) ==" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fails += 1
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
