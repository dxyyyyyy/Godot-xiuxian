extends Node
const TestGuard := preload("res://tests/test_guard.gd")
## 行动方案周期进度条冒烟: seek/travel 按目的地次第(6–10 / 4–8 月)派生 + 节奏 + lundao 倒计时 + 方案卡渲染。
## 运行: Godot --headless --path . res://tests/seek_cd_smoke.tscn

var _fails := 0


func _ready() -> void:
	if not TestGuard.ensure_isolated("SEEKCD_SMOKE"):
		get_tree().quit(2)
		return
	Game.debug_seed(31)
	Game._start_life(DataManager.origins[0], 0)
	Game.speed = 0
	Game.run.travel_dest = "baimenzong"   # 固定基准图(序列 idx0): 周期派生确定性

	# 1) 周期常数与派生进度: 六个月满一次, 走满即检定
	_check(Game.SEEK_PERIOD == 6, "SEEK_PERIOD=6")
	for cd in [6, 3, 2, 1, 0]:
		Game.run.secret_cd = cd
		_check(Game.seek_cd() == cd, "seek_cd(%d) 回读" % cd)
		var want := float(6 - cd) / 6.0
		_check(absf(Game.seek_progress() - want) < 1e-6, "cd=%d 进度 %.2f (期望 %.2f)" % [cd, Game.seek_progress(), want])

	# 2) 老档缺键防御: getter 不崩, _ensure_run 补默认
	Game.run.erase("secret_cd")
	_check(Game.seek_cd() == 0 and absf(Game.seek_progress() - 1.0) < 1e-6, "缺键档: getter 防御读 0(下月即判定)")
	Game._ensure_run()
	_check(Game.run.has("secret_cd") and int(Game.run.secret_cd) == 0, "_ensure_run 老档补 secret_cd=0")

	# 3) 引擎月结同步: 冷却扣尽触发 → 重置为周期(进度归零); 气血不济 → 短拍 2 月
	Game.run.qi = Game.qi_max()
	Game.run.plan = "seek"
	Game.run.secret_cd = 1
	Game._execute_plan()
	if not Game.pending.is_empty():
		Game.resolve_option(0)
	_check(Game.seek_cd() == Game.SEEK_PERIOD and absf(Game.seek_progress()) < 1e-6, "触发检定后: 进度归零重新走 6 月")
	Game.run.secret_cd = 1
	Game.run.qi = 0
	Game._execute_plan()
	_check(Game.seek_cd() == 2, "气血不足短拍: 余 2 月(进度条不崩语义不误)")
	Game.run.qi = Game.qi_max()

	# 3b) 寻道周期按目的地次第(6–10 月, 与游历同口径): 不周山脊 10 月; 切近图旧 cd 钳位
	Game.run.plan = "seek"
	Game.run.qi = Game.qi_max()
	Game.run.travel_dest = "buzhou"   # idx4 → 周期 10 月
	_check(Game.seek_period() == Game.SEEK_PERIOD + 4, "寻道·不周山脊: 周期 10 月")
	Game.run.secret_cd = 5
	_check(absf(Game.seek_progress() - 0.5) < 1e-6, "cd=5 / 周期 10 → 进度 0.50")
	Game.run.secret_cd = 1
	Game._execute_plan()
	if not Game.pending.is_empty():
		Game.resolve_option(0)
	_check(Game.seek_cd() == Game.SEEK_PERIOD + 4, "寻道·不周山脊: 到期检定后重置回 10 月")
	Game.run.secret_cd = 9
	Game.run.travel_dest = "qingxicun"   # idx1 → 7 月: 旧 cd 超周期 → 钳位满格
	_check(absf(Game.seek_progress() - 0.0) < 1e-6, "寻道: 切近图后旧 cd 超周期钳位(进度显示不会为负)")
	Game.run.secret_cd = 2
	Game.run.travel_dest = "baimenzong"   # 恢复基准(6 月周期)供后续断言

	# 4) 大比倒计时: 开局距首届 116 月 → 届年 9 月归零 → 本届派发后顺延回到 120
	Game.run.age_m = Game.START_AGE_M
	_check(Game.lundao_months_to_festival() == 116, "开局(第1年): 距首届 116 月")
	Game.run.age_m = Game.START_AGE_M + 116
	_check(Game.lundao_months_to_festival() == 0, "届年 9 月: 本届开锣在即(满格)")
	Game.run.lundao = {"last": 10, "best": 0}
	_check(Game.lundao_months_to_festival() == 120, "本届已派发: 顺延下届回到 120 月")
	Game.run.lundao = {"last": -1, "best": 0}

	# 5) plan_cycle 派生: 情缘按 date_cd(负值钳 0), 每月方案返回空
	Game.run.plan = "seek"
	var pc: Dictionary = Game.plan_cycle()
	_check(absf(float(pc.get("frac", -1.0)) - Game.seek_progress()) < 1e-6 and String(pc.get("label", "")) == "4/6月", "seek 周期描述符与冷却一致")
	Game.run.plan = "romance"
	Game.run.date_cd = 2
	pc = Game.plan_cycle()
	_check(absf(float(pc.get("frac", -1.0)) - 1.0 / 3.0) < 1e-6 and String(pc.get("label", "")) == "1/3月", "情缘: date_cd=2 → 1/3月")
	Game.run.date_cd = -7
	pc = Game.plan_cycle()
	_check(absf(float(pc.get("frac", -1.0)) - 1.0) < 1e-6, "情缘: 负冷却钳 0 → 满格可约")
	Game.run.plan = "travel"
	Game.run.travel_dest = "baimenzong"   # 序列 idx0 → 周期 4 月
	for tcd in [4, 2, 0]:
		Game.run.travel_cd = tcd
		pc = Game.plan_cycle()
		_check(absf(float(pc.get("frac", -1.0)) - float(4 - tcd) / 4.0) < 1e-6 and String(pc.get("label", "")) == "%d/4月" % (4 - tcd), "游历·百味宗: cd=%d → %d/4月" % [tcd, 4 - tcd])
	Game.run.travel_dest = "buzhou"   # idx4 → 周期 8 月(派生只看序列位次, 不走 set_travel_dest 的境界门槛)
	Game.run.travel_cd = 3
	pc = Game.plan_cycle()
	_check(absf(float(pc.get("frac", -1.0)) - 5.0 / 8.0) < 1e-6 and String(pc.get("label", "")) == "5/8月", "游历·不周山脊: 周期升到 8 月")
	Game.run.travel_dest = "qingxicun"   # idx1 → 5 月
	Game.run.travel_cd = 6
	pc = Game.plan_cycle()
	_check(absf(float(pc.get("frac", -1.0)) - 0.0) < 1e-6 and String(pc.get("label", "")) == "0/5月", "游历: 切更近的图后 cd 超周期 → 钳位归 0")
	for pid in ["cook", "pure", "household"]:
		Game.run.plan = pid
		_check(Game.plan_cycle().is_empty(), "%s(按月结算)无周期" % pid)

	# 5b) 游历节奏: 到期即判, 下次周期按目的地次第(4–8 月)重置; 未到期只减不判
	Game.run.plan = "travel"
	Game.run.travel_dest = "baimenzong"
	Game.run.travel_cd = 1
	Game._execute_plan()
	_check(Game.travel_cd() == Game.TRAVEL_PERIOD, "游历·百味宗: 到期判定后重置回 4 月")
	Game.run.travel_cd = 4
	Game._execute_plan()
	_check(Game.travel_cd() == 3, "游历: 未到期 → 仅递减, 不判定")
	Game.run.travel_dest = "buzhou"   # 月结分支信数据直判(不走 set_travel_dest 的 UI 门槛): 远图重置到 8 月
	Game.run.travel_cd = 1
	Game._execute_plan()
	_check(Game.travel_cd() == Game.TRAVEL_PERIOD + 4, "游历·不周山脊: 到期判定后重置回 8 月")

	# 6) 方案卡渲染: seek/romance/lundao 各 1 条进度条且值/文案与 plan_cycle 一致; 每月方案无条
	Game.run.plan = "romance"
	Game.run.date_cd = 1
	for pid in ["seek", "romance", "travel", "lundao"]:
		Game.run.plan = pid
		var desc: Dictionary = Game.plan_cycle()
		var sc = load("res://scripts/schedule_screen.gd").new()   # 动态 new, 不标类型以便调用子类方法
		var card: PanelContainer = sc._plan_card()
		var bars := card.find_children("*", "ProgressBar", true, false)
		_check(bars.size() == 1, "%s 方案卡含 1 条进度条(实得 %d)" % [pid, bars.size()])
		if bars.size() == 1:
			# ProgressBar 默认 step=0.01 会量化取值, 容差按百分数 0.01 计
			_check(absf(float((bars[0] as ProgressBar).value) / 100.0 - float(desc.get("frac", -9.0))) < 0.01, "%s 进度条值与 plan_cycle 一致" % pid)
		_check(_label_texts(card).has(String(desc.get("label", ""))), "%s 卡上有「%s」文案" % [pid, String(desc.get("label", ""))])
		card.free()
		sc.free()
	Game.run.plan = "pure"
	var sc_pure = load("res://scripts/schedule_screen.gd").new()
	var card_pure: PanelContainer = sc_pure._plan_card()
	_check(card_pure.find_children("*", "ProgressBar", true, false).is_empty(), "非周期方案卡无进度条")
	card_pure.free()
	sc_pure.free()

	# 7) 游历去向卡门控: 仅「寻道探索/出门游历」方案显示, 其余方案收走
	for pair in [["pure", false], ["travel", true], ["seek", true], ["cook", false]]:
		Game.run.plan = String(pair[0])
		var ss: Control = load("res://scripts/schedule_screen.gd").new()
		get_tree().root.add_child.call_deferred(ss)
		await _settle()
		var shown := false
		for l in ss.find_children("*", "Label", true, false):
			if String((l as Label).text) == "游历去向":
				shown = true
		_check(shown == bool(pair[1]), "%s 方案时游历去向卡%s" % [String(pair[0]), "显示" if bool(pair[1]) else "隐藏"])
		ss.queue_free()
		await _settle()

	print("== seek_cd_smoke: %s (%d FAIL) ==" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _label_texts(root: Node) -> Array[String]:
	var out: Array[String] = []
	for l in root.find_children("*", "Label", true, false):
		out.append(String((l as Label).text))
	return out


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok: ", msg)
	else:
		_fails += 1
		print("FAIL: ", msg)
