extends Node
## 退养闭关冒烟: 秘境善后选「退养」→ 实打实闭关 24 月 ——
## 方案封存(切不动/自动行为停)、赠礼解契守卫生效、倒计时逐月递减、出关自动解禁。
## 运行: Godot --headless --path . res://tests/recover_smoke.tscn

var _fails := 0


func _ready() -> void:
	Game.debug_seed(7)
	Game._start_life(DataManager.origins[0], 0)
	Game.speed = 0
	Game.deterministic = false
	Game.run.plan = "travel"   # 预设非修炼方案, 验证退养会封存回「认真修炼」

	# 1) 选「退养」: 心魔 24 月 + 闭关 24 月 + 方案封存
	Game.pending = {"title": "秘境善后", "text": "探秘境重伤。", "options": [{"t": "硬扛"}, {"t": "退养"}], "kind": "secret", "data": {}}
	Game.resolve_option(1)
	_check(int(Game.run.inner) == 24, "退养后心魔=24月")
	_check(Game.recover_months() == 24, "退养后闭关=24月")
	_check(String(Game.run.plan) == "pure", "退养封存方案为认真修炼")

	# 2) 关内封锁: 切方案被拒 / 守卫拦截出门动作 / 加持栏可见
	Game.set_plan("seek")
	_check(String(Game.run.plan) == "pure", "关内 set_plan 被拒, 仍为 pure")
	_check(Game._recover_guard("赠礼"), "关内赠礼/解契守卫返回 true")
	_check(Game.buffs_summary().contains("闭关注养"), "加持栏显示闭关注养")

	# 3) 逐月倒计时: 第 1 月 23, 第 24 月归零出关
	Game._tick_core()
	_check(Game.recover_months() == 23, "tick 一个月后闭关余 23 月")
	for i in 23:
		Game._tick_core()
	_check(Game.recover_months() == 0, "24 月后闭关归零")
	var has_out := false
	for e in GameState.chronicle:
		if String(e.text).contains("将养出关"):
			has_out = true
	_check(has_out, "纪事落下「将养出关」一行")

	# 4) 出关解禁: 方案可切, 守卫放行
	Game.set_plan("seek")
	_check(String(Game.run.plan) == "seek", "出关后可切寻道探索")
	_check(not Game._recover_guard("赠礼"), "出关后守卫返回 false")
	_check(not Game.buffs_summary().contains("闭关注养"), "出关后加持栏无闭关字样")

	print("== recover_smoke: %s (%d FAIL) ==" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fails += 1
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
