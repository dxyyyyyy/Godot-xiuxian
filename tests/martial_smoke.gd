extends Node
## 武力值冒烟: §5.4 口径的 wu_li 单调性(境界层数/食补↑, 心魔/低气血↓) + 寻道检定走通三档。
## 运行: Godot --headless --path . res://tests/martial_smoke.tscn

var _fails := 0


func _ready() -> void:
	Game.debug_seed(23)
	Game._start_life(DataManager.origins[0], 0)
	Game.speed = 0
	Game.deterministic = false
	Game.run.qi = Game.qi_max()

	# 1) 起点: 无加成无折扣 → 武力=境界基数
	var base0: float = Game._realm_base_now()
	_check(absf(Game.wu_li() - base0) < 1e-4, "初始武力=境界基数 %.1f" % base0)

	# 2) 同境深修涨武力
	Game.run.layer = 4
	_check(Game.wu_li() > base0, "炼气 5 层武力 %.1f > 基线" % Game.wu_li())

	# 3) 食补/气运抬升, 心魔/低气血折扣
	var w0 := Game.wu_li()
	Game._buff_apply("cult_pct", 0.2, 3)
	_check(Game.wu_li() > w0, "食修+20%% buff 抬武力 (%.1f→%.1f)" % [w0, Game.wu_li()])
	Game.run.buffs = {}
	Game.run.luck = 1
	_check(absf(Game.wu_li() / w0 - 1.03) < 1e-4, "气运 1 档 = 战力+3%%(GDD 口径)")
	Game.run.luck = 0
	Game.run.inner = 12
	_check(absf(Game.wu_li() / w0 - 0.9) < 1e-4, "心魔折扣 −10%(与冲关率同幅)")
	Game.run.inner = 0
	Game.run.qi = 0
	_check(absf(Game.wu_li() / w0 - 0.85) < 1e-4, "气血见底折扣下限 0.85")
	Game.run.qi = Game.qi_max()

	# 4) 寻道检定走通: 冷却扣尽即判, 三档之一落地, 消耗一次检定计数
	Game.run.plan = "seek"
	Game.run.secret_cd = 1
	var sec0 := int(Game.run.secret)
	Game._execute_plan()
	_check(int(Game.run.secret) == sec0 + 1, "检定触发(寻道次数 +1)")
	if not Game.pending.is_empty():
		Game.resolve_option(0)   # 撞进受创档: 善后即清, 不纠结分支
	_check(Game.pending.is_empty() or String(Game.pending.kind) == "secret", "打断只可能是检定善后")

	# 5) 气血不济不判: 冷却走短拍
	Game.run.secret_cd = 1
	Game.run.qi = 0
	var sec1 := int(Game.run.secret)
	Game._execute_plan()
	_check(int(Game.run.secret) == sec1 and int(Game.run.secret_cd) == 2, "气血不足: 不判定, 短冷却 2 月")

	print("== martial_smoke: %s (%d FAIL) ==" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fails += 1
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
