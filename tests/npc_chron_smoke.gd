extends Node
## 纪事弹层回归冒烟: Game.chronicle_of 检索语义 + 名录详情「纪事」子弹层交互。
## 纪事条目为合成注入(绕开月度节奏, 断言确定); ⚠ 会 Game.new_game() 清档, 跑前备份存档。

var _fails := 0


func _chk(name: String, ok: bool) -> void:
	print(("PASS: " if ok else "FAIL: ") + name)
	if not ok:
		_fails += 1


func _ready() -> void:
	Game.set_speed(0)
	# ---- 覆盖: 每月坊市侧写 —— 未被互动的入册者也要进纪事(不再只归互动对象) ----
	Game.new_game()
	Game.deterministic = true
	for _m in 24:
		Game.tick_month()
		while not Game.pending.is_empty():
			Game.resolve_option(0)
		if Game.is_ended():
			break
	var named := 0
	for k0 in ["jianshu", "yaoshi", "shanjun", "moxiu", "shushu", "huzhu"]:
		if not Game.chronicle_of(String(k0)).is_empty():
			named += 1
	var pool_named := 0
	for kp in (Game.run.world_npcs as Dictionary).keys():
		if not Game.chronicle_of(String(kp)).is_empty():
			pool_named += 1
	var scene_n := 0
	for e in GameState.chronicle:
		if String(e.text).contains("坊市一景: 【"):
			scene_n += 1
	_chk("侧写行按月入纪事(≥18/24月)", scene_n >= 18)
	_chk("纪事提及多名 NPC(≥3 人有故事)", named >= 3)
	_chk("世界池未识随机 NPC 亦有纪事(≥1 人)", pool_named >= 1)
	# ---- 检索语义(合成注入, 确定性) ----
	Game.new_game()
	var key := "jianshu"
	var nm := Game.npc_name(key)
	var other := "shanjun"
	var onm := Game.npc_name(other)
	# 候选: 池内随机 NPC(名字不与固定 NPC 互为子串, 验【】括住的唯一性)
	var pk := ""
	for k in Game.run.npcs:
		if String(k).begins_with("rand_"):
			pk = String(k)
			break
	# ---- chronicle_of 检索语义(直接注入纪事, 确定性) ----
	GameState.chronicle.clear()
	GameState.log_chronicle("◇ 与【%s】攀谈几句 —— 入册缘分页" % nm)
	GameState.log_chronicle("坊市都道: 【%s】与【%s】情逾金石" % [nm, onm])
	GameState.log_chronicle("修为 +10(与任何人无关)")
	GameState.log_chronicle("第1年·3月 · 修为 +1 · 【%s】与【%s】闲话 → 更亲近 · 【%s】独酌" % [nm, onm, onm])
	GameState.log_chronicle("这句没有括号包住的%s不该算上" % nm)
	var hits: Array = Game.chronicle_of(key)
	_chk("命中相关行", hits.size() == 3)
	var joined := ""
	for h in hits:
		joined += String((h as Dictionary).get("text", "")) + "\n"
	_chk("无括号不算数", not joined.contains("不该算上"))
	_chk("月汇总只留提及条", joined.contains("闲话 →") and not joined.contains("独酌"))
	_chk("共提一行双方都算", joined.contains("坊市都道"))
	_chk("最新在前", String((hits[0] as Dictionary).get("text", "")).contains("闲话 →"))
	var hits2: Array = Game.chronicle_of(other)
	var both := false
	for h in hits2:
		if String((h as Dictionary).get("text", "")).contains("坊市都道"):
			both = true
	_chk("共提条目对方亦可得", both)
	var day_ok := true
	for h in hits:
		if String((h as Dictionary).get("day", "")) == "":
			day_ok = false
	_chk("每条带时间标签", day_ok)
	# ---- UI: 主场景 → 详情弹层 → 纪事子弹层 ----
	var main: Control = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.request_npc_detail(key)
	await get_tree().process_frame
	var ds: Node = main._screens.get("directory", null)
	_chk("名录屏就位", ds != null)
	if ds != null:
		ds._open_npc_chron(key)
		await get_tree().process_frame
		_chk("详情可开纪事弹层", ds._npc_chron != null)
		_chk("纪事按钮选中态", ds._detail_chron != null)
		ds._close_detail()
		await get_tree().process_frame
		_chk("关详情连纪事一起收", ds._npc_chron == null and ds._detail == null)
	# 池内随机 NPC 亦可检索(与固定 NPC 名互斥不误伤)
	if pk != "":
		var h3: Array = Game.chronicle_of(pk)
		_chk("池内人检索不误伤", h3.is_empty())
	print("NPC_CHRON_SMOKE %s" % ("PASS" if _fails == 0 else "FAIL(%d)" % _fails))
	get_tree().quit()
