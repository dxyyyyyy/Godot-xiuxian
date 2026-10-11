extends Node
## 双层存档(GDD §12): MetaSave(道韵/魂印/三生石) 常驻一个文件;
## RunSave 一世一文件(baiwei_run_life_N.json), 防档毁。灰盒只写必要字段。
## 防误毁三道闸: ① save_run/save_meta/GameState.savegame 写前轮转 .bak1/.bak2/.bak3(3 代可回滚, 清档不清备份);
## ② 坏档/schema 不符读入时改名 .unreadable-<ts> 保全(run 在 load_open_run, meta 在 Game._load_meta_or_init,
##    savegame 在 GameState._load_or_init), 绝不静默覆盖;
## ③ 会写盘的测试一律经 tools/run_tests.sh(APPDATA 隔离 + 标记), 裸跑被 test_guard 拒绝。

const META_PATH := "user://baiwei_meta.json"
## meta 档版本, 与 run 的 Game.SCHEMA 解耦: 此后各自演进, bump SCHEMA 不再牵连 meta 清档。
## 4 = 现存 meta 档的在盘值(旧档一直按 SCHEMA 落盘), 老档直读不受影响。
const META_SCHEMA := 4
const RUN_PREFIX := "baiwei_run_life_"
const RUN_SUFFIX := ".json"
const BAK_KEEP := 3

## 落盘 meta: 写前轮转 .bak(闸①), 与 save_run 同口径。
func save_meta(meta: Dictionary) -> bool:
	_rotate_bak(META_PATH)
	return _write_json(META_PATH, meta)

func load_meta() -> Dictionary:
	return _read_json(META_PATH)

## 落盘一世档: 写前轮转 .bak, 并给 rng_state 盖上 RNG 流戳(读档续流, 与不间断推进一致, v2.7)。
func save_run(run: Dictionary) -> bool:
	if run.is_empty():
		return false
	run["rng_state"] = Game.rng.state
	var path := "user://%s%d%s" % [RUN_PREFIX, int(run.get("life", 1)), RUN_SUFFIX]
	_rotate_bak(path)
	return _write_json(path, run)

## 写前轮转: 当前→.bak1, .bak1→.bak2, .bak2→.bak3(共留 3 代, 误覆盖可回滚)
func _rotate_bak(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var abs_cur := ProjectSettings.globalize_path(path)
	for i in [BAK_KEEP, BAK_KEEP - 1]:   # i ∈ [3, 2]: bak2→bak3, bak1→bak2
		if FileAccess.file_exists("%s.bak%d" % [path, i - 1]):
			DirAccess.rename_absolute("%s.bak%d" % [abs_cur, i - 1], "%s.bak%d" % [abs_cur, i])
	DirAccess.copy_absolute(abs_cur, "%s.bak1" % abs_cur)

## 闸①对外复用: GameState.savegame 等外部存档写前轮转, 与 save_run/save_meta 同一代数。
func rotate_bak(path: String) -> void:
	_rotate_bak(path)

## 保全一个读不出/版本不合的存档: 改名 <原名>.unreadable-<时间戳>, 防兜底新世静默覆盖好档。
## 时间戳只有秒级精度, 同秒多次保全时目标名追加 -N 序号, 否则 Windows 上改名撞车失败会把坏档留在原地。
func preserve_unreadable(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var abs_from := ProjectSettings.globalize_path(path)
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
	var target := "%s.unreadable-%s" % [path, stamp]
	var k := 0
	while FileAccess.file_exists(target):
		k += 1
		target = "%s.unreadable-%s-%d" % [path, stamp, k]
	DirAccess.rename_absolute(abs_from, ProjectSettings.globalize_path(target))

## 找最新的"未结束"一世存档; 没有则返回空字典(开新局)。
## expected_schema>0 时顺带版本闸: 解析失败/schema 不符的档一律保全改名, 不再当活档用。
func load_open_run(expected_schema := 0) -> Dictionary:
	var dir := DirAccess.open("user://")
	if dir == null:
		return {}
	var best_life := 0
	var best: Dictionary = {}
	for f in dir.get_files():
		if f.begins_with(RUN_PREFIX) and f.ends_with(RUN_SUFFIX):
			var life := int(f.trim_prefix(RUN_PREFIX).trim_suffix(RUN_SUFFIX))
			var data := _read_json("user://" + f)
			if data.is_empty():
				preserve_unreadable("user://" + f)   # 文件在但读不出(半截写/锁读/损坏)
				continue
			if expected_schema > 0 and int(data.get("schema", 0)) != expected_schema:
				preserve_unreadable("user://" + f)   # 版本不合的老档
				continue
			if not bool(data.get("ended", true)):
				if life > best_life:
					best_life = life
					best = data
	return best

## 新开一世清档: 只清活档与 meta; .bak*/.unreadable-* 安全副本刻意保留(想彻底清就手动删)。
func clear_all() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(META_PATH))
	for f in dir.get_files():
		if f.begins_with(RUN_PREFIX) and f.ends_with(RUN_SUFFIX):
			dir.remove(f)

func _write_json(path: String, data: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("存档写入失败: %s" % path)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	return f.get_open_error() == OK

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else {}
