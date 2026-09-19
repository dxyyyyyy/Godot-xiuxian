extends Node
## 数据驱动地基(GDD §12): 境界/方案/出身/占位NPC/事件/全局调参 = res://data/*.json。
## v1.2: actions.json(AP 表)退役, 新增 plans.json(行动方案倍率)与 npcs.json(好感占位对象)。
## relations.json: NPC 之间的关系网(手写预设无向边 a/b + 身份标签 tag + 亲疏值 val −100~+100)。

var realms: Array = []
var plans: Array = []
var origins: Array = []
var npcs: Array = []
var relations: Array = []
var events: Array = []
var seeds: Array = []
var recipes: Array = []
var facilities: Array = []
var wall: Array = []
var yaoguai: Array = []
var traits: Array = []
var auras: Array = []
var tuning: Dictionary = {}
var economy: Dictionary = {}

## 固定 NPC 出厂外貌基线（_ready 时留档）：捏脸回写 npcs.json 后仍可「复原」
var _npc_raw: Dictionary = {}

var _plan_index: Dictionary = {}
var _seed_index: Dictionary = {}
var _recipe_index: Dictionary = {}
var _facility_index: Dictionary = {}
var _wall_index: Dictionary = {}
var _yaoguai_index: Dictionary = {}
var _traits_index: Dictionary = {}
var _aura_index: Dictionary = {}

func _ready() -> void:
	realms = _load_array("res://data/realms.json")
	plans = _load_array("res://data/plans.json")
	origins = _load_array("res://data/origins.json")
	npcs = _load_array("res://data/npcs.json")
	relations = _load_array("res://data/relations.json")   # NPC 之间的关系网(手写预设, 无向边)
	events = _load_array("res://data/events.json")
	seeds = _load_array("res://data/seeds.json")
	recipes = _load_array("res://data/recipes.json")
	facilities = _load_array("res://data/facilities.json")
	wall = _load_array("res://data/wall.json")
	yaoguai = _load_array("res://data/yaoguai.json")
	traits = _load_array("res://data/traits.json")
	auras = _load_array("res://data/auras.json")
	tuning = _load_dict("res://data/tuning.json")
	economy = _load_dict("res://data/economy_tuning.json")
	for n in npcs:
		_npc_raw[String(n.get("key", ""))] = (n.get("appearance", {}) as Dictionary).duplicate(true)
	for p in plans:
		_plan_index[String(p.get("id", ""))] = p
	for s in seeds:
		_seed_index[String(s.get("id", ""))] = s
	for r in recipes:
		_recipe_index[String(r.get("id", ""))] = r
	for f in facilities:
		_facility_index[String(f.get("id", ""))] = f
	for w in wall:
		_wall_index[String(w.get("id", ""))] = w
	for g in yaoguai:
		_yaoguai_index[String(g.get("id", ""))] = g
	for t in traits:
		_traits_index[String(t.get("id", ""))] = t
	for a in auras:
		_aura_index[String(a.get("name", ""))] = a

func plan(id: String) -> Dictionary:
	return _plan_index.get(id, _plan_index.get("pure", {}))

func seed(id: String) -> Dictionary:
	return _seed_index.get(id, {})

func recipe(id: String) -> Dictionary:
	return _recipe_index.get(id, {})

func facility(id: String) -> Dictionary:
	return _facility_index.get(id, {})

func wall_post(id: String) -> Dictionary:
	return _wall_index.get(id, {})

func yaoguai_def(id: String) -> Dictionary:
	return _yaoguai_index.get(id, {})

func traits_def(id: String) -> Dictionary:
	return _traits_index.get(id, {})

## 气质定义(按名字索引): {id,name,color,self:{cult/insight/break/aff/event},npc:{aff},note}
func aura_def(name: String) -> Dictionary:
	return _aura_index.get(name, {})

## 固定 NPC 出厂外貌（深拷贝；捏脸页「复原」用）
func npc_raw_appearance(key: String) -> Dictionary:
	return (_npc_raw.get(key, {}) as Dictionary).duplicate(true)

## 捏脸回写：改内存档案并落盘 data/npcs.json（跨世生效）。只读环境落盘失败时内存仍生效，返回是否落盘。
func write_npc_appearance(key: String, ap: Dictionary) -> bool:
	for n in npcs:
		if String(n.get("key", "")) == key:
			n["appearance"] = ap.duplicate(true)
			return _save_npcs()
	return false

func _save_npcs() -> bool:
	var f := FileAccess.open("res://data/npcs.json", FileAccess.WRITE)
	if f == null:
		push_warning("捏脸回写失败(只读环境): res://data/npcs.json —— 仅本进程生效")
		return false
	# sort_keys=false 保原键序; _jsonable 把 7.0 还原成 7; 缩进单空格与手写档案一致
	f.store_string(JSON.stringify(_jsonable(npcs), " ", false) + "\n")
	return true

## JSON 数值统一被解析成 float, 落盘前把整数值的还原回 int(7.0 → 7)
static func _jsonable(v: Variant) -> Variant:
	if v is Dictionary:
		var d := {}
		for k in (v as Dictionary):
			d[k] = _jsonable((v as Dictionary)[k])
		return d
	if v is Array:
		var a := []
		for e in (v as Array):
			a.append(_jsonable(e))
		return a
	if v is float:
		var fv := float(v)
		if absf(fv) < 9.0e15 and is_equal_approx(fv, round(fv)):
			return int(fv)
		return fv
	return v

func realm(idx: int) -> Dictionary:
	if idx < 0 or idx >= realms.size():
		return {}
	return realms[idx]

## 全局小层序号偏移: 前面所有境界的层数之和(炼气 0, 筑基 9, 金丹 12…)
func layer_offset(idx: int) -> int:
	var n := 0
	for i in range(idx):
		n += int(realm(i).get("layers", 3))
	return n

func total_layers() -> int:
	return layer_offset(realms.size())

func _load_array(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("打不开数据文件: %s" % path)
		return []
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Array:
		return data
	push_error("JSON 格式错误(应为数组): %s" % path)
	return []

func _load_dict(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("打不开数据文件: %s" % path)
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		return data
	push_error("JSON 格式错误(应为对象): %s" % path)
	return {}
