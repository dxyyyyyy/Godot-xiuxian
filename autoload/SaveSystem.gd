extends Node
## 双层存档(GDD §12): MetaSave(道韵/魂印/三生石) 常驻一个文件;
## RunSave 一世一文件(baiwei_run_life_N.json), 防档毁。灰盒只写必要字段。

const META_PATH := "user://baiwei_meta.json"
const RUN_PREFIX := "baiwei_run_life_"
const RUN_SUFFIX := ".json"

func save_meta(meta: Dictionary) -> void:
	_write_json(META_PATH, meta)

func load_meta() -> Dictionary:
	return _read_json(META_PATH)

func save_run(run: Dictionary) -> void:
	if run.is_empty():
		return
	_write_json("user://%s%d%s" % [RUN_PREFIX, int(run.get("life", 1)), RUN_SUFFIX], run)

## 找最新的"未结束"一世存档; 没有则返回空字典(开新局)。
func load_open_run() -> Dictionary:
	var dir := DirAccess.open("user://")
	if dir == null:
		return {}
	var best_life := 0
	var best: Dictionary = {}
	for f in dir.get_files():
		if f.begins_with(RUN_PREFIX) and f.ends_with(RUN_SUFFIX):
			var life := int(f.trim_prefix(RUN_PREFIX).trim_suffix(RUN_SUFFIX))
			var data := _read_json("user://" + f)
			if not data.is_empty() and not bool(data.get("ended", true)):
				if life > best_life:
					best_life = life
					best = data
	return best

func clear_all() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(META_PATH))
	for f in dir.get_files():
		if f.begins_with(RUN_PREFIX):
			dir.remove(f)

func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("存档写入失败: %s" % path)
		return
	f.store_string(JSON.stringify(data, "\t"))

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else {}
