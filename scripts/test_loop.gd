extends Node
## 生产闭环自动化测试（临时自动加载，验证后从 project.godot 移除注册即可）。
## 以 GameState 数据层复现"点击空地→弹窗选配方→扣材料→收获回库"全链路：
## 弹窗的确认/取消分别对应 slot_start()/不动作，空地点击对应 slot_interact()，
## 手动推进 TimeManager.game_hours 模拟生长。测试前后备份/还原真实存档。

var _ran := false
var _fails := 0


func _ready() -> void:
	await get_tree().process_frame
	_run()


func _run() -> void:
	if _ran:
		return
	_ran = true

	# 备份真实存档，避免测试写档污染玩家进度
	var had_save := FileAccess.file_exists(GameState.SAVE_PATH)
	var old_save := ""
	if had_save:
		var rf := FileAccess.open(GameState.SAVE_PATH, FileAccess.READ)
		old_save = rf.get_as_text()
		rf.close()

	GameState._init_fresh()
	_test_tables()
	_test_inventory_api()
	_test_slot_start_validation()
	_test_full_loop()
	_test_save_roundtrip()

	# 还原真实存档
	if had_save:
		var wf := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
		wf.store_string(old_save)
		wf.close()
	else:
		var dir := DirAccess.open("user://")
		if dir:
			dir.remove("savegame.json")

	print("LOOP_TEST %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	get_tree().quit()


func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("  FAIL: " + label)


## A. 配方表：kind 分类与顺序
func _test_tables() -> void:
	_check(GameState.recipes_of_kind("plot") == ["lingdao", "xiancao", "lingzhi", "tianlian"],
			"plot 配方列表")
	_check(GameState.recipes_of_kind("stove") == ["gaodian", "yanghun"],
			"stove 配方列表")


## B. 库存 API：can_afford / consume_items（原子性）
func _test_inventory_api() -> void:
	_check(GameState.get_item_count("lingcao") == 120, "初始灵草 120")
	_check(GameState.can_afford({"lingcao": 120}), "can_afford 恰好够")
	_check(not GameState.can_afford({"lingcao": 121}), "can_afford 差 1 不够")
	var costs := {"lingcao": 1, "lingzhi_c": 999}
	_check(not GameState.consume_items(costs), "consume_items 不足返回 false")
	_check(GameState.get_item_count("lingcao") == 120, "不足时一项都不扣（原子性）")
	_check(GameState.consume_items({"lingcao": 10}), "consume_items 足够成功")
	_check(GameState.get_item_count("lingcao") == 110, "扣除后灵草 110")


## C/D. slot_start 校验：空地点击不自动种植、各失败分支不改状态不扣款
func _test_slot_start_validation() -> void:
	var stove1: Dictionary = GameState.stoves[1]  # 空闲灶台（last_recipe=gaodian）
	_check(bool(stove1.unlocked) and String(stove1.recipe) == "", "stoves[1] 为空闲灶台")
	_check(GameState.slot_interact(stove1) == "", "空地点击不再自动开始生产")
	_check(String(stove1.recipe) == "", "空地点击后仍为空")
	_check(GameState.get_item_count("lingcao") == 110, "空地点击不扣材料")

	_check(not GameState.slot_start(stove1, "not_a_recipe"), "未知配方拒绝")
	_check(not GameState.slot_start(stove1, "lingdao"), "kind 与槽位类型不符拒绝")
	_check(not GameState.slot_start(GameState.farmland[4], "lingdao"), "未解锁槽位拒绝")
	_check(not GameState.slot_start(GameState.farmland[0], "lingdao"), "生产中槽位拒绝")
	_check(not GameState.slot_start(stove1, "gaodian"), "材料不足拒绝（无灵稻）")
	_check(String(stove1.recipe) == "" and GameState.get_item_count("lingcao") == 110,
			"全部拒绝分支无状态变化")


## E. 全链路：收获灵稻→空地弹窗选灵稻（扣灵草）→灶台糕点（扣灵稻）→收获回库
func _test_full_loop() -> void:
	TimeManager.game_hours += 50.0  # 预置槽位全部成熟

	var field0: Dictionary = GameState.farmland[0]
	_check(GameState.slot_interact(field0) == "harvest", "点击可收获→收取")
	_check(GameState.get_item_count("lingdao_c") == 50, "灵稻 +50 进背包")
	_check(String(field0.recipe) == "", "收获后槽位归空")

	# 弹窗确认 = slot_start：扣材料开始生产
	_check(GameState.slot_start(field0, "lingdao"), "空地以灵稻开始生产")
	_check(GameState.get_item_count("lingcao") == 100, "开始生产扣灵草 10")
	_check(is_equal_approx(float(field0.started), TimeManager.game_hours), "started 记录当前时刻")
	_check(String(field0.last_recipe) == "lingdao", "last_recipe 更新（供弹窗默认高亮）")

	var stove1: Dictionary = GameState.stoves[1]
	_check(GameState.slot_start(stove1, "gaodian"), "灶台以糕点开始生产")
	_check(GameState.get_item_count("lingdao_c") == 40 and GameState.get_item_count("lingcao") == 95,
			"糕点扣灵稻 10 + 灵草 5")

	TimeManager.game_hours += 10.0
	_check(GameState.slot_interact(field0) == "harvest", "灵稻再收获")
	_check(GameState.get_item_count("lingdao_c") == 90, "灵稻回库 40+50")
	_check(GameState.slot_interact(stove1) == "harvest", "糕点收取")
	_check(GameState.get_item_count("gaodian_c") == 1, "糕点入背包")

	# 下游产物可作再生产材料：田产灵稻 → 糕点
	_check(GameState.slot_start(stove1, "gaodian"), "收灵稻可供糕点再生产")
	_check(GameState.get_item_count("lingdao_c") == 80, "再扣灵稻 10")
	TimeManager.game_hours += 0.4
	_check(GameState.slot_progress(stove1) > 0.0
			and GameState.slot_progress(stove1) < 1.0, "再生产槽位处于生产中")


## F. 存档兼容：生产中槽位保存/读取后进度正确、材料不重复结算
func _test_save_roundtrip() -> void:
	GameState.save_game()
	var started := float(GameState.stoves[1].started)
	var progress_at_save := GameState.slot_progress(GameState.stoves[1])
	var lingcao := GameState.get_item_count("lingcao")
	var lingdao_c := GameState.get_item_count("lingdao_c")
	TimeManager.game_hours += 0.5  # 模拟掉档期间时间推进

	_check(GameState._load_game(), "读档成功")
	_check(String(GameState.stoves[1].recipe) == "gaodian", "读档后生产中槽位保留")
	_check(absf(float(GameState.stoves[1].started) - started) < 1e-4, "started 精度保留")
	_check(absf(GameState.slot_progress(GameState.stoves[1]) - progress_at_save) < 1e-3,
			"进度以存档为准，不被重复结算")
	_check(GameState.get_item_count("lingcao") == lingcao
			and GameState.get_item_count("lingdao_c") == lingdao_c, "材料扣除不被回滚")
