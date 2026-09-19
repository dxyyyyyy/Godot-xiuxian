extends Node
## 天生特质冒烟: 转世组合扣款/超支拒转/非法 id 丢弃; 八效果精确(武力/冲关/修为/寿元/事件/收成/成菜/免死);
## buffs_summary 与入世志可见; 老档回填。
## 运行: Godot --headless --path . res://tests/trait_smoke.tscn

var _fails := 0


func _ready() -> void:
	Game.debug_seed(53)
	Game._start_life(DataManager.origins[0], 0)
	Game.speed = 0
	Game.deterministic = false
	var o0: Dictionary = DataManager.origins[0]

	# 1) 记账: 单灵根240+铸体2×20+眷顾50+剑骨60+道心70 = 460
	Game.meta.dao = 1000
	Game.rebirth(o0, 2, 1, {"n": 1, "els": ["火"]}, ["jian", "daoheart"])
	_check(int(Game.meta.dao) == 540, "组合扣款 240+40+50+60+70=460 → 余 540")
	_check(Array(Game.run.traits) == ["jian", "daoheart"], "run.traits 落账")
	# 超支拒转
	Game.meta.dao = 300
	Game.rebirth(o0, 0, 0, {}, ["chanyi", "fuyuan"])   # 120+90=210 ≤300 → 成交
	_check(int(Game.meta.dao) == 90, "210 韵组合在 300 内成交")
	var root_before := float(Game.run.root)
	Game.rebirth(o0, 0, 0, {}, ["lingxi", "chanyi"])   # 80+120=200 > 90 → 拒
	_check(int(Game.meta.dao) == 90 and absf(float(Game.run.root) - root_before) < 1e-9, "道韵不足(90<200): 整单拒转")
	# 非法 id 静默丢弃
	Game.rebirth(o0, 0, 0, {}, ["jian", "ghost"])
	_check(Array(Game.run.traits) == ["jian"], "非法特质 ghost 被丢弃")

	# 2) 效果比值: 先记基线, 再逐一挂 run.traits 对比
	Game.run.traits = []
	var w0: float = Game.wu_li()
	var e0: float = Game.efficiency()
	var b0: float = Game.break_chance()
	var l0: int = Game.lifespan_cap_years()
	Game.run.traits = ["jian"]
	_check(absf(Game.wu_li() / w0 - 1.12) < 1e-6, "剑骨: 武力 ×1.12")
	Game.run.traits = ["lingxi"]
	_check(absf(Game.efficiency() / e0 - 1.08) < 1e-6, "灵息体: 每月修为(聚灵) ×1.08")
	Game.run.traits = ["daoheart"]
	_check(absf(Game.break_chance() - b0 - 0.03) < 1e-6, "道心: 冲关率 +3pp")
	Game.run.traits = ["changshou"]
	_check(Game.lifespan_cap_years() == l0 + 8, "长寿相: 寿元 +8 年(%d→%d)" % [l0, Game.lifespan_cap_years()])
	Game.run.traits = ["fuyuan"]
	_check(absf(Game._trait_fx("event") - 0.15) < 1e-9, "福缘深: 事件概率乘子 +0.15")
	Game.run.traits = ["chanyi"]
	_check(absf(Game._trait_fx("survive") - 0.15) < 1e-9, "避劫蝉衣: 殒落率减 0.15")

	# 3) 绿蓑: 固定条件收获, 产量 = round(y×2)(收成 +100%)
	Game.run.traits = []
	var chi: Dictionary = DataManager.seed("chiyanjiao")
	var n0: int = _harvest_count(chi)
	Game.run.traits = ["jisou"]
	var n1: int = _harvest_count(chi)
	var y0: float = float(chi.yield) * Game._season_mult("春")
	_check(n1 == maxi(1, int(round(y0 * 2.0))), "绿蓑: 灵田收成 +100%%(%d→%d, 期望 %d)" % [n0, n1, maxi(1, int(round(y0 * 2.0)))])

	# 4) 炊玉: 同样开火次数, 多出的份数 ≈ 60%
	Game._inv_add("chunjiu", "凡", 200)
	Game.run.plan = "cook"
	Game.debug_seed(54)
	Game.run.traits = []
	var c0 := _cook_n(10)
	Game.debug_seed(54)
	Game.run.traits = ["cuiyu"]
	var c1 := _cook_n(10)
	_check(c1 > c0, "炊玉: 10 次下厨多成菜(%d→%d)" % [c0, c1])
	Game.run.traits = []

	# 5) 可见性: 加持栏与入世志
	Game.run.traits = ["jian", "cuiyu"]
	_check(Game.buffs_summary().contains("天生:剑骨·炊玉"), "加持栏含 %s" % Game.trait_display())
	Game.run.traits = []
	_check(not Game.buffs_summary().contains("天生"), "无特质时不显示")

	# 6) 老档回填
	Game.run.erase("traits")
	Game._ensure_run()
	_check(Array(Game.run.traits).is_empty(), "老档回填 traits=[]")

	print("== trait_smoke: %s (%d FAIL) ==" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


## 以固定条件收获一次赤焰椒(春/无虫/无变异), 返回入库株数
func _harvest_count(s: Dictionary) -> int:
	Game.debug_seed(9)
	var plot := {"seed": String(s.id), "pest": false, "mutated": false}
	var before := _inv_total(String(s.id))
	Game._harvest_plot(plot, s, "春")
	return _inv_total(String(s.id)) - before


func _inv_total(sid: String) -> int:
	var t := 0
	var inv: Dictionary = Game.farm().inv
	if inv.has(sid):
		for g in inv[sid]:
			t += int(inv[sid][g])
	return t


## 连续 n 个月走一遍 _cook_once 的成菜计数差
func _cook_n(n: int) -> int:
	var f := Game.farm()
	var c0 := int(f.cook)
	for i in n:
		Game._cook_once()
	return int(f.cook) - c0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fails += 1
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
