extends Node
const TestGuard := preload("res://tests/test_guard.gd")
## 家园布局探针: 灵田/伙房格定高定宽 —— 换长名/长效果/虫害变异标签后尺寸不跳动。
## 运行: bash tools/run_tests.sh home_layout_probe


func _ready() -> void:
	if not TestGuard.ensure_isolated("HOMEPROBE"):
		get_tree().quit(2)
		return
	Game.debug_seed(7)
	Game._start_life(DataManager.origins[0], 0)
	var f: Dictionary = Game.farm()
	var hs: Control = load("res://scripts/home_screen.gd").new()
	get_tree().root.add_child.call_deferred(hs)
	await _settle()
	# —— 场景 A: 1 块耕 empty + 8 块未开垦(荒地格) / 1 空灶 + 3 未点亮 ——
	var a_farm := _tile_stats(hs, 3)
	var a_kit := _tile_stats(hs, 2)
	# —— 场景 B: 境界顶满, 9 块全种最长名灵植+虫害+变异; 4 灶全烹最长名长效果菜已出锅 ——
	var long_r := _longest(DataManager.recipes, "effect")
	for p in f.plots:
		p.open = true
		p.seed = String(_longest(DataManager.seeds, "name").id)
		p.age = 1
		p.pest = true
		p.mutated = true
	Game.run.realm = DataManager.realms.size() - 1
	for st in Game._stoves():
		st.clear()
		st.recipe = String(long_r.id)
		st.age = Game.cook_months(DataManager.recipe(String(long_r.id)))
	Game.changed.emit()
	await _settle()
	var b_farm := _tile_stats(hs, 3)
	var b_kit := _tile_stats(hs, 2)
	var fails := 0
	fails += _check(a_farm, b_farm, "灵田")
	fails += _check(a_kit, b_kit, "伙房")
	if fails == 0:
		print("HOMEPROBE PASS")
	else:
		print("HOMEPROBE FAIL: %d 项" % fails)
	get_tree().quit(0 if fails == 0 else 1)


## 取网格(按列数)每个子格尺寸与网格最小高。
func _tile_stats(hs: Control, cols: int) -> Array:
	for g in hs.find_children("*", "GridContainer", true, false):
		if (g as GridContainer).columns == cols:
			var out: Array = []
			for t in (g as GridContainer).get_children():
				out.append({"size": (t as Control).size, "min": (t as Control).get_combined_minimum_size()})
			out.append({"grid_min_y": (g as GridContainer).get_combined_minimum_size().y})
			return out
	return []


## A/B 同位格尺寸必须一致(不随文字内容跳动), 且格内高度一致。
func _check(a: Array, b: Array, label: String) -> int:
	var fails := 0
	if a.is_empty() or b.is_empty():
		print("%s FAIL: 未找到网格(A=%d 项, B=%d 项)" % [label, a.size(), b.size()])
		return 1
	if a.size() != b.size():
		print("%s FAIL: 格数 %d != %d" % [label, a.size(), b.size()])
		return 1
	for i in a.size() - 1:   # 末项是网格最小高哨兵
		if a[i].size != b[i].size:
			print("%s FAIL: 格%d A=%s B=%s (文字长短改变格尺寸)" % [label, i, a[i].size, b[i].size])
			fails += 1
		elif a[i].size.y < a[i].min.y and a[i].size.y > 0:
			print("%s FAIL: 格%d 尺寸 %s 低于内容最小 %s" % [label, i, a[i].size, a[i].min])
			fails += 1
	if a.back().grid_min_y != b.back().grid_min_y:
		print("%s FAIL: 网格最小高 A=%f B=%f (随内容漂移)" % [label, a.back().grid_min_y, b.back().grid_min_y])
		fails += 1
	else:
		print("%s OK: %d 格 A/B 同尺寸, 网格最小高恒 %f" % [label, a.size() - 1, a.back().grid_min_y])
	return fails


func _longest(arr: Array, field: String) -> Dictionary:
	var best := {}
	var bl := 0
	for r in arr:
		if String(r.get("tier", "")) == "dark":
			continue   # 黑暗谱名/效果玩家侧只显「？？？」, 不算最长文本
		var l := String(r.get(field, "")).length()
		if l > bl:
			bl = l
			best = r
	return best


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
