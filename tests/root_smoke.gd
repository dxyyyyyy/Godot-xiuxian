extends Node
## 炼灵根冒烟: 五行俱全免费默认; 炼至四/三/二/单行累计 30/80/150/240 道韵(边际递增), 不足拒转;
## 行数定系数(五0.65→单1.65, +0.25/行), 持有五行自择; 多行亲和与反属封锁; 转易换根不换行数; 老档回填。
## 运行: Godot --headless --path . res://tests/root_smoke.tscn

var _fails := 0


func _ready() -> void:
	Game.debug_seed(43)
	Game._start_life(DataManager.origins[0], 0)
	Game.speed = 0

	# 1) 默认五灵根: ×0.65 全五行, 免费
	Game.meta.dao = 1000
	Game.rebirth(DataManager.origins[0], 0, 0, {})
	_check(absf(float(Game.run.root) - 0.65) < 1e-9 and int(Game.run.root_count) == 5 and String(Game.run.element) == "金", "五灵根默认 ×0.65·金木水火土")
	_check(int(Game.meta.dao) == 1000, "五行免费")
	_check(String(Game.root_display()) == "五灵根·金·木·水·火·土", "root_display=%s" % Game.root_display())

	# 2) 递减计费(累计): 四 30→×0.90 / 三 80→×1.15 / 二 150→×1.40 / 单 240→×1.65
	Game.rebirth(DataManager.origins[0], 0, 0, {"n": 4, "els": ["金", "木", "水", "火"]})
	_check(int(Game.meta.dao) == 970 and absf(float(Game.run.root) - 0.90) < 1e-9, "炼四行 −30韵 ×0.90")
	Game.rebirth(DataManager.origins[0], 0, 0, {"n": 3, "els": ["木", "水", "火"]})
	_check(int(Game.meta.dao) == 890 and absf(float(Game.run.root) - 1.15) < 1e-9, "炼三行累计 −80韵 ×1.15")
	Game.rebirth(DataManager.origins[0], 0, 0, {"n": 2, "els": ["金", "水"]})
	_check(int(Game.meta.dao) == 740 and absf(float(Game.run.root) - 1.40) < 1e-9, "炼二行累计 −150韵 ×1.40")
	Game.rebirth(DataManager.origins[0], 0, 0, {"n": 1, "els": ["火"]})
	_check(int(Game.meta.dao) == 500 and absf(float(Game.run.root) - 1.65) < 1e-9 and String(Game.run.element) == "火", "炼单行累计 −240韵 ×1.65·火")
	# 与铸体叠加 / 道韵不足拒炼
	Game.rebirth(DataManager.origins[0], 2, 0, {"n": 3, "els": ["金", "木", "水"]})   # 80+40
	_check(int(Game.meta.dao) == 380 and absf(float(Game.run.root) - 1.35) < 1e-9, "三行+铸体×2: ×1.35, 合并扣 120")
	Game.meta.dao = 200
	Game.rebirth(DataManager.origins[0], 0, 0, {"n": 1, "els": ["土"]})   # 240 > 200 → 拒
	_check(int(Game.meta.dao) == 200 and int(Game.run.root_count) == 3, "道韵不足(200<240): 拒炼单灵根, run 不动")

	# 3) 非法输入兜底: 行数非法回五; 重复/非法属清洗、缺位按序补齐
	Game.rebirth(DataManager.origins[0], 0, 0, {"n": 6, "els": ["火", "火", "水"]})
	_check(int(Game.run.root_count) == 5 and absf(float(Game.run.root) - 0.65) < 1e-9, "n=6 兜底五行")
	Game.rebirth(DataManager.origins[0], 0, 0, {"n": 3, "els": ["火", "火", "水", "风"]})
	_check(Array(Game.run.roots).size() == 3 and not Array(Game.run.roots).has("风"), "重复/非法属清洗为 3 行: %s" % str(Game.run.roots))

	# 4) 多行亲和: 单火行 → 火种 −1 月、水种被反属封锁; 水火同身则皆免
	var chi: Dictionary = DataManager.seed("chiyanjiao")
	var bing: Dictionary = DataManager.seed("bingxincai")
	Game.meta.dao = 999
	Game.rebirth(DataManager.origins[0], 0, 0, {"n": 1, "els": ["火"]})
	var chi_f: int = Game.seed_eff_months(chi)
	var bing_f: int = Game.seed_eff_months(bing)
	_check(chi_f < int(chi.months) * 3 and bing_f == int(bing.months) * 3, "持火: 火种 −1 月(%d), 水种不吃(%d)" % [chi_f, bing_f])
	_check(not Game._seed_blocked_top(chi) and Game._seed_blocked_top(bing), "单火行: 火种不封锁, 水种被反属封锁")
	Game.rebirth(DataManager.origins[0], 0, 0, {"n": 4, "els": ["金", "木", "水", "火"]})
	_check(not Game._seed_blocked_top(chi) and not Game._seed_blocked_top(bing), "水火同身: 皆亲和免封锁")

	# 5) 五行转易: 换根不换行数(梦蝶仙馔)
	var roots_before: Array = Array(Game.run.roots).duplicate()
	Game._apply_dish_fx({"name": "测试", "tier": "low", "effect": "换根", "fx": {"kind": "element"}})
	var roots_after: Array = Array(Game.run.roots)
	_check(roots_after.size() == roots_before.size(), "转易后行数不变(%d)" % roots_after.size())
	var changed := false
	for e in roots_after:
		if not roots_before.has(String(e)):
			changed = true
	_check(changed and String(Game.run.element) == String(roots_after[0]), "转易换出一行且 element 同步")

	# 6) 老档回填: 无 roots/root_count → 按旧单属归一
	Game.run.erase("roots")
	Game.run.erase("root_count")
	Game._ensure_run()
	_check(Array(Game.run.roots).size() >= 1 and String(Game.run.roots[0]) == String(Game.run.element), "老档回填 roots=[element]")

	# 7) 五围图: 顶点几何(自上方顺时针金木水火土)、命中检测与 toggled 信号
	var Radar := preload("res://scripts/root_radar.gd")
	var radar: Control = Radar.new()
	add_child(radar)
	radar.size = Vector2(244, 236)
	radar.setup(PackedStringArray(["金", "木", "水", "火", "土"]), PackedStringArray(["金", "火"]), "×1.65 · 单灵根")
	var pts: PackedVector2Array = radar.vertex_points()
	_check(pts.size() == 5 and is_equal_approx(pts[0].x, radar.size.x / 2.0) and pts[0].y < pts[1].y, "首顶点=金(正上, 顺时针排布)")
	_check(radar.el_at_point(pts[0]) == "金" and radar.el_at_point(pts[2] + Vector2(0, 12)) == "水", "顶点/标签附近命中对应五行")
	_check(radar.el_at_point(radar.size * 0.5) == "", "盘心不误触")
	var got: Array = []
	radar.toggled.connect(func(el: String) -> void: got.append(el))
	var mb := InputEventMouseButton.new()
	mb.pressed = true
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.position = pts[4]   # 土(左下)
	radar._gui_input(mb)
	_check(got.size() == 1 and String(got[0]) == "土", "点击顶点发出 toggled(土)")

	print("== root_smoke: %s (%d FAIL) ==" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fails += 1
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
