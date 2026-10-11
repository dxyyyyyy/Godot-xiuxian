extends Node
## 数据驱动地基(GDD §12): 境界/方案/出身/占位NPC/事件/全局调参 = res://data/*.json。
## v1.2: actions.json(AP 表)退役, 新增 plans.json(行动方案倍率)与 npcs.json(好感占位对象)。
## relations.json: NPC 之间的关系网(手写预设无向边 a/b + 关系 key tag + 亲疏值 val −100~+100)。
## rel_tags.json: 关系标签统一词表(单一事实源) —— 静态边/动态边生成池/兜底默认名/亲族方向称谓/恋爱夫妻名分都查这一张表;
## 边的 tag 字段存稳定 key(如 oldfriend), 玩家可见措辞经 rel_tag_display 集中解析, 改词只动数据文件。

var realms: Array = []
var plans: Array = []
var origins: Array = []
var npcs: Array = []
var relations: Array = []
var rel_tags: Array = []
var qy: Array = []
var ax: Array = []   # 暗线五碎片+开炉双链+灶火长明(8.3 v0.2 弹框链: Game._ax_tick 派发, manual 条目仅由渡劫口/结局/开局直调)
var ax_stone: Dictionary = {}   # 三生石暗线图鉴词条(8.3 v0.2 §5.2)
var reunion_texts: Dictionary = {}
var chat_texts: Dictionary = {}   # 交谈台词池(细案《恋爱系统》§1.2 交谈演出层): 固定六人分段池+性格语气池+通用池, Game._chat_line 取词
var node_events: Dictionary = {}   # 好感门槛/心动时分弹框文案(§1.4/§7): Game._fire_node_event/_focus_mile_check 取模板, 内嵌串兜底
var date_scenes: Array = []   # 十四景约会(细案《恋爱系统》§4.1): note+scenes, 选景引擎在 Game._pick_date_scene
var events: Array = []
var seeds: Array = []
var recipes: Array = []
var dark: Array = []   # 黑暗料理 6 道喜剧文案(小灶图鉴 §黑暗料理): 按菜谱 id 取 {text=赠礼反应, moxiu=猎奇反应, eat=自吃, aff?=好感特例, assemble?=百味乱炖三池拼装}
var facilities: Array = []
var wall: Array = []
var yaoguai: Array = []
var traits: Array = []
var gongfa: Array = []   # 功法 12 部(GDD §5.3): 残页合成/坊市购入 → 藏经阁研通 → 装备写 run.tech(×1–×3 活乘数)
var auras: Array = []
var tuning: Dictionary = {}
var economy: Dictionary = {}

## 固定 NPC 出厂外貌基线（_ready 时留档）：捏脸回写 npcs.json 后仍可「复原」
var _npc_raw: Dictionary = {}

var _plan_index: Dictionary = {}
var _seed_index: Dictionary = {}
var _recipe_index: Dictionary = {}
var _dark_index: Dictionary = {}
var _facility_index: Dictionary = {}
var _wall_index: Dictionary = {}
var _yaoguai_index: Dictionary = {}
var _traits_index: Dictionary = {}
var _gongfa_index: Dictionary = {}
var _aura_index: Dictionary = {}
var _rel_tag_index: Dictionary = {}      # key → 词表条目
var _rel_tag_lookup: Dictionary = {}     # key/现名/旧别名 → key(兜底解析与旧档迁移共用)

func _ready() -> void:
	realms = _load_array("res://data/realms.json")
	plans = _load_array("res://data/plans.json")
	origins = _load_array("res://data/origins.json")
	npcs = _load_array("res://data/npcs.json")
	relations = _load_array("res://data/relations.json")   # NPC 之间的关系网(手写预设, 无向边)
	rel_tags = _load_array("res://data/rel_tags.json")     # 关系标签统一词表(静态/动态/兜底/亲族/夫妻 单一事实源)
	reunion_texts = _load_dict("res://data/reunion_texts.json")   # 魂印跨世重逢文本(三档/六人认人通道/H08 弹窗/壁帖/三生石)
	chat_texts = _load_dict("res://data/chat_texts.json")         # 交谈台词池(§1.2): 固定六人分段+道侣日常/12 性格语气/通用段位池
	node_events = _load_dict("res://data/node_events.json")       # 门槛事件/心动时分弹框文案(§1.4/§7): title/body/opts 模板外置
	date_scenes = (_load_dict("res://data/date_scenes.json") as Dictionary).get("scenes", [])   # 十四景约会数据+文本池(§4.1)
	qy = _load_array("res://data/qy_events.json")                 # 奇缘族 30 条全静默(17 奇缘 + 10 无面人池 + 3 好久不见): 命中随机选选项直接结算入月报, trigger 门控+账本在 Game._qy_tick
	ax = _load_array("res://data/ax_events.json")                 # 暗线五碎片弹框链(8.3 v0.2 §0.2 缺口①②③实装): Game._ax_tick/_dujie_gate/_kailu 派发
	ax_stone = _load_dict("res://data/ax_stone.json")             # 三生石暗线图鉴(五词条获取版/重读版 + 「再看一眼」文案, 8.3 v0.2 §5.2): app_lifestone 渲染
	events = _load_array("res://data/events.json")
	seeds = _load_array("res://data/seeds.json")
	recipes = _load_array("res://data/recipes.json")
	dark = _load_array("res://data/dark_events.json")   # 黑暗料理喜剧文案(按菜谱 id 索引, Game.kitchen_gift/eat 取词)
	facilities = _load_array("res://data/facilities.json")
	wall = _load_array("res://data/wall.json")
	yaoguai = _load_array("res://data/yaoguai.json")
	traits = _load_array("res://data/traits.json")
	gongfa = _load_array("res://data/gongfa.json")
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
	for d in dark:
		_dark_index[String(d.get("id", ""))] = d
	for f in facilities:
		_facility_index[String(f.get("id", ""))] = f
	for w in wall:
		_wall_index[String(w.get("id", ""))] = w
	for g in yaoguai:
		_yaoguai_index[String(g.get("id", ""))] = g
	for t in traits:
		_traits_index[String(t.get("id", ""))] = t
	for g in gongfa:
		_gongfa_index[String(g.get("id", ""))] = g
	for a in auras:
		_aura_index[String(a.get("name", ""))] = a
	for t in rel_tags:
		var tk := String(t.get("key", ""))
		_rel_tag_index[tk] = t
		_rel_tag_lookup[tk] = tk
		_rel_tag_lookup[String(t.get("name", ""))] = tk
		for al in (t.get("aliases", []) as Array):
			_rel_tag_lookup[String(al)] = tk

func plan(id: String) -> Dictionary:
	return _plan_index.get(id, _plan_index.get("pure", {}))

func seed(id: String) -> Dictionary:
	return _seed_index.get(id, {})

func recipe(id: String) -> Dictionary:
	return _recipe_index.get(id, {})

## 黑暗料理喜剧文案(按菜谱 id 取): 未收录的 id 返回空字典, 调用方自行兜底
func dark_event(id: String) -> Dictionary:
	return _dark_index.get(id, {})

func facility(id: String) -> Dictionary:
	return _facility_index.get(id, {})

func wall_post(id: String) -> Dictionary:
	return _wall_index.get(id, {})

func yaoguai_def(id: String) -> Dictionary:
	return _yaoguai_index.get(id, {})

func traits_def(id: String) -> Dictionary:
	return _traits_index.get(id, {})

## 功法定义(按 id 取): {id,name,mult,pages,research,market,price,desc} —— mult 即装备后的 run.tech(GDD §11 ×1–×3)
func gongfa_def(id: String) -> Dictionary:
	return _gongfa_index.get(id, {})

## 气质定义(按名字索引): {id,name,color,self:{cult/insight/break/aff/event},npc:{aff},note}
func aura_def(name: String) -> Dictionary:
	return _aura_index.get(name, {})

## —— 关系标签统一词表(rel_tags.json) ——
## 条目按 key 取: {key,name,kind,pos|neg|kin|love,gen,min,max,notes,aliases}
func rel_tag(key: String) -> Dictionary:
	return _rel_tag_index.get(key, {})

## 显示措辞: 边存的是 key/现名/旧别名都能解析; 空串兜底「初识」; 未知串原样透传(旧档/手造边不破显示)。
func rel_tag_display(stored: String) -> String:
	if stored == "":
		return String(_rel_tag_index.get("firstmeet", {}).get("name", "初识"))
	var k := String(_rel_tag_lookup.get(stored, ""))
	if k == "":
		return stored
	return String(_rel_tag_index.get(k, {}).get("name", stored))

## 归一为 key(旧档迁移用): key 照旧、现名/别名→key、未知串原样透传。
func rel_tag_key(stored: String) -> String:
	return String(_rel_tag_lookup.get(stored, stored))

## 标签性质: "pos"/"neg"/"kin"/"love"; 未识别返回空串。
func rel_tag_kind(stored: String) -> String:
	var k := String(_rel_tag_lookup.get(stored, ""))
	if k == "":
		return ""
	return String(_rel_tag_index.get(k, {}).get("kind", ""))

## 动态边抽取池: gen=true 条目按正/负分带(负带 = kind=="neg")。
func rel_tag_pool(neg: bool) -> Array:
	var out: Array = []
	for t in rel_tags:
		if bool(t.get("gen", false)) and String(t.get("kind", "")) == "neg" == neg:
			out.append(t)
	return out

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
