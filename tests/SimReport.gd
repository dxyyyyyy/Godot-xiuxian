extends Node
## v1.2 灰盒三段校验:
## A. 铁律回归(§12): 同种子下, 逐月调用与批量调用结果逐字节一致(时速档只改频率不改结算)。
## B. 确定性曲线: 纯修炼/灵田混合 两策略的历月与决策密度, 对照 xlsx v1.1 混合基准与 80–150 目标。
## C. 随机多世: meta 闭环(道韵→眷顾→飞升)仍成立。
## 运行: Godot --headless --path . res://tests/SimReport.tscn ++ --LIVES=6

## xlsx(v1.1 口径)分境界月数 —— 仅作参照: v1.2 方案倍率下积累必然更快, 数值待 M0 重标
const XLSX_REF_MONTHS := {"炼气": 171, "筑基": 223, "金丹": 440, "元婴": 784, "化神": 1451, "炼虚": 2675, "合体": 4932, "渡劫": 8877}

func _ready() -> void:
	Game.logged.connect(func(t): print(t))
	var n := 6
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--LIVES="):
			n = int(String(a).trim_prefix("--LIVES="))

	print("== A. 铁律回归: 1×(逐月) ≡ 100×(批量), 同种子 7 ==")
	var dump_a := _fresh_and_step(7, 1, 2000)
	var dump_b := _fresh_and_step(7, 2000, 1)
	if dump_a == dump_b:
		print("PASS: 两档位结算完全一致(%d 月, 修为 %s)" % [int(Game.run.kpi.ticks), Game._fmt(float(Game.run.cult))])
	else:
		print("FAIL: 结算与调用频率相关, 违反 §12 铁律!")
		print("A: ", dump_a.left(200))
		print("B: ", dump_b.left(200))

	print("")
	print("== B. 确定性曲线(灵根×功法×洞府=1) ==")
	for strat in ["pure", "mixed"]:
		_reset_meta()
		Game.debug_seed(99)
		Game._start_life(DataManager.origins[0], 0)
		Game.run.root = 1.0
		Game.run.npcs[DataManager.npcs[0].key].aff = 0.0
		Game.deterministic = true
		Game.simulate_life(strat)
		Game.deterministic = false
		print("策略 %s | 各境月数 vs v1.1混合参照:" % strat)
		var trace := Game.sim_trace
		var total := int(Game.run.age_m) - Game.START_AGE_M
		for i in range(trace.size()):
			var rn: String = trace[i][0]
			var end_m: int = total if i == trace.size() - 1 else int(trace[i + 1][1])
			var got := end_m - int(trace[i][1])
			var ref := int(XLSX_REF_MONTHS.get(rn, 0))
			print("  %s: %d 月 (v1.1参照 %d, %+.0f%%)" % [rn, got, ref, (float(got - ref) / float(ref) * 100.0) if ref > 0 else 0.0])
		var k := Game.kpi_summary()
		print("  → 历月 %d, 保底打断 %d, 决策估 %d 次(目标 80–150): %s" % [int(k.ticks), int(k.floors), int(k.decisions),
			"✓ 达标" if int(k.decisions) <= int(Game.tune("target_decisions", 150)) else "✗ 超预算 → 调 check_interval_months/interrupt_chance 或压日历"])

	print("")
	print("== C. 随机 meta 闭环 × %d 世(弹窗自动选首项) ==" % n)
	_reset_meta()
	Game.deterministic = false
	for i in range(n):
		var origin: Dictionary = DataManager.origins[i % DataManager.origins.size()]
		Game.debug_seed(1000 + i)
		Game._start_life(origin, 0)
		Game.simulate_life("mixed")
		var kc := Game.kpi_summary()
		print("世%d | %s(×%.2f) | %s | 止步%s | 在世%d年 | 道韵%d | 决策%d" % [
			int(Game.run.life), Game.run.origin, float(Game.run.root),
			String(Game.run.get("end_kind", "?")), String(Game.realm().name),
			(int(Game.run.age_m) - Game.START_AGE_M) / 12, int(Game.meta.dao), int(kc.decisions)])
		var bless := mini(5, int(Game.meta.dao) / Game.BLESS_COST)
		var left := int(Game.meta.dao) - bless * Game.BLESS_COST
		var forge := mini(5, left / Game.FORGE_COST)
		if bless > 0 or forge > 0:
			Game.rebirth(origin, forge, bless)
			Game.simulate_life("mixed")
			var k2 := Game.kpi_summary()
			print("  ↳ 铸体×%d+眷顾×%d: 眷顾+%.0f%%, 结局 %s, 道韵 %d, 决策 %d" % [
				forge, bless, float(Game.meta.get("bless_pct", 0.0)) * 100.0,
				String(Game.run.get("end_kind", "?")), int(Game.meta.dao), int(k2.decisions)])
	print("== 结束: 历 %d 世, 最高 %s, 结局 %s ==" % [
		int(Game.meta.lives), String(Game.meta.best_name), str(Game.meta.endings)])
	SaveSystem.clear_all()
	get_tree().quit()

## 重置 → 定种子 → 开一世 → 按 chunk 大小跑 steps 段 step_months(1) —— 返回终态字符串
func _fresh_and_step(seed: int, chunk: int, rounds: int) -> String:
	_reset_meta()
	Game.debug_seed(seed)
	Game._start_life(DataManager.origins[0], 0)
	Game.run.root = 1.0
	for i in range(rounds):
		Game.step_months(chunk)
		if Game.is_ended():
			break
	return JSON.stringify(Game.run)

func _reset_meta() -> void:
	Game.meta = {"schema": Game.SCHEMA, "dao": 0, "lives": 0, "best_ord": 0, "best_name": "无", "bless_pct": 0.0, "bonds": 0, "endings": {}}
