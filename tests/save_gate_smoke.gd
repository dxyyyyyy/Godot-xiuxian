extends Node
const TestGuard := preload("res://tests/test_guard.gd")
## 存档三道闸冒烟: meta/savegame 写前轮转(.bak1-3 封顶 3 代)与坏档/schema 不符保全(.unreadable-<ts>, 同秒多次加 -N);
## meta 版本与 run 的 SCHEMA 解耦(SaveSystem.META_SCHEMA); savegame 缺 schema 键旧档直读(day:int→string 迁移仍生效)。
## 运行: bash tools/run_tests.sh save_gate
## 注意: 隔离目录必须绝对路径(runner 已保证) —— 相对 APPDATA 下 DirAccess.open("user://") 会失败(err 31)。

var _fails := 0


func _ready() -> void:
	if not TestGuard.ensure_isolated("SAVE_GATE_SMOKE"):
		get_tree().quit(2)
		return
	Game.speed = 0   # 冻结月度 tick, 防纪事被模拟日志干扰断言

	# ---- meta 闸①: 写前轮转 ----
	for dao_v in [11, 12, 13, 14]:
		SaveSystem.save_meta({"schema": SaveSystem.META_SCHEMA, "dao": dao_v})
	_check(FileAccess.file_exists(SaveSystem.META_PATH + ".bak3"), "meta 连写 4 次滚出 bak3")
	_check(not FileAccess.file_exists(SaveSystem.META_PATH + ".bak4"), "轮转封顶 3 代, 无 bak4")
	_check(int(SaveSystem._read_json(SaveSystem.META_PATH + ".bak3").get("dao", 0)) == 11
		and int(SaveSystem._read_json(SaveSystem.META_PATH + ".bak1").get("dao", 0)) == 13
		and int(SaveSystem._read_json(SaveSystem.META_PATH).get("dao", 0)) == 14, "轮转次序正确(bak3=第1次/bak1=第3次/活档=第4次)")

	# ---- meta 闸②: 坏档保全 + 兜底 ----
	_write_raw(SaveSystem.META_PATH, "{这不是JSON")
	Game._load_meta_or_init()
	_check(int(Game.meta.get("dao", -1)) == Game.START_DAO and int(Game.meta.get("lives", -1)) == 0, "坏 meta → 兜底新 meta(dao=START_DAO)")
	_check(not FileAccess.file_exists(SaveSystem.META_PATH), "坏 meta 原文件已改名让位")
	_check(_unreadable_count("baiwei_meta.json.unreadable-") == 1, "保全副本恰 1 份")

	# ---- meta 闸②: schema 不符同样保全 ----
	SaveSystem.save_meta({"schema": SaveSystem.META_SCHEMA + 1, "dao": 55})
	Game._load_meta_or_init()
	_check(int(Game.meta.get("dao", -1)) == Game.START_DAO and _unreadable_count("baiwei_meta.json.unreadable-") == 2, "schema 高于 META_SCHEMA → 保全+兜底")

	# ---- meta 现行版本直读 ----
	SaveSystem.save_meta({"schema": SaveSystem.META_SCHEMA, "dao": 88, "lives": 2})
	Game._load_meta_or_init()
	_check(int(Game.meta.get("dao", -1)) == 88 and int(Game.meta.get("lives", -1)) == 2
		and _unreadable_count("baiwei_meta.json.unreadable-") == 2, "现行版本 meta 直读, 不触发保全")

	# ---- savegame 闸①: 写前轮转 ----
	GameState.wall_full_name = false
	GameState.save_game()   # 首写: 文件此前不在盘上, 不轮转
	GameState.chronicle.append({"day": "闸测·次月", "text": "第二次写入"})
	GameState.save_game()   # 二写: 上一版滚入 bak1
	_check(FileAccess.file_exists(GameState.SAVE_PATH + ".bak1"), "savegame 二写滚出 bak1")
	_check(int(SaveSystem._read_json(GameState.SAVE_PATH + ".bak1").get("schema", 0)) == 1
		and int(SaveSystem._read_json(GameState.SAVE_PATH).get("schema", 0)) == 1, "savegame 活档与 bak1 均带版本键")

	# ---- savegame 好档往返 ----
	GameState.wall_full_name = true
	GameState.chronicle.clear()
	GameState._load_or_init()
	_check(GameState.wall_full_name == false, "好档往返: 设置从盘还原")
	var has_roundtrip := false
	for e in GameState.chronicle:
		if String(e.get("text", "")) == "第二次写入":
			has_roundtrip = true
	_check(has_roundtrip, "好档往返: 纪事从盘还原")

	# ---- savegame 闸②: 坏档保全 + 重建 ----
	_write_raw(GameState.SAVE_PATH, "){broken json")
	GameState._load_or_init()
	_check(GameState.chronicle.size() == 1
		and String(GameState.chronicle[0].get("text", "")).begins_with("入百味宗门墙"), "坏 savegame → 兜底重建(纪事只剩开局志)")
	_check(GameState.wall_full_name == false, "重建沿用内存现值(设置不回默认)")
	_check(not FileAccess.file_exists(GameState.SAVE_PATH), "坏 savegame 原文件已改名让位")
	_check(_unreadable_count("savegame.json.unreadable-") == 1, "保全副本恰 1 份")

	# ---- savegame 闸②: 版本不符 ----
	GameState.sound_volume = 40
	_write_raw(GameState.SAVE_PATH, JSON.stringify({"schema": 99, "settings": {"sound": 7}}))
	GameState._load_or_init()
	_check(GameState.sound_volume == 40 and _unreadable_count("savegame.json.unreadable-") == 2, "schema 高于 SAVEGAME_SCHEMA → 保全重建, 盘上设置不落内存")

	# ---- savegame 旧档兼容(无 schema 键, day 仍是 int) ----
	_write_raw(GameState.SAVE_PATH, JSON.stringify({"settings": {"sound": 33}, "chronicle": [{"day": 5, "text": "旧档int天"}]}))
	GameState._load_or_init()
	_check(GameState.sound_volume == 33, "无版本键旧档直读")
	_check(GameState.chronicle.size() == 1 and String(GameState.chronicle[0].get("day", "")) == "旧岁·5", "旧档 day:int→string 迁移仍生效")
	_check(_unreadable_count("savegame.json.unreadable-") == 2, "旧档直读不触发保全")

	print("== save_gate_smoke: %s (%d FAIL) ==" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fails += 1
	print("%s: %s" % ["PASS" if ok else "FAIL", label])


func _write_raw(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _unreadable_count(prefix: String) -> int:
	var n := 0
	var dir := DirAccess.open("user://")
	if dir == null:
		return -1
	for fname in dir.get_files():
		if fname.begins_with(prefix):
			n += 1
	return n
