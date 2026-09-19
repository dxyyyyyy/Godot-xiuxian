extends Node
## 临时集成冒烟:主场景 + 100× 常流时钟,压 tick→UI 重建全链路;顺带踩交互 API。

func _ready() -> void:
	var main: Control = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	Game.set_speed(100)
	_run.call_deferred()


func _run() -> void:
	# 跑约 2.2 秒 @100×(≈0.5月/秒×100×2.2 ≈ 110 月), 期间 UI 反复重建
	await get_tree().create_timer(2.2).timeout
	print("TICKS_SO_FAR=", int(Game.run.kpi.ticks), " PENDING=", not Game.pending.is_empty())
	# 事件若在待决策, 决策掉
	var guard := 0
	while not Game.pending.is_empty() and guard < 50:
		Game.resolve_option(0)
		guard += 1
	# 交互 API 踩点(应打日志, 不应崩溃)
	Game.set_speed(0)
	Game.set_plan("household")
	Game.set_plan("cook")
	Game.set_travel_dest("qingxicun")
	var season := "冬"
	var m := (int(Game.run.age_m) % 12) + 1
	season = "春" if m >= 3 and m <= 5 else ("夏" if m >= 6 and m <= 8 else ("秋" if m >= 9 and m <= 11 else "冬"))
	for s in DataManager.seeds:
		if Game.seed_in_season(s, season):
			Game.farm_plant(0, String(s.id))
			break
	Game.farm_reclaim()
	Game.farm_sell_all()
	Game._stoves()
	Game.kitchen_cook(0, "suchaochunjiu")
	Game.kitchen_collect(0)
	Game.kitchen_eat("suchaochunjiu")
	Game.set_speed(50)
	await get_tree().create_timer(0.6).timeout
	Game.set_speed(0)
	while not Game.pending.is_empty():
		Game.resolve_option(0)
	print("SMOKE_INTEG PASS: ticks=", int(Game.run.kpi.ticks), " year=", Game.calendar(), " stones=", int(Game.farm().stones))
	# 默认不清档（会抹掉真实游玩进度）；需重置环境时加参数: ++ --CLEAN
	if OS.get_cmdline_user_args().has("--CLEAN"):
		SaveSystem.clear_all()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
	get_tree().quit()
