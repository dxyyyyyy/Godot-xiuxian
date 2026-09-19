extends Node
## UI 级全局状态：设置 / 纪事 / 图鉴发现 / 玉牌红点 + JSON 存档。
## 玩法状态（修炼/灵田/伙房/缘分/轮回）全部在 Game autoload（移植自百味长生灰盒），
## 本单例只承接跨页呈现数据；Game.logged → 纪事，Game.changed → 图鉴回填 + 红点刷新。

signal chronicle_changed
signal tablet_unread_changed

const SAVE_PATH := "user://savegame.json"
const AUTOSAVE_INTERVAL := 30.0

# ---- 设置（音量暂存数值，接音频总线时再生效）----
var sound_volume := 75
var music_volume := 60
var quality := "high"
var notifications := true

# ---- 玉牌数据：纪事 / 图鉴发现 / 红点 / 壁讯订阅 ----
const CHRONICLE_LIMIT := 200
var chronicle: Array = []       # [{day: String("第X世·第X年·M月"), text: String}]，按时间顺序
var discovered_items := {}      # 灵植/占位料 id -> true（图鉴·灵植，源自 DataManager.seeds）
var discovered_recipes := {}    # 菜谱 id -> true（图鉴·菜谱，源自 DataManager.recipes）
var tablet_unread := {}         # app_id -> 未读计数（红点）
var chronicle_unread := 0
var codex_unread := 0
var gossip_subscribed := false

var _autosave_accum := 0.0

## 开始界面「新开一世」置 true → 主界面据此先落玉牌捏脸页(一次性, 读用即清)。
var fresh_start := false


func _ready() -> void:
	_load_or_init()
	# 桥接灰盒核心：月度日志入纪事；结算变化回填图鉴发现并刷新红点
	Game.logged.connect(log_chronicle)
	Game.changed.connect(_on_game_changed)
	sync_discoveries()
	_refresh_unread()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


func _process(delta: float) -> void:
	_autosave_accum += delta
	if _autosave_accum >= AUTOSAVE_INTERVAL:
		_autosave_accum = 0.0
		save_game()


func _on_game_changed() -> void:
	sync_discoveries()
	_refresh_unread()


# ---- 纪事 ----

## 纪事记录：一行为一事，滚动上限 CHRONICLE_LIMIT；时间戳取灰盒月历。
func log_chronicle(text: String) -> void:
	chronicle.append({"day": Game.calendar(), "text": text})
	while chronicle.size() > CHRONICLE_LIMIT:
		chronicle.pop_front()
	chronicle_unread += 1
	chronicle_changed.emit()
	_refresh_unread()


# ---- 图鉴发现（由灰盒 run 状态推导回填）----

## 已入库灵植 / 千年灵植 / 已烹已吃菜谱 / 已习得菜谱（境界门槛达到即算习得）。
func sync_discoveries() -> void:
	if Game.run.is_empty() or not Game.run.has("farm"):
		return
	var f: Dictionary = Game.farm()
	for seed_id in f.get("inv", {}):
		_discover_item(String(seed_id))
	if int(f.get("millennium", 0)) > 0:
		_discover_item("millennium")
	if int(f.get("yaodan", 0)) > 0:
		_discover_item("yaodan")
	for p in f.get("plots", []):
		if String(p.get("seed", "")) != "":
			_discover_item(String(p.seed))
	for rid in f.get("dishes", {}):
		_discover_recipe(String(rid))
	for rid in f.get("eaten", {}):
		_discover_recipe(String(rid))
	for r in DataManager.recipes:
		if int(Game.run.get("realm", 0)) >= int(r.get("min_realm", 0)):
			_discover_recipe(String(r.id))


## 图鉴发现：notify=false 用于读档/初始化回填，不亮红点。
func _discover_item(item_id: String, notify := true) -> void:
	if discovered_items.has(item_id):
		return
	discovered_items[item_id] = true
	if notify:
		codex_unread += 1
		_refresh_unread()


func _discover_recipe(recipe_id: String, notify := true) -> void:
	if discovered_recipes.has(recipe_id):
		return
	discovered_recipes[recipe_id] = true
	if notify:
		codex_unread += 1
		_refresh_unread()


# ---- 红点 ----

## 打开 app 即消红点：纪事/图鉴清计数器，闲话壁清灰盒已读位。
func mark_app_opened(app_id: String) -> void:
	match app_id:
		"chronicle":
			chronicle_unread = 0
		"codex":
			codex_unread = 0
		"gossip":
			Game.wall_mark_read()
	_refresh_unread()


## 各 app 未读数（红点总开关关闭时全部归零，玉牌照常可用）。
func app_unread(app_id: String) -> int:
	if not notifications:
		return 0
	return int(tablet_unread.get(app_id, 0))


func unread_total() -> int:
	if not notifications:
		return 0
	var total := 0
	for app_id in tablet_unread:
		total += int(tablet_unread[app_id])
	return total


## 闲话壁红点来自灰盒壁帖未读数；纪事/图鉴走未读计数器。
func _refresh_unread() -> void:
	var next := {
		"chronicle": chronicle_unread,
		"codex": codex_unread,
		"gossip": Game.wall_unread(),
	}
	if next != tablet_unread:
		tablet_unread = next
		tablet_unread_changed.emit()


func set_notifications(v: bool) -> void:
	if notifications == v:
		return
	notifications = v
	tablet_unread_changed.emit()


# ---- 初始化与存档 ----

func _load_or_init() -> void:
	if FileAccess.file_exists(SAVE_PATH) and _load_game():
		return
	_init_fresh()


## 开始界面「新开一世」: 清空 UI 侧存档(纪事 / 图鉴发现 / 红点)并落盘。
func reset_all() -> void:
	discovered_items.clear()
	discovered_recipes.clear()
	chronicle.clear()
	chronicle_unread = 0
	codex_unread = 0
	_init_fresh()
	_refresh_unread()
	save_game()


func _init_fresh() -> void:
	chronicle.clear()
	chronicle_unread = 0
	codex_unread = 0
	gossip_subscribed = false
	tablet_unread = {}
	log_chronicle("入百味宗门墙 —— 选时速档、选行动方案，岁月自会走。")


func save_game() -> void:
	var data := {
		"settings": {"sound": sound_volume, "music": music_volume, "quality": quality, "notifications": notifications},
		"chronicle": chronicle,
		"tablet": {
			"chronicle_unread": chronicle_unread,
			"codex_unread": codex_unread,
			"gossip_subscribed": gossip_subscribed,
		},
		"discovered": {"items": discovered_items.keys(), "recipes": discovered_recipes.keys()},
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()


func _load_game() -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = parsed

	var st: Dictionary = data.get("settings", {})
	sound_volume = int(st.get("sound", sound_volume))
	music_volume = int(st.get("music", music_volume))
	quality = String(st.get("quality", quality))
	notifications = bool(st.get("notifications", notifications))

	# 纪事（旧档 day 为 int 天数，迁为字符串标签；缺节走默认值）
	chronicle.clear()
	var ch: Variant = data.get("chronicle", [])
	if typeof(ch) == TYPE_ARRAY:
		for e in ch:
			if typeof(e) == TYPE_DICTIONARY:
				var d: Variant = e.get("day", "")
				var day_s := String(d) if typeof(d) == TYPE_STRING else "旧岁·%s" % str(d)
				chronicle.append({"day": day_s, "text": String(e.get("text", ""))})
	var tb_v: Variant = data.get("tablet", {})
	var tb: Dictionary = tb_v if typeof(tb_v) == TYPE_DICTIONARY else {}
	chronicle_unread = int(tb.get("chronicle_unread", 0))
	codex_unread = int(tb.get("codex_unread", 0))
	gossip_subscribed = bool(tb.get("gossip_subscribed", false))
	discovered_items.clear()
	discovered_recipes.clear()
	var dv_v: Variant = data.get("discovered", {})
	var dv: Dictionary = dv_v if typeof(dv_v) == TYPE_DICTIONARY else {}
	var di: Variant = dv.get("items", [])
	if typeof(di) == TYPE_ARRAY:
		for id in di:
			_discover_item(String(id), false)
	var dr: Variant = dv.get("recipes", [])
	if typeof(dr) == TYPE_ARRAY:
		for id in dr:
			_discover_recipe(String(id), false)
	tablet_unread = {}
	return true
