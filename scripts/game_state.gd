extends Node
## 全局游戏状态：玩家属性、背包、灵田/灶台生产槽位 + JSON 存档。
## 自动加载单例，任意脚本可直接用 GameState 访问。

signal inventory_changed
signal slots_changed
signal stats_changed

const SAVE_PATH := "user://savegame.json"
const AUTOSAVE_INTERVAL := 30.0

## 物品定义（id -> 定义），from/to 是背包图标方块的渐变色（hex）
const ITEMS := {
	"huilingdan": {"name": "回灵丹", "icon": "💊", "attribute": "恢复灵力", "from": "93c5fd", "to": "60a5fa"},
	"liaoshangyao": {"name": "疗伤药", "icon": "🩹", "attribute": "恢复生命", "from": "fca5a5", "to": "f87171"},
	"julingshi": {"name": "聚灵石", "icon": "💎", "attribute": "提升修为", "from": "d8b4fe", "to": "c084fc"},
	"pojingdan": {"name": "破境丹", "icon": "⭐", "attribute": "突破境界", "from": "fde047", "to": "facc15"},
	"lingcao": {"name": "灵草", "icon": "🌿", "attribute": "炼丹材料", "from": "86efac", "to": "4ade80"},
	"xianjian": {"name": "仙剑", "icon": "⚔️", "attribute": "攻击+500", "from": "d1d5db", "to": "9ca3af"},
	"hushenfu": {"name": "护身符", "icon": "🛡️", "attribute": "防御+300", "from": "fdba74", "to": "fb923c"},
	"chuansongfu": {"name": "传送符", "icon": "📜", "attribute": "瞬间移动", "from": "f9a8d4", "to": "f472b6"},
	"lingshoudan": {"name": "灵兽蛋", "icon": "🥚", "attribute": "孵化灵兽", "from": "fcd34d", "to": "fbbf24"},
	"xianlu": {"name": "仙露", "icon": "💧", "attribute": "增加寿命", "from": "67e8f9", "to": "22d3ee"},
	"fabasuipian": {"name": "法宝碎片", "icon": "✨", "attribute": "合成法宝", "from": "a5b4fc", "to": "818cf8"},
	"miji": {"name": "秘籍", "icon": "📖", "attribute": "学习技能", "from": "fda4af", "to": "fb7185"},
	# —— 产物流：种田/烹饪闭环的产出 ——
	"lingdao_c": {"name": "灵稻", "icon": "🌾", "attribute": "灵田产物", "from": "a3e635", "to": "84cc16"},
	"xiancao_c": {"name": "仙草", "icon": "🍀", "attribute": "灵田产物", "from": "6ee7b7", "to": "10b981"},
	"lingzhi_c": {"name": "灵芝", "icon": "🍄", "attribute": "灵田产物", "from": "fdba74", "to": "f97316"},
	"tianlian_c": {"name": "天莲", "icon": "🌺", "attribute": "灵田产物", "from": "fda4af", "to": "fb7185"},
	"gaodian_c": {"name": "灵气糕点", "icon": "🥮", "attribute": "烹饪产物", "from": "fcd34d", "to": "f59e0b"},
	"yanghun_c": {"name": "养魂汤", "icon": "🍜", "attribute": "烹饪产物", "from": "fb923c", "to": "ea580c"},
	# —— 新增灵植：火/水属性食材 ——
	"zhuyan_c": {"name": "朱焰果", "icon": "🔴", "attribute": "灵田产物", "from": "fecaca", "to": "ef4444"},
	"xuanbing_c": {"name": "玄冰瓜", "icon": "🍈", "attribute": "灵田产物", "from": "bae6fd", "to": "38bdf8"},
	# —— 凡膳档 ——
	"biquan_c": {"name": "碧泉灵米粥", "icon": "🥣", "attribute": "恢复灵力+25", "from": "bbf7d0", "to": "4ade80"},
	"cuiyu_c": {"name": "翠玉仙草冻", "icon": "🍡", "attribute": "恢复生命+5%", "from": "a7f3d0", "to": "34d399"},
	"jiaomi_c": {"name": "火候焦米饼", "icon": "🫓", "attribute": "修为+5·生命-1%", "from": "fed7aa", "to": "ea580c"},
	# —— 灵膳档 ——
	"yishou_c": {"name": "灵芝益寿面", "icon": "🥢", "attribute": "寿命+1年", "from": "fef3c7", "to": "fcd34d"},
	"qingxin_c": {"name": "天莲清心羹", "icon": "🍵", "attribute": "突破概率+3%", "from": "ccfbf1", "to": "5eead4"},
	"babao_c": {"name": "紫芝八宝饭", "icon": "🍚", "attribute": "灵力+60·生命+10%", "from": "e9d5ff", "to": "a855f7"},
	"qiongyu_c": {"name": "琼玉双拼", "icon": "🍱", "attribute": "修炼速度+10%", "from": "cffafe", "to": "06b6d4"},
	# —— 仙馔档 ——
	"yaochi_c": {"name": "瑶池仙露炖", "icon": "🍮", "attribute": "寿命+3年·突破+5%", "from": "e0e7ff", "to": "818cf8"},
	"jiuzhuan_c": {"name": "九转还魂羹", "icon": "🥘", "attribute": "生命灵力全恢复", "from": "fde68a", "to": "f97316"},
	"longfeng_c": {"name": "烹龙炮凤", "icon": "🔥", "attribute": "突破+10%·修为大增", "from": "fdba74", "to": "dc2626"},
	"binghuo_c": {"name": "冰火两重天", "icon": "♨️", "attribute": "灵力+150·生命-5%", "from": "fca5a5", "to": "67e8f9"},
}
const ITEM_ORDER := [
	"huilingdan", "liaoshangyao", "julingshi", "pojingdan",
	"lingcao", "xianjian", "hushenfu", "chuansongfu",
	"lingshoudan", "xianlu", "fabasuipian", "miji",
	"lingdao_c", "xiancao_c", "lingzhi_c", "tianlian_c",
	"zhuyan_c", "xuanbing_c",
	"gaodian_c", "yanghun_c",
	"biquan_c", "cuiyu_c", "jiaomi_c",
	"yishou_c", "qingxin_c", "babao_c", "qiongyu_c",
	"yaochi_c", "jiuzhuan_c", "longfeng_c", "binghuo_c",
]
const INITIAL_INVENTORY := {
	"huilingdan": 25, "liaoshangyao": 18, "julingshi": 50, "pojingdan": 3,
	"lingcao": 120, "xianjian": 1, "hushenfu": 8, "chuansongfu": 15,
	"lingshoudan": 2, "xianlu": 30, "fabasuipian": 45, "miji": 5,
}

## 生产配方（灵田/灶台共用）：kind = "plot" 种植 / "stove" 烹饪，
## hours = 成熟所需游戏小时，output = 收获数量，costs = 开始生产时扣除的材料。
const RECIPES := {
	"lingdao": {"name": "灵稻", "icon": "🌾", "kind": "plot", "hours": 4.0, "output": 50, "item": "lingdao_c",
		"costs": {"lingcao": 10}},
	"xiancao": {"name": "仙草", "icon": "🍀", "kind": "plot", "hours": 6.0, "output": 30, "item": "xiancao_c",
		"costs": {"lingcao": 15}},
	"lingzhi": {"name": "灵芝", "icon": "🍄", "kind": "plot", "hours": 8.0, "output": 20, "item": "lingzhi_c",
		"costs": {"lingcao": 25, "xiancao_c": 2}},
	"tianlian": {"name": "天莲", "icon": "🌺", "kind": "plot", "hours": 10.0, "output": 15, "item": "tianlian_c",
		"costs": {"lingcao": 40}},
	"zhuyan": {"name": "朱焰果", "icon": "🔴", "kind": "plot", "hours": 7.0, "output": 20, "item": "zhuyan_c",
		"costs": {"lingcao": 30}},
	"xuanbing": {"name": "玄冰瓜", "icon": "🍈", "kind": "plot", "hours": 6.0, "output": 25, "item": "xuanbing_c",
		"costs": {"lingcao": 20}},
	
	
	
	
	"gaodian": {"name": "灵气糕点", "icon": "🥮", "kind": "stove", "hours": 1.25, "output": 1, "item": "gaodian_c",
		"costs": {"lingdao_c": 10, "lingcao": 5}},
	"yanghun": {"name": "养魂汤", "icon": "🍲", "kind": "stove", "hours": 2.0, "output": 1, "item": "yanghun_c",
		"costs": {"xiancao_c": 3, "lingzhi_c": 1}},
	# —— 凡膳档 ——
	"biquan": {"name": "碧泉灵米粥", "icon": "🥣", "kind": "stove", "hours": 0.5, "output": 1, "item": "biquan_c",
		"costs": {"lingdao_c": 6, "lingcao": 4}},
	"cuiyu": {"name": "翠玉仙草冻", "icon": "🍡", "kind": "stove", "hours": 0.75, "output": 1, "item": "cuiyu_c",
		"costs": {"xiancao_c": 3, "lingdao_c": 5}},
	"jiaomi": {"name": "火候焦米饼", "icon": "🫓", "kind": "stove", "hours": 0.5, "output": 1, "item": "jiaomi_c",
		"costs": {"lingdao_c": 8, "lingcao": 2}},
	# —— 灵膳档 ——
	"yishou": {"name": "灵芝益寿面", "icon": "🥢", "kind": "stove", "hours": 2.5, "output": 1, "item": "yishou_c",
		"costs": {"lingzhi_c": 1, "lingdao_c": 10}},
	"qingxin": {"name": "天莲清心羹", "icon": "🍵", "kind": "stove", "hours": 2.5, "output": 1, "item": "qingxin_c",
		"costs": {"tianlian_c": 2, "xiancao_c": 4}},
	"babao": {"name": "紫芝八宝饭", "icon": "🍚", "kind": "stove", "hours": 3.0, "output": 1, "item": "babao_c",
		"costs": {"lingdao_c": 15, "lingzhi_c": 2, "tianlian_c": 1}},
	"qiongyu": {"name": "琼玉双拼", "icon": "🍱", "kind": "stove", "hours": 2.0, "output": 1, "item": "qiongyu_c",
		"costs": {"lingzhi_c": 2, "xiancao_c": 5}},
	# —— 仙馔档 ——
	"yaochi": {"name": "瑶池仙露炖", "icon": "🍮", "kind": "stove", "hours": 5.0, "output": 1, "item": "yaochi_c",
		"costs": {"xianlu": 3, "tianlian_c": 3, "lingzhi_c": 2}},
	"jiuzhuan": {"name": "九转还魂羹", "icon": "🥘", "kind": "stove", "hours": 6.0, "output": 1, "item": "jiuzhuan_c",
		"costs": {"tianlian_c": 5, "lingzhi_c": 4, "xiancao_c": 8}},
	"longfeng": {"name": "烹龙炮凤", "icon": "🔥", "kind": "stove", "hours": 8.0, "output": 1, "item": "longfeng_c",
		"costs": {"lingdao_c": 5, "xiancao_c": 5, "lingzhi_c": 5, "tianlian_c": 5, "zhuyan_c": 5, "xuanbing_c": 5}},
	"binghuo": {"name": "冰火两重天", "icon": "♨️", "kind": "stove", "hours": 4.0, "output": 1, "item": "binghuo_c",
		"costs": {"zhuyan_c": 4, "xuanbing_c": 4, "lingcao": 10}},
	
}

# ---- 玩家属性（暂时静态，等日程/修炼系统接入后再动）----
var player_name := "修仙者"
var player_title := "初入仙途"
var age := 18
var spirit := 750
var spirit_pct := 75.0
var health_pct := 90.0
var breakthrough_pct := 45.0

# ---- 设置（音量暂存数值，接音频总线时再生效）----
var sound_volume := 75
var music_volume := 60
var quality := "high"
var notifications := true

# ---- 运行时数据 ----
var inventory := {}
var farmland := []   # 种植槽位
var stoves := []     # 烹饪槽位

var _slot_state_cache := ""
var _autosave_accum := 0.0


func _ready() -> void:
	_load_or_init()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


func _process(delta: float) -> void:
	_autosave_accum += delta
	if _autosave_accum >= AUTOSAVE_INTERVAL:
		_autosave_accum = 0.0
		save_game()
	var key := _slots_state_key()
	if key != _slot_state_cache:
		_slot_state_cache = key
		slots_changed.emit()


# ---- 槽位逻辑（灵田/灶台通用：空 → 生产中 → 可收获 → 收获归空）----

func slot_progress(slot: Dictionary) -> float:
	# started 允许为负：新档从 06:00 开始，预置进度可能早于第 1 天零点。
	# "未开始"只以 recipe 为空判断（收获后 recipe 清空、started 置回 -1 哨兵）。
	if slot.recipe == "" or not RECIPES.has(slot.recipe):
		return 0.0
	return clampf((TimeManager.game_hours - float(slot.started)) / float(RECIPES[slot.recipe].hours), 0.0, 1.0)


func slot_ready(slot: Dictionary) -> bool:
	return slot.recipe != "" and slot_progress(slot) >= 1.0


## 点击槽位：可收获→收进背包。返回动作名（"harvest"/""）。
## 空地点击不再自动种植，由 UI 层（recipe_picker 弹窗）确认后调用 slot_start()。
func slot_interact(slot: Dictionary) -> String:
	if not slot.unlocked:
		return ""
	if slot_ready(slot):
		var def: Dictionary = RECIPES[slot.recipe]
		slot.last_recipe = slot.recipe
		add_item(String(def.item), int(def.output))
		slot.recipe = ""
		slot.started = -1.0
		slots_changed.emit()
		return "harvest"
	return ""


## 配方分类列表：kind = "plot" 种植 / "stove" 烹饪，按 RECIPES 声明顺序返回 id。
func recipes_of_kind(kind: String) -> Array:
	var out := []
	for id in RECIPES:
		if String(RECIPES[id].kind) == kind:
			out.append(String(id))
	return out


## 空闲槽位以指定配方开始生产：校验解锁、空闲、配方存在、kind 匹配、材料足够，
## 全部通过才一次性扣材料并写入槽位；任一失败返回 false 且状态无任何变化。
func slot_start(slot: Dictionary, recipe_id: String) -> bool:
	if not bool(slot.unlocked) or String(slot.recipe) != "":
		return false
	if not RECIPES.has(recipe_id):
		return false
	var def: Dictionary = RECIPES[recipe_id]
	if String(def.kind) != _slot_kind(slot):
		return false
	var costs: Dictionary = def.costs
	if not can_afford(costs):
		return false
	consume_items(costs)
	slot.recipe = recipe_id
	slot.started = TimeManager.game_hours
	slot.last_recipe = recipe_id
	slots_changed.emit()
	return true


## 槽位归属类型："plot" / "stove"，未知返回 ""。
## 4.6 已无 same()，Dictionary 的 in/has 按内容匹配；farmland 与 stoves 槽位的
## recipe/last_recipe 天然分居 plot/stove 配方域，正常数据不会跨域内容碰撞；
## 若同时命中两数组（仅手改存档可能）则视为歧义，返回 "" 拒绝。
func _slot_kind(slot: Dictionary) -> String:
	var in_plot := farmland.has(slot)
	var in_stove := stoves.has(slot)
	if in_plot and not in_stove:
		return "plot"
	if in_stove and not in_plot:
		return "stove"
	return ""


func slots_state_key() -> String:
	return _slots_state_key()


func _slots_state_key() -> String:
	var parts := PackedStringArray()
	for slot in farmland + stoves:
		parts.append("%s:%s" % [slot.recipe, slot_ready(slot)])
	return ",".join(parts)


# ---- 背包 ----

func add_item(item_id: String, count: int) -> void:
	inventory[item_id] = int(inventory.get(item_id, 0)) + count
	inventory_changed.emit()


func get_item_count(item_id: String) -> int:
	return int(inventory.get(item_id, 0))


## 库存是否满足一组材料需求（costs: item_id -> 数量）
func can_afford(costs: Dictionary) -> bool:
	for item_id in costs:
		if get_item_count(String(item_id)) < int(costs[item_id]):
			return false
	return true


## 原子扣除一组材料：足够则全部扣除并发信号；任一不足返回 false 且不扣任何一项。
func consume_items(costs: Dictionary) -> bool:
	if not can_afford(costs):
		return false
	for item_id in costs:
		inventory[String(item_id)] = get_item_count(String(item_id)) - int(costs[item_id])
	inventory_changed.emit()
	return true


# ---- 初始化与存档 ----

func _load_or_init() -> void:
	if FileAccess.file_exists(SAVE_PATH) and _load_game():
		return
	_init_fresh()


func _init_fresh() -> void:
	inventory = INITIAL_INVENTORY.duplicate()
	farmland = _default_farmland()
	stoves = _default_stoves()
	TimeManager.game_hours = 6.0
	TimeManager.speed = 1.0
	# 按 Figma 设计稿预置生长进度：灵稻75% 仙草40% 灵芝90% 天莲60% / 糕点60% 汤25%
	_seed_progress(farmland[0], 0.75)
	_seed_progress(farmland[1], 0.40)
	_seed_progress(farmland[2], 0.10)
	_seed_progress(farmland[3], 0.60)
	_seed_progress(stoves[0], 0.60)
	_seed_progress(stoves[2], 0.25)


func _seed_progress(slot: Dictionary, frac: float) -> void:
	slot.started = TimeManager.game_hours - float(RECIPES[slot.recipe].hours) * frac


func _default_farmland() -> Array:
	return [
		{"unlocked": true, "level": 3, "recipe": "lingdao", "started": -1.0, "last_recipe": "lingdao"},
		{"unlocked": true, "level": 5, "recipe": "xiancao", "started": -1.0, "last_recipe": "xiancao"},
		{"unlocked": true, "level": 2, "recipe": "lingzhi", "started": -1.0, "last_recipe": "lingzhi"},
		{"unlocked": true, "level": 4, "recipe": "tianlian", "started": -1.0, "last_recipe": "tianlian"},
		{"unlocked": false, "level": 15, "recipe": "", "started": -1.0, "last_recipe": "lingdao"},
		{"unlocked": false, "level": 20, "recipe": "", "started": -1.0, "last_recipe": "lingdao"},
		{"unlocked": false, "level": 25, "recipe": "", "started": -1.0, "last_recipe": "lingdao"},
		{"unlocked": false, "level": 30, "recipe": "", "started": -1.0, "last_recipe": "lingdao"},
	]


func _default_stoves() -> Array:
	return [
		{"unlocked": true, "level": 1, "recipe": "gaodian", "started": -1.0, "last_recipe": "gaodian"},
		{"unlocked": true, "level": 1, "recipe": "", "started": -1.0, "last_recipe": "gaodian"},
		{"unlocked": true, "level": 5, "recipe": "yanghun", "started": -1.0, "last_recipe": "yanghun"},
		{"unlocked": true, "level": 5, "recipe": "", "started": -1.0, "last_recipe": "yanghun"},
		{"unlocked": false, "level": 10, "recipe": "", "started": -1.0, "last_recipe": "gaodian"},
		{"unlocked": false, "level": 15, "recipe": "", "started": -1.0, "last_recipe": "gaodian"},
		{"unlocked": false, "level": 20, "recipe": "", "started": -1.0, "last_recipe": "gaodian"},
		{"unlocked": false, "level": 25, "recipe": "", "started": -1.0, "last_recipe": "gaodian"},
	]


func save_game() -> void:
	var data := {
		"time": {"hours": TimeManager.game_hours, "speed": TimeManager.speed},
		"player": {"age": age, "spirit": spirit, "health_pct": health_pct, "breakthrough_pct": breakthrough_pct},
		"settings": {"sound": sound_volume, "music": music_volume, "quality": quality, "notifications": notifications},
		"inventory": inventory,
		"farmland": _serialize_slots(farmland),
		"stoves": _serialize_slots(stoves),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()


func _serialize_slots(slots: Array) -> Array:
	var out := []
	for s in slots:
		out.append({
			"unlocked": bool(s.unlocked), "level": int(s.level),
			"recipe": String(s.recipe), "started": float(s.started),
			"last_recipe": String(s.get("last_recipe", "")),
		})
	return out


func _load_game() -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = parsed

	var t: Dictionary = data.get("time", {})
	TimeManager.game_hours = float(t.get("hours", 6.0))
	TimeManager.speed = float(t.get("speed", 1.0))

	var p: Dictionary = data.get("player", {})
	age = int(p.get("age", age))
	spirit = int(p.get("spirit", spirit))
	health_pct = float(p.get("health_pct", health_pct))
	breakthrough_pct = float(p.get("breakthrough_pct", breakthrough_pct))

	var st: Dictionary = data.get("settings", {})
	sound_volume = int(st.get("sound", sound_volume))
	music_volume = int(st.get("music", music_volume))
	quality = String(st.get("quality", quality))
	notifications = bool(st.get("notifications", notifications))

	inventory.clear()
	var inv: Dictionary = data.get("inventory", {})
	if typeof(inv) == TYPE_DICTIONARY:
		for k in inv:
			inventory[String(k)] = int(inv[k])
	else:
		inventory = INITIAL_INVENTORY.duplicate()

	farmland = _deserialize_slots(data.get("farmland"), _default_farmland())
	stoves = _deserialize_slots(data.get("stoves"), _default_stoves())
	return true


func _deserialize_slots(arr: Variant, defaults: Array) -> Array:
	if typeof(arr) != TYPE_ARRAY or (arr as Array).is_empty():
		return defaults
	var out := []
	for i in defaults.size():
		var slot: Dictionary = defaults[i].duplicate()
		if i < (arr as Array).size() and typeof(arr[i]) == TYPE_DICTIONARY:
			var sd: Dictionary = arr[i]
			slot.unlocked = bool(sd.get("unlocked", slot.unlocked))
			slot.level = int(sd.get("level", slot.level))
			slot.recipe = String(sd.get("recipe", ""))
			slot.started = float(sd.get("started", -1.0))
			slot.last_recipe = String(sd.get("last_recipe", ""))
		out.append(slot)
	return out
