extends Node
## 《百味长生》M0 灰盒核心模拟器 —— GDD v1.2 口径(2026-09-10 22:46)。
## v1.2 换代: 取消 AP/回合/忙闲月 —— 时间在线常流(月 tick, 关闭即冻结),
## 主页时速档(暂停→100×, 1×≈2秒/月); 玩家选「行动方案」(倍率×冷却自动执行);
## 特殊事件命中即自动暂停待决策, 结算琐碎逐月并为『第Y年·M月 · …』一行入「一世纪事」(2026-09-11 拍板: 取消保底打断与暂停月报弹窗)。
## 铁律(§12): 时速档只改 tick 频率、不改结算逻辑 —— 一切结算都在 tick_month() 唯一入口。
## 数值锚点沿用 v1.1 标定: 寿元九档、30 小层 100×1.55^(n−1)、境界基数、道韵/结局表。

signal logged(text: String, day: String)   # day=纪事时间戳: 月报行传「刚过去月」, 其余空→calendar()
signal changed
signal ended(summary: Dictionary)
signal interrupted(event: Dictionary)   # {title,text,options:Array,kind,data}

const SCHEMA := 4
const START_AGE_M := 192                 # 16 岁测灵根入道(月)
const ENDING_MULT := {"飞升": 2.0, "圆满隐退": 1.2, "渡劫陨落": 0.5, "寿尽坐化": 0.3}  # §4.2 未改
const START_DAO := 100                   # 新档起始道韵(入世即可购灵根/特质的预算)
const FORGE_COST := 20                   # 铸体: 20 道韵 → 灵根+0.1(一世)
const FORGE_STEP := 0.1
const BLESS_COST := 50                   # 天道眷顾: 50 道韵 → 冲关率+2%(永久, §11)
const BLESS_STEP := 0.02
const ELEMENTS := ["金", "木", "水", "火", "土"]
## 灵根即「身负几行」: 默认五行俱全(五灵根)免费; 每炼去一行更贵(边际 30/50/70/90, 累计 30/80/150/240)。
## 行数定聚灵系数(每炼一行 +0.25), 持有哪几行定灵田亲和覆盖面 —— 五行广而垫底, 单行窄而极强。
const ROOT_COUNTS := [5, 4, 3, 2, 1]
const ROOT_COUNT_COEF := {5: 0.65, 4: 0.90, 3: 1.15, 2: 1.40, 1: 1.65}
const ROOT_TRIM_COST := {4: 30, 3: 80, 2: 150, 1: 240}   # 炼到该行数的一世总花费(五行=0)
const MUTE_PASS := ["═══", "——", "寿元曲线", "享年", "结算", "魂魄", "◎"]

var rng := RandomNumberGenerator.new()
const NpcGeneratorScript := preload("res://sim/NpcGenerator.gd")
var npc_generator := NpcGeneratorScript.new()
const WorldSimScript := preload("res://sim/WorldSim.gd")
var world_sim := WorldSimScript.new()
const Portrait := preload("res://scripts/portrait.gd")
var meta: Dictionary = {}
var run: Dictionary = {}
var muted := false
var deterministic := false               # 模拟: 无随机事件、冲关必成、打断自动选第一项
var duijie_cap := 1800                   # M0 旋钮: 渡劫寿元 1800 ↔ 1500
var sim_trace: Array = []

# ---- 常流时钟 ------------------------------------------------
var speed := 0                           # 0=暂停; 1/2/5/10/25/50/100
var _resume_speed := 0                   # 事件打断前的档位
var _tick_acc := 0.0

# ---- 事件与月报行 ----------------------------------------------
var pending: Dictionary = {}             # 当前待决策打断(空=无事)
var month_notes: PackedStringArray = []  # 本月结算琐碎(只存结果不存过程), 月末随『第Y年·M月 · …』行入日志后清空

func tune(key: String, def: Variant = null) -> Variant:
	return DataManager.tuning.get(key, def)

## 经营系统调参(详解卷 6.6.1: 概率与倍率集中在 economy_tuning.json)
func econ(key: String, def: Variant = null) -> Variant:
	return DataManager.economy.get(key, def)

func _ready() -> void:
	rng.randomize()
	duijie_cap = int(tune("duijie_cap_years", 1800))
	meta = SaveSystem.load_meta()
	if meta.is_empty() or int(meta.get("schema", 0)) != SCHEMA:
		meta = {"schema": SCHEMA, "dao": START_DAO, "lives": 0, "best_ord": 0, "best_name": "无", "bless_pct": 0.0, "bonds": 0, "endings": {}}
	var loaded := SaveSystem.load_open_run()
	if not loaded.is_empty() and int(loaded.get("schema", 0)) == SCHEMA:
		run = loaded
		_log("—— 读档: 继续第 %d 世(%s·%s), 时间静止于 %d× ——" % [run.life, run.origin, realm().name, 0])
	else:
		_start_life(default_origin(), 0)
	_ensure_run()
	changed.emit()

## 老档惰性补齐(食修效果字段, 不 bump SCHEMA)
func _ensure_run() -> void:
	if run.is_empty() or not run.has("farm"):
		return
	if not run.has("buffs"):
		run.buffs = {}
	if not run.has("qi"):
		run.qi = 100
	if not run.has("aptitude"):
		run.aptitude = 0.0
	if not run.has("life_bonus"):
		run.life_bonus = 0
	if not run.has("luck"):
		run.luck = 0
	if not run.has("break_bonus"):
		run.break_bonus = 0.0
	if not run.has("recover"):
		run.recover = 0   # 退养闭关剩余月数(老档补 0)
	if not run.has("roots"):
		# 老档单属灵根 → 归一为「单行」持有(系数沿用旧值不重算), 不 bump SCHEMA
		run.roots = [String(run.element)] if String(run.element) in ELEMENTS else ["木"]
		run.root_count = int(run.roots.size())
	if not run.has("traits"):
		run.traits = []   # 天生特质(一世, 转世卡兑换; 老档无=没买)
	if not run.has("facilities"):
		run.facilities = {"julingzhen": 0, "lingquan": 0, "cangjingge": 0, "daiketingyuan": 0}
	if not run.has("wall"):
		run.wall = {"posts": [], "queue": [], "read": 0, "rotate_cd": 1}
	if Array(run.wall.get("posts", [])).is_empty():
		_wall_seed_opening()   # 照壁不是空壁: 新世/旧空档(含被旧版本补过空 wall 的档)一律预置旧帖
	if not run.has("travel_dest"):
		run.travel_dest = "auto"
	if not run.has("world_npcs"):
		run.world_npcs = {}
		run.world_rels = []
		_seed_world()   # 老档补一次世界池(只补这一次; 后加的固定 NPC 不追溯, 新世自然生效)
	if not run.has("npc_romance"):
		run.npc_romance = {}
	if not run.has("follows"):
		# 老档补关注列表: 已设「喜欢」(原特别关注)者默认在册; 不 bump SCHEMA
		var f_old := String(run.get("focus", ""))
		if f_old != "" and bool((run.get("npcs", {}) as Dictionary).get(f_old, {}).get("met", false)):
			run.follows = [f_old]
		else:
			run.follows = []
	if not run.farm.has("yaodan"):
		run.farm.yaodan = 0   # 妖丹计数(伏妖战功, 老档补 0, 不 bump SCHEMA)
	for key in run.get("npcs", {}):   # NPC 档迁移: 旧 5 态 0-100 量程 → 新 6 态 0-1000(陌生态插入), 全员视作已入册
		var npc: Dictionary = run.npcs[key]
		if not npc.has("met"):
			npc.met = true
			npc.aff = float(npc.aff) * 10.0
			npc.stage = int(npc.stage) + 1
			npc.hidden = 0.0
			npc.talk_q = 0
			npc.gift_q = 0
			npc.dao_lu = int(npc.stage) >= 5
		if not npc.has("talk_q"):
			npc.talk_q = 0
		if not npc.has("gift_q"):
			npc.gift_q = 0
		if not npc.has("love"):
			# 双轨拆分迁移: 旧档 3 段以上(心动/相恋/道侣)者, 超出相熟阈值(400)的好感即为已积累的情分; 其余情值自 0
			npc.love = maxf(0.0, float(npc.get("aff", 0.0)) - 400.0) if int(npc.get("stage", 0)) >= 3 else 0.0
		if String(key).begins_with("rand_") and npc_generator.OLD_FLAVOR_NAMES.has(String(npc.get("name", ""))):
			var used_names := {}   # 旧版风味名(非真名) → 迁移为程序化新名 + 人称别号
			for k2 in run.npcs:
				used_names[String(run.npcs[k2].get("name", ""))] = true
			npc.name = npc_generator.generate_name(rng, used_names)
			npc.alias = npc_generator.generate_epithet(rng)
	# 人生档案回填(四柱·寿元): 在册/池内老人补生辰/灵根/气血; 掷到成年者顺带 grown, 不误触成年礼报闻
	for pool in [run.npcs, run.get("world_npcs", {})]:
		for key in (pool as Dictionary).keys():
			_npc_vitals_backfill((pool as Dictionary)[key], String(key))

func _process(delta: float) -> void:
	if speed <= 0 or not run.has("age_m") or is_ended() or not pending.is_empty():
		return
	_tick_acc += delta * float(speed) * float(tune("speed_base_mps", 0.5))
	var guard := 0
	while _tick_acc >= 1.0:
		_tick_acc -= 1.0
		tick_month()
		guard += 1
		if guard >= 64 or is_ended() or not pending.is_empty():   # 单帧保护 & 命中即停
			break

## 移植增强: 关窗/退出时保档(与 GameState 的 WM_CLOSE 存档并存, 各写各的文件)
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not run.is_empty() and not bool(run.get("ended", false)):
		SaveSystem.save_run(run)

## 测试用: 以「逐月调用」的方式推进 n 月(与 _process 走同一 tick_month 入口, 验证倍速无关性)
func step_months(n: int) -> void:
	for i in range(n):
		if is_ended():
			break
		if not pending.is_empty():
			resolve_option(0)
		tick_month()
	if is_ended():
		return
	changed.emit()

func debug_seed(s: int) -> void:
	rng.seed = s

# ---------------------------------------------------------------- 状态访问

func realm() -> Dictionary:
	return DataManager.realm(int(run.get("realm", 0)))

func is_ended() -> bool:
	return bool(run.get("ended", false))

func plan() -> Dictionary:
	return DataManager.plan(String(run.get("plan", "pure")))

func plan_mult() -> float:
	return float(plan().get("mult", 1.0))

func age_years() -> float:
	return float(run.age_m) / 12.0

func lifespan_cap_years() -> int:
	# 仙膳「寿命」永久加成(全世合计 ≤+3 年, 图鉴 6.5 已记冲突拍板: 触碰寿元硬时钟, M0 纳入模拟重标); 长寿相同为加数
	if String(realm().get("key", "")) == "dujie":
		return duijie_cap + int(run.get("life_bonus", 0)) + int(round(_trait_fx("life")))
	return int(realm().lifespan_cap) + int(run.get("life_bonus", 0)) + int(round(_trait_fx("life")))

func calendar() -> String:
	var y := (int(run.age_m) - START_AGE_M) / 12 + 1
	var m := (int(run.age_m) - START_AGE_M) % 12 + 1
	return "第%d世 · 第%d年 · %d月" % [run.life, y, m]


## 「刚过去月」(0 基序号)的月历标签: tick 开头已把 age_m 前拨, 月报纪事若用 calendar() 会整体早一个月
## (腊月线落进下一年卷) —— 纪事日戳须按结算月计, 与 _emit_month_note 的 idx 同一口径。
func calendar_idx(idx: int) -> String:
	return "第%d世 · 第%d年 · %d月" % [run.life, idx / 12 + 1, idx % 12 + 1]

## —— 气质(aura)修正: 主角取 run.look.aura, NPC 取原型/存档的 appearance.aura; 量级克制(±2~3%/10%)
## self 键: cult=月修为乘项 insight=顿悟pp break=冲关率加项 aff=好感增速乘项 event=机缘概率乘项
## npc  键: aff=他人追这位 NPC 时的好感增速乘项
func aura_self(key: String) -> float:
	var a := DataManager.aura_def(String(player_look().get("aura", "")))
	return float((a.get("self", {}) as Dictionary).get(key, 0.0))


## 名录页用的气质提示串: 清冷「好感 −10%」/ 热络「好感 +10%」, 中性返回空串。
func aura_npc_hint(npc_key: String) -> String:
	var m := aura_npc_aff(npc_key)
	if absf(m) < 0.001:
		return ""
	return "（好感 %+.0f%%）" % (m * 100.0)


func aura_npc_aff(npc_key: String) -> float:
	var npc: Dictionary = run.get("npcs", {}).get(npc_key, {})
	var arch: Dictionary = npc_arch(npc_key)   # 原型(固定 NPC 的外观含气质)
	var appr: Dictionary = arch.get("appearance", npc.get("appearance", {}))
	var a := DataManager.aura_def(String(appr.get("aura", "")))
	return float((a.get("npc", {}) as Dictionary).get("aff", 0.0))


## —— NPC 关系网: 两层边 —— ① relations.json 手写静态边(固定 NPC 之间, 数据层不随存档变化);
## ② run.world_rels 动态边(世界池生成, 随存档)。每条边 {a,b,tag,val,note[,r_note]}:
## val 亲疏值 −100~+100; tag/note 是「从 a 看 b」的口径, 反向看取 r_note(r_tag), 没写就照搬。
## 查表先静态后动态 —— 手写设定永远压过程序生成。

## 取两人关系(无向): {peer,tag,val,note[,aff,stage,married]}; 没有预设关系返回空字典。
## 恋爱态(run.npc_romance)覆盖展示 tag: 已婚→夫妻, 否则按好感段(相识/相熟/心动/相恋)。
func relation_between(a: String, b: String) -> Dictionary:
	if a == "" or b == "" or a == b:
		return {}
	var base := {}
	for e in DataManager.relations:
		var ea := String(e.get("a", ""))
		var eb := String(e.get("b", ""))
		if ea == a and eb == b:
			base = {"peer": b, "tag": String(e.get("tag", "旧识")), "val": float(e.get("val", 0.0)), "note": String(e.get("note", ""))}
			break
		if ea == b and eb == a:
			base = {"peer": b, "tag": String(e.get("r_tag", e.get("tag", "旧识"))), "val": float(e.get("val", 0.0)), "note": String(e.get("r_note", e.get("note", "")))}
			break
	if base.is_empty():
		for e in run.get("world_rels", []):
			var ea2 := String(e.get("a", ""))
			var eb2 := String(e.get("b", ""))
			if ea2 == a and eb2 == b:
				base = {"peer": b, "tag": String(e.get("tag", "新识")), "val": float(e.get("val", 0.0)), "note": String(e.get("note", ""))}
				break
			if ea2 == b and eb2 == a:
				# 动态边同静态边一样支持方向称谓(亲子边 tag=娃视角, r_tag=长辈视角)
				base = {"peer": b, "tag": String(e.get("r_tag", e.get("tag", "新识"))), "val": float(e.get("val", 0.0)), "note": String(e.get("r_note", e.get("note", "")))}
				break
	var r: Dictionary = run.get("npc_romance", {}).get(_pair_key(a, b), {})
	if not r.is_empty():
		if base.is_empty():
			base = {"peer": b, "tag": "新识", "val": 0.0, "note": ""}
		var names: Array = tune("aff_stages", ["陌生", "相识", "相熟", "心动", "相恋", "道侣"])
		base.tag = "夫妻" if bool(r.get("married", false)) else String(names[clampi(int(r.get("stage", 0)), 1, 4)])
		base.aff = float(r.get("aff", 0.0))
		base.stage = int(r.get("stage", 0))
		base.married = bool(r.get("married", false))
	return base


## 某人对外的人际关系全表, 按亲疏从亲到疏排序(名录/详情/传言共用)。静态边优先, 按 peer 去重。
func npc_relations(key: String) -> Array:
	var out: Array = []
	var seen := {}
	for e in DataManager.relations:
		var ea := String(e.get("a", ""))
		var eb := String(e.get("b", ""))
		if ea != key and eb != key:
			continue
		var peer := eb if ea == key else ea
		out.append(relation_between(key, peer))
		seen[peer] = true
	for e in run.get("world_rels", []):
		var ea2 := String(e.get("a", ""))
		var eb2 := String(e.get("b", ""))
		if ea2 != key and eb2 != key:
			continue
		var peer2 := eb2 if ea2 == key else ea2
		if seen.has(peer2):
			continue
		seen[peer2] = true
		out.append(relation_between(key, peer2))
	out.sort_custom(func(x, y): return float(x.val) > float(y.val))
	return out


## 关系光环(轻度联动 · 只加分不扣分): 你亲近的人 A 若与 B 交好, 则 B 领你的情面, 好感增速上浮;
## 亲疏(val/100) × 你与 A 的情分(aff/1000) × 系数累加, 全员合计不超上限 —— 变心的后果只是没了这份加成,
## 绝不做负面折扣(乙女红线: 没有惩罚性恋爱系统)。交恶者(val≤0)直接跳过, 既不加也不减。
func relation_halo(key: String) -> float:
	if run.is_empty() or not run.has("npcs"):
		return 0.0
	var per := float(tune("rel_halo_per", 0.30))
	var cap := float(tune("rel_halo_max", 0.20))
	var sum := 0.0
	for other in run.npcs:
		var ok := String(other)
		if ok == key or not bool(run.npcs[ok].get("met", false)):
			continue
		var rel := relation_between(ok, key)
		if rel.is_empty():
			continue
		var v := float(rel.get("val", 0.0))
		if v <= 0.0:
			continue
		var bond := clampf(maxf(float(run.npcs[ok].get("aff", 0.0)), float(run.npcs[ok].get("love", 0.0))) / 1000.0, 0.0, 1.0)
		sum += (v / 100.0) * bond * per
	return minf(sum, cap)


## 初见礼(轻度联动): 与你亲近的人恰好是 Ta 的故交时, 攀谈入册即携一份初始好感(与「介绍人携好感」同口径,
## 也是首遇制的既有例外); 取「最铁的那条线」而非累加, 上限 tune(rel_gift_max)。交恶不计 —— 不做惩罚。
## 返回 {v=好感, from=牵线人}。
func _relation_gift(key: String) -> Dictionary:
	if run.is_empty() or not run.has("npcs"):
		return {"v": 0.0, "from": ""}
	var per := float(tune("rel_gift_per", 0.30))
	var cap := float(tune("rel_gift_max", 20.0))
	var best := 0.0
	var who := ""
	for other in run.npcs:
		var ok := String(other)
		if ok == key or not bool(run.npcs[ok].get("met", false)):
			continue
		var rel := relation_between(ok, key)
		if rel.is_empty():
			continue
		var v := float(rel.get("val", 0.0))
		if v <= 0.0:
			continue
		var bond := clampf(maxf(float(run.npcs[ok].get("aff", 0.0)), float(run.npcs[ok].get("love", 0.0))) / 1000.0, 0.0, 1.0)
		var g := v * bond * per
		if g > best:
			best = g
			who = npc_name(ok)
	return {"v": minf(best, cap), "from": who}


## 名录页用的关系提示串: 「故人情面 好感 +8%」; 无光环返回空串。
func relation_halo_hint(npc_key: String) -> String:
	var m := relation_halo(npc_key)
	if m < 0.001:
		return ""
	return "（故人情面 好感 +%.0f%%）" % (m * 100.0)


# ---------------------------------------------------------------- 世界 NPC 池(未识亦在世)

## 开局即在世的随机 NPC: run.world_npcs(生成器快照, 不进名录) + run.world_rels(动态边)。
## 主角未遇见不入册; 但池内彼此、池与固定 NPC(含后续新增的掌门等档案)之间预有关系 ——
## 八卦有来由、初见有情面、拒绝过的脸日后可再遇。边模板放本侧, NpcGenerator 只管造人。

const WORLD_REL_TAGS := [
	["新识", 15, 30, ["%s与%s近日才认识, 见面还客客气气。", "一个是%s, 一个是%s, 坊市里刚处上点头之交。"]],
	["街坊", 20, 45, ["%s和%s是街坊, 抬头不见低头见。", "%s家的灶台挨着%s家的, 烟都往一处飘。"]],
	["同门", 30, 60, ["%s与%s同出一门, 师兄弟相称。", "听%s说, 当年与%s一起挑过水。"]],
	["酒友", 20, 50, ["%s与%s顿顿对饮, 酒钱轮流掏。", "%s不醉, 因为酒都让%s喝了。"]],
	["棋友", 15, 40, ["%s与%s在茶摊摆棋, 输了付茶钱。", "%s的棋, 只有%s肯连输三局还笑。"]],
	["点头交", 10, 25, ["%s与%s点头之交, 多年没说过整句。", "路上遇见, %s朝%s拱拱手, 就算打过照面。"]],
	["旧怨", -40, -15, ["%s与%s为地契拌过嘴, 至今不同席。", "%s欠%s一句道歉, 拖了十年。"]],
]


func _npc_is_met(key: String) -> bool:
	return run.has("npcs") and run.npcs.has(key) and bool(run.npcs[key].get("met", false))


## 造人/连边时给生成器看的「已占用」集: 已入册 + 已在池(姓名去重与 rand_ 序号都靠它)。
func _world_existing() -> Dictionary:
	var m: Dictionary = run.npcs.duplicate()
	if run.has("world_npcs"):
		m.merge(run.world_npcs, true)
	return m


## 造一条动态边。派系亲疏先验: 同派系更不易结怨(neg 概率 world_rel_neg_same, 默认 5%,
## 异派系 15% —— 低头不见抬头见), 且亲疏整体上移 world_rel_same_bonus —— 同门照拂、同行相护,
## 同派系的边更容易落进 rel_close_min 的亲近带(至交漂移/传言/初见情面都吃这个带)。
func _make_world_edge(a: String, b: String) -> Dictionary:
	var fac_a := _npc_faction(a)
	var same := fac_a != "" and fac_a == _npc_faction(b)
	var neg_rate := float(tune("world_rel_neg_same", 0.05)) if same else float(tune("world_rel_neg_rate", 0.15))
	var neg := rng.randf() < neg_rate
	var pool: Array = []
	for t in WORLD_REL_TAGS:
		if (neg and int(t[1]) < 0) or (not neg and int(t[1]) >= 0):
			pool.append(t)
	var t: Array = pool[rng.randi_range(0, pool.size() - 1)]
	var note := String(t[3][rng.randi_range(0, (t[3] as Array).size() - 1)]) % [npc_name(a), npc_name(b)]
	var val := float(rng.randi_range(int(t[1]), int(t[2])))
	if same:
		val += float(tune("world_rel_same_bonus", 15.0))
	return {"a": a, "b": b, "tag": String(t[0]), "val": clampf(val, -100.0, 100.0), "note": note}


## 派系(identity): 在册/池内快照与固定档案(npcs.json)同字段取名 —— 「物以类聚」的关系先验用它。
func _npc_faction(key: String) -> String:
	var e := _npc_entry(key)
	if not e.is_empty():
		return String(e.get("identity", ""))
	for nd in DataManager.npcs:
		if String(nd.get("key", "")) == key:
			return String(nd.get("identity", ""))
	return ""


## 两人是否已有边(本轮 pairs 或存档 静态+动态) —— 选对端时先探一刀, 免得抽签空转。
func _pair_known(a: String, b: String, pairs: Dictionary) -> bool:
	if a == "" or b == "" or a == b:
		return true
	var pair := a + "|" + b if a < b else b + "|" + a
	return pairs.has(pair) or not relation_between(a, b).is_empty()


## 挑「相识对端」(派系先验): 以 world_rel_same_faction 的概率在同派系里找(试连 8 次避开已有边);
## 同派系无人可连或概率未命中 → 退回全池随机。派系是偏向不是隔离: 跨派系的缘分照旧发生。
func _pick_relate_partner(a: String, all_keys: Array, pairs: Dictionary, same_p: float) -> String:
	if rng.randf() < same_p:
		var fac := _npc_faction(a)
		if fac != "":
			var kin: Array = []
			for k in all_keys:
				var ks := String(k)
				if ks != a and _npc_faction(ks) == fac:
					kin.append(ks)
			for _t in mini(8, kin.size()):
				var cand := String(kin[rng.randi_range(0, kin.size() - 1)])
				if not _pair_known(a, cand, pairs):
					return cand
	return String(all_keys[rng.randi_range(0, all_keys.size() - 1)])


## 开世造世界: 一批池内 NPC + 彼此/与固定 NPC 的关系边。循环一律遍历 DataManager.npcs,
## 后续新增固定档案(掌门等)自动进网; 已有边(静态或动态)不重复连。
## 派系先验: 每人 1~2 条边走 _pick_relate_partner(同派系更易相识、更亲近, 见 _make_world_edge);
## 枢纽边保持全池随机 —— 枢纽的天职就是跨派系搭桥, 网才连成一张而不是一堆孤岛。
func _seed_world() -> void:
	var count := int(tune("world_npc_count", 50))
	for _i in count:
		var npc := npc_generator.generate(rng, _world_existing())
		if npc.is_empty():
			break
		run.world_npcs[String(npc.key)] = npc
		_npc_vitals_backfill(npc, String(npc.key))
	var world_keys: Array = (run.world_npcs as Dictionary).keys()
	var all_keys := world_keys.duplicate()
	for nd in DataManager.npcs:
		all_keys.append(String(nd.key))
	var same_p := float(tune("world_rel_same_faction", 0.75))
	var pairs := {}
	for a in world_keys:
		var want := 1 + (1 if rng.randf() < maxf(0.0, float(tune("world_rel_per_npc", 1.5)) - 1.0) else 0)
		for _w in want:
			_try_world_edge(String(a), _pick_relate_partner(String(a), all_keys, pairs, same_p), pairs)
	for _h in int(count * 0.3):   # 枢纽边: 让少数人认识很多人, 网才有「世故」味
		_try_world_edge(String(all_keys[rng.randi_range(0, all_keys.size() - 1)]), String(all_keys[rng.randi_range(0, all_keys.size() - 1)]), pairs)
	_seed_fixed_floor(world_keys, pairs)   # 保底: 每位固定 NPC 至少一条边 —— 新档案自动进网是口径, 不靠抽签
	_seed_start_couples()


## 固定 NPC 保底连线: 抽签式的 per-NPC/hub 边可能漏掉档案新人(掌门等), 无边的补一条到池内随机人。
func _seed_fixed_floor(world_keys: Array, pairs: Dictionary) -> void:
	if world_keys.is_empty():
		return
	for nd in DataManager.npcs:
		var fk := String(nd.key)
		var linked := false
		for e in run.world_rels:
			if String(e.get("a", "")) == fk or String(e.get("b", "")) == fk:
				linked = true
				break
		if linked:
			continue
		var n0: int = int(run.world_rels.size())
		for _t in 8:
			if run.world_rels.size() > n0:
				break
			_try_world_edge(fk, String(world_keys[rng.randi_range(0, world_keys.size() - 1)]), pairs)


## 开局婚配: 世界池随机点几对成年未婚异性结为夫妻 —— 市井本该有人家。
## 走与月结婚配同一套恋爱边(run.npc_romance married 态 + 双方 spouse 字段), 日后可降段退婚、按率添丁;
## 静默播种不发报闻(玩家未逢, 无喜可观), 一夫一妻由 _rom_taken/_rom_eligible 双守卫; 婚配边亲疏拉进高带(60~90) —— 夫妻必高好感。
func _seed_start_couples() -> void:
	var rom: Dictionary = run.get("npc_romance", {})
	var keys: Array = (run.world_npcs as Dictionary).keys()
	var want := int(tune("world_start_couples", 2))
	var guard := maxi(want, 1) * 15   # 防抽样死循环: 池小/多幼年时尽力而为
	while want > 0 and guard > 0 and keys.size() >= 2:
		guard -= 1
		var a := String(keys[rng.randi_range(0, keys.size() - 1)])
		var b := String(keys[rng.randi_range(0, keys.size() - 1)])
		if _rom_taken(rom, a) or _rom_taken(rom, b) or not _rom_eligible(a, b):
			continue
		_try_world_edge(a, b, {})   # 缘分来由: 无则补一条边(已有则跳过)
		for e in run.world_rels:   # 夫妻必高亲疏: 婚配边拉进高带, 杜绝「旧怨夫妻」(展示层恋爱态只覆盖 tag 不改 val)
			var ea2 := String(e.get("a", ""))
			var eb2 := String(e.get("b", ""))
			if (ea2 == a and eb2 == b) or (ea2 == b and eb2 == a):
				e.val = float(rng.randi_range(60, 90))
				break
		rom[_pair_key(a, b)] = {"aff": 1000.0, "stage": 5, "married": true}
		var ea := _npc_entry(a)
		var eb := _npc_entry(b)
		ea.spouse = b
		eb.spouse = a
		want -= 1


func _try_world_edge(a: String, b: String, pairs: Dictionary, allow_dead := false) -> void:
	if a == "" or b == "" or a == b:
		return
	if not allow_dead and (npc_is_dead(a) or npc_is_dead(b)):
		return   # 故者与生人不结新交(旧边保留作纪念); 亲子边例外 —— 血脉名分不因死而断
	var pair := a + "|" + b if a < b else b + "|" + a
	if pairs.has(pair) or not relation_between(a, b).is_empty():
		return
	pairs[pair] = true
	run.world_rels.append(_make_world_edge(a, b))


## 从世界池抽一位未识者: 多数偏向「与已入册者有边」的 —— 情面/八卦有来由。
func _pick_pool_npc() -> String:
	if not run.has("world_npcs") or (run.world_npcs as Dictionary).is_empty():
		return ""
	var keys: Array = []
	for k in (run.world_npcs as Dictionary).keys():
		if not bool(((run.world_npcs as Dictionary)[k] as Dictionary).get("dead", false)):
			keys.append(String(k))   # 坐化者退出生抽: 缘不再牵给故纸堆
	if keys.is_empty():
		return ""
	if rng.randf() < float(tune("world_pool_prefer_met", 0.6)):
		var connected: Array = []
		for k in keys:
			for e in run.world_rels:
				var ea := String(e.get("a", ""))
				var eb := String(e.get("b", ""))
				var peer := eb if ea == String(k) else (ea if eb == String(k) else "")
				if peer != "" and _npc_is_met(peer):
					connected.append(String(k))
					break
		if not connected.is_empty():
			return String(connected[rng.randi_range(0, connected.size() - 1)])
	return String(keys[rng.randi_range(0, keys.size() - 1)])


## 从池入册: 快照并入状态基底, 移出池; 初见情面由 _gift_note 统一处理(查表已含动态边)。
func _enroll_pool_npc(key: String) -> void:
	if not run.has("world_npcs") or not (run.world_npcs as Dictionary).has(key):
		return
	var base := _npc_init()
	base.merge((run.world_npcs as Dictionary)[key] as Dictionary, true)
	base.met = true
	run.npcs[key] = base
	run.world_npcs.erase(key)
	_gift_note(key)
	changed.emit()


## 友情值(边 val)按月漂移: 至交或更铁或稍淡、久不往来渐淡、宿怨可解可结 —— 静默无报闻。
## 只动世界池动态边: 静态边(relations.json)是 GDD 预设设定不随存档变; 亲子血亲不漂。
## 淡出止于 0、和解止于 0, 归零即休眠 —— 变淡只到陌生, 缘尽不再漂; 新交情由事件另起(游历/婚配/播种),
## 宿怨恶化同理只在负带内。
func _friendship_drift() -> void:
	var rate := float(tune("friend_drift_rate", 0.25))
	var step_min := int(tune("friend_drift_step_min", 1))
	var step_max := int(tune("friend_drift_step_max", 3))
	for e in run.get("world_rels", []):
		if _is_kin(String(e.get("tag", ""))) or _is_kin(String(e.get("r_tag", ""))):
			continue   # 血亲不漂(方向称谓任一侧落亲族词即算)
		var v := float(e.get("val", 0.0))
		if v == 0.0:   # 陌生休眠: 不掷随机, 杜绝 0→有 的无来由翻转
			continue
		if rng.randf() >= rate:
			continue
		var step := float(rng.randi_range(step_min, step_max))
		var warm := rng.randf()
		if v >= float(tune("rel_close_min", 35.0)):
			v += step if warm < 0.6 else -step          # 至交: 六成续温, 四成小淡
		elif v <= -40.0:
			v += step if warm < 0.5 else -step          # 宿怨: 五五开, 可解可结
		elif v > 0.0:
			v += step if warm < 0.35 else -step         # 浅交: 三分热络七分随淡
			v = maxf(v, 0.0)
		else:
			v += step if warm < 0.65 else -step         # 微恙: 偏向释怀
			v = minf(v, 0.0)
		e.val = clampf(v, -100.0, 100.0)


## 世界脉动: 偶尔补一位新客入池, 顺手牵一条边 —— 市井本该有人搬来, 有人攀上交情。
func _world_churn() -> void:
	if not run.has("world_npcs"):
		return
	var alive := 0   # 空位看活人: 坐化者占册不占坑, 市井总得有人搬来
	for e in (run.world_npcs as Dictionary).values():
		if not bool((e as Dictionary).get("dead", false)):
			alive += 1
	if alive >= int(tune("world_npc_count", 50)):
		return
	var npc := npc_generator.generate(rng, _world_existing())
	if npc.is_empty():
		return
	run.world_npcs[String(npc.key)] = npc
	_npc_vitals_backfill(npc, String(npc.key))
	var all_keys: Array = (run.world_npcs as Dictionary).keys()
	for nd in DataManager.npcs:
		all_keys.append(String(nd.key))
	# 新客的牵线也走派系先验: 同乡同业先搭上线, 人生地不熟才四处撞缘分
	_try_world_edge(String(npc.key), _pick_relate_partner(String(npc.key), all_keys, {}, float(tune("world_rel_same_faction", 0.75))), {})


# ---------------------------------------------------------------- NPC 恋爱·婚配·子嗣(好感度驱动)

## NPC 之间的感情与玩家恋爱同规格: 恋爱边存 run.npc_romance{"a|b"→{aff,stage,married}},
## 逐月涨好、按 aff_thresholds 六段升段(相识→相熟→心动→相恋), 满段成婚写 spouse;
## 争风扣好可降段退婚; 婚后按率受孕、怀胎五年添丁, 孩子遗传双亲容貌、满 npc_adult_years 成年入修炼。
## 玩家道侣位/玩家好感线与此完全隔离(红线: 只动 NPC 互好)。
## 互好 aff/stage/married 只允许 _npc_romance_tick(月度随机掷)与开局婚配播种写入, 任何玩家操作路径不得触碰。

func _pair_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a

## 亲族称谓集: 新边用方向词(娃看长辈=父/母亲, 长辈看娃=儿/女儿), 旧档遗留的「亲子」一并认。
const FAMILY_TAGS := ["亲子", "父亲", "母亲", "儿子", "女儿"]

func _is_kin(tag: String) -> bool:
	return tag in FAMILY_TAGS

## 亲族并提对词(茶摊/帖面用): 长辈头衔+孩子排行 → 父子/父女/母子/母女。
func _kin_pair(parent_key: String, child_key: String) -> String:
	var p := "父" if npc_male(parent_key) else "母"
	var c := "子" if String(_npc_entry(child_key).get("gender", "male")) == "male" else "女"
	return p + c


## NPC 生效字典(名录或世界池, 均为存档内引用, 可直接改)。
func _npc_entry(key: String) -> Dictionary:
	if run.npcs.has(key):
		return run.npcs[key]
	if run.has("world_npcs") and (run.world_npcs as Dictionary).has(key):
		return (run.world_npcs as Dictionary)[key]
	return {}


func _npc_age_years(key: String) -> int:
	var e := _npc_entry(key)
	if e.is_empty() or not e.has("born_m"):
		return 999   # 无出生月=开局老世辈, 一律成年
	return int((int(run.age_m) - int(e.get("born_m", 0))) / 12.0)


func _npc_is_minor(key: String) -> bool:
	var e := _npc_entry(key)
	# grown 守卫: 已行过成年礼者永不回退幼年 —— 阈值上调后, 老档里 12-15 岁已成年的孩子不回落幼儿脸、修炼不断
	return e.has("born_m") and not bool(e.get("grown", false)) and _npc_age_years(key) < int(tune("npc_adult_years", 16))


## 容貌渲染套件: 未成年用幼儿套(脸A kid), 成年按性别走男/女套 —— Portrait 与幼儿捏脸共用此一口径。
func npc_kit(key: String) -> String:
	return "kid" if _npc_is_minor(key) else ("male" if npc_male(key) else "female")


func _rom_stage(aff: float) -> int:
	var s := 0
	for th in tune("aff_thresholds", [200, 400, 600, 800, 1000]):
		if aff >= float(th):
			s += 1
	return s


## 恋爱推进: 已有边涨好升段/成婚; 按率把亲密对物化成恋爱边; 争风降段退婚。
## 一夫一妻守卫: 播种排除已在恋爱中者; 推进时若已被他人娶/嫁则边作废; _marry 再兜底。
func _npc_romance_tick() -> void:
	var rom: Dictionary = run.get("npc_romance", {})
	var names: Array = tune("aff_stages", ["陌生", "相识", "相熟", "心动", "相恋", "道侣"])
	# 1) 已有恋爱: 涨好升段
	for pk in rom.keys().duplicate():
		var r: Dictionary = rom[pk]
		var parts: PackedStringArray = String(pk).split("|")
		var a := String(parts[0]); var b := String(parts[1])
		if bool(r.get("married", false)):
			continue
		var ea := _npc_entry(a); var eb := _npc_entry(b)
		if ea.is_empty() or eb.is_empty() or String(ea.get("spouse", "")) != "" or String(eb.get("spouse", "")) != "":
			rom.erase(pk)   # 一方已嫁娶(被抢婚/旧档残留) —— 此缘作废
			continue
		if bool(ea.get("dead", false)) or bool(eb.get("dead", false)):
			rom.erase(pk)   # 一方坐化 —— 此缘作古(正常在 _npc_death 已清, 防御旧档残留)
			continue
		r.aff = float(r.get("aff", 0.0)) + float(rng.randi_range(int(tune("npc_court_gain_min", 4)), int(tune("npc_court_gain_max", 12))))
		var old_stage := int(r.get("stage", 0))
		r.stage = _rom_stage(float(r.aff))
		if int(r.stage) > old_stage:
			if int(r.stage) >= 5:
				_marry(a, b, r)
			else:
				_report("坊市都道: 【%s】与【%s】%s" % [npc_name(a), npc_name(b), String(names[clampi(int(r.stage), 0, 5)])])
				if int(r.stage) == 3:
					_queue_wall_event("npc_xindong", {"a": npc_name(a), "b": npc_name(b)})   # 闲话壁: NPC 心动磕糖帖(延迟 1 月)
				elif int(r.stage) == 4:
					_queue_wall_event("npc_xianglian", {"a": npc_name(a), "b": npc_name(b)})   # 闲话壁: NPC 相恋实锤帖
	# 2) 新恋情物化: 从亲密边里挑一对未婚成年异性(且双方都未在别段恋爱中)
	if rng.randf() < float(tune("npc_court_seed_rate", 0.15)):
		var cands: Array = []
		for e in _all_edges():
			var ea2 := String(e.get("a", "")); var eb2 := String(e.get("b", ""))
			if float(e.get("val", 0.0)) < float(tune("rel_close_min", 35.0)):
				continue
			if rom.has(_pair_key(ea2, eb2)) or _rom_taken(rom, ea2) or _rom_taken(rom, eb2):
				continue
			if _rom_eligible(ea2, eb2):
				cands.append(e)
		if not cands.is_empty():
			var pick: Dictionary = cands[rng.randi_range(0, cands.size() - 1)]
			var pa := String(pick.get("a", "")); var pb := String(pick.get("b", ""))
			var seed := clampf(float(pick.get("val", 0.0)) * 10.0, 0.0, 800.0)
			rom[_pair_key(pa, pb)] = {"aff": seed, "stage": _rom_stage(seed), "married": false}
			_report("坊市闲话: 听说【%s】与【%s】越走越近, 有了心思" % [npc_name(pa), npc_name(pb)])
			_queue_wall_event("npc_seed", {"a": npc_name(pa), "b": npc_name(pb)})   # 闲话壁: 新恋情萌芽帖(延迟 1 月)
	# 3) 争风吃醋: 随机挑一条恋爱扣好, 已婚者可能降段退婚
	if not rom.is_empty() and rng.randf() < float(tune("worldsim_rival_rate", 0.04)):
		var keys: Array = rom.keys()
		var jk := String(keys[rng.randi_range(0, keys.size() - 1)])
		var jr: Dictionary = rom[jk]
		jr.aff = maxf(0.0, float(jr.get("aff", 0.0)) - float(rng.randi_range(30, 60)))
		var js := _rom_stage(float(jr.aff))
		var jp: PackedStringArray = jk.split("|")
		if js < int(jr.get("stage", 0)):
			if bool(jr.get("married", false)) and js < 4:
				_divorce(String(jp[0]), String(jp[1]), jr)
			else:
				_report("茶摊闲话: 【%s】与【%s】闹了别扭, 凉了半截" % [npc_name(String(jp[0])), npc_name(String(jp[1]))])
				_queue_wall_event("npc_nao", {"a": npc_name(String(jp[0])), "b": npc_name(String(jp[1]))})   # 闲话壁: 闹别扭观察帖(延迟 1 月)
		jr.stage = js


## 某人是否已名花有主(在任一段恋爱中)。
func _rom_taken(rom: Dictionary, key: String) -> bool:
	for pk in rom:
		var ps: PackedStringArray = String(pk).split("|")
		if String(ps[0]) == key or String(ps[1]) == key:
			return true
	return false


## 恋爱资格: 异性、皆成年、皆未婚、非玩家道侣、彼此非亲缘。
func _rom_eligible(a: String, b: String) -> bool:
	if a == "" or b == "" or a == b:
		return false
	var ea := _npc_entry(a); var eb := _npc_entry(b)
	if ea.is_empty() or eb.is_empty():
		return false
	if bool(ea.get("dead", false)) or bool(eb.get("dead", false)):
		return false   # 亡者不续缘
	if _npc_is_minor(a) or _npc_is_minor(b):
		return false
	if String(ea.get("spouse", "")) != "" or String(eb.get("spouse", "")) != "":
		return false
	if bool(ea.get("dao_lu", false)) or bool(eb.get("dao_lu", false)):
		return false
	if npc_male(a) == npc_male(b):
		return false
	var rel := relation_between(a, b)
	return not _is_kin(String(rel.get("tag", "")))   # 血亲不恋爱(方向称谓任一视角落亲族词即算)


## 全部关系边(静态+动态)一览。
func _all_edges() -> Array:
	var out: Array = []
	out.append_array(DataManager.relations)
	out.append_array(run.get("world_rels", []))
	return out


func _marry(a: String, b: String, r: Dictionary) -> void:
	var ea := _npc_entry(a); var eb := _npc_entry(b)
	if ea.is_empty() or eb.is_empty():
		return
	if String(ea.get("spouse", "")) != "" or String(eb.get("spouse", "")) != "":
		return   # 兜底: 已名花有主, 不再许婚
	r.married = true
	r.stage = 5
	ea.spouse = b
	eb.spouse = a
	_report("◆ 大喜: 【%s】与【%s】结为夫妻 —— 坊间随了份子" % [npc_name(a), npc_name(b)])
	_queue_wall_event("relation", {"a": npc_name(a), "b": npc_name(b), "tag": "夫妻"})


func _divorce(a: String, b: String, r: Dictionary) -> void:
	r.married = false
	var ea := _npc_entry(a); var eb := _npc_entry(b)
	if String(ea.get("spouse", "")) == b:
		ea.spouse = ""
	if String(eb.get("spouse", "")) == a:
		eb.spouse = ""
	_report("◆ 可惜: 【%s】与【%s】缘尽于此, 婚约作废" % [npc_name(a), npc_name(b)])
	_queue_wall_event("npc_divorce", {"a": npc_name(a), "b": npc_name(b)})   # 闲话壁: 和离唏嘘帖(延迟 1 月)


## 添丁: 已婚未孕之妻按率受孕(npc_conceive_rate), 修仙者怀胎 npc_gestation_years 年方临盆。
## 产期与生父挂在母亲档案(preg_due_m/preg_fa, 随档保存): 婚变乃至恋爱边作废都不吞胎儿, 到月生给生父。
func _npc_family_tick() -> void:
	# 1) 待产结算: 名录与世界池合览, 到产期的先落地
	for pool in [run.npcs, run.get("world_npcs", {})]:
		var pl: Dictionary = pool if pool is Dictionary else {}
		for key in pl.keys():
			var mom: Dictionary = pl[key]
			var due := int(mom.get("preg_due_m", 0))
			if due <= 0 or int(run.age_m) < due:
				continue
			var fa := String(mom.get("preg_fa", ""))
			mom.erase("preg_due_m")
			mom.erase("preg_fa")
			var ef := _npc_entry(fa)
			if ef.is_empty():
				continue   # 生父档案缺失(理论上走不到) —— 静默, 不留无父胎记录
			_birth_child(fa, String(key), ef, mom)
	# 2) 掷孕: 一夫一妻已婚对, 未怀、未超生 → 按率有喜
	var rom: Dictionary = run.get("npc_romance", {})
	for pk in rom.keys():
		var r: Dictionary = rom[pk]
		if not bool(r.get("married", false)):
			continue
		var parts: PackedStringArray = String(pk).split("|")
		var a := String(parts[0]); var b := String(parts[1])
		var ea := _npc_entry(a); var eb := _npc_entry(b)
		if ea.is_empty() or eb.is_empty():
			continue
		if bool(ea.get("dead", false)) or bool(eb.get("dead", false)):
			continue   # 已婚对一方已故(边未清干净时兜底): 不再掷孕
		if int(ea.get("children", []).size()) >= int(tune("npc_kids_max", 2)):
			continue
		# 恋爱资格保证一男一女: 妻=女方, fa/mo 位仅是字典序拆键, 称谓在 _birth_child 按性别现取
		var wife_key := b if npc_male(a) else a
		var husband := a if npc_male(a) else b
		var wife: Dictionary = eb if npc_male(a) else ea
		if int(wife.get("preg_due_m", 0)) > 0:
			continue
		if rng.randf() >= float(tune("npc_conceive_rate", 0.02)):
			continue
		wife.preg_due_m = int(run.age_m) + int(tune("npc_gestation_years", 5)) * 12
		wife.preg_fa = husband
		_report("◆ 喜脉: 【%s】有了身孕 —— 修行之人怀胎五年, 坊间掰着指头待添丁" % npc_name(wife_key))


func _birth_child(fa: String, mo: String, ef: Dictionary, em: Dictionary) -> void:
	var kid := npc_generator.breed_child(rng, ef, em, _world_existing())
	if kid.is_empty():
		return
	var kid_key := String(kid.key)
	kid["born_m"] = int(run.age_m)
	kid["parents"] = [fa, mo]
	# 随父母入册: 双亲皆在名录 → 孩子进名录(可见可交互); 否则进世界池(未识)
	if run.npcs.has(fa) and run.npcs.has(mo):
		var base := _npc_init()
		base.merge(kid, true)
		base.met = true
		run.npcs[kid_key] = base
	else:
		run.world_npcs[kid_key] = kid
	if not ef.has("children"):
		ef.children = []
	if not em.has("children"):
		em.children = []
	(ef.children as Array).append(kid_key)
	(em.children as Array).append(kid_key)
	_try_world_edge(kid_key, fa, {}, true)
	_try_world_edge(kid_key, mo, {}, true)
	# 亲子边固定方向称谓+val(覆盖随机模板): 娃看长辈=父亲/母亲, 长辈看娃=儿子/女儿
	# 注意: 婚配边按字典序拆 fa|mo, 首位未必是男 —— 称谓一律按性别现取
	var kid_word := "儿子" if String(kid.get("gender", "")) == "male" else "女儿"
	var fa_word := "父亲" if npc_male(fa) else "母亲"
	var mo_word := "父亲" if npc_male(mo) else "母亲"
	for e in run.world_rels:
		var ea := String(e.get("a", "")); var eb := String(e.get("b", ""))
		if (ea == kid_key and eb == fa) or (ea == fa and eb == kid_key):
			e.tag = fa_word if ea == kid_key else kid_word
			e.r_tag = kid_word if ea == kid_key else fa_word
			e.val = 70.0; e.note = "%s是%s的%s —— 眉眼像爹, 脾气像娘" % [npc_name(kid_key), npc_name(fa), kid_word]
		if (ea == kid_key and eb == mo) or (ea == mo and eb == kid_key):
			e.tag = mo_word if ea == kid_key else kid_word
			e.r_tag = kid_word if ea == kid_key else mo_word
			e.val = 70.0; e.note = "%s是%s的%s —— 眉眼像爹, 脾气像娘" % [npc_name(kid_key), npc_name(mo), kid_word]
	_report("◆ 添丁: 【%s】家喜得%s【%s】" % [npc_name(fa), kid_word, npc_name(kid_key)])
	changed.emit()


## 成年礼: 满 npc_adult_years 的孩子上报一声, 自此入修炼与婚配池(境界 0 起步)。
func _npc_growth_tick() -> void:
	for key in run.npcs.keys():
		_growth_check(String(key))
	if run.has("world_npcs"):
		for key in (run.world_npcs as Dictionary).keys():
			_growth_check(String(key))


func _growth_check(key: String) -> void:
	var e := _npc_entry(key)
	if e.is_empty() or not e.has("born_m") or bool(e.get("grown", false)) or bool(e.get("dead", false)):
		return
	if _npc_age_years(key) < int(tune("npc_adult_years", 16)):
		return
	e.grown = true
	_report("◇ 岁月催人: 【%s】家孩子长大成人, 开始修行" % npc_name(key))


# ---------------------------------------------------------------- NPC 四柱·寿元(与主角同口径: 灵根/气血/武力/寿元)

const ROOT_CN := {5: "五", 4: "四", 3: "三", 2: "二", 1: "单"}

## 是否已坐化: 档案永留(亲缘/纪事不断线), 但不再吃月度结算、不结新缘、不入名录。
func npc_is_dead(key: String) -> bool:
	return bool(_npc_entry(key).get("dead", false))

## 境界序(在册/池快照优先, 固定档案兜底) —— 与 _npc_cultivation / npc_break_chance 同一口径。
func npc_realm_ord(key: String) -> int:
	var e := _npc_entry(key)
	var ord := int(e.get("realm_ord", -99))
	if ord == -99:
		ord = int(npc_arch(key).get("realm_ord", -1))
	return ord

## 灵根: 快照/固定档案优先; 有册无根的旧人掷一次轮盘落档(同世稳定)。未入册且档案无根者现掷不写档。
func npc_roots(key: String) -> Array:
	var e := _npc_entry(key)
	var r: Array = e.get("roots", [])
	if not r.is_empty():
		return r
	r = npc_arch(key).get("roots", [])
	if r is Array and not (r as Array).is_empty():
		if not e.is_empty():
			e.roots = r   # 档案灵根落到本世册上, 后续读取免翻档
		return r
	if not e.is_empty():
		e.roots = npc_generator.roll_roots(rng)
		return e.roots
	return npc_generator.roll_roots(rng)

## 聚灵系数: 与玩家同表(ROOT_COUNT_COEF), 行数越多越钝 —— 直接乘进 _npc_cultivation 月增益。
func npc_root_coef(key: String) -> float:
	return float(ROOT_COUNT_COEF.get(clampi(npc_roots(key).size(), 1, 5), 0.65))

func npc_roots_display(key: String) -> String:
	var r := npc_roots(key)
	return "%s灵根·%s" % [String(ROOT_CN.get(clampi(r.size(), 1, 5), "?")), "·".join(PackedStringArray(r))]

## 气血上限: 同玩家公式 —— 基数 + 境界档×每境增量(无境界者按炼气档)。
func npc_qi_max(key: String) -> int:
	return int(econ("qi_max_base", 100)) + maxi(0, npc_realm_ord(key)) * int(econ("qi_max_per_realm", 50))

## 当前气血: 缺值首次读即落满(惰性初始化, 老档免迁移)。
func npc_qi(key: String) -> int:
	var e := _npc_entry(key)
	if e.is_empty():
		return npc_qi_max(key)
	if not e.has("qi"):
		e.qi = npc_qi_max(key)
	return int(e.qi)

## 武力(灰盒口径, 同 wu_li 化简): 境界基数×(1+本层进度) × (1+灵根超额加成) × 气血心情; 死者归零。
func npc_wu_li(key: String) -> float:
	if npc_is_dead(key):
		return 0.0
	var e := _npc_entry(key)
	var ord := clampi(npc_realm_ord(key), 0, DataManager.realms.size() - 1)
	var re: Dictionary = DataManager.realm(ord)
	var layers := maxi(1, int(re.get("layers", 3)))
	var base := float(re.get("gain_base", 10)) * (1.0 + float(int(e.get("nlayer", 0))) / float(layers))
	var gear := 1.0 + maxf(0.0, npc_root_coef(key) - 1.0)
	var mood := 0.85 + 0.15 * clampf(float(npc_qi(key)) / float(maxi(1, npc_qi_max(key))), 0.0, 1.0)
	return base * gear * mood

## 寿元上限: 同玩家 —— 境界表 lifespan_cap(无境界凡人按炼气档 80)。
func npc_lifespan_cap(key: String) -> int:
	var ord := npc_realm_ord(key)
	if ord < 0:
		return int(DataManager.realm(0).get("lifespan_cap", 80))
	return int(DataManager.realm(clampi(ord, 0, DataManager.realms.size() - 1)).get("lifespan_cap", 80))

## 人生档案首填: 有册者补生辰(按境界适龄掷龄)、灵根、气血; 掷到成年者顺带置 grown —— 不误触成年礼报闻。
func _npc_vitals_backfill(e: Dictionary, key: String) -> void:
	if e.is_empty():
		return
	if not e.has("born_m"):
		var ord := npc_realm_ord(key)
		var cap := int(DataManager.realm(clampi(maxi(0, ord), 0, DataManager.realms.size() - 1)).get("lifespan_cap", 80))
		var age := rng.randi_range(18, maxi(19, cap - 15))
		e.born_m = int(run.age_m) - age * 12
		if age >= int(tune("npc_adult_years", 16)):
			e.grown = true
	if not e.has("roots"):
		npc_roots(key)   # 惰性掷根并落档(轮盘见 NpcGenerator.roll_roots)
	if not e.has("qi"):
		e.qi = npc_qi_max(key)

## 气血与寿元月度: 活人按制回气; 尘世凡人(rand_*)寿数过界即坐化 ——
## 固定档案(掌门/贤邻等)道行深不可测, 不受此限(故事不因讣闻断线)。
func _npc_mortality_tick() -> void:
	var regen := int(econ("qi_regen", 5))
	for pool in [run.npcs, run.get("world_npcs", {})]:
		for key in (pool as Dictionary).keys():
			var ks := String(key)
			var e: Dictionary = (pool as Dictionary)[key]
			if bool(e.get("dead", false)) or not e.has("born_m"):
				continue
			e.qi = mini(npc_qi_max(ks), int(e.get("qi", npc_qi_max(ks))) + regen)
			if not ks.begins_with("rand_") or _npc_age_years(ks) < npc_lifespan_cap(ks):
				continue
			_npc_death(ks)

## 坐化: 档案标记 dead(亲子边与子女反指永久保留), 撤孕期, 解除婚姻与恋爱边(生者记新丧),
## 清喜欢/关注 —— 纪事一行讣闻。不弹框、不入结局线。
func _npc_death(key: String) -> void:
	var e := _npc_entry(key)
	if e.is_empty() or bool(e.get("dead", false)):
		return
	e.dead = true
	e.erase("preg_due_m")
	e.erase("preg_fa")
	var other_sp := String(e.get("spouse", ""))
	e.spouse = ""
	var rom: Dictionary = run.get("npc_romance", {})
	for pk in rom.keys().duplicate():
		var ps: PackedStringArray = String(pk).split("|")
		if String(ps[0]) != key and String(ps[1]) != key:
			continue
		rom.erase(pk)
		var other := String(ps[1]) if String(ps[0]) == key else String(ps[0])
		var eo := _npc_entry(other)
		if not eo.is_empty() and String(eo.get("spouse", "")) == key:
			eo.spouse = ""
			if not bool(eo.get("dead", false)):
				_report("◇ 【%s】新丧在礼 —— 从此形单影只" % npc_name(other))
	var ord := npc_realm_ord(key)
	var realm_txt := "凡人" if ord < 0 else String(DataManager.realm(ord).get("name", "?"))
	_report("◇ 讣闻: 【%s】(%s·享年 %d 岁) 寿元耗尽, 坐化而去 —— 坊间叹一声来世再见" % [npc_name(key), realm_txt, _npc_age_years(key)])
	if String(run.get("focus", "")) == key:
		run.focus = ""
	if (run.get("follows", []) as Array).has(key):
		(run.follows as Array).erase(key)
	changed.emit()


## 聚灵效率 = 境界基数 × 灵根系数 × 功法倍率 × 洞府聚灵阵 ×(1+资质)×(1+食修效率 buff)×(1+灵息体)×(1+气质)
func efficiency() -> float:
	return float(realm().gain_base) * float(run.root) * float(run.tech) * cave_mult() * (1.0 + float(run.get("aptitude", 0.0))) * (1.0 + _buff_pct("eff_pct")) * (1.0 + _trait_fx("eff")) * (1.0 + aura_self("cult"))

## 月修为 = E × 方案倍率 × 境界速度系数 ×(1+食修「当月修为」buff)
func month_gain() -> float:
	return efficiency() * plan_mult() * float(realm().max_ap) * (1.0 + _buff_pct("cult_pct"))

## 境界基数(战力口径): gain_base × (1 + 本境层数/总层数) —— 同境越深基数越高
func _realm_base_now() -> float:
	var re := realm()
	return float(re.gain_base) * (1.0 + float(run.layer) / float(maxi(1, int(re.get("layers", 1)))))

## 武力值(§5.4 检定式战斗的战力口径, 灰盒): 战力 = 境界基数 × (1+功法/灵器加成) × 心情/料理 buff。
##   加成项 = 灵根超出 1 的部分 + 功法超出 1 的部分(灵器未实装, 并入功法位) + 气运每档 +3%(§6.4.2) + 食修「修为」buff;
##   心情 = 气血八五~满载折扣(低血告急战力先亏) × 心魔 −10%(与冲关率同幅)。
func wu_li() -> float:
	var gear := (1.0 + maxf(0.0, float(run.root) - 1.0) + maxf(0.0, float(run.tech) - 1.0) \
		+ float(run.get("luck", 0)) * 0.03 + _buff_pct("cult_pct")) * (1.0 + _trait_fx("wu"))
	var mood := 0.85 + 0.15 * clampf(float(_qi()) / float(maxi(1, qi_max())), 0.0, 1.0)
	if int(run.inner) > 0:
		mood *= 0.9
	return _realm_base_now() * gear * mood

func global_n() -> int:
	return DataManager.layer_offset(int(run.realm)) + int(run.layer) + 1

func layer_need() -> float:
	return float(tune("layer_need_base", 100.0)) * pow(float(tune("layer_growth", 1.55)), global_n() - 1)

func realm_ready() -> bool:
	var re := realm()
	return int(run.layer) == int(re.layers) - 1 and float(run.cult) >= layer_need()

func is_final_realm() -> bool:
	return int(run.realm) >= DataManager.realms.size() - 1

## 冲关成功率: 境界基础 + 天道眷顾(永久) + 败中悟道(每败一次+5%, 成功清零)
##   + 食修(照骨羹一次性 / 下次检定 buff / 气运+3%) + 聚灵阵每级+2%(§6.4.2) − 气血低线 10% − 心魔 10%
func break_chance() -> float:
	return clampf(float(realm().break_prob) + float(meta.get("bless_pct", 0.0)) + _trait_fx("break")
		+ float(tune("pity_step", 0.05)) * int(run.get("pity", 0))
		+ float(run.get("break_bonus", 0.0)) + float(run.get("luck", 0)) * 0.03 + _buff_pct("check_pct")
		+ float(econ("facility_break_step", 0.02)) * facility_level("julingzhen") + aura_self("break")
		- (0.10 if _qi() < low_qi_line() else 0.0)
		- (0.10 if int(run.inner) > 0 else 0.0), 0.01, 0.99)

func next_realm_name() -> String:
	return "飞升" if is_final_realm() else String(DataManager.realm(int(run.realm) + 1).name)

# ---- 食修 buff 与气血(详解卷 6.2.4: 同类取最强、不同类最多并存 2 条) ----

## 气血上限随境界成长: 基数 + 每境 +qi_max_per_realm(突破即扩上限, 2026-09-12 拍板)
func qi_max() -> int:
	return int(econ("qi_max_base", 100)) + int(run.get("realm", 0)) * int(econ("qi_max_per_realm", 50))

## 低血告急阈值 = 上限 × low_qi_pct(绝对值随上限水涨船高, 三成以下才罚)
func low_qi_line() -> int:
	return int(float(qi_max()) * float(econ("low_qi_pct", 0.3)))

func _qi() -> int:
	return int(run.get("qi", 100))

# ---- 洞府设施(§6.4: 四设施 0–3 级, 筑基 1/金丹 2/元婴 3; 材料并入灵石价, §6.4.1) ----

func facility_level(id: String) -> int:
	return int(run.get("facilities", {}).get(id, 0))

## 当前境界允许的设施等级上限(炼气 0 / 筑基 1 / 金丹 2 / 元婴起 3)
func facility_cap() -> int:
	return clampi(int(run.get("realm", 0)), 0, 3)

## 设施效果值(levels 数组第 lv 档)
func facility_level_eff(id: String) -> float:
	var f := DataManager.facility(id)
	var levels: Array = f.get("levels", [0.0, 0.0, 0.0, 0.0])
	return float(levels[clampi(facility_level(id), 0, levels.size() - 1)])

func cave_upgrade(id: String) -> void:
	if _blocked("升级设施"):
		return
	var f := DataManager.facility(id)
	if f.is_empty():
		return
	var lv := facility_level(id)
	var costs: Array = f.get("costs", [])
	if lv >= costs.size():
		_log("【%s】已圆满(3 级) —— 化神后的「圆满」微层(+5 名望)留 P1" % String(f.name))
		return
	if lv >= facility_cap():
		_log("【%s】当前境界最多 %d 级 —— 突破大境界解锁更高上限(§6.4.1)" % [String(f.name), facility_cap()])
		return
	var cost := int(costs[lv])
	if int(farm().stones) < cost:
		_log("灵石不足: 【%s】升级需 %d, 现有 %d(卖余货换灵石)" % [String(f.name), cost, int(farm().stones)])
		return
	farm().stones = int(farm().stones) - cost
	run.facilities[id] = lv + 1
	_log("◇ 【%s】升至 %d 级, 花 %d 灵石 —— %s" % [String(f.name), lv + 1, cost, String(f.desc)])
	changed.emit()

## 洞府聚灵乘项(§11 唯一洞府位: 聚灵阵 ×1+0/20/40/60%)
func cave_mult() -> float:
	return 1.0 + facility_level_eff("julingzhen")

## 藏经阁灰盒折算: 常驻顿悟率 +0/2/3/4.5pp(原研速 ×1/1.2/1.45/1.7 只作用功法研习, P1 落地后切回)
func insight_pp() -> float:
	var pp := [0.0, 0.02, 0.03, 0.045]
	return float(pp[clampi(facility_level("cangjingge"), 0, 3)]) + aura_self("insight")

## 待客庭院并行约会名额(levels: 0 级=1 名 … 3 级=4 名; 等级不跨世)
func parlor_dates() -> int:
	var f := DataManager.facility("daiketingyuan")
	var levels: Array = f.get("levels", [1, 2, 3, 4])
	return clampi(int(levels[clampi(facility_level("daiketingyuan"), 0, levels.size() - 1)]), 1, 4)

# ---- 闲话壁(论坛体系统: 百话楼照壁, 呈现层零结算 · 永不弹窗 · 帖是「当世的」) ----

## 每月至多上 1 帖: 事件帖(延迟 1 月) > 年节窗口 > 势力轮换(每 wall_rotate_cd 月 1 条) > random 概率补位。
## 随机 roll 每月恒 1 次(铁律: 同种子逐月等价); **一世内同一帖不重上**(2026-09-12 拍板, 收紧图鉴「同一年不重复」口径)——池尽则该月静默, 不硬凑重复。
func _wall_tick() -> void:
	if is_ended():
		return
	_ensure_run()
	var wall: Dictionary = run.wall
	var month := (int(run.age_m) % 12) + 1
	if not Array(wall.get("queue", [])).is_empty():
		var item: Variant = Array(wall.queue).pop_front()
		# 队列项: {"ev": 事件名, "sub": 占位替换}; 旧档遗留的纯字符串事件名也兼容
		var ev := String(item.get("ev", item)) if item is Dictionary else String(item)
		var qsub: Dictionary = (item as Dictionary).get("sub", {}) if item is Dictionary else {}
		if _wall_put_event(ev, qsub):
			return
	var yearly := _wall_pick("yearly", func(w: Dictionary) -> bool:
		var win: Array = w.trigger.get("window", [])
		for m in win:
			if int(m) == month:   # JSON 数字解析为 float, 显式 int 比较
				return true
		return false)
	if yearly != "":
		_wall_put(yearly)
		return
	wall.rotate_cd = int(wall.get("rotate_cd", 1)) - 1
	if int(wall.rotate_cd) <= 0:
		wall.rotate_cd = int(econ("wall_rotate_cd", 3))
		var rot := _wall_pick("faction_rotate", func(_w: Dictionary) -> bool: return true)
		if rot != "":
			_wall_put(rot)
			return
	if rng.randf() < float(econ("wall_random_rate", 0.02)):
		var rid := _wall_pick("random", func(_w: Dictionary) -> bool: return true)
		if rid == "":
			rid = _wall_pick("faction_rotate", func(_w: Dictionary) -> bool: return true)   # 池尽回退水帖
		if rid != "":
			_wall_put(rid)

## 事件帖延迟 1 月: 入队(由突破/道侣/恋爱节点/论道等真实事件调用); sub 供模板 {npc} 等占位替换
func _queue_wall_event(ev_name: String, sub: Dictionary = {}) -> void:
	if is_ended():
		return
	_ensure_run()
	run.wall.queue.append({"ev": ev_name, "sub": sub})

## 文案占位替换: "{npc}" → 实际人名等
func _wall_sub(line: String, sub: Dictionary) -> String:
	for k in sub:
		line = line.replace("{%s}" % k, String(sub[k]))
	return line

## 派发辅助: 从 wall.json 取第一个满足 filter 且**一世内未上过**的帖 id; 空=无
func _wall_pick(type: String, extra: Callable) -> String:
	var taken: Array = _wall_taken_ids()
	for w in DataManager.wall:
		var t: Dictionary = w.get("trigger", {})
		if String(t.get("type", "")) != type:
			continue
		if taken.has(String(w.id)):
			continue
		if extra.call(w):
			return String(w.id)
	return ""

func _wall_put(id: String, sub: Dictionary = {}) -> void:
	var wall: Dictionary = run.wall
	var year := _wall_this_year()
	wall.posts.append({"id": id, "month": (int(run.age_m) % 12) + 1, "year": year, "sub": sub})
	var r := DataManager.wall_post(id)
	if not r.is_empty():
		_report("%s(壁上有全文)" % _wall_sub(String(r.report_line), sub))

## 事件帖: event 型 trigger 匹配队里事件名(一世内未上过才上)
func _wall_put_event(ev_name: String, sub: Dictionary = {}) -> bool:
	var taken: Array = _wall_taken_ids()
	for w in DataManager.wall:
		var t: Dictionary = w.get("trigger", {})
		if String(t.get("type", "")) != "event" or String(t.get("event", "")) != ev_name:
			continue
		if taken.has(String(w.id)):
			continue
		_wall_put(String(w.id), sub)
		return true
	return false

func _wall_this_year() -> int:
	return (int(run.age_m) - START_AGE_M) / 12

func _wall_taken_ids() -> Array:
	var ids: Array = []
	for p in Array(run.wall.get("posts", [])):
		ids.append(String(p.id))
	return ids

## 未读与已读(红点口径: 上壁未读, 点开闲话壁页即清)
func wall_unread() -> int:
	if not run.has("wall"):
		return 0
	return maxi(0, Array(run.wall.get("posts", [])).size() - int(run.wall.get("read", 0)))

## 开局预置: 照壁不是空壁 —— 预上 3 条旧帖(不入月报, 不占年节/轮换节律, 年内不重逻辑照旧)。
## 调用方(_ensure_run / _start_life)已保证 run.wall 存在; 此处不得再调 _ensure_run(壁空条件下会互相递归)。
func _wall_seed_opening() -> void:
	for id in ["wall_001", "wall_004", "wall_017"]:
		if DataManager.wall_post(id).is_empty():
			continue
		run.wall.posts.append({"id": id, "month": 1, "year": 0})

func wall_mark_read() -> void:
	if not run.has("wall"):
		return
	run.wall.read = Array(run.wall.get("posts", [])).size()

func _buff_pct(kind: String) -> float:
	var buffs: Dictionary = run.get("buffs", {})
	return float(buffs.get(kind, {}).get("pct", 0.0))

## 检定类 buff 只加突破率: 寻道检定不受益不消费; 未冲关不随月消散, 冲关成功才消费(2026-09-12 拍板)
func _consume_check_buff() -> float:
	var buffs: Dictionary = run.get("buffs", {})
	if buffs.has("check_pct"):
		var p := float(buffs["check_pct"].get("pct", 0.0))
		buffs.erase("check_pct")
		return p
	return 0.0

## 吃下同 kind buff 叠加(2026-09-12 拍板: 同类相加、不同类无并存上限, 取代图鉴 6.2.4「取最强/≤2 条」)
## name 非空则取代加持栏的通用名(负向 debuff 挂一个名字, 如「寒邪余韵」而非「聚灵」); pct 为负即减益。
func _buff_apply(kind: String, pct: float, months: int, name := "") -> void:
	_ensure_run()
	var buffs: Dictionary = run.buffs
	if buffs.has(kind):
		var b: Dictionary = buffs[kind]
		b.pct = float(b.pct) + pct             # 同类叠加: 数值相加
		b.months = maxi(int(b.months), months) # 时长取 max
		if name != "":
			b.name = name
		return
	buffs[kind] = {"pct": pct, "months": months, "name": name}

func _buffs_tick() -> void:
	var buffs: Dictionary = run.get("buffs", {})
	for k in buffs.keys():
		if String(k) == "check_pct":
			continue   # 突破率加成: 未冲关不消散, 冲关成功才消费
		buffs[k].months = int(buffs[k].months) - 1
		if int(buffs[k].months) <= 0:
			buffs.erase(k)

## 检定失败受伤: 气血 −30(回血菜是唯一日常恢复来源)
func _wound() -> void:
	run.qi = maxi(0, _qi() - int(econ("wound_qi_loss", 30)))

func buffs_summary() -> String:
	var buffs: Dictionary = run.get("buffs", {})
	var names := {"cult_pct": "修为", "check_pct": "检定", "wuxing": "悟性", "eff_pct": "聚灵", "regen": "回复"}
	var parts: Array = []
	if recover_months() > 0:
		parts.append("闭关注养·%d月" % recover_months())
	for k in buffs:
		var bd: Dictionary = buffs[k]
		var bp := float(bd.get("pct", 0.0)) * 100.0
		var nm := String(bd.get("name", ""))            # debuff 自带名优先
		if nm == "":
			nm = String(names.get(String(k), String(k)))   # 否则用通用名(老档无 name 键亦在此兜住)
		if String(k) == "check_pct":
			parts.append("%+.0f%%检定·待冲关" % bp)
		else:
			parts.append("%+.0f%%%s·%d月" % [bp, nm, int(bd.get("months", 0))])
	if int(run.get("inner", 0)) > 0:
		parts.append("心魔%d月" % int(run.inner))
	var td := trait_display()
	if td != "":
		parts.append(td)
	return " / ".join(parts)

func realm_display() -> String:
	var re := realm()
	if String(re.key) == "lianqi":
		return "%s%d层(%d/9)" % [re.name, int(run.layer) + 1, int(run.layer) + 1]
	return "%s%s(%d/3)" % [re.name, ["初期", "中期", "后期"][clampi(int(run.layer), 0, 2)], int(run.layer) + 1]

func sealed_count() -> int:
	var n := 0
	for key in run.npcs:
		if bool(run.npcs[key].get("sealed", false)):
			n += 1
	return n

## KPI: 特殊事件弹出次数 = M0 决策预算(目标 80–150/世, §3.1)
func kpi_summary() -> Dictionary:
	var k: Dictionary = run.get("kpi", {"ticks": 0, "interrupts": 0, "floors": 0})
	var decisions := int(k.get("interrupts", 0)) + int(k.get("floors", 0))
	var mins := decisions * float(tune("minutes_interrupt", 2.0))
	return {"ticks": int(k.get("ticks", 0)), "interrupts": int(k.get("interrupts", 0)), "floors": int(k.get("floors", 0)), "decisions": decisions, "decision_hours": mins / 60.0}

# ---------------------------------------------------------------- 玩家接口(轻决策)

func set_speed(s: int) -> void:
	if s > 0:
		_resume_speed = s
	speed = s
	changed.emit()

func set_plan(id: String) -> void:
	if is_ended():
		return
	if recover_months() > 0 and String(id) != "pure":
		_log("◇ 闭关注养中(余 %d 月) —— 方案封存为「认真修炼」, 出关再议" % recover_months())
		changed.emit()
		return
	run.plan = id
	_log("◇ 方案切换: %s(×%.2f), 自下一月生效" % [String(plan().name), plan_mult()])
	changed.emit()

func set_focus(key: String) -> void:
	if key != "":
		if not run.npcs.has(key) or not bool(run.npcs[key].get("met", false)):
			return   # 喜欢对象仅限已首遇 NPC(§5)
		run.focus = key
		var f := follows()
		if not f.has(key) and f.size() < FOLLOW_MAX:
			f.append(key)   # 「喜欢」的 NPC 默认为关注
		_log("◇ 喜欢: %s" % String(npc_name(key)))
	else:
		_log("◇ 取消喜欢")
		run.focus = ""
	changed.emit()

## 关注名单上限(「喜欢」对象自动入册, 亦占名额)
const FOLLOW_MAX := 10

## 关注列表(本世 run.follows, 元素为 NPC key): 只有被关注 NPC 的事会出现在日程页「一世纪事」
func follows() -> Array:
	if not run.has("follows"):
		run.follows = []
	return run.follows

## 是否已关注: 「喜欢」对象恒视为关注(即便列表满员未入册)
func is_followed(key: String) -> bool:
	return String(run.get("focus", "")) == key or follows().has(key)

## 添加/取消关注: 添加仅限已入册 NPC 且名单未满; 取关「喜欢」对象时顺带一并取消喜欢。
## 返回 false = 被拒(未入册/名单满), 由 UI 给提示。
func set_follow(key: String, on: bool) -> bool:
	var f := follows()
	if on:
		if not run.npcs.has(key) or not bool(run.npcs[key].get("met", false)):
			return false
		if f.has(key):
			return true
		if f.size() >= FOLLOW_MAX:
			return false
		f.append(key)
		_log("◇ 关注【%s】" % String(npc_name(key)))
	else:
		if not f.has(key) and String(run.get("focus", "")) != key:
			return true   # 本就不在关注之列
		if f.has(key):
			f.erase(key)
		_log("◇ 取消关注【%s】" % String(npc_name(key)))
		if String(run.get("focus", "")) == key:
			run.focus = ""   # 喜欢 ⊆ 关注: 取关一并取消喜欢
	changed.emit()
	return true

## 主角容貌（捏脸）：存于本世 run.look；无则用默认
func player_look() -> Dictionary:
	var lk: Variant = run.get("look", null)
	if lk is Dictionary and not (lk as Dictionary).is_empty():
		return lk as Dictionary
	return Portrait.default_look()

func set_player_look(a: Dictionary) -> void:
	run.look = a.duplicate(true)
	changed.emit()   # 换容不入纪事(避免刷屏)

## 主角性别（捏脸工坊可切换，默认女相）
func player_male() -> bool:
	return String(player_look().get("gender", "female")) == "male"

## —— 固定 NPC 容貌（捏脸 · 他人页）：直接改档案 data/npcs.json（跨世生效），不落本世 run。
## 性别锁死档案值（npc_male），只捏部件/配色/气质。
func npc_look(key: String) -> Dictionary:
	var arch := npc_arch(key)
	var ap: Dictionary = {}
	var av: Variant = arch.get("appearance", null)
	if av is Dictionary:
		ap = (av as Dictionary).duplicate(true)
	if run.npcs.has(key):
		var rv: Variant = run.npcs[key].get("appearance", null)
		if rv is Dictionary:
			for k in (rv as Dictionary):
				ap[k] = (rv as Dictionary)[k]
	var look := NpcGeneratorScript.resolve_look(ap, npc_male(key))
	for k in ["hair_hue", "hair_sat", "eye_hue", "eye_sat"]:   # resolve_look 会把调色兜成原色, 此处还原
		look[k] = int(ap.get(k, NpcGeneratorScript.COLOR_IDENTITY[k]))
	look["aura"] = String(ap.get("aura", ""))
	return look

## 应用：写内存档案 + 回写 npcs.json；落盘失败（只读环境）仍保内存改动，返回是否落盘成功
func set_npc_look(key: String, ap: Dictionary) -> bool:
	var merged := npc_look(key)
	for k in ap:
		merged[k] = ap[k]
	var ok := DataManager.write_npc_appearance(key, merged)
	changed.emit()   # 换容不入纪事
	return ok

## 复原出厂容貌（DataManager 启动时留的基线）
func reset_npc_look(key: String) -> bool:
	var ok := DataManager.write_npc_appearance(key, DataManager.npc_raw_appearance(key))
	changed.emit()
	return ok

## 手动冲关入口已移除: 修为圆满即在 tick 内自动突破(§3.2 v1.2 + 玩家拍板)
func retire() -> void:
	if is_ended():
		return
	if int(run.realm) < 3:
		_log("元婴以下谈不上隐退, 大道未成")
		changed.emit()
		return
	_ending("圆满隐退")

func toggle_duijie_cap() -> void:
	duijie_cap = int(tune("dujie_cap_alt", 1500)) if duijie_cap >= int(tune("duijie_cap_years", 1800)) else int(tune("duijie_cap_years", 1800))
	_log("◎ 渡劫寿元上限切换为 %d 年(M0 实测旋钮)" % duijie_cap)
	changed.emit()

## 事件弹窗的选项回调(i 对应 options 下标) —— 每个分支都在「一世纪事」留下抉择与其结果
func resolve_option(i: int) -> void:
	if pending.is_empty():
		return
	var kind := String(pending.kind)
	var opt_v: Variant = pending.options[clampi(i, 0, int(pending.options.size()) - 1)]
	var choice := String(opt_v.get("t", "")) if opt_v is Dictionary else String(opt_v)
	match kind:
		"chance":
			if i == 0:
				var cost := int(pending.data.get("cost", 0))
				if cost > 0:
					farm().stones = maxi(0, int(farm().stones) - cost)
					_log("◇ 抉择「%s」(花 %d 灵石)" % [choice, cost])
				else:
					_log("◇ 抉择「%s」" % choice)
				_apply_event_effect(String(pending.data.get("id", "")))   # ◆ 结果行随效果落下
			else:
				# 选项自带 opt_effect 则该选项有代价(如「运功逼散」耗神); 没有才真是「任它随风去了」
				var oe: Dictionary = (opt_v as Dictionary).get("opt_effect", {}) if opt_v is Dictionary else {}
				if oe.is_empty():
					_log("◇ 抉择「%s」—— 你合上眼, 任它随风去了。" % choice)
				else:
					_log("◇ 抉择「%s」" % choice)
					_apply_event_effect("", {"label": String(oe.get("label", "抉择结果 · %s" % choice)), "effect": oe})
		"node":
			var nk := String(pending.data.key)
			var rates: Array = pending.data.rates
			var npc_n: Dictionary = run.npcs[nk]
			var ntrack := "love" if int(npc_n.get("stage", 0)) >= 2 else "friend"   # 心动起节点进恋爱轨, 之前仍是友情轨
			var nunit := "情分" if ntrack == "love" else "好感"
			if deterministic or rng.randf() < float(rates[clampi(i, 0, rates.size() - 1)]):
				_bump_aff(nk, 50.0, ntrack)
				_log("◇ 抉择「%s」—— 说到了 Ta 心坎上(%s +50)" % [choice, nunit])
				_advance_node(nk)
			else:
				var wave := -float(rng.randi_range(int(tune("aff_drift", [2, 10])[0]) + 8, int(tune("aff_drift", [2, 10])[1]) + 20))
				_bump_aff(nk, wave, ntrack)
				_log("◇ 抉择「%s」—— 话没接住, %s %.0f(这道闸顺延, 来日再提)" % [choice, nunit, wave])
		# 2026-09-22 拍板: 遇见 NPC 不再弹「是否攀谈」框, 命中即直接入册 —— 以下三个分支仅为旧存档中未响应的弹框兜底
		"met_note":
			if i == 0:
				_first_meet(String(pending.data.key))
			else:
				_log("◇ 你把这张脸记在心里 —— 有缘自会再见(缘分页仍为传闻中的面孔)。")
		"travel_meet":
			var tn: Dictionary = pending.data.npc
			var pk := String(pending.data.get("pool_key", ""))
			if i == 0:
				if pk != "":
					_enroll_pool_npc(pk)
				else:
					_enroll_npc(tn)
				_log("◇ 你与【%s】攀谈几句 —— 入册缘分页(%s)" % [npc_name(String(tn.key)), String(tn.get("id_name", ""))])
			else:
				_log("◇ 你把这张脸记在心里 —— %s" % ("这张脸还在世上, 缘未尽自会再见。" if pk != "" else "换个去处, 自会遇见别的缘分。"))
		"friend_meet":
			var fn: Dictionary = pending.data.npc
			if i == 0:
				_enroll_npc(fn)
				if bool(pending.data.get("favor", false)):
					run.npcs[String(fn.key)].aff = 20.0
				_log("◇ 你与【%s】攀谈几句 —— 入册缘分页(经【%s】引荐%s)" % [npc_name(String(fn.key)), npc_name(String(pending.data.get("introducer", ""))), (", 携初始好感 20" if bool(pending.data.get("favor", false)) else "")])
			else:
				_log("◇ 你点头而过 —— 名录不出此人, 缘分另受。")
		"luochang_ok":
			var t3 := String(pending.data.third)
			var d3 := String(pending.data.dao)
			if i == 0:
				var a := rng.randi_range(int(tune("confess_range", [-30, 20])[0]), int(tune("confess_range", [-30, 20])[1]))
				_bump_aff(t3, float(a), "love")
				_bump_aff(d3, float(a), "love")
				_log("◇ 坦白从宽: 你把话与【%s】、【%s】摊开 —— 各自情分 %+d, 此线自此透明" % [npc_name(t3), npc_name(d3), a])
			else:
				run.npcs[t3].luochang_lowkey = true
				_log("◇ 低调维持: 风平浪静 —— 只是同一位的局, 12 月内再引爆率 +10%%")
		"luochang_bad":
			var t4 := String(pending.data.third)
			var d4 := String(pending.data.dao)
			if i == 0:
				var a2 := rng.randi_range(int(tune("confess_range", [-30, 20])[0]), int(tune("confess_range", [-30, 20])[1]))
				_bump_aff(t4, float(a2), "love")
				_bump_aff(d4, float(a2), "love")
				_log("◇ 坦白从宽: 满城风雨里你把话说尽 —— 各自情分 %+d" % a2)
			else:
				_log("◇ 打马虎眼: 「那是远房表妹。」—— 茶摊笑作一团, 谁也没当真, 谁也没受伤。")
		"seal":
			if i == 0:
				_log("◇ 抉择「%s」" % choice)
				var k := String(pending.data.key)
				run.npcs[k].sealed = true
				meta.bonds = int(meta.get("bonds", 0)) + 1
				SaveSystem.save_meta(meta)
				_log("◆ 你在【%s】魂魄上烙下印记 —— 来世 Ta 会带着模糊的记忆寻你。" % npc_name(k))
			else:
				_log("◇ 抉择「%s」—— 你笑了笑: 若真有来世, 认路的人总会再遇见。" % choice)
		"focus_mile":
			var mk := String(pending.data.key)
			if i == 0:
					_bump_aff(mk, 10.0, "love")   # 心动时分是恋意的坎 —— 进情轨(同性 focus 自动落回友情轨)
					_log("◇ 你顺势靠近了些 —— 与【%s】的话头多了几分暖意(情分 +10)" % npc_name(mk))
			else:
				_log("◇ 你把这份暖意收进岁月里 —— 静待花开。")
		"neglect":
			var lk := String(pending.data.key)
			if i == 0:
				_bump_aff(lk, 30.0)
				_log("◇ 一顿家常小菜下肚, 【%s】的眉眼又弯了起来(好感 +30)" % npc_name(lk))
			else:
				_bump_aff(lk, 10.0)
				_log("◇ 说了些旧年趣事, 【%s】点点头: 「下回别把我忘啦。」(好感 +10)" % npc_name(lk))
		"millennium":
			run.farm.millennium = int(run.farm.millennium) + 1
			_log("◆ 千年灵植入库 —— 可卖坊市 %d 灵石, 或赠礼(好感+80)。" % int(econ("millennium_price", 500)))
		"secret":
			if i == 0:   # 硬扛: 损一年寿元
				run.inner = maxi(int(run.inner), 12)
				_log("◇ 抉择「%s」—— 咬着牙赶完余程, 损一年寿元, 心魔一年" % choice)
				_advance_years(12)
			else:        # 退养: 真闭关 2 年(方案封存, 对外的缘分动作暂停) · 心魔两年不换寿
				run.inner = maxi(int(run.inner), 24)
				run.recover = int(tune("recover_months", 24))
				run.plan = "pure"   # 闭关期间方案封存在「认真修炼」(×1.0, 无附加行动)
				_log("◇ 抉择「%s」—— 伤在洞府里将养半年, 寿元无损, 只是心魔两年才化开" % choice)
				_log("◆ 闭关注养 %d 载 —— 方案封存为「认真修炼」, 其间不游历、不相闻问(赠礼/解契候出关再办)。" % (int(run.recover) / 12))
	pending = {}
	speed = _resume_speed
	changed.emit()

## 月末结算: 本月琐碎并为一条月报行进右侧「一世纪事」(2026-09-11: 替代暂停月报弹窗, 只存结果不存过程)
## 纪年与左侧 calendar() 同口径: 每世自「第1年·1月」起(tick 先自增 age_m, 故回退一个月取刚过去之月)。
func _emit_month_note() -> void:
	if month_notes.is_empty():
		return
	var idx := maxi(0, int(run.age_m) - START_AGE_M - 1)   # 刚过去月份的 0 基序号
	_log("第%d年·%d月 · %s" % [idx / 12 + 1, idx % 12 + 1, (" · ").join(month_notes)], calendar_idx(idx))
	month_notes.clear()

# ---------------------------------------------------------------- 模拟(灰盒节奏仪)

## strategy: "pure"=全程纯修炼; "mixed"=按各境 busy_ratio 代理值切「照顾灵田」(v1.1 混合策略对照)
func simulate_life(strategy := "pure") -> void:
	if not is_ended():
		_log("—— 模拟一世(策略: %s, deterministic=%s) ——" % ["纯修炼" if strategy == "pure" else "灵田混合", "开" if deterministic else "关"])
	muted = true
	var last_realm := -1
	var guard := 0
	var acc := 0.0
	sim_trace = []
	while not is_ended() and guard < 300000:
		guard += 1
		if int(run.realm) != last_realm:
			last_realm = int(run.realm)
			acc = 0.0
			sim_trace.append([String(realm().name), int(run.age_m) - START_AGE_M])
		if strategy == "mixed":
			acc += float(realm().get("busy_ratio", 0.5))
			run.plan = "household" if acc >= 1.0 else "pure"
			if acc >= 1.0:
				acc -= 1.0
		if not pending.is_empty():
			resolve_option(0)
		tick_month()
	muted = false
	var k := kpi_summary()
	var curve: Array = []
	for t in sim_trace:
		curve.append("%s@%d年" % [t[0], int(t[1]) / 12])
	_log("—— 模拟结束: 历 %d 月(%.0f 年), 事件弹出 %d 次(保底 %d), 决策估 %.1f h(目标 %d 决策/%.0f h) ——" % [
		int(k.ticks), float(k.ticks) / 12.0, int(k.interrupts), int(k.floors), float(k.decision_hours),
		int(tune("target_decisions", 150)), float(tune("target_hours", 6.0))])
	_log("寿元曲线: %s" % ", ".join(curve))
	month_notes.clear()
	changed.emit()

## 出身设定已废: 一律「宗门弟子」(origins.json 只剩这一条, 保留数据位只为兼容旧档读取)。
func default_origin() -> Dictionary:
	for o in DataManager.origins:
		if String(o.get("name", "")) == "宗门弟子":
			return o
	return DataManager.origins[0] if not DataManager.origins.is_empty() else {"name": "宗门弟子", "root_coef": 1.0, "element": "木", "bonus_plot": false}


func rebirth(origin: Dictionary, forge_times: int, bless_times: int, root_choice := {}, trait_ids := []) -> void:
	if origin.is_empty():
		origin = default_origin()   # 出身设定已废: 一律宗门弟子
	var nr := _normalize_roots(root_choice)
	var traits := _normalize_traits(trait_ids)
	var root_cost := int(ROOT_TRIM_COST.get(int(nr[0]), 0))
	var trait_cost := 0
	for tid in traits:
		trait_cost += int(DataManager.traits_def(String(tid)).cost)
	var spend := forge_times * FORGE_COST + bless_times * BLESS_COST + root_cost + trait_cost
	if spend > int(meta.get("dao", 0)):
		_log("道韵不足(需 %d, 有 %d)" % [spend, int(meta.get("dao", 0))])
		return
	meta.dao = int(meta.dao) - spend
	meta.bless_pct = float(meta.get("bless_pct", 0.0)) + bless_times * BLESS_STEP
	SaveSystem.save_meta(meta)
	var trim_txt := "" if int(nr[0]) >= 5 else "炼灵根至 %d 行·" % int(nr[0])
	_log("—— 前世遗产折价 %d 道韵: %s铸体×%d, 天道眷顾×%d(+%.0f%%冲关率)%s ——" % [spend, trim_txt, forge_times, bless_times, bless_times * BLESS_STEP * 100.0, ("·" + trait_display(traits)) if not traits.is_empty() else ""])
	_start_life(origin, forge_times, root_choice, traits)

## 开始界面「新开一世」: Meta 重置(道韵回到起始值, 历世/最佳境界全清)并起第 1 世(灵根五行俱全)。
## 只管内存与落盘; 文件级清档由 SaveSystem.clear_all() 先行。
func new_game() -> void:
	meta = {"schema": SCHEMA, "dao": START_DAO, "lives": 0, "best_ord": 0, "best_name": "无", "bless_pct": 0.0, "bonds": 0, "endings": {}}
	SaveSystem.save_meta(meta)
	rebirth({}, 0, 0, {}, [])

## 特质清单归一: 只留合法 id(存在即收, 去重), 非法静默丢弃
func _normalize_traits(trait_ids: Array) -> Array:
	var out: Array = []
	for tid in trait_ids:
		var id := String(tid)
		if not DataManager.traits_def(id).is_empty() and not (id in out):
			out.append(id)
	return out

## 特质名串(账目/入世志/加持栏共用): 「天生:剑骨·道心」; 空清单回空串
func trait_display(traits := []) -> String:
	var names := PackedStringArray()
	for tid in (traits if not traits.is_empty() else run.get("traits", [])):
		names.append(String(DataManager.traits_def(String(tid)).get("name", String(tid))))
	return "天生:%s" % "·".join(names) if not names.is_empty() else ""

## 灵根显示名: 五/四/三/二/单灵根 + 持有五行(如「三灵根·金水火」); 老档无 roots 按单属呈现
func root_display() -> String:
	var cn := String({5: "五", 4: "四", 3: "三", 2: "二", 1: "单"}.get(int(run.get("root_count", 1)), "?"))
	var roots: Array = run.get("roots", [])
	var owned: String = "·".join(PackedStringArray(roots)) if not roots.is_empty() else String(run.element)
	return "%s灵根·%s" % [cn, owned]

## 天生特质效果汇总(按 fx.kind 求和, 可叠): 只读 run.traits —— 一世结算, 全部在结算入口内生效(§12)
func _trait_fx(kind: String) -> float:
	var s := 0.0
	for tid in run.get("traits", []):
		var fx: Dictionary = DataManager.traits_def(String(tid)).get("fx", {})
		if String(fx.get("kind", "")) == kind:
			s += float(fx.get("v", 0.0))
	return s

# ---------------------------------------------------------------- 唯一结算入口(§12 铁律)

## 一切月度结算都在这一个入口: 时速档只改调用频率、不改任何逻辑 ——
## 因此 1× 与 100× 的数值输出逐月等价(SimReport 回归保证); 月末收尾把当月流水并入「一世纪事」。
func tick_month() -> void:
	_tick_core()
	_emit_month_note()
	# 移植增强: 原灰盒只在开世/结局写档, 这里补跨年保档(腊月), 中途关游戏不丢一整年进度
	if not is_ended() and not run.is_empty() and (int(run.age_m) - START_AGE_M) % 12 == 11:
		SaveSystem.save_run(run)

func _tick_core() -> void:
	if is_ended() or not pending.is_empty():
		return
	_ensure_run()
	var kpi: Dictionary = run.kpi
	kpi.ticks = int(kpi.ticks) + 1
	run.age_m = int(run.age_m) + 1
	# 1) 灵田结算(详解卷 6.0.3: 灵田→巡视→灶; 千年灵植变异是唯一经营弹窗「大机缘+」)
	if _farm_tick():
		changed.emit()
		return
	# 2) 修炼: 聚灵效率 × 方案倍率 × 境界速度系数
	var gain := month_gain()
	_add_cult(gain)
	_report("修为 +%s(%s ×%.2f)" % [_fmt(gain), String(plan().name), plan_mult()])
	# 2) 方案执行器(冷却驱动, 自动)
	_execute_plan()
	# 2b) 气血自然回复 +5/月(cap=气血上限, 详解卷 6.2.4)
	run.qi = mini(qi_max(), _qi() + int(econ("qi_regen", 5)) + int(round(_buff_pct("regen"))))
	# 2c) 灶上烹制推进: 已起火的锅逐月计时, 到期可收取
	_kitchen_tick()
	# 3) 琐碎小事件: 每月 3% 顿悟/走火(+悟性 buff + 藏经阁折算) —— 入本月月报行(§3.3 不打断)
	if not deterministic and rng.randf() < float(tune("monthly_event_chance", 0.03)) + _buff_pct("wuxing") + insight_pp():
		if rng.randf() < 0.6:
			var e := layer_need() * 0.15
			_add_cult(e)
			_report("小顿悟 +%s" % _fmt(e))
		else:
			var l := float(run.cult) * 0.12
			run.cult = maxf(0.0, float(run.cult) - l)
			_report("行功不稳 -%s" % _fmt(l))
	# 4) 修为圆满 → 自动冲关(不打断挂机; 失败耗寿挂心魔+败中悟道+5%, 成功延寿清零)
	if realm_ready():
		_do_breakthrough()
		if is_ended():
			changed.emit()
			return
	# 5) 心魔消退 · 寿元硬时钟; 食修 buff 在本月所有结算(修炼/方案/检定冲关)之后再衰减一格
	if not run.buffs.is_empty():
		_buffs_tick()
	if int(run.inner) > 0:
		run.inner = int(run.inner) - 1
	if recover_months() > 0:   # 闭关将养倒计时: 心魔同步逐月消散, 两载圆满自解封锁
		run.recover = recover_months() - 1
		if recover_months() <= 0:
			_report("◆ 将养出关 —— 闭关两载功行圆满, 方案解禁。")   # 走月报线入纪事(tick 内直发 _log 会早标一月)
	if int(run.age_m) >= lifespan_cap_years() * 12:
		_ending("寿尽坐化")
		changed.emit()
		return
	# 5b) 闲话壁(论坛体·呈现层零结算): 每月至多上 1 帖, 月报留摘要, 永不打断
	_wall_tick()
	# 5c) 缘分月度(恋爱系统): 幽布衣首月自动首遇 · 首遇检定 · 季度限额重置 · WorldSim 关系网 · 好感微幅波动
	if not run.npcs.has("moxiu"):
		_first_meet("moxiu", "隔壁墙头递来一碟菜")
	var npcq := int((int(run.age_m) - START_AGE_M) / 3)
	if int(run.get("quarter", -1)) != npcq:
		run.quarter = npcq
		for key in run.npcs:
			run.npcs[key].talk_q = 0
			run.npcs[key].gift_q = 0
	_first_meet_roll()   # 被动首遇检定: 命中直接入册(2026-09-22 拍板: 不再弹框询问攀谈)
	_worldsim_tick()
	if rng.randf() < float(tune("world_npc_churn", 0.02)):
		_world_churn()   # 世界脉动: 偶有新客搬来, 顺手攀一条交情
	_aff_drift()
	_favor_gift_tick()      # 好感厚礼: 心动段及以上 NPC 按主角境界差人送菜/送灵植(每月至多一份)
	_npc_cultivation()      # NPC 修行: 各自周期到点破境(上限渡劫, 话本成精等无境界者不参与)
	_focus_neglect_tick()   # 喜欢的代价: 他人好感每月 -1, 冷落累计触发「故人心思」事件
	# 6) 打断判定(优先级: 好感节点/烙印 > 喜欢心动时分 > 他人冷落 > 机缘) —— 命中即自动暂停
	if _npc_prompt_check():
		changed.emit()
		return
	if _focus_mile_check():
		changed.emit()
		return
	if _neglect_check():
		changed.emit()
		return
	if not deterministic and rng.randf() < float(tune("interrupt_chance_per_month", 0.008)) * (1.0 + 0.1 * float(run.get("luck", 0))) * (1.0 + _trait_fx("event")) * (1.0 + aura_self("event")):
		var ce := _pick_event("chance")
		if not ce.is_empty():
			var ev_id := String(ce.id)
			var ev_opts: Array = (ce.options as Array).duplicate(true)   # 深拷贝: 免改共享事件档
			var cost := 0
			if ev_id == "relic":
				cost = relic_cost()
				if ev_opts.size() > 0:
					var o0: Dictionary = ev_opts[0]
					o0["t"] = "买下（需 %d 灵石）" % cost
					o0["disabled"] = int(farm().stones) < cost   # 灵石不足: 置灰不可点
			_fire_interrupt("特殊事件", String(ce.text), ev_opts, "chance", {"id": ev_id, "cost": cost, "auto": bool(ce.get("auto", false))})
		changed.emit()
		return
	changed.emit()

# ---------------------------------------------------------------- 方案执行器

func _execute_plan() -> void:
	match String(run.get("plan", "pure")):
		"cook":
			_cook_once()   # 专职下厨(6.2.3): 每月按已有食材自动烹一道已习得低/中阶谱(缺库优先)入洞府仓库(不自动赠予)
		"romance":
			var fk := _explicit_focus()
			for key in run.npcs:
				var npc: Dictionary = run.npcs[key]
				if not bool(npc.get("met", false)):
					continue
				# 交谈: 陌生段起唯一涨好感渠道 —— 每对象 3 月冷却 + 每季 ≤4 次(§1.2); 获取动率不随喜欢变化
				npc.talk_cd = int(npc.get("talk_cd", 0)) - 1
				if int(npc.talk_cd) <= 0 and int(npc.get("talk_q", 0)) < int(tune("talk_quarter_cap", 4)):
					npc.talk_cd = int(tune("talk_cd", 3))
					npc.talk_q = int(npc.get("talk_q", 0)) + 1
					_bump_aff(String(key), float(tune("talk_gain", 10)))
					if String(key) == fk:
						_report("与【%s】谈心(好感+%d)" % [npc_name(String(key)), int(tune("talk_gain", 10))])
			run.date_cd = int(run.date_cd) - 1
			if int(run.date_cd) <= 0:
				# 约会: 心动段(600)起解锁, 且只有男性 NPC 可赴约(恋爱/结侣仅限男性); 并行名额=待客庭院 1–4(§4.1), 第一顺位=专注, 其余按好感补足; 道侣在场则过修罗场检定
				var ranked: Array = []
				for key in run.npcs:
					var npc: Dictionary = run.npcs[key]
					if not bool(npc.get("met", false)) or int(npc.stage) < 3 or not npc_male(String(key)):
						continue
					ranked.append(String(key))
				ranked.sort_custom(func(a, b): return float(run.npcs[a].get("love", 0.0)) > float(run.npcs[b].get("love", 0.0)))
				var f2 := _focus_key()
				if f2 == "" and ranked.size() > 0:
					f2 = String(ranked[0])
				if f2 != "" and ranked.has(f2):
					ranked.erase(f2)
					ranked.push_front(f2)
					if f2 != "" and ranked.size() > 0:
						run.date_cd = int(tune("date_cd", 3))
						var went: Array = []
						var third := ""
						for i in range(mini(parlor_dates(), ranked.size())):
							var k3 := String(ranked[i])
							_bump_aff(k3, float(tune("date_gain", 60)), "love")
							went.append(npc_name(k3))
							if third == "" and k3 != _dao_key():
								third = k3
						if went.size() > 0:
							_report("同游灯会(%d 人): %s 情意各+%.0f" % [went.size(), "、".join(went), float(tune("date_gain", 60))])
						# 多人同游被撞破 → 火葬场: 发现者情分重挫, 吃瓜帖延迟 1 月上壁(人越多越容易被撞破)
						if went.size() >= 2:
							var found_rate := minf(0.9, float(econ("date_found_rate", 0.45)) + (0.25 if went.size() >= 3 else 0.0))
							if rng.randf() < found_rate:
								var found := String(ranked[rng.randi_range(0, went.size() - 1)])
								var hit := float(tune("jealousy_hit", 200))
								_bump_aff(found, -hit, "love")
								_report("【%s】撞见了另一场灯会 —— 火葬场了(情分 -%.0f)" % [npc_name(found), hit])
								_queue_wall_event("huozangchang", {"npc": npc_name(found)})
						if third != "":
							_luochang_check(third)
		"travel":
			_travel_tick()
		"seek":
			run.secret_cd = int(run.secret_cd) - 1
			if int(run.secret_cd) <= 0:
				var scost := int(econ("seek_qi_cost", 20))
				if _qi() < scost:
					run.secret_cd = 2   # 气血不济, 短冷却后再生龙活虎
					_report("寻道受阻: 气血 %d/%d —— 先回洞府吃口热的(§5.4 气血储备)" % [_qi(), scost])
				else:
					run.secret_cd = 6
					run.qi = _qi() - scost
					run.secret = int(run.secret) + 1
					# §5.4 检定式战斗: 有效战力 = 武力 × 随机扰动 U[0.7, 1.3], 对秘境两条线 ——
					# ≥ 大获线(0.97)有获 / < 受创线(0.79)遇妖潮 / 其间无功而返。
					# 气血满、无 buff 无折扣时基准概率与旧定值一致(55%/30%/15%), 加成与状态只平移分布。
					var adv := wu_li() / maxf(1.0, _realm_base_now()) * rng.randf_range(0.7, 1.3)
					if adv >= float(tune("seek_big_line", 0.97)):
						var g := layer_need() * 0.4
						_add_cult(g)
						_report("秘境一行有获, 修为 +%s(气血−%d)%s" % [_fmt(g), scost, _seek_forage()])
					elif adv < float(tune("seek_hurt_line", 0.79)):
						_wound()   # 检定失败受伤: 气血−30, 善后抉择只管寿元/心魔
						if not deterministic:
							_fire_interrupt("检定善后", "寻道途中遇妖潮, 你带伤退出(气血−%d) —— 如何善后?" % int(econ("wound_qi_loss", 30)), [
								{"t": "硬扛", "need": "折寿 1 年", "result": "心魔 1 年 · 余程走完"},
								{"t": "退养", "need": "闭关 2 年", "result": "心魔 2 年 · 寿元无损"},
							], "secret", {})
					else:
						_yaoguai_encounter(scost)   # 其间档: 游遇小妖 —— 武力对妖力的检定战(§5.4)

# ---------------------------------------------------------------- 灵田(详解卷 6.1, 数据: seeds.json + economy_tuning.json)

func farm() -> Dictionary:
	return run.farm

func _season(age_m: int) -> String:
	var m := (age_m % 12) + 1
	if m >= 3 and m <= 5:
		return "春"
	if m >= 6 and m <= 8:
		return "夏"
	if m >= 9 and m <= 11:
		return "秋"
	return "冬"

func _season_mult(season: String) -> float:
	var t: Dictionary = econ("season_mult", {})
	return float(t.get(season, 1.0))

## 地块上限 = 境界序(炼气1…渡劫8) + 灵田一脉出身 1, 软上限 9(§6.1.1)
func farm_cap() -> int:
	var bonus := 1 if _origin_bonus_plot() else 0
	return mini(int(econ("plot_soft_cap", 9)), int(realm().ordinal) + bonus)

func _origin_bonus_plot() -> bool:
	for o in DataManager.origins:
		if String(o.name) == String(run.origin):
			return bool(o.get("bonus_plot", false))
	return false

func farm_open_count() -> int:
	var n := 0
	for p in farm().plots:
		if bool(p.open):
			n += 1
	return n

func farm_reclaim_cost() -> int:
	var costs: Array = econ("plot_costs", [80, 140, 240, 400, 640, 960, 1400])
	var idx := farm_open_count() - 1
	if idx < 0 or idx >= costs.size():
		return -1
	return int(costs[idx])

## 下一块地所需的境界名: 扩地条件 = 境界序 + 出身加成 ≥ 已开块数 + 1; 已满软上限返回空串。
func farm_plot_need_realm() -> String:
	var bonus := 1 if _origin_bonus_plot() else 0
	var need_ord := int(farm_open_count()) + 1 - bonus
	if need_ord > int(econ("plot_soft_cap", 9)):
		return ""
	var i := clampi(need_ord - 1, 0, DataManager.realms.size() - 1)
	return String(DataManager.realms[i].get("name", "?"))

## 是否身负某行(灵根亲和判定): 读 run.roots; 老档无该字段时回退 run.element
func _root_has(el: String) -> bool:
	var roots: Array = run.get("roots", [])
	if roots.is_empty():
		return el != "" and String(run.element) == el
	return el in roots

## 水火互斥(6.1.4): 种子属水/火, 玩家不亲和该属却身负其反属 → 禁升「上」。多行灵根下逐种判定
func _seed_blocked_top(s: Dictionary) -> bool:
	var aff := String(s.get("affinity", ""))
	if aff == "火":
		return (not _root_has("火")) and _root_has("水")
	if aff == "水":
		return (not _root_has("水")) and _root_has("火")
	return false

## 实际成熟月数: 基础月数 × 全局节奏倍率 grow_time_mult(6.6.1 集中调参), 再吃亲和修正(6.1.4 同属 −1 月)
func seed_eff_months(s: Dictionary) -> int:
	var m := int(s.months)
	var mult := float(econ("grow_time_mult", 1.0))
	if mult != 1.0:
		m = maxi(1, int(round(float(m) * mult)))
	if _root_has(String(s.affinity)) and m > 1:
		m -= 1
	return m

func seed_in_season(s: Dictionary, season: String) -> bool:
	var ss: Array = s.get("seasons", [])
	return ss.is_empty() or ss.has(season)

## 收益/格·月(选种优化的排序键)
func seed_value(s: Dictionary, season: String) -> float:
	return float(s.yield) * float(s.price) * _season_mult(season) / float(seed_eff_months(s))

func _pest_rate(season: String) -> float:
	if season == "夏":
		return float(econ("pest_rate_summer", 0.18))
	if season == "冬":
		return float(econ("pest_rate_winter", 0.03))
	return float(econ("pest_rate", 0.10))

func _make_plots(start_open: int) -> Array:
	var arr: Array = []
	for i in range(9):
		arr.append({"open": i < start_open, "seed": "", "age": 0, "pest": false, "mutated": false})
	return arr

## 灵田月度结算(6.0.3 顺序 1–2: 生长/成熟收获 + 巡视三检定); 返回 true = 千年弹窗打断了本月
func _farm_tick() -> bool:
	if not run.has("farm"):
		return false
	var f := farm()
	if int(f.tonic_cd) > 0:
		f.tonic_cd = int(f.tonic_cd) - 1
	var season := _season(int(run.age_m))
	var household := String(run.plan) == "household"
	var cleared := 0
	var mutated := 0
	var mill_hit := false
	for p in f.plots:
		if not bool(p.open):
			continue
		if String(p.seed) == "":
			if household:
				_auto_plant(p, season)   # 巡视·选种优化: 库存没有的当季作物优先
			continue
		var s := DataManager.seed(String(p.seed))
		if s.is_empty():
			continue
		# 虫害(6.1.3): 照顾灵田=自动除虫免罚; 非=中标记 −30%
		if rng.randf() < _pest_rate(season):
			if household:
				cleared += 1
			elif not bool(p.pest):
				p.pest = true
				_report("虫害未除: 【%s】本收成 −%.0f%%" % [String(s.name), float(econ("pest_penalty", 0.3)) * 100.0])
		p.age = int(p.age) + 1
		if int(p.age) >= seed_eff_months(s):
			# 变异检定(巡视限定): 0.2% 千年灵植(大机缘弹窗) / 2% 品质升档
			if household:
				var mr := rng.randf()
				if mr < float(econ("millennium_rate", 0.002)):
					mill_hit = true
				elif mr < float(econ("mutate_rate", 0.02)):
					mutated += 1
					p.mutated = true
			_harvest_plot(p, s, season)
	if household:
		_report("巡视 %d 格 · 除虫 %d · 变异 %d" % [farm_open_count(), cleared, mutated])
	if mill_hit:
		_fire_interrupt("大机缘 · 千年灵植", "收获时忽见叶脉泛起紫纹 —— 一株千年灵植破土而出!(坊市可卖 %d 灵石, 或赠礼好感+80)" % int(econ("millennium_price", 500)), [
			{"t": "收下这天赐", "need": "无", "result": "入库: 坊市卖 %d 灵石 / 赠礼好感+80" % int(econ("millennium_price", 500))},
		], "millennium", {})
		return not pending.is_empty()
	return false

## 收获(6.1.4 品质模型): 产量=基础×四季×灵泉×虫害; 品质=基础档+升档roll(亲和×2, 水火异属禁升上)+变异
func _harvest_plot(p: Dictionary, s: Dictionary, season: String) -> void:
	var y := float(s.yield) * _season_mult(season) * (1.0 + facility_level_eff("lingquan")) * (1.0 + _trait_fx("farm"))   # 灵泉产量通道(§6.4.1) · 绿蓑特质产量乘项
	if bool(p.get("pest", false)):
		y *= 1.0 - float(econ("pest_penalty", 0.3))
	var n := maxi(1, int(round(y)))
	var grade := String(s.grade)
	var blocked_top := _seed_blocked_top(s)
	var up := float(econ("grade_up_chance", 0.10)) + facility_level_eff("lingquan")   # 灵泉品质通道: 升档概率 +0/10/20/30pp
	if _root_has(String(s.affinity)):
		up *= 2.0
	if rng.randf() < up:
		grade = _grade_up(grade, blocked_top)
	if bool(p.get("mutated", false)):
		grade = _grade_up(grade, blocked_top)
	_inv_add(String(s.id), grade, n)
	_report("收获【%s】×%d(%s品 · %s季 ×%.1f)" % [String(s.name), n, grade, season, _season_mult(season)])
	p.seed = ""
	p.age = 0
	p.pest = false
	p.mutated = false

func _grade_up(g: String, blocked_top: bool) -> String:
	var gs: Array = econ("grade_names", ["凡", "灵", "上"])
	var i := gs.find(g)
	if i < 0 or i >= gs.size() - 1:
		return g
	if blocked_top and i + 1 == gs.size() - 1:
		return g   # 水火异属互斥: 品质不可升「上」(6.1.4)
	return String(gs[i + 1])

## 巡视·选种优化(6.1.3): 优先种「库存没有」的当季作物(其中取收益最高, 补食材多样性);
## 当季全部已有库存 → 回退全局收益最高者保现金流。不消耗 RNG, 铁律无涉。
## 播种收费/留种规则同手动播种: 灵石不足或稀有留种无库的种子不进候选。
func _auto_plant(p: Dictionary, season: String) -> void:
	var best: Dictionary = {}
	var best_v := -1.0
	var best_missing := false
	for s in DataManager.seeds:
		if not seed_in_season(s, season):
			continue
		if int(farm().stones) < seed_plant_cost(s):
			continue
		if seed_gated(s) and _inv_seed_total(String(s.id)) < 1:
			continue
		var missing: bool = _inv_seed_total(String(s.id)) <= 0
		var v := seed_value(s, season)
		if (missing and not best_missing) or (missing == best_missing and v > best_v):
			best_missing = missing
			best_v = v
			best = s
	if best.is_empty():
		return
	farm().stones = int(farm().stones) - seed_plant_cost(best)
	if seed_gated(best):
		_inv_take(String(best.id), 1)
	p.seed = String(best.id)
	p.age = 0
	p.pest = false
	p.mutated = false
	_report("自动播种【%s】(选种优化: %s季收益 %.1f/格·月 · %s)" % [
		String(best.name), season, best_v, "库存没有, 优先补种" if best_missing else "当季皆已有库存, 回退收益最高"])

## 灶(§6.2.3): 「做饭」方案按月自动成菜 —— 按已有食材从已习得低/中阶谱里挑一道,
## 优先做洞府仓库还没有的(缺库优先, 按数据序); 全有库存则重复烹(叠放入库)。
## 仙膳与含占位料(千年灵植/奇花等)的谱永不自动烹(图鉴: 手动限定); 成菜不自动赠予 NPC。
func _cook_once() -> void:
	var f := farm()
	var dishes := _dishes()
	var first: Dictionary = {}
	var repeat: Dictionary = {}
	for r in DataManager.recipes:
		var tier := String(r.get("tier", ""))
		if tier != "low" and tier != "mid":
			continue
		if int(run.realm) < int(r.get("min_realm", 0)):
			continue
		var pure := true
		for m in r.get("mats", []):
			if DataManager.seed(String(m.seed)).is_empty():
				pure = false
				break
		if not pure or recipe_missing(r) != "":
			continue
		if int(dishes.get(String(r.id), 0)) > 0:
			if repeat.is_empty():
				repeat = r
		elif first.is_empty():
			first = r
	var pick: Dictionary = first if not first.is_empty() else repeat
	if pick.is_empty():
		_report("灶上空转(无可烹之谱/食材)")
		return
	for m in pick.get("mats", []):
		_mat_take(String(m.seed), int(m.n))
	var pid := String(pick.id)
	dishes[pid] = int(dishes.get(pid, 0)) + 1
	f.cook = int(f.cook) + 1
	_report("灶上成菜入库【%s】(×%d, 累计 %d)" % [String(pick.name), int(dishes[pid]), int(f.cook)])
	# 炊玉: 灶下生辉, 概率再成一道(食材再次校验, 不足则作罢)
	var cv := _trait_fx("cook")
	if cv > 0.0 and rng.randf() < cv and recipe_missing(pick) == "":
		for m in pick.get("mats", []):
			_mat_take(String(m.seed), int(m.n))
		dishes[pid] = int(dishes[pid]) + 1
		f.cook = int(f.cook) + 1
		_report("「%s」 —— 灶下生辉, 又成一道!(累计 %d)" % [String(pick.name), int(f.cook)])

# ---- 库存 ----

func _inv_add(seed_id: String, grade: String, n: int) -> void:
	var inv: Dictionary = farm().inv
	if not inv.has(seed_id):
		inv[seed_id] = {"凡": 0, "灵": 0, "上": 0}
	inv[seed_id][grade] = int(inv[seed_id].get(grade, 0)) + n

func _inv_seed_total(seed_id: String) -> int:
	var inv: Dictionary = farm().inv
	if not inv.has(seed_id):
		return 0
	var t := 0
	for g in inv[seed_id]:
		t += int(inv[seed_id][g])
	return t

func _inv_type_count(type: String) -> int:
	var t := 0
	for s in DataManager.seeds:
		if String(s.type) == type:
			t += _inv_seed_total(String(s.id))
	return t

## 从低品质起消耗(凡→灵→上), 返回是否足量
func _inv_take(seed_id: String, n: int) -> bool:
	if _inv_seed_total(seed_id) < n:
		return false
	var inv: Dictionary = farm().inv
	for g in econ("grade_names", ["凡", "灵", "上"]):
		while n > 0 and int(inv[seed_id].get(String(g), 0)) > 0:
			inv[seed_id][String(g)] = int(inv[seed_id][String(g)]) - 1
			n -= 1
	return true

func _inv_take_type(type: String, n: int) -> bool:
	if _inv_type_count(type) < n:
		return false
	for g in econ("grade_names", ["凡", "灵", "上"]):
		for s in DataManager.seeds:
			if String(s.type) != type:
				continue
			var inv: Dictionary = farm().inv
			var sid := String(s.id)
			while n > 0 and inv.has(sid) and int(inv[sid].get(String(g), 0)) > 0:
				inv[sid][String(g)] = int(inv[sid][String(g)]) - 1
				n -= 1
	return true

func seed_stock_value(seed_id: String) -> int:
	var s := DataManager.seed(seed_id)
	if s.is_empty():
		return 0
	var inv: Dictionary = farm().inv
	if not inv.has(seed_id):
		return 0
	var mults: Dictionary = econ("grade_price_mult", {})
	var total := 0.0
	for g in inv[seed_id]:
		total += int(inv[seed_id][g]) * float(s.price) * float(mults.get(String(g), 1.0))
	return int(round(total))

# ---- 玩家接口(灵田页按钮) ----

func farm_plant(slot: int, seed_id: String) -> void:
	if _blocked("播种"):
		return
	var plots: Array = farm().plots
	if slot < 0 or slot >= plots.size() or not bool(plots[slot].open) or String(plots[slot].seed) != "":
		_log("该地块不可播种(未开垦或已有作物)")
		return
	var s := DataManager.seed(seed_id)
	if s.is_empty():
		return
	var season := _season(int(run.age_m))
	if not seed_in_season(s, season):
		_log("【%s】非当季(%s季不可播), 误了农时" % [String(s.name), season])
		return
	# 已有留种: 消耗库存 1 株, 不再花灵石(2026-09-20 拍板); 无库存则按播种费现购种子
	var has_stock := _inv_seed_total(seed_id) > 0
	var cost := 0 if has_stock else seed_plant_cost(s)
	if int(farm().stones) < cost:
		_log("灵石不足: 播种【%s】需 %d 灵石, 现有 %d(坊市卖些余货再来)" % [String(s.name), cost, int(farm().stones)])
		changed.emit()
		return
	var gated := seed_gated(s)
	if gated and not _inv_take(seed_id, 1):
		_log("【%s】为稀有留种 —— 仓库需有 1 株方可播种(灵石宽裕可先购种入库)" % String(s.name))
		changed.emit()
		return
	if has_stock:
		_inv_take(seed_id, 1)
	farm().stones = int(farm().stones) - cost
	plots[slot].seed = seed_id
	plots[slot].age = 0
	plots[slot].pest = false
	plots[slot].mutated = false
	var pay := "耗种×1" if has_stock else "花 %d 灵石" % cost
	_log("◇ 第 %d 格播下【%s】(%s季 · %d 月熟 · %s亲和)—— %s%s" % [slot + 1, String(s.name), season, seed_eff_months(s), String(s.affinity), pay, " · 稀有留种" if gated else ""])
	changed.emit()

## 播种费用: 种价 × seed_cost_mult, 至少 1 灵石
func seed_plant_cost(s: Dictionary) -> int:
	return maxi(1, int(round(float(s.price) * float(econ("seed_cost_mult", 0.5)))))

## 稀有留种: 「上」品种子播种需仓库留种 1 株(播种时消耗), 首株走坊市购种
func seed_gated(s: Dictionary) -> bool:
	return String(s.grade) == "上"

## 坊市购种: 价 × seed_buy_mult, 入库为「凡」品留种
func seed_buy_cost(s: Dictionary) -> int:
	return maxi(1, int(round(float(s.price) * float(econ("seed_buy_mult", 8)))))

func seed_buy(seed_id: String) -> bool:
	var s := DataManager.seed(seed_id)
	if s.is_empty() or _blocked("购种"):
		return false
	var cost := seed_buy_cost(s)
	if int(farm().stones) < cost:
		_log("灵石不足: 购【%s】种需 %d 灵石, 现有 %d" % [String(s.name), cost, int(farm().stones)])
		changed.emit()
		return false
	farm().stones = int(farm().stones) - cost
	_inv_add(seed_id, "凡", 1)
	_log("◇ 坊市购得【%s】种一株, 花 %d 灵石(入库留种)" % [String(s.name), cost])
	changed.emit()
	return true

func farm_reclaim() -> void:
	if _blocked("开垦"):
		return
	var cost := farm_reclaim_cost()
	if cost < 0 or farm_open_count() >= farm_cap():
		_log("地块已达当前境界上限(%d 块) —— 想扩地, 去突破(§6.1.1)" % farm_cap())
		return
	if int(farm().stones) < cost:
		_log("灵石不足: 开垦需 %d, 现有 %d(卖余货换灵石)" % [cost, int(farm().stones)])
		return
	farm().stones = int(farm().stones) - cost
	for p in farm().plots:
		if not bool(p.open):
			p.open = true
			break
	_log("◇ 开垦新地块(第 %d 块), 花 %d 灵石" % [farm_open_count(), cost])
	changed.emit()

func farm_sell(seed_id: String) -> void:
	if _blocked("出售"):
		return
	var total := _inv_seed_total(seed_id)
	if total <= 0:
		return
	var value := seed_stock_value(seed_id)
	farm().stones = int(farm().stones) + value
	farm().inv.erase(seed_id)
	_log("◇ 坊市出售【%s】×%d, 得 %d 灵石" % [String(DataManager.seed(seed_id).name), total, value])
	changed.emit()

func farm_sell_all() -> void:
	if _blocked("出售"):
		return
	var value := 0
	for seed_id in farm().inv.keys():
		value += seed_stock_value(String(seed_id))
	farm().inv = {}
	if value > 0:
		farm().stones = int(farm().stones) + value
		_log("◇ 坊市清空余货, 共得 %d 灵石" % value)
	else:
		_log("◇ 库存空空, 坊市摊主与你相顾无言")
	changed.emit()

func farm_sell_millennium() -> void:
	if _blocked("出售"):
		return
	var n := int(farm().millennium)
	if n <= 0:
		return
	farm().millennium = 0
	farm().stones = int(farm().stones) + n * int(econ("millennium_price", 500))
	_log("◇ 千年灵植 ×%d 高价出手, 得 %d 灵石(8–12 倍于同种, §6.1.3)" % [n, n * int(econ("millennium_price", 500))])
	changed.emit()

## 妖丹出手(伏妖战功, §5.4 妖战掉落): 单枚卖坊市 yaodan_price, 点击一次卖一枚
func farm_sell_yaodan() -> void:
	if _blocked("出售"):
		return
	if int(farm().get("yaodan", 0)) <= 0:
		return
	farm().yaodan = int(farm().yaodan) - 1
	var p := int(econ("yaodan_price", 120))
	farm().stones = int(farm().stones) + p
	_log("◇ 妖丹一枚出手坊市, 得 %d 灵石 —— 摊主验了又验: 「货真, 带妖煞。」" % p)
	changed.emit()

## 妖丹赠礼: 相识段起、每对象每季 1 次(同灵植/奇花); 闭关注养中候出关再办
func farm_gift_yaodan() -> void:
	if _blocked("赠礼"):
		return
	if _recover_guard("赠礼"):
		return
	if int(farm().get("yaodan", 0)) <= 0:
		return
	var fk := _focus_key()
	if fk == "":
		_log("尚无缘分对象可赠")
		return
	var npc: Dictionary = run.npcs[fk]
	if not bool(npc.get("met", false)) or int(npc.get("stage", 0)) < 1:
		_log("【%s】尚未相识 —— 陌生段只有交谈一条路" % npc_name(fk))
		return
	if int(npc.get("gift_q", 0)) >= int(tune("gift_quarter_cap", 1)):
		_log("【%s】本季已收过礼 —— 赠礼每对象每季至多 1 次" % npc_name(fk))
		return
	farm().yaodan = int(farm().yaodan) - 1
	npc.gift_q = int(npc.get("gift_q", 0)) + 1
	_bump_aff(fk, float(econ("gift_yaodan", 60)))
	_log("◇ 妖丹赠予【%s】, 好感+%d —— 「拿这去换护身符, 别总往险处跑。」" % [npc_name(fk), int(econ("gift_yaodan", 60))])
	changed.emit()

## 灵药直接服用(6.0.4 三出口之一): 每月自用 ≤1 株, 修为 += 单价×E×系数
func farm_tonic(seed_id: String) -> void:
	if _blocked("服用"):
		return
	var s := DataManager.seed(seed_id)
	if s.is_empty() or String(s.type) != "herb" or not Array(s.get("use", [])).has("tonic"):
		return
	if int(farm().tonic_cd) > 0:
		_log("本月已服用过灵药(每月自用 ≤1 株)")
		return
	if not _inv_take(seed_id, 1):
		_log("库存中没有【%s】" % String(s.name))
		return
	farm().tonic_cd = 1
	var g := float(s.price) * efficiency() * float(econ("tonic_factor", 0.5))
	_add_cult(g)
	_log("◇ 服用【%s】, 药力化开, 修为 +%s" % [String(s.name), _fmt(g)])
	changed.emit()

## 赠礼(6.2.4): 奇花 → 专注对象好感(相识段起, 每季 1 次; 固定值不走投喜表)
func farm_gift(seed_id: String) -> void:
	if _blocked("赠礼"):
		return
	if _recover_guard("赠礼"):
		return
	var s := DataManager.seed(seed_id)
	if s.is_empty() or not Array(s.get("use", [])).has("gift"):
		return
	var fk := _focus_key()
	if fk == "":
		_log("尚无缘分对象可赠")
		return
	var npc: Dictionary = run.npcs[fk]
	if not bool(npc.get("met", false)) or int(npc.get("stage", 0)) < 1:
		_log("【%s】尚未相识 —— 陌生段只有交谈一条路" % npc_name(fk))
		return
	if int(npc.get("gift_q", 0)) >= int(tune("gift_quarter_cap", 1)):
		_log("【%s】本季已收过礼 —— 赠礼每对象每季至多 1 次" % npc_name(fk))
		return
	if not _inv_take(seed_id, 1):
		_log("库存中没有【%s】" % String(s.name))
		return
	npc.gift_q = int(npc.get("gift_q", 0)) + 1
	_bump_aff(fk, float(econ("gift_flower", 50)))
	_log("◇ 将【%s】赠予【%s】, 好感+%d(奇花固定值)" % [String(s.name), npc_name(fk), int(econ("gift_flower", 50))])
	changed.emit()

func farm_gift_millennium() -> void:
	if _blocked("赠礼"):
		return
	if _recover_guard("赠礼"):
		return
	if int(farm().millennium) <= 0:
		return
	var fk := _focus_key()
	if fk == "":
		_log("尚无缘分对象可赠")
		return
	var npc: Dictionary = run.npcs[fk]
	if not bool(npc.get("met", false)) or int(npc.get("stage", 0)) < 1:
		_log("【%s】尚未相识 —— 陌生段只有交谈一条路" % npc_name(fk))
		return
	if int(npc.get("gift_q", 0)) >= int(tune("gift_quarter_cap", 1)):
		_log("【%s】本季已收过礼 —— 赠礼每对象每季至多 1 次" % npc_name(fk))
		return
	farm().millennium = int(farm().millennium) - 1
	npc.gift_q = int(npc.get("gift_q", 0)) + 1
	_bump_aff(fk, float(econ("gift_millennium", 80)))
	_log("◇ 千年灵植赠予【%s】, 好感+%d(§6.1.3)" % [npc_name(fk), int(econ("gift_millennium", 80))])
	changed.emit()

# ---------------------------------------------------------------- 伙房(§6.2 · 四小灶: 每两个大境界点亮一灶 · 烹饪→吃/送双轨)

const STOVE_TOTAL := 4

func _stoves() -> Array:
	if not run.farm.has("stoves"):
		run.farm.stoves = [{}, {}, {}, {}]
	if not run.farm.has("eaten"):
		run.farm.eaten = {}
	if not run.farm.has("dishes"):
		run.farm.dishes = {}
	return run.farm.stoves

## 洞府仓库: 菜谱 id → 份数(只存已收取的成菜, 食材仍在灵田库房)
func _dishes() -> Dictionary:
	_stoves()
	return run.farm.dishes

## 已点亮灶数: 炼气 1 灶, 此后每突破两个大境界段 +1(金丹 2 / 化神 3 / 合体 4)
func stove_open_count() -> int:
	return clampi(1 + int(run.get("realm", 0)) / 2, 1, STOVE_TOTAL)

## 点亮第 N 灶(1 起)所需的境界
func stove_unlock_realm(stove: int) -> Dictionary:
	return DataManager.realm(clampi(2 * (stove - 1), 0, DataManager.realms.size() - 1))

## 占位食材的显示名(其余走 seeds.json 反查)
func mat_name(seed_id: String) -> String:
	match seed_id:
		"millennium": return "千年灵植"
		"flower_any": return "奇花"
		"winter_any": return "冬·任何食材"
		"any": return "任何食材"
	return String(DataManager.seed(seed_id).get("name", seed_id))

func _mat_available(seed_id: String) -> int:
	match seed_id:
		"millennium":
			return int(farm().millennium)
		"flower_any":
			var t := 0
			for s in DataManager.seeds:
				if String(s.type) == "flower":
					t += _inv_seed_total(String(s.id))
			return t
		"any", "winter_any":
			return _inv_type_count("food") + _inv_type_count("herb")
		_:
			return _inv_seed_total(seed_id)

## 缺料提示(空串=足量); 同一菜谱内食材 id 不重复, 逐味检查即可
func recipe_missing(r: Dictionary) -> String:
	var parts: Array = []
	for m in r.get("mats", []):
		if _mat_available(String(m.seed)) < int(m.n):
			parts.append("%s×%d" % [mat_name(String(m.seed)), int(m.n)])
	return "/".join(parts)

func _mat_take(seed_id: String, n: int) -> bool:
	match seed_id:
		"millennium":
			if int(farm().millennium) < n:
				return false
			farm().millennium = int(farm().millennium) - n
			return true
		"flower_any":
			for s in DataManager.seeds:
				if String(s.type) != "flower":
					continue
				while n > 0 and _inv_seed_total(String(s.id)) > 0:
					if not _inv_take(String(s.id), 1):
						break
					n -= 1
				if n <= 0:
					return true
			return n <= 0
		"any", "winter_any":
			for typ in ["food", "herb"]:
				for s in DataManager.seeds:
					if String(s.type) != typ:
						continue
					var take_n := mini(_inv_seed_total(String(s.id)), n)
					if take_n > 0:
						_inv_take(String(s.id), take_n)
						n -= take_n
					if n <= 0:
						return true
			return n <= 0
		_:
			return _inv_take(seed_id, n)

func _stove_dish(stove: int) -> Dictionary:
	var stoves := _stoves()
	if stove < 0 or stove >= stoves.size():
		return {}
	return DataManager.recipe(String(stoves[stove].get("recipe", "")))

## 烹制耗时: 按菜谱档位取月数(economy_tuning.cook_months), 稀有度越高越久; 暗谱/缺失回落 1 月
func cook_months(r: Dictionary) -> int:
	var cm: Dictionary = econ("cook_months", {"low": 1, "mid": 2, "high": 3})
	return maxi(1, int(cm.get(String(r.get("tier", "low")), 1)))

## 灶上是否已烹好可收取(旧档无 age 字段按已好处理)
func stove_done(stove: int) -> bool:
	var stoves := _stoves()
	if stove < 0 or stove >= stoves.size():
		return false
	var st: Dictionary = stoves[stove]
	var r := DataManager.recipe(String(st.get("recipe", "")))
	if r.is_empty():
		return false
	return int(st.get("age", cook_months(r))) >= cook_months(r)

## 灶上月度烹制: 已起火的锅逐月 +1, 到期入月报提示可收取
func _kitchen_tick() -> void:
	for st in _stoves():
		var rid := String(st.get("recipe", ""))
		if rid == "":
			continue
		if int(st.get("age", 0)) >= cook_months(DataManager.recipe(rid)):
			continue   # 已可收取, 静候玩家
		st.age = int(st.get("age", 0)) + 1
		if int(st.age) >= cook_months(DataManager.recipe(rid)):
			_report("【%s】出锅可收取" % String(DataManager.recipe(rid).get("name", rid)))

func kitchen_cook(stove: int, recipe_id: String) -> void:
	if _blocked("烹饪"):
		return
	if stove < 0 or stove >= stove_open_count():
		_log("灶 #%d 尚未点亮 —— 突破大境界段, 伙房自会添灶" % (stove + 1))
		return
	if String(_stoves()[stove].get("recipe", "")) != "":
		_log("灶 #%d 上已有菜在烹/待收 —— 先收取入库, 再烹下一道" % (stove + 1))
		return
	var r := DataManager.recipe(recipe_id)
	if r.is_empty() or String(r.tier) == "dark":
		return
	if int(run.realm) < int(r.get("min_realm", 0)):
		_log("【%s】尚未习得 —— 晋升【%s】后其谱自会入灶" % [String(r.name), String(DataManager.realm(int(r.min_realm)).name)])
		return
	var missing := recipe_missing(r)
	if missing != "":
		_log("缺料: %s —— 先去灵田种一茬" % missing)
		return
	for m in r.get("mats", []):
		_mat_take(String(m.seed), int(m.n))
	_stoves()[stove].recipe = recipe_id
	_stoves()[stove].age = 0
	_log("◇ 灶 #%d 起火烹【%s】(%s) —— 需 %d 月, 到期点「收取」入洞府仓库" % [stove + 1, String(r.name), String(r.effect), cook_months(r)])
	changed.emit()

func kitchen_collect(stove: int) -> void:
	if _blocked("收取"):
		return
	if stove < 0 or stove >= stove_open_count():
		return
	var r := _stove_dish(stove)
	if r.is_empty():
		return
	if not stove_done(stove):
		var left := cook_months(r) - int(_stoves()[stove].get("age", 0))
		_log("【%s】还在灶上烹着 —— 还需 %d 月才得" % [String(r.name), left])
		changed.emit()
		return
	_stoves()[stove] = {}
	var dishes := _dishes()
	var rid := String(r.id)
	dishes[rid] = int(dishes.get(rid, 0)) + 1
	_log("◇ 灶 #%d 收取【%s】入洞府仓库(共 ×%d)" % [stove + 1, String(r.name), int(dishes[rid])])
	changed.emit()

func kitchen_eat(recipe_id: String) -> void:
	if _blocked("吃"):
		return
	var r := DataManager.recipe(recipe_id)
	if r.is_empty() or String(r.tier) == "dark":
		return
	var dishes := _dishes()
	if int(dishes.get(recipe_id, 0)) <= 0:
		_log("洞府仓库里没有【%s】" % String(r.name))
		return
	if String(r.tier) == "high":
		var eaten: Dictionary = run.farm.eaten   # _dishes() 已保证字段存在
		if int(eaten.get(recipe_id, 0)) >= 1:
			_log("天道有常: 【%s】每世只许入口一次 —— 仓库里那份留着吧" % String(r.name))
			return
		eaten[recipe_id] = int(eaten.get(recipe_id, 0)) + 1
	dishes[recipe_id] = int(dishes.get(recipe_id, 0)) - 1
	if int(dishes[recipe_id]) <= 0:
		dishes.erase(recipe_id)
	_apply_dish_fx(r)
	changed.emit()

## 吃下一道: 按 fx 把效果列真正落地(图鉴 6.2.4); 仙膳另得「6 个月聚灵产出」灵气(图鉴口径)
func _apply_dish_fx(r: Dictionary) -> void:
	var fx: Dictionary = r.get("fx", {})
	var kind := String(fx.get("kind", ""))
	var v := float(fx.get("v", 0.0))
	var months := int(fx.get("months", 1))
	var gain := String(r.effect)
	match kind:
		"cult_pct":
			_buff_apply("cult_pct", v, months)
			gain = "下月修炼 +%d%%(%d 月)" % [int(round(v * 100.0)), months]
		"cult_flat":
			var fg := efficiency() * float(realm().max_ap) * v
			_add_cult(fg)
			gain = "修为 +%s(直接入账, ≈%.2f 月聚灵)" % [_fmt(fg), v]
		"eff_pct":
			_buff_apply("eff_pct", v, months)
			gain = "聚灵效率 +%d%%(%d 月)" % [int(round(v * 100.0)), months]
		"regen":
			_buff_apply("regen", v, months)
			gain = "气血自然回复 +%d/月(%d 月)" % [int(round(v)), months]
		"check_pct":
			_buff_apply("check_pct", v, months)
			gain = "下次冲关成功率 +%d%%(未冲关不消散, 冲关成功后消失)" % int(round(v * 100.0))
		"wuxing":
			_buff_apply("wuxing", v, months)
			gain = "顿悟率 +%dpp(%d 月)" % [int(round(v * 100.0)), months]
		"heal":
			if v >= 999.0:
				run.qi = qi_max()
				gain = "气血尽复(现 %d/%d)" % [_qi(), qi_max()]
			else:
				run.qi = mini(qi_max(), _qi() + int(v))
				gain = "气血 +%d(现 %d/%d)" % [int(v), _qi(), qi_max()]
		"inner":
			var i0 := int(run.inner)
			run.inner = maxi(0, i0 - int(v))
			gain = "心魔 −%d 月(%d→%d)" % [int(v), i0, int(run.inner)]
		"break_once":
			run.break_bonus = float(run.get("break_bonus", 0.0)) + v
			gain = "下次冲关 +%d%%(一次性)" % int(round(v * 100.0))
		"aptitude":
			var a0 := float(run.get("aptitude", 0.0))
			run.aptitude = minf(0.04, a0 + v)
			gain = "永久资质 +%.0f%%(全世 %.0f%%/4%%, 入聚灵乘项)" % [(float(run.aptitude) - a0) * 100.0, float(run.aptitude) * 100.0]
		"lifespan":
			var l0 := int(run.get("life_bonus", 0))
			run.life_bonus = mini(3, l0 + int(v))
			gain = "永久寿元 +%d 年(全世合计 +%d/3 年)" % [int(run.life_bonus) - l0, int(run.life_bonus)]
		"luck":
			run.luck = mini(1, int(run.get("luck", 0)) + int(v))
			gain = "永久气运 +%d 档(冲关+3%%, 机缘概率+10%%)" % int(run.luck)
		"element":
			# 多行灵根: 换根不换行数 —— 随机把身负的一行换成未持有的另一行
			var roots: Array = run.get("roots", [String(run.element)])
			var idx := rng.randi_range(0, roots.size() - 1)
			var old := String(roots[idx])
			var avail: Array = []
			for e in ELEMENTS:
				if not (String(e) in roots):
					avail.append(String(e))
			var neo := String(avail[rng.randi() % avail.size()])
			roots[idx] = neo
			run.roots = roots
			run.root_count = roots.size()
			run.element = String(roots[0])
			gain = "灵根·五行转易: %s→%s(亲和修正随之改换)" % [old, neo]
	if String(r.tier) == "high":
		var gains: Dictionary = econ("eat_gain_months", {"low": 0.05, "mid": 0.25, "high": 6.0})
		var g := efficiency() * float(realm().max_ap) * float(gains.get("high", 6.0))
		_add_cult(g)
		gain += " · 灵气 +%s(≈6 月聚灵产出)" % _fmt(g)
	_log("◇ 吃了【%s】: %s" % [String(r.name), gain])

func kitchen_gift(recipe_id: String) -> void:
	if _blocked("赠礼"):
		return
	if _recover_guard("赠礼"):
		return
	var r := DataManager.recipe(recipe_id)
	if r.is_empty() or String(r.tier) == "dark":
		return
	var dishes := _dishes()
	if int(dishes.get(recipe_id, 0)) <= 0:
		_log("洞府仓库里没有【%s】" % String(r.name))
		return
	var fk := _focus_key()
	if fk == "":
		_log("尚无缘分对象可赠")
		return
	var npc: Dictionary = run.npcs[fk]
	if not bool(npc.get("met", false)) or int(npc.get("stage", 0)) < 1:
		_log("【%s】尚未相识 —— 陌生段只有交谈一条路(恋爱系统 §1.2)" % npc_name(fk))
		return
	if int(npc.get("gift_q", 0)) >= int(tune("gift_quarter_cap", 1)):
		_log("【%s】本季已收过礼 —— 投喜料理每对象每季至多 1 次" % npc_name(fk))
		return
	dishes[recipe_id] = int(dishes.get(recipe_id, 0)) - 1
	if int(dishes[recipe_id]) <= 0:
		dishes.erase(recipe_id)
	npc.gift_q = int(npc.get("gift_q", 0)) + 1
	var fav := npc_taste_base(fk)
	var hit: bool = Array(r.get("tags", [])).has(fav)
	var v := int(tune("gift_gain", 30)) * (int(tune("gift_fav_mult", 2)) if hit else 1)
	_bump_aff(fk, float(v))
	_log("◇ 将【%s】赠予【%s】, 好感+%d%s" % [String(r.name), npc_name(fk), v, ("(投喜! Ta 最爱「%s」味)" % fav) if hit else ""])
	changed.emit()

# ---------------------------------------------------------------- 缘分(NPC 系统: 恋爱系统 v1.7 灰盒口径 —— 量程 0-1000 · 六态 · 首遇制 · 投喜 · 修罗场喜剧化)

func npc_arch(key: String) -> Dictionary:
	for n in DataManager.npcs:
		if String(n.key) == key:
			return n
	return {}

func npc_name(key: String) -> String:
	if run.npcs.has(key) and run.npcs[key].has("name"):
		return String(run.npcs[key].name)   # 随机 NPC: 档案快照在 run 侧
	if run.has("world_npcs") and (run.world_npcs as Dictionary).has(key):
		return String(((run.world_npcs as Dictionary)[key] as Dictionary).get("name", key))   # 世界池未识者: 名字照报, 脸不见
	for n in DataManager.npcs:
		if String(n.key) == key:
			return String(n.name)
	return key


## 某人相关的纪事(名录·详情「纪事」页用): 两路合并, 返回最新在前 [{day,text}] ——
## 1) 日志: 扫 GameState.chronicle 认「【Ta】」写法(日志出口都以【名】括人名, 姓名在册+池内防重);
##    月末汇总行(「第X年·M月 · 条目 · 条目…」)按条拆开, 只留提及 Ta 的条。
## 2) 照壁: 世界戏剧(NPC 心动/相恋/成婚/闹别扭)多上壁少入日志, 未入册者尤甚 —— 帖标题经
##    sub 代入后含 Ta 名即算一条, 标「上壁 · 第X年 · M月」。两路按(年,月)倒序合并。
## 两路皆空时(旧档补池的陌生脸/刚入册还没留痕者), 以坊间传闻兜底 —— 纪事人人可看(2026-09-23)。
func chronicle_of(key: String) -> Array:
	var nm := npc_name(key)
	var tag := "【%s】" % nm
	var dated: Array = []   # [{ym, seq, day, text}]; ym=年*12+月, 解析失败 -1 垫底
	var seq := 0
	for e in GameState.chronicle:
		var text := String(e.get("text", ""))
		if not text.contains(tag):
			continue
		var day := String(e.get("day", ""))
		if text.begins_with("第") and text.contains(" · "):
			var segs: PackedStringArray = []
			for s in text.split(" · "):
				if String(s).contains(tag):
					segs.append(String(s))
			if segs.is_empty():
				continue
			text = " · ".join(segs)
		dated.append({"ym": _chron_ym(day), "seq": seq, "day": day, "text": text})
		seq += 1
	if run.has("wall"):
		for p in Array(run.wall.get("posts", [])):
			var post: Dictionary = DataManager.wall_post(String((p as Dictionary).get("id", "")))
			if post.is_empty():
				continue
			var sv: Variant = (p as Dictionary).get("sub", {})
			var sub: Dictionary = sv if sv is Dictionary else {}
			var title := _wall_sub(String(post.get("title", "")), sub)
			if title == "" or not title.contains(nm):
				continue
			var y := int((p as Dictionary).get("year", 0))
			var m := int((p as Dictionary).get("month", 1))
			dated.append({"ym": y * 12 + m, "seq": seq, "day": "上壁 · 第%d年 · %d月" % [y, m], "text": "照壁: %s" % title})
			seq += 1
	dated.sort_custom(func(a, b): return int(a.ym) > int(b.ym) if int(a.ym) != int(b.ym) else int(a.seq) > int(b.seq))
	var out: Array = []
	for d in dated:
		out.append({"day": String((d as Dictionary).day), "text": String((d as Dictionary).text)})
	if out.is_empty():
		out = _rumor_chronicle(key)
	return out


## 纪事 day 标签(「第X世 · 第Y年 · M月」)取年月 → ym 可排序键; 解析失败(旧档「旧岁·N」等)回 -1。
var _chron_ym_re := RegEx.create_from_string("第(\\d+)年[^第]*?(\\d+)月")


func _chron_ym(day: String) -> int:
	var m := _chron_ym_re.search(day)
	if m == null:
		return -1
	return int(m.get_string(1)) * 12 + int(m.get_string(2))


## 坊间传闻兜底纪事(2026-09-23 拍板): 名录灰显的传闻脸与刚入册者常常一条真纪事都没有,
## 点开空白违背「纪事人人可看, 世间事不因未见而不发生」—— 从世界池真实状态(档案/配偶/动态边/家眷)
## 拼出传闻小料: 素材全是世界生成的真事实, 没查到就不编; 不落结算日志、不造日期, 期号一律「坊间传闻」。
func _rumor_chronicle(key: String) -> Array:
	var e: Dictionary = _npc_entry(key)
	if e.is_empty():
		e = npc_arch(key)
	if e.is_empty():
		return []
	var nm := npc_name(key)
	var dead := bool(e.get("dead", false))
	var day := "旧闻" if dead else "坊间传闻"
	var out: Array = []
	var sc := String(e.get("scene", ""))
	var idn := String(e.get("id_name", String(e.get("identity", ""))))
	var alias := String(e.get("alias", ""))
	var head := "市井耳目: 【%s】%s" % [nm, ("(已故) " if dead else "")]
	var marks: Array = []
	for s2 in [sc, idn]:
		if String(s2) != "":
			marks.append(String(s2))
	if not marks.is_empty():
		head += "(%s)" % "·".join(marks)
	if alias != "":
		head += " —— 坊间唤作「%s」" % alias
	elif String(e.get("moe", "")) != "":
		head += " —— %s" % String(e.get("moe", ""))
	out.append({"day": day, "text": head})
	var sp := String(e.get("spouse", ""))
	if sp != "":
		out.append({"day": day, "text": "茶摊都说: 【%s】与【%s】是结发夫妻 —— 这桩喜事当年坊间是随过份子的" % [nm, npc_name(sp)]})
	var used := 0
	for ed in run.get("world_rels", []):
		if used >= 2:
			break
		var a := String(ed.get("a", ""))
		var b := String(ed.get("b", ""))
		var peer := ""
		if a == key:
			peer = b
		elif b == key:
			peer = a
		else:
			continue
		if peer == sp or String(ed.get("tag", "")) in ["夫妻", "父亲", "母亲", "儿子", "女儿"]:
			continue   # 婚配由 spouse 行代述; 亲缘方向词并提不通顺(「是「父亲」」), 子嗣行已覆盖
		out.append({"day": day, "text": "茶摊闲话: 【%s】与【%s】是「%s」—— %s" % [nm, npc_name(peer), String(ed.get("tag", "旧识")), String(ed.get("note", ""))]})
		used += 1
	var kids: Array = e.get("children", [])
	if not kids.is_empty():
		var kn: Array = []
		for kid in kids.slice(0, 3):
			kn.append("【%s】" % npc_name(String(kid)))
		out.append({"day": day, "text": "坊间都道: 【%s】膝下有 %d 个孩子 —— %s" % [nm, kids.size(), "、".join(kn)]})
	return out.slice(0, 5)


## 日程预览「一世纪事」的关注过滤: 提及未关注 NPC(未入册者亦算未关注; 「喜欢」恒算已关注)的条目隐去。
## 月报大行(「第X年·M月 · 条 · 条…」)按 " · " 拆段, 逐段滤除后重拼; 普通行命中即整条丢弃;
## 与在册 NPC 无关的条目(修炼/方案/突破等)原样返回。返回空串 = 整条不显示。
func filter_chronicle_for_follows(text: String) -> String:
	var tags: PackedStringArray = []
	for key in run.get("npcs", {}):
		if not is_followed(String(key)):
			tags.append("【%s】" % npc_name(String(key)))
	for key in run.get("world_npcs", {}):   # 未入册者亦算未关注: 坊市闲话/婚丧添丁等池人纪事不上日程页(玉牌仍有全文)
		if not is_followed(String(key)):
			tags.append("【%s】" % npc_name(String(key)))
	if tags.is_empty():
		return text
	var mentions := func(s: String) -> bool:
		for tg in tags:
			if s.contains(tg):
				return true
		return false
	if text.begins_with("第") and text.contains(" · "):
		var segs: PackedStringArray = []
		for s in text.split(" · "):
			if not mentions.call(String(s)):
				segs.append(String(s))
		return " · ".join(segs)
	return "" if mentions.call(text) else text

## 专注对象仅限已首遇 NPC(§5); 未设则默认好感最高者
func _focus_key() -> String:
	var f := String(run.get("focus", ""))
	if f != "" and run.npcs.has(f) and bool(run.npcs[f].get("met", false)):
		return f
	var best := ""
	var best_aff := -1.0
	for key in run.npcs:
		if not bool(run.npcs[key].get("met", false)):
			continue
		var bond: float = maxf(float(run.npcs[key].aff), float(run.npcs[key].get("love", 0.0)))   # 双轨取最重: 情浓者亦系心
		if bond > best_aff:
			best_aff = bond
			best = String(key)
	return best

## 显式设置的喜欢(区别于 _focus_key 的最高好感兜底)
func _explicit_focus() -> String:
	var f := String(run.get("focus", ""))
	if f != "" and run.npcs.has(f) and bool(run.npcs[f].get("met", false)):
		return f
	return ""

## 喜欢的代价: 他人好感每月 -1(focus_drain), 累计冷落 focus_neglect_months 个月后可触发「故人心思」
func _focus_neglect_tick() -> void:
	var fk := _explicit_focus()
	if fk == "":
		return
	for key in run.npcs:
		var npc: Dictionary = run.npcs[key]
		if not bool(npc.get("met", false)) or String(key) == fk:
			continue
		npc.aff = maxf(0.0, float(npc.get("aff", 0.0)) - float(tune("focus_drain", 1)))
		npc.nlost = int(npc.get("nlost", 0)) + 1

## 冷落事件(温柔版, 无惩罚 debuff —— 乙女红线): 每位 NPC 每轮只弹一次, 处置后重新计数
func _neglect_check() -> bool:
	var fk := _explicit_focus()
	if fk == "":
		return false
	for key in run.npcs:
		var npc: Dictionary = run.npcs[key]
		if not bool(npc.get("met", false)) or String(key) == fk:
			continue
		if int(npc.get("nlost", 0)) >= int(tune("focus_neglect_months", 12)):
			npc.nlost = 0
			_fire_interrupt("故人心思 · %s" % npc_name(String(key)),
				"【%s】察觉你近来眼里只有【%s】—— 没说什么, 只是笑意淡了些。要紧吗?" % [npc_name(String(key)), npc_name(fk)],
				[
					{"t": "请 Ta 吃顿好的", "need": "亲自下厨", "result": "好感 +30 · 心结化开"},
					{"t": "陪 Ta 说说话", "need": "半个时辰", "result": "好感 +10 · 心结化开"},
				], "neglect", {"key": String(key)})
			return true
	return false

## 喜欢的甜头: 好感每跨过一道 100 的坎, 触发一次「心动时分」小事件(仅对象)
func _focus_mile_check() -> bool:
	var fk := _explicit_focus()
	if fk == "" or not run.npcs.has(fk):
		return false
	var npc: Dictionary = run.npcs[fk]
	if not bool(npc.get("mile_pending", false)):
		return false
	npc.mile_pending = false
	var stage_name := String(tune("aff_stages", ["陌生", "相识", "相熟", "心动", "相恋", "道侣"])[clampi(int(npc.get("stage", 0)), 0, 5)])
	_fire_interrupt("心动时分 · %s" % npc_name(fk),
		"好感悄悄跨过了一道坎(现 %.0f · %s) —— 与【%s】之间, 似乎有什么不一样了。此刻做点什么?" % [float(npc.aff), stage_name, npc_name(fk)],
		[
			{"t": "顺势靠近", "need": "多问一句心里话", "result": "好感 +10"},
			{"t": "静待花开", "need": "不急这一时", "result": "把这份暖意记在心里"},
		], "focus_mile", {"key": fk})
	return true

## NPC 修行: 与主角完全同构 —— 修为逐月积累(主角节奏 ×npc_cult_mult), 圆满自动冲关,
## 冲关率与主角同源(境界 break_prob ± npc_break_bonus), 失败散三成修为; 上限渡劫后期; 无境界者(书页)不参与。
## 破境/失手全员入月报→纪事(2026-09-22 拍板: 世间事不因未关注而不留痕; 旧口径只记特别关注对象)。
func _npc_cultivation() -> void:
	for key in run.npcs:
		var npc: Dictionary = run.npcs[key]
		if not bool(npc.get("met", false)):
			continue
		if bool(npc.get("dead", false)):
			continue   # 坐化者功行盖棺, 不再结算
		if _npc_is_minor(String(key)):
			continue   # 幼年不修炼(成年礼后入轨)
		var ord := int(npc.get("realm_ord", -99))
		if ord == -99:
			ord = int(npc_arch(key).get("realm_ord", -1))
			npc.realm_ord = ord
		if ord < 0 or ord >= DataManager.realms.size() - 1:
			continue   # 无境界者(话本成精) / 已至渡劫后期(修士尽头)
		var re: Dictionary = DataManager.realm(ord)
		var layers := maxi(1, int(re.get("layers", 3)))
		var nlayer := int(npc.get("nlayer", 0))
		var need: float = float(tune("layer_need_base", 100.0)) * pow(float(tune("layer_growth", 1.55)), float(DataManager.layer_offset(ord) + nlayer))
		npc.cult = float(npc.get("cult", 0.0)) + float(re.get("gain_base", 10)) * float(re.get("max_ap", 1)) * float(tune("npc_cult_mult", 0.5)) * npc_root_coef(String(key))
		var chance: float = clampf(float(re.get("break_prob", 0.4)) + float(tune("npc_break_bonus", 0.0)), 0.05, 0.99)
		var guard := 0
		while float(npc.cult) >= need and nlayer < layers - 1 and guard < 8:
			guard += 1
			if deterministic or rng.randf() < chance:
				npc.cult = float(npc.cult) - need
				npc.nlayer = nlayer + 1
				nlayer = int(npc.nlayer)
				need = float(tune("layer_need_base", 100.0)) * pow(float(tune("layer_growth", 1.55)), float(DataManager.layer_offset(ord) + nlayer))
			else:
				npc.cult = float(npc.cult) * float(econ("npc_fail_keep", 0.7))
				_report("【%s】小层冲关失手, 修为散去三成" % npc_name(String(key)))
				break
		# 末层圆满 → 大境界冲关(同一突破率)
		if nlayer >= layers - 1 and float(npc.cult) >= need:
			if deterministic or rng.randf() < chance:
				npc.cult = float(npc.cult) - need
				npc.nlayer = 0
				npc.realm_ord = ord + 1
				npc.realm = String(DataManager.realm(ord + 1).get("name", "?"))
				_report("【%s】冲关成功 —— 破境「%s」!" % [npc_name(String(key)), String(npc.realm)])
			else:
				npc.cult = float(npc.cult) * float(econ("npc_fail_keep", 0.7))
				_report("【%s】大境界冲关失手, 修为散去三成" % npc_name(String(key)))

## 口味先验: 固定 NPC 读档案双层先验的 base 味; 随机 NPC 读 run 侧快照
func npc_taste_base(key: String) -> String:
	if run.npcs.has(key) and run.npcs[key].has("taste_base"):
		return String(run.npcs[key].taste_base)
	return String(npc_arch(key).get("favorite_taste", {}).get("base", ""))

## 性别: 固定 NPC 读档案, 随机 NPC 读 run 快照; 旧档缺性别按男性处理(不影响既有缘分)
func npc_male(key: String) -> bool:
	var g := ""
	if run.npcs.has(key):
		g = String(run.npcs[key].get("gender", ""))
	if g == "" and run.has("world_npcs") and (run.world_npcs as Dictionary).has(key):
		g = String(((run.world_npcs as Dictionary)[key] as Dictionary).get("gender", ""))
	if g == "":
		g = String(npc_arch(key).get("gender", "male"))
	return g != "female"

## 六态: 陌生(0)→相识(1)→相熟(2)→心动(3)→相恋(4)→道侣(5); 0-2 段吃 aff(友情轨), 3-5 段吃 love(恋爱轨)
## love 仅异性 NPC 可涨(同性恒 0 不可变动); aff 沿用 0-1000 满量程。
func _npc_init() -> Dictionary:
	return {"aff": 0.0, "love": 0.0, "hidden": 0.0, "stage": 0, "gate": 0, "met": false,
		"talk_cd": 0, "talk_q": 0, "gift_q": 0, "date_cd": 0,
		"sealed": false, "dao_lu": false, "luochang_lowkey": false}

## 首遇制(§1.7): 相遇不加好感, 好感自 0 起; 时光闸自入册 tick 起算(gate=0)。药商家出身遇温半夏相遇即相识(+200)。
func _first_meet(key: String, reason := "") -> void:
	if is_ended() or run.npcs.has(key):
		return
	var arch := npc_arch(key)
	var npc := _npc_init()
	npc.met = true
	if String(key) == "yaoshi" and String(run.get("origin", "")) == "药商世家女":
		npc.aff = 200.0
		npc.stage = 1
	run.npcs[key] = npc
	_npc_vitals_backfill(npc, key)   # 固定档案也上生辰/灵根/气血(寿数只示人不坐化 —— mortality 豁免固定者)
	_log("◆ 初遇【%s】(%s·%s)%s —— 缘分页已入册" % [npc_name(key), String(arch.get("identity", "")), String(arch.get("scene", "")), ("" if reason == "" else " —— " + reason)])
	_gift_note(key)
	changed.emit()

## 双轨好感: track="friend"(aff, 人人可涨) / "love"(love, 恋爱行为专属 —— 同性守回落回友情轨)。
## 各轨 0-1000 封顶, 溢出 100% 转「情深许」隐藏值(§1.5); 微幅负波动先扣隐藏、隐藏不足才落面板(下限 0)
func _bump_aff(key: String, v: float, track := "friend") -> void:
	var npc: Dictionary = run.npcs[key]
	if track == "love" and not npc_male(key):
		track = "friend"   # 同性守门: 女性 NPC 情值恒 0 —— 恋爱类行为落在她们身上只算友情
	var cap := float(tune("aff_thresholds", [200, 400, 600, 800, 1000])[4])
	# 气质 + 关系网: 主角气质、这位 NPC 的气质、以及「Ta 的故交恰是你的故交」这道情面 —— 都只放大正向, 不放大扣分
	var dv := v * (1.0 + aura_self("aff") + aura_npc_aff(key) + relation_halo(key)) if v > 0.0 else v
	var cur := float(npc.aff) if track == "friend" else float(npc.get("love", 0.0))
	var na := cur + dv
	if na > cap:
		npc.hidden = float(npc.get("hidden", 0.0)) + (na - cap)
		na = cap
	elif v < 0.0 and na < cap:
		var back: float = minf(float(npc.get("hidden", 0.0)), cap - na)
		npc.hidden = float(npc.get("hidden", 0.0)) - back
		na += back
	if track == "friend":
		npc.aff = maxf(0.0, na)
	else:
		npc.love = maxf(0.0, na)
	# 喜欢里程碑: 好感每跨过一道 100 的坎, 记一次待触发的「心动时分」(⑥ 打断判定统一弹出)
	if key == _explicit_focus():
		var m := int(float(npc.aff if track == "friend" else npc.get("love", 0.0)) / 100.0)
		if m > int(npc.get("mile", 0)):
			npc.mile = m
			npc.mile_pending = true

func _dao_key() -> String:
	for key in run.npcs:
		if int(run.npcs[key].get("stage", 0)) >= 5:
			return String(key)
	return ""

## 好感厚礼(§7 恋爱后续): 心动(3)段及以上 NPC, 按段位概率差人给主角送菜肴/灵植。
## 内容随主角境界水涨船高: 菜肴只送当前境界学得会的最高三档; 灵植品阶随境界有灵/上概率。每月至多一份, 月报入纪事。
func _favor_gift_tick() -> void:
	var cands: Array = []
	for key in run.npcs:
		var npc: Dictionary = run.npcs[key]
		if bool(npc.get("met", false)) and int(npc.get("stage", 0)) >= 3:
			cands.append(String(key))
	if cands.is_empty():
		return
	var key := String(cands[rng.randi_range(0, cands.size() - 1)])
	var stage := int(run.npcs[key].get("stage", 3))
	var rate: float = [0.0, 0.0, 0.0, 0.25, 0.4, 0.55][clampi(stage, 0, 5)]   # 心动 25% / 相恋 40% / 道侣 55%
	if rng.randf() >= rate:
		return
	var who := npc_name(key)
	var stage_name := String(tune("aff_stages", ["陌生", "相识", "相熟", "心动", "相恋", "道侣"])[clampi(stage, 0, 5)])
	var ord := int(realm().ordinal)
	if rng.randf() < 0.5:
		var pool: Array = []
		for r in DataManager.recipes:
			if int(r.get("min_realm", 0)) <= ord:
				pool.append(r)
		if pool.is_empty():
			return
		pool.sort_custom(func(a, b): return int(a.get("min_realm", 0)) < int(b.get("min_realm", 0)))
		var top: Array = pool.slice(maxi(0, pool.size() - 3))   # 当前境界吃得起的最高三档
		var dish: Dictionary = top[rng.randi_range(0, top.size() - 1)]
		var did := String(dish.id)
		var dishes: Dictionary = farm().dishes
		dishes[did] = int(dishes.get(did, 0)) + 1
		_report("【%s】差人送来一份【%s】—— 「听说你近来冲关, 补一补。」(%s段 · 好感深厚)" % [who, String(dish.name), stage_name])
	else:
		var grade := "凡"
		var roll := rng.randf()
		if ord >= 5 and roll < 0.25:
			grade = "上"
		elif ord >= 2 and roll < 0.45:
			grade = "灵"
		var s: Dictionary = DataManager.seeds[rng.randi_range(0, DataManager.seeds.size() - 1)]
		var sid := String(s.id)
		_inv_add(sid, grade, 1)
		_report("【%s】差人送来一株【%s】(%s品) —— 「灶上添个菜。」(%s段 · 好感深厚)" % [who, String(s.name), grade, stage_name])

## NPC 境界突破率(与月结 _npc_cultivation 同源): 该境界 break_prob ± 调参, 钳 5%~99%;
## 无境界者(话本成精)或已至渡劫后期返回 -1(详情界面不显示)。
func npc_break_chance(key: String) -> float:
	var npc: Dictionary = run.npcs.get(key, {})
	var ord := int(npc.get("realm_ord", -99))
	if ord == -99:
		ord = int(npc_arch(key).get("realm_ord", -1))
	if ord < 0 or ord >= DataManager.realms.size() - 1:
		return -1.0
	var re: Dictionary = DataManager.realm(ord)
	return clampf(float(re.get("break_prob", 0.4)) + float(tune("npc_break_bonus", 0.0)), 0.05, 0.99)

func _advance_node(key: String) -> void:
	var npc: Dictionary = run.npcs[key]
	var names: Array = tune("aff_stages", ["陌生", "相识", "相熟", "心动", "相恋", "道侣"])
	if int(npc.stage) + 1 >= 5 and _dao_key() != "":
		_log("◇ 道侣位唯一 —— 【%s】的心意收进岁月里, 此生以道友相称" % npc_name(key))
		return
	npc.stage = int(npc.stage) + 1
	npc.gate = 0
	_log("◆ 与【%s】关系推进: %s → %s" % [npc_name(key), String(names[clampi(int(npc.stage) - 1, 0, 5)]), String(names[clampi(int(npc.stage), 0, 5)])])
	if int(npc.stage) >= 5:
		npc.dao_lu = true
		_queue_wall_event("daolv", {"npc": npc_name(key)})   # 闲话壁: 结道侣贺帖(延迟 1 月)
	elif int(npc.stage) == 4:
		_queue_wall_event("xianglian", {"npc": npc_name(key)})   # 闲话壁: 相恋实锤帖
	elif int(npc.stage) == 3:
		_queue_wall_event("xindong", {"npc": npc_name(key)})   # 闲话壁: 心动吃瓜帖

## 门槛事件(§1.4): 3 选 1 对话检定 —— 命中萌点 0.85 / 笨拙但真诚 0.70 / 本心直给 0.55(数值·M0 拍板进 tuning);
## 成功 ±50 直给并推进; 失败微幅波动、不重置好感、这道闸顺延(暂缓不消耗资格, 每 tick 重弹)。
func _fire_node_event(key: String, stage: int) -> void:
	var arch := npc_arch(key)
	var names: Array = tune("aff_stages", ["陌生", "相识", "相熟", "心动", "相恋", "道侣"])
	var to_name := String(names[clampi(stage + 1, 0, 5)])
	var moe := String(arch.get("moe", "那个人"))
	_fire_interrupt("缘分节点 · %s" % String(arch.get("scene", "")),
		"【%s】(%s · 好感 %.0f) —— 时光闸已到, 这一步迈不迈? 说到 Ta 心坎上, 关系便是另一番天地。" % [npc_name(key), String(names[clampi(stage, 0, 5)]), float(run.npcs[key].aff)],
		[
			{"t": "谈起「%s」" % moe, "need": "勾起 Ta 最在意的那件事", "result": "检定 85% · 成功好感+50 并推进段位 · 失败顺延"},
			{"t": "本心直给", "need": "不加修饰, 坦陈心迹", "result": "检定 55% · 成功同上 · 失败顺延"},
		], "node", {"key": key, "rates": [tune("node_moe_rate", 0.85), tune("node_base_rate", 0.55)]})

## 节点/时光闸/魂印 —— 命中即打断; 节点「满阈 + 闸到期」每 tick 重弹; 魂印走年终检定(道侣位 + 隐藏≥10000)
func _npc_prompt_check() -> bool:
	var ths: Array = tune("aff_thresholds", [200, 400, 600, 800, 1000])
	var lovs: Array = tune("love_thresholds", [200, 500, 1000])   # 心动/相恋/道侣 三跳的情值门槛
	for key in run.npcs:
		var npc: Dictionary = run.npcs[key]
		if not bool(npc.get("met", false)):
			continue
		if _npc_is_minor(String(key)):
			continue   # 红线: 幼年绝不进入玩家恋爱线
		npc.gate = int(npc.gate) + 1
		var stage := int(npc.stage)
		# 双轨门槛: 0~2 段比 aff(友情), 3~5 段比 love(恋爱轨 · 同性恒 0 故永不达标)
		var cur := float(npc.aff) if stage <= 2 else float(npc.get("love", 0.0))
		var need := float(ths[stage]) if stage <= 2 else float(lovs[clampi(stage - 3, 0, 2)])
		if stage < ths.size() and cur >= need and int(npc.gate) >= int(tune("gate_months", 24)):
			# 缘分门槛: 只有男性 NPC 可谈恋爱/结道侣 —— 女性止步「相熟」, 不弹心动节点
			if not npc_male(String(key)) and stage >= 2:
				continue
			_fire_node_event(String(key), stage)
			return true
	if int(run.age_m) % 12 == 11:   # 年终 tick(腊月)
		var dao := _dao_key()
		if dao != "" and not bool(run.npcs[dao].sealed):
			var hidden := float(run.npcs[dao].get("hidden", 0.0))
			if hidden >= float(tune("seal_hidden_need", 10000)):
				var p := float(tune("seal_base", 0.15)) + float(tune("seal_year_step", 0.05)) * float(_wall_this_year()) + float(tune("seal_hidden_step", 0.02)) * (hidden / 1000.0)
				if deterministic or rng.randf() < p:
					_fire_interrupt("灵魂烙印", "【%s】情深许 %.0f —— Ta 是你此生最深的牵系。是否烙下魂魄印记, 约一来世?" % [npc_name(dao), hidden], [
						{"t": "烙下印记", "need": "道侣位 · 情深许 ≥10000", "result": "每世唯一契约 · 来世认出三档 · 羁绊计入道韵"},
						{"t": "来世再说", "need": "无", "result": "不罚不锁 · 次年腊月再检定"},
					], "seal", {"key": dao})
					return true
	return false

## 修罗场(§4.2): 已结道侣后与第三人约会(心动级) → 当月检定 55%+性格修正(D+A 两枚)+现任段位 +5;
## 通过=坦白(双方 −30~+20)/低调(零数值, 12 月内再引爆 +10%); 失败=喜剧善后(茶摊议论/话本传唱), 永不罚数值。
func _luochang_check(third_key: String) -> void:
	var dao := _dao_key()
	if dao == "" or third_key == dao:
		return
	var third: Dictionary = run.npcs[third_key]
	var tbl: Dictionary = tune("luochang_tag_fix", {})
	var persona: Dictionary = npc_arch(third_key).get("persona", run.npcs[third_key].get("persona", {}))
	var fix := 0.0
	for k in [String(persona.get("dongxin", "")), String(persona.get("biaoda", ""))]:
		fix += float(tbl.get(k, 0.0))
	var p := float(tune("luochang_base", 0.55)) + fix + float(tune("luochang_partner_bonus", 5)) / 100.0
	if bool(third.get("luochang_lowkey", false)):
		p += float(tune("luochang_recur", 0.10))   # 低调维持: 同一对象 12 月内再引爆概率 +10%
	if not deterministic and rng.randf() >= p:
		_queue_wall_event("xiuluo")   # 曝光演出 → 吃瓜帖(延迟 1 月, 全员化名)
		_fire_interrupt("修罗场 · 曝光", "茶摊话本连夜更新, 坊市都在传你与【%s】的段子 —— 【%s】就站在你身后。如何善后?(喜剧演出, 不罚任何数值)" % [npc_name(third_key), npc_name(dao)], [
			{"t": "坦白从宽", "need": "满城风雨里把话说尽", "result": "好感微幅波动 · 零惩罚"},
			{"t": "打马虎眼", "need": "面不改色", "result": "喜剧演出 · 零数值"},
		], "luochang_bad", {"third": third_key, "dao": dao})
		return
	_fire_interrupt("修罗场 · 表态", "你与【%s】的往来瞒不住了 —— 是否向现任道侣【%s】坦白?" % [npc_name(third_key), npc_name(dao)], [
			{"t": "坦白", "need": "当着现任把话说清", "result": "双方好感 −30~+20 · 此线透明不再引爆"},
			{"t": "低调维持", "need": "按下不表", "result": "零数值 · 同一对象 12 月内再引爆率 +10%"},
		], "luochang_ok", {"third": third_key, "dao": dao})

## 解契(§1.6 简化口径): 道侣位释放, 对方好感锁定相恋段(≥800); 解契不解印, 每世可再结
func dao_cancel(key: String) -> void:
	if _blocked("解契"):
		return
	if _recover_guard("解契"):
		return
	if not run.npcs.has(key) or not bool(run.npcs[key].get("dao_lu", false)):
		return
	var npc: Dictionary = run.npcs[key]
	npc.dao_lu = false
	npc.stage = 4
	npc.love = maxf(float(npc.get("love", 0.0)), float(tune("love_thresholds", [200, 500, 1000])[1]))   # 情分收在相恋位(旧档语义: aff 顶回 800)
	npc.gate = 0
	_log("◇ 与【%s】解契 —— 道侣位已释放, 情分锁在相恋段; 魂印若有, 不随契解(§1.6)" % npc_name(key))
	_queue_wall_event("jieqi", {"npc": npc_name(key)})   # 闲话壁: 解契唏嘘帖(延迟 1 月)
	changed.emit()

# ---------------------------------------------------------------- 游历(游历系统: 行动方案第 7 格 —— 名录的主动泵, 全程静默零弹窗)

const TRAVEL_MAPS := {
	"baimenzong": {"name": "百味宗", "unlock": 0, "ids": ["baimenzong"], "scene": "灶房帮工与山门香客", "flora": ["chunjiu", "qingfengsun", "zixiaqie", "yunmujun", "huiyuancao"]},
	"qingxicun": {"name": "清溪村", "unlock": 0, "ids": ["fangshi", "shanshen", "wenmai"], "scene": "山货集与春社", "flora": ["linglushu", "xueliqing", "qiudao", "chiyanjiao", "ningshencao"]},
	"qingwucheng": {"name": "青梧城", "unlock": 1, "ids": ["baimenzong", "tongming", "jianpai", "yoududao", "shanshen", "huizu", "wenmai", "fangshi"], "scene": "夜市与坊市四宝", "flora": ["huoronggua", "jinlvmai", "bingxincai", "xisuiteng", "yanxinguo", "yanghunteng"]},
	"yunmengze": {"name": "云梦泽", "unlock": 2, "ids": ["huizu", "fangshi"], "scene": "水上集市与鲜货船", "flora": ["bingxincai", "longwenyu", "yinshadou", "xisuiteng", "mengdielan"]},
	"buzhou": {"name": "不周山脊", "unlock": 4, "ids": ["shanshen", "jianpai", "tongming"], "scene": "朝圣路与云海", "flora": ["fengqili", "chixueshen", "yujingxuelian", "jiuzhuan", "zhaoguhua"]},
}

## 地图解锁境界 = unlock 阶数 ×2(大境界序号, 1起: 炼气1阶…渡劫8阶) → 境界索引(0起)。
## 0 阶(百味宗/清溪村)恒为开局可去; 1→筑基(idx1) 2→元婴(idx3) 4→渡劫(idx7)。
func map_unlock_realm(id: String) -> int:
	return maxi(0, int(TRAVEL_MAPS.get(id, {}).get("unlock", 0)) * 2 - 1)

func set_travel_dest(id: String) -> void:
	if is_ended():
		return
	if id != "auto" and (not TRAVEL_MAPS.has(id) or int(run.realm) < map_unlock_realm(id)):
		_log("游历去向【%s】尚未开放 —— 地图随境界解锁(§8.2)" % String(TRAVEL_MAPS.get(id, {}).get("name", id)))
		return
	run.travel_dest = id
	_log("◇ 游历去向: %s" % ("自动轮换" if id == "auto" else String(TRAVEL_MAPS[id].name)))
	changed.emit()

## 自动轮换 = 已解锁地图逐月轮转(§2)
func _travel_dest() -> String:
	var d := String(run.get("travel_dest", "auto"))
	if d != "auto" and TRAVEL_MAPS.has(d):
		return d
	var unlocked: Array = []
	for k in TRAVEL_MAPS:
		if int(run.realm) >= map_unlock_realm(String(k)):
			unlocked.append(String(k))
	return "baimenzong" if unlocked.is_empty() else String(unlocked[int(run.age_m) % unlocked.size()])

## 寻道采获: 按当月游历去向(auto 亦解析到轮换中的实地)从该地风物池采得一株植物入库,
## 兼拾获灵石(数额随地图 unlock 位阶水涨船高)。返回可直接拼进月报的收获串。
func _seek_forage() -> String:
	var info: Dictionary = TRAVEL_MAPS.get(_travel_dest(), {})
	var parts: Array = []
	var flora: Array = info.get("flora", [])
	if not flora.is_empty():
		var sid := String(flora[rng.randi() % flora.size()])
		var s := DataManager.seed(sid)
		if not s.is_empty():
			_inv_add(sid, String(s.grade), 1)
			parts.append("采得【%s】(%s品)" % [String(s.name), String(s.grade)])
	var stones := rng.randi_range(int(econ("seek_stones_lo", 5)), int(econ("seek_stones_hi", 15))) * (int(info.get("unlock", 0)) + 1)
	farm().stones = int(farm().stones) + stones
	parts.append("拾获灵石 %d" % stones)
	return " · " + " · ".join(parts)

## 遇妖(秘境检定的「其间」档): §5.4 检定式战斗 —— 有效战力 = 武力 × 扰动 U[0.7,1.3],
## 妖力 = 境界基数 × yaoguai.power × 扰动 U[0.85,1.15], 两数归一到基数后直接比大小:
## 满状态基准约五五开(妖池均值 power≈1.05), 食补/灵根/气运拉胜率, 低气血/心魔压胜率。
## 打赢: 灵石(econ yaoguai_stones 档) + 妖丹×1(灵植同款计数位, 可卖可赠);
## 打输: 轻一档 —— 只走 _wound 气血−30, 不弹框(善后弹框专属妖潮档, §5.4 无战败红线)。
func _yaoguai_encounter(scost: int) -> void:
	var pool: Array = DataManager.yaoguai
	if pool.is_empty():
		_report("秘境一行, 无功而返(气血−%d)" % scost)
		return
	var total := 0
	for e in pool:
		total += int(e.get("weight", 1))
	var pick := rng.randi_range(1, maxi(1, total))
	var g: Dictionary = pool[0]
	for e in pool:
		pick -= int(e.get("weight", 1))
		if pick <= 0:
			g = e
			break
	var adv := wu_li() / maxf(1.0, _realm_base_now()) * rng.randf_range(0.7, 1.3)
	var yao := float(g.get("power", 1.0)) * rng.randf_range(0.85, 1.15)
	var nm := String(g.get("name", "不知名的妖"))
	var scene := String(g.get("scene", ""))
	if adv >= yao:
		var stones := rng.randi_range(int(econ("yaoguai_stones_lo", 15)), int(econ("yaoguai_stones_hi", 40)))
		farm().stones = int(farm().stones) + stones
		farm().yaodan = int(farm().get("yaodan", 0)) + 1
		_report("游遇【%s】(%s) —— 一掌伏之, 拾灵石 %d · 得妖丹一枚(气血−%d)" % [nm, scene, stones, scost])
	else:
		_wound()
		_report("游遇【%s】(%s) —— 力怯退避, 带伤而回(气血−%d), 那妖竟也未追" % [nm, scene, scost + int(econ("wound_qi_loss", 30))])

func _rand_count() -> int:
	var n := 0
	for key in run.npcs:
		if String(key).begins_with("rand_"):
			n += 1
	return n

## 游历月度判定(§3): 年节 ×2 → 三分支: 首遇 15%(静默入册, 软上限 20 降级面熟路人) / 偶遇 30%(短交谈或好友介绍) / 风物其余
func _travel_tick() -> void:
	if is_ended():
		return
	_ensure_run()
	var info: Dictionary = TRAVEL_MAPS[_travel_dest()]
	var month := (int(run.age_m) % 12) + 1
	var mult := 1.0
	for m in tune("travel_festivals", [1, 2, 3, 9, 12]):
		if int(m) == month:   # JSON 数字解析为 float, 显式 int 比较
			mult = float(tune("travel_festival_mult", 2.0))
	var roll := rng.randf()
	var fm := float(tune("travel_first_meet", 0.15)) * mult
	if roll < fm:
		if _rand_count() >= int(tune("travel_name_cap", 20)):
			_report("游历%s: 遇见几位面熟的路人, 点头而过" % String(info.name))
			return
		var pool_key := _pick_pool_npc()
		var npc: Dictionary = {}
		if pool_key != "":
			npc = run.world_npcs[pool_key]
		else:
			npc = npc_generator.generate(rng, run.npcs, info.ids)   # 池空回退: 当场造人(不入池, 入册即用)
		if npc.is_empty():
			_report("游历%s: 人潮里没遇见新鲜面孔" % String(info.name))
			return
		if pool_key != "":
			_enroll_pool_npc(pool_key)
		else:
			_enroll_npc(npc)
		_report("游历%s: 遇见【%s】(%s) —— %s, 攀谈几句, 入册缘分页(可交谈/赠礼/约会)" % [String(info.name), String(npc.name), String(npc.get("id_name", "")), String(npc.get("moe", ""))])
		return
	if roll < fm + float(tune("travel_encounter", 0.30)) * mult:
		var met_rands: Array = []
		for key in run.npcs:
			if String(key).begins_with("rand_") and bool(run.npcs[key].get("met", false)):
				met_rands.append(String(key))
		if met_rands.is_empty():
			_report("游历%s: %s(此间尚无熟人, 遇见的多是初面)" % [String(info.name), String(info.scene)])
			return
		var k := String(met_rands[rng.randi_range(0, met_rands.size() - 1)])
		var npc: Dictionary = run.npcs[k]
		if int(npc.get("talk_cd", 0)) <= 0:
			npc.talk_cd = int(tune("talk_cd", 3))
			_bump_aff(k, 10.0)
			_report("游历%s偶遇【%s】, 短叙几句(好感+10)" % [String(info.name), npc_name(k)])
		else:
			_report("游历%s: 风物正好, 旧友匆匆一面" % String(info.name))
		return
	_report("游历%s: %s" % [String(info.name), String(info.scene)])

## 入册(游历/好友介绍共用): 快照合并默认结构; 相遇不加好感(红线); 游历首遇=直接入册不弹框(2026-09-22)
func _enroll_npc(npc: Dictionary) -> void:
	var base := _npc_init()
	base.merge(npc, true)
	base.met = true
	run.npcs[String(base.key)] = base
	_gift_note(String(base.key))
	changed.emit()

## 关系网初见礼: 有故人情面则把初始好感记上并留一行纪要(无则不提, 不打扰默认口径)
func _gift_note(key: String) -> void:
	var rg := _relation_gift(key)
	var gift := float(rg.get("v", 0.0))
	if gift < 1.0 or not run.npcs.has(key):
		return
	var npc: Dictionary = run.npcs[key]
	npc.aff = maxf(float(npc.get("aff", 0.0)), gift)
	_log("◇ 领【%s】的情面 —— 与【%s】初见便带了 %.0f 好感" % [String(rg.get("from", "")), npc_name(key), gift])

## 好友介绍弹框(2026-09-13 拍板: 通道关闭, 随机新 NPC 唯一来源=游历首遇)—— 保留函数体备查, P1 若恢复「偶遇引荐」可复用
func _introduce_friend(introducer: String) -> bool:
	if _rand_count() >= int(tune("travel_name_cap", 20)):
		return false
	var npc := npc_generator.generate(rng, run.npcs)
	if npc.is_empty():
		return false
	world_sim.note_friend()
	var favor := rng.randf() < float(tune("friend_favor_chance", 0.10))
	_fire_interrupt("引荐 · %s" % String(npc.get("scene", "")), "【%s】拉着一位新面孔过来 —— 【%s】(%s), %s。是否攀谈?(相遇不加好感; 入册后可交谈/赠礼/约会)" % [npc_name(introducer), String(npc.name), String(npc.get("id_name", "")), String(npc.get("moe", ""))], [
		{"t": "攀谈几句(入册)", "need": "无", "result": "入册缘分页%s" % (" · 与介绍人相熟, 携初始好感 20" if favor else " · 好感自 0 起")},
		{"t": "点头而过", "need": "无", "result": "不入册 · 名录不出此人"},
	], "friend_meet", {"npc": npc, "favor": favor, "introducer": introducer})
	return true

## 人物侧写文案池(纪事人均覆盖): 此前 NPC 进纪事只有 10%/月的茶摊传言(至多提两人)与玩家互动线,
## 未被互动也未卷入事件者一世零纪事 —— 2026-09-21 拍板: 每月为一位坊间人物写一行小景。
## 候选两档加权: 主角团(入册已识+未遇固定)为主, 世界池未识者为辅(名录灰显关系区可见, 纪事人人可看)。
## 只入月报不上壁(不占闲话壁每月一帖; 上壁仍须有事件出处)。
const SIDE_SCENES := {
	"baimenzong": ["在灶房试新方, 半条街都闻着香", "挑了食盒去灵田, 说是给菜们听听人话", "把昨夜的剩饭翻成了新点心, 一点没浪费", "对着灶火发呆, 说这把火今天有点闹脾气", "给巡夜的同门留了碗热汤在灶边"],
	"tongming": ["在论道会上把一件旧事讲了三遍, 回回都有人听", "替仙门抄公文, 抄到笔头开叉", "清晨在演武场站桩, 站得比石狮子还稳", "被师弟缠着讲当年, 讲到一半忘了词", "下山采买, 顺手捎了半条街的零碎"],
	"jianpai": ["在剑炉前蹲了一日, 出来时头发都是直的", "劈柴劈得比谁都齐, 说是练腕", "背着剑走过长街, 影子都比人横", "替人押了一趟货, 货没事人瘦了一圈", "把赊的串钱还了, 摊主愣了半天"],
	"yoududao": ["背着旧剑从山道走过, 谁也没搭话", "在城根下晒太阳, 剑横在膝上打盹", "替人追回一只惊跑的驴, 转身就没影", "半夜坐在坊市墙头, 被巡山司记了一笔", "买了两个馒头, 转手给了一个要饭的"],
	"shanshen": ["在山神庙扫了一整日落叶, 谁来都递碗热茶", "给庙前那盏灯添了油, 说是照晚归的人", "坐在庙檐下听雨, 说山神爱听这个", "把香客落下的物件收进木匣, 等人来认", "修庙门的活计做三天歇一天, 一点不急"],
	"huizu": ["在货摊支起批南边来的稀罕货, 围了里三层", "笑吟吟给老主顾塞了一包桂花糖", "跟客人讨价还价, 赢了还倒贴一串铜铃", "把摊子挪到城门口, 说要迎八方客", "打烊前给街角的小乞儿留了个糖人"],
	"wenmai": ["茶摊开了新书, 满座没人肯走", "把昨日的坊市闲话编进了新段子", "在照壁前抄帖, 抄一句笑一声", "给孩子们讲前朝旧事, 讲到一半自己先笑场", "说书说到嗓子哑, 含着枚话梅接着说"],
	"fangshi": ["在坊市替人看了一上午铺子, 分文不取", "把货摊擦得能照出人影, 就是没人问价", "蹲在摊后扒拉午饭, 扒拉得比卖货还认真", "替街坊写了半日书信, 字比人稳重", "收摊时顺手把邻摊的幌子扶正了"],
}
const SIDE_SCENES_KID := ["在巷口追鸡, 摔了一身泥还在笑", "蹲在灶房门口偷看, 被塞了块刚出锅的点心", "攒了一兜石子, 说要拿去换糖", "跟着大人逛坊市, 回来学了一嘴新鲜词"]

func _side_scene_tick() -> void:
	if is_ended() or run.npcs.is_empty():
		return
	var keys: Array = []
	for k in run.npcs:
		if bool(run.npcs[k].get("met", false)) and not bool(run.npcs[k].get("dead", false)):
			keys.append(String(k))
	for n in DataManager.npcs:
		var fk := String(n.key)
		if not run.npcs.has(fk) and not (run.has("world_npcs") and (run.world_npcs as Dictionary).has(fk)):
			keys.append(fk)   # 未遇固定者也在坊间过日子 —— 纪事口径「世间事不因未见而不发生」
	var pool: Array = []
	for k in run.get("world_npcs", {}):
		if bool(((run.world_npcs as Dictionary)[k] as Dictionary).get("dead", false)):
			continue   # 故者不入坊间一景
		pool.append(String(k))   # 世界池未识者: 名录关系区灰显可见、纪事人人可看, 坊间也得有他们的日子
	if keys.is_empty() and pool.is_empty():
		return
	# 两档加权: 主角团(入册+未遇固定)为主, 池内陌生人为辅 —— 不让几十张生脸稀释熟人的戏份
	var k := ""
	if pool.is_empty() or (not keys.is_empty() and rng.randf() < float(tune("side_scene_main_bias", 0.7))):
		k = String(keys[rng.randi_range(0, keys.size() - 1)])
	else:
		k = String(pool[rng.randi_range(0, pool.size() - 1)])
	var line := ""
	if _npc_is_minor(k):
		line = String(SIDE_SCENES_KID[rng.randi_range(0, SIDE_SCENES_KID.size() - 1)])
	else:
		var e := _npc_entry(k)
		var idt := String(e.get("identity", npc_arch(k).get("identity", "fangshi")))
		var scenes: Array = SIDE_SCENES.get(idt, SIDE_SCENES["fangshi"])
		line = String(scenes[rng.randi_range(0, scenes.size() - 1)])
	_report("坊市一景: 【%s】%s" % [npc_name(k), line])


## WorldSim 关系网月度 tick(§4.3): 成交好/拌嘴 → 月报一行(≤40 字为宜) + 延迟上壁。
## v2.4 起传言优先命中 relations.json 的预设关系(GDD §4.3「NPC 关系网」口径): 有出处才有人味,
## 命中不了(随机 NPC 或未写关系的两人)再退回纯随机 —— 月报一行 + 延迟上壁，节奏与旧口径一致。
func _worldsim_tick() -> void:
	if is_ended() or run.npcs.is_empty():
		return
	_friendship_drift()    # 友情值(亲疏边)按月漂移: 先漂后恋, 新恋情挑的是当月的温度
	_npc_romance_tick()    # NPC 恋爱六段推进/成婚/争风(全员含池内)
	_npc_family_tick()     # 已婚受孕、怀胎临盆(遗传造娃)
	_npc_growth_tick()     # 满 npc_adult_years 岁成年礼
	_npc_mortality_tick()  # 气血月回 + 凡人寿尽坐化(固定档案不受此限)
	var met: Array = []
	for k in run.npcs:
		if bool(run.npcs[k].get("met", false)):
			met.append(String(k))
	if met.size() < 2:
		return
	_side_scene_tick()   # 每月一位入册者的坊市侧写: 纪事不再只落在被互动/卷入事件者头上
	if rng.randf() < float(tune("worldsim_pair_rate", 0.06)):
		var pk := _gossip_pair(met, false)
		if pk.is_empty():
			return
		world_sim.note_pair()
		_report(_gossip_line(String(pk[0]), String(pk[1]), false))
		return
	if rng.randf() < float(tune("worldsim_rival_rate", 0.04)):
		var rk := _gossip_pair(met, true)
		if rk.is_empty():
			return
		world_sim.note_rival()
		_report(_gossip_line(String(rk[0]), String(rk[1]), true))
		return
	# 好友介绍入世通道已关闭(2026-09-13 拍板: 随机新 NPC 唯一来源=出门游历首遇)

## 挑一对八卦主角: 亲近向挑 val≥rel_close_min 的预设边, 拌嘴向挑 val<0 的边; 多数时候偏向有关系的那对,
## 其余按旧口径随机抽两个人。返回 [a, b] 或空数组(抽到同一个人)。
func _gossip_pair(met: Array, negative: bool) -> Array:
	var hit: Array = []
	for e in DataManager.relations:
		var a := String(e.get("a", ""))
		var b := String(e.get("b", ""))
		if not met.has(a) or not met.has(b):
			continue
		var v := float(e.get("val", 0.0))
		if (negative and v < 0.0) or (not negative and v >= float(tune("rel_close_min", 35.0))):
			hit.append([a, b])
	for e in run.get("world_rels", []):   # 动态边: 至少一端入册即可成话 —— 八卦能提到没见过的脸
		var a2 := String(e.get("a", ""))
		var b2 := String(e.get("b", ""))
		if not (met.has(a2) or met.has(b2)):
			continue
		var v2 := float(e.get("val", 0.0))
		if (negative and v2 < 0.0) or (not negative and v2 >= float(tune("rel_close_min", 35.0))):
			hit.append([a2, b2])
	if not hit.is_empty() and rng.randf() < float(tune("worldsim_relation_bias", 0.8)):
		return hit[rng.randi_range(0, hit.size() - 1)]
	var a2 := String(met[rng.randi_range(0, met.size() - 1)])
	var b2 := String(met[rng.randi_range(0, met.size() - 1)])
	return [a2, b2] if a2 != b2 else []

## 传言一行: 有预设关系就照它的标签与短注说人话, 并排一条延迟上壁的帖; 没有就用旧的无出处模板(只上月报)。
func _gossip_line(a: String, b: String, negative: bool) -> String:
	var rel := relation_between(a, b)
	if not rel.is_empty():
		var tag := String(rel.get("tag", "旧识"))
		# 亲族方向词并提时归对词(「A与B是「父亲」」不通 → 「A与B是「父子」」): 按孩子性别定子/女
		if tag == "父亲" or tag == "母亲":
			tag = _kin_pair(b, a)   # b 是 a 的长辈
		elif tag == "儿子" or tag == "女儿":
			tag = _kin_pair(a, b)   # b 是 a 的小辈
		_queue_wall_event("relation_bad" if negative else "relation", {"a": npc_name(a), "b": npc_name(b), "tag": tag})
		if negative:
			return "茶摊闲话: 【%s】与【%s】那点「%s」又发作了 —— %s" % [npc_name(a), npc_name(b), tag, String(rel.get("note", ""))]
		return "茶摊闲话: 【%s】与【%s】是「%s」—— %s" % [npc_name(a), npc_name(b), tag, String(rel.get("note", ""))]
	# 无关系的随机搭对: 只在月报留一行, 不上壁 —— 帖子要说得有出处才有人味, 也不占那每月一帖的名额
	if negative:
		return "茶摊都说: 【%s】与【%s】起了口角, 怕要出话本" % [npc_name(a), npc_name(b)]
	return "坊市传言: 【%s】与【%s】走得近了" % [npc_name(a), npc_name(b)]

## 被动首遇检定(§1.7): 概率 roll(恒定消费, deterministic 不短路) → 命中直接入册(2026-09-22 拍板: 不再弹「是否攀谈」框)。
## 候选为固定六人中未入册者。
func _first_meet_roll() -> void:
	if is_ended():
		return
	if rng.randf() >= float(tune("first_meet_chance", 0.03)) * (1.0 + _trait_fx("event")):
		return
	var candidates: Array = []
	for n in DataManager.npcs:
		var k2 := String(n.key)
		if String(n.get("enrolled", "meet")) == "meet" and not run.npcs.has(k2):
			candidates.append(k2)
	if candidates.is_empty():
		return
	var pick := String(candidates[rng.randi_range(0, candidates.size() - 1)])
	_first_meet(pick, "山道拐角打了个照面, 攀谈几句")
## 好感微幅波动 ±2-10/月(全段, 静默): 恋爱系统 §1.2 表「月报微幅波动」通道
func _aff_drift() -> void:
	var met: Array = []
	for key in run.npcs:
		if bool(run.npcs[key].get("met", false)):
			met.append(String(key))
	if met.is_empty():
		return
	if rng.randf() >= 0.5:
		return
	var k := String(met[rng.randi_range(0, met.size() - 1)])
	var d := float(rng.randi_range(int(tune("aff_drift", [2, 10])[0]), int(tune("aff_drift", [2, 10])[1])))
	_bump_aff(k, d if rng.randf() < 0.6 else -d)

# ---------------------------------------------------------------- 冲关(§5.1, 不占方案位)

## 冲关失手统一代价(小层/大境界同源, 2026-09-12 拍板): 散三成修为 + 心魔 N 月 + 败中悟道+5%(成功清零);
## 返回散去的修为供调用方入日志; 大境界另计折寿与气血(见 _do_breakthrough), 小层不折寿不伤气血。
func _breakout_fail(inner_months: int) -> float:
	run.pity = int(run.get("pity", 0)) + 1
	var lost := float(run.cult) * 0.3
	run.cult = maxf(0.0, float(run.cult) - lost)
	run.inner = maxi(int(run.inner), inner_months)
	return lost

func _do_breakthrough() -> void:
	var pity := int(run.get("pity", 0))
	var p := 1.0 if deterministic else break_chance()
	var had_bonus: bool = float(run.get("break_bonus", 0.0)) > 0.0 or run.get("buffs", {}).has("check_pct")
	var next_name := next_realm_name()
	_log("引动天象, 冲关「%s」—— 成功率 %.0f%%%s…" % [next_name, p * 100.0, ("(败中悟道+%.0f%%)" % (float(tune("pity_step", 0.05)) * pity * 100.0)) if pity > 0 else ""])
	if rng.randf() < p:
		run.pity = 0
		_consume_check_buff()      # 冲关成功才消费: 检定 buff 与照骨羹一次性加成
		run.break_bonus = 0.0
		if is_final_realm():
			_ending("飞升")
			return
		run.cult = 0.0
		run.inner = 0
		run.realm = int(run.realm) + 1
		run.layer = 0
		_log("◆ 雷停云开, 晋升%s! 寿元延至 %d 年, 聚灵更速" % [realm().name, lifespan_cap_years()])
		_queue_wall_event("breakthrough")   # 闲话壁: 渡劫天象围观帖(延迟 1 月)
	else:
		if is_final_realm():
			run.pity = pity + 1
			if rng.randf() < 0.5 - _trait_fx("survive"):
				_ending("渡劫陨落")
			else:
				run.realm = int(run.realm) - 1
				run.layer = int(realm().layers) - 1
				run.cult = 0.0
				run.inner = maxi(int(run.inner), 60)
				_wound()
				if _trait_fx("survive") > 0.0:
					_log("◆ 蝉衣代劫, 碎裂于雷下 —— 天雷只烧去一件旧衣")
				_log("◆ 天雷及体, 道基崩毁 —— 重伤退回%s, 折寿十年, 心魔五年, 气血−%d" % [String(realm().name), int(econ("wound_qi_loss", 30))])
				_advance_years(120)
			return
		_breakout_fail(36)
		var lost := rng.randi_range(12, 24)
		_wound()
		_log("冲关失败: 修为散去三成, 损 %d 月寿元, 心魔三年, 气血−%d%s" % [lost, int(econ("wound_qi_loss", 30)), "(突破率加成仍在, 下次再冲)" if had_bonus else ""])
		_advance_years(lost)

func _advance_years(months: int) -> void:
	for i in range(months):
		run.age_m = int(run.age_m) + 1
		if int(run.inner) > 0:
			run.inner = int(run.inner) - 1
		if int(run.age_m) >= lifespan_cap_years() * 12:
			_ending("寿尽坐化")
			return

# ---------------------------------------------------------------- 结算内部

## 灵根系数预览(与 _start_life 同公式, 三生石转世卡用): 行数 + 铸体叠加
func root_coef_preview(n: int, forge_times: int) -> float:
	return float(ROOT_COUNT_COEF.get(n, ROOT_COUNT_COEF[5])) + FORGE_STEP * forge_times

## 归一化择根输入: 行数合法化(默认五行) + 持有列表去重截断、不足按五行序补齐; 返回 [n, roots]
func _normalize_roots(root_choice: Dictionary) -> Array:
	var n := int(root_choice.get("n", 5))
	if not ROOT_COUNTS.has(n):
		n = 5
	var roots: Array = []
	for e in root_choice.get("els", []):
		var es := String(e)
		if (es in ELEMENTS) and not (es in roots):
			roots.append(es)
		if roots.size() == n:
			break
	for e in ELEMENTS:   # 防御: UI 保证选满, 缺位按五行序补齐
		if roots.size() >= n:
			break
		if not (e in roots):
			roots.append(String(e))
	return [n, roots]

func _start_life(origin: Dictionary, forge_times: int, root_choice := {}, trait_ids := []) -> void:
	pending = {}
	month_notes.clear()
	# 容貌跨世延续: 本函数整换 run, 先把上一世已应用的容貌留底(三生石/转世卡预览的正是它), 新世重新落上
	var carry_look: Dictionary = {}
	var prev_lk: Variant = run.get("look", null)
	if prev_lk is Dictionary and not (prev_lk as Dictionary).is_empty():
		carry_look = (prev_lk as Dictionary).duplicate(true)
	# 灵根三源归一: 出身只定风味/地块, 灵根 = 行数(钱) + 持有五行(免费自择); 铸体照常叠加
	var nr := _normalize_roots(root_choice)
	var n := int(nr[0])
	var roots: Array = nr[1]
	var coef := root_coef_preview(n, forge_times)
	var npcs: Dictionary = {}
	for nd in DataManager.npcs:
		if String(nd.get("enrolled", "meet")) == "start":   # 首遇制: 仅季忘川开局在册
			var npc0 := _npc_init()
			npc0.met = true
			npcs[String(nd.key)] = npc0
	run = {
		"schema": SCHEMA,
		"life": int(meta.get("lives", 0)) + 1,
		"origin": String(origin.name),
		"root": coef,
		"root_count": n,
		"roots": roots,
		"traits": _normalize_traits(trait_ids),
		"tech": 1.0,
		"element": String(roots[0]),
		"age_m": START_AGE_M,
		"realm": 0, "layer": 0, "cult": 0.0,
		"plan": "pure", "focus": "", "follows": [], "pity": 0,
			"inner": 0, "secret": 0, "recover": 0,
			"buffs": {}, "qi": 100, "aptitude": 0.0, "life_bonus": 0, "luck": 0, "break_bonus": 0.0,
			"facilities": {"julingzhen": 0, "lingquan": 0, "cangjingge": 0, "daiketingyuan": 0},
			"wall": {"posts": [], "queue": [], "read": 0, "rotate_cd": 1},		"date_cd": 0, "secret_cd": 0, "check_clock": 0,
		"npcs": npcs,
		"farm": {
			"stones": 100, "millennium": 0, "yaodan": 0, "tonic_cd": 0, "cook": 0,
			"stoves": [{}, {}, {}, {}], "eaten": {}, "dishes": {},
			"plots": _make_plots(1 + (1 if bool(origin.get("bonus_plot", false)) else 0)),
			"inv": {},
		},
		"kpi": {"ticks": 0, "interrupts": 0, "floors": 0},
		"world_npcs": {},
		"world_rels": [],
		"npc_romance": {},
		"ended": false,
	}
	if not carry_look.is_empty():
		run.look = carry_look
	_seed_world()   # 世界 NPC 池: 未识亦在世, 彼此有关系
	_wall_seed_opening()   # 入世时照壁正热闹: 预置旧帖(不入月报)
	_inv_add("chunjiu", "凡", 10)   # 初始家底: 春韭种子 ×10(留种/烹「素炒春韭」皆可用)
	_log("—— 第 %d 世: 宗主在山道上又捡回了一个孩子。出身【%s】, 灵根 ×%.2f(%s), 16 岁测灵入炼气 ——" % [run.life, run.origin, run.root, root_display()])
	if trait_display() != "":
		_log("◆ %s —— 这副骨头, 是拿道韵跟老天爷预支过的。" % trait_display())
	_log("◇ 时间在常流: 选时速档、选方案, 岁月自会走。特殊事件会自己跳出来等你拍板。")
	SaveSystem.save_run(run)
	changed.emit()

func _add_cult(x: float) -> void:
	run.cult = float(run.cult) + x
	var re := realm()
	while int(run.layer) < int(re.layers) - 1 and float(run.cult) >= layer_need():
		# 2026-09-12 拍板: 小层冲关与大境界同率掷骰(break_chance); 失手散三成修为+心魔一年(不折寿不伤气血), 成功败中悟道清零
		var p := 1.0 if deterministic else break_chance()
		if rng.randf() < p:
			run.pity = 0
			run.cult = float(run.cult) - layer_need()
			run.layer = int(run.layer) + 1
			_report("突破小层 → %s" % realm_display())
			_log("　突破! %s" % realm_display())
		else:
			var lost := _breakout_fail(12)
			_report("小层冲关失手(率%.0f%%): 修为散 %s · 心魔一年" % [p * 100.0, _fmt(lost)])
			break

## 静默打断(不弹框)的两条来源:
## 1) kind 在 SILENT_AFF_KINDS —— 好感类: node=缘分节点时光闸(检定+50) focus_mile=心动时分(+10)
##    neglect=故人心思(+30) luochang_*=修罗场坦白(双方 −30~+20);
## 2) 事件档 events.json 自带 "auto": true —— 默认参与(如故纸堆 insight), 见即按首选项结算。
## 二者同样: 不弹框、时钟不暂停, 只在「一世纪事」留果。
const SILENT_AFF_KINDS := ["node", "focus_mile", "neglect", "luochang_ok", "luochang_bad"]

func _fire_interrupt(title: String, text: String, options: Array, kind: String, data: Dictionary) -> void:
	pending = {"title": title, "text": text, "options": options, "kind": kind, "data": data}
	if deterministic or kind in SILENT_AFF_KINDS or bool(data.get("auto", false)):
		# auto=事件档自带「默认参与」: 不弹框、不暂停时钟, 按首选项结算, 只在纪事留果(如故纸堆)
		var keep := speed   # resolve_option 收尾会按 _resume_speed 复位时钟, 静默结算要把时速原样还回去
		resolve_option(0)
		speed = keep
		return
	var kpi: Dictionary = run.kpi
	kpi.interrupts = int(kpi.interrupts) + 1
	if speed > 0:
		_resume_speed = speed
	speed = 0
	_report("⏸ %s: %s" % [title, text.replace("\n", " ")])
	interrupted.emit(pending)

## 选池: "check"=保底打断(id 带 chk_ 前缀); "chance"=机缘打断(level=interrupt 且无前缀); 其余=月报琐碎
func _pick_event(group: String) -> Dictionary:
	var pool: Array = []
	var total := 0
	for e in DataManager.events:
		var is_check := String(e.get("id", "")).begins_with("chk_")
		var ok := false
		match group:
			"check":
				ok = is_check
			"chance":
				ok = (not is_check) and String(e.get("level", "report")) == "interrupt"
			_:
				ok = (not is_check) and String(e.get("level", "report")) == "report"
		if ok:
			pool.append(e)
			total += int(e.get("weight", 1))
	if pool.is_empty() or total <= 0:
		return {}
	var r := rng.randi_range(1, total)
	for e in pool:
		r -= int(e.get("weight", 1))
		if r <= 0:
			return e
	return pool[0]

## 秘境残页购价: 随境界水涨船高 —— 炼气 240 → 筑基 540 → 金丹 960 → 元婴 1500 → 化神 2160 → 渡劫 4860
func relic_cost() -> int:
	var ord := int(realm().ordinal)
	return int(tune("relic_cost_base", 60)) * (ord + 1) * (ord + 1)

## 事件结算: id 命中事件档则用档里的 effect; fallback 非空(选项自带的 opt_effect)则结算选项效果。
func _apply_event_effect(id: String, fallback: Dictionary = {}) -> void:
	var ev := fallback
	if ev.is_empty():
		for e in DataManager.events:
			if String(e.get("id", "")) == id:
				ev = e
				break
	if ev.is_empty():
		return
	var msg := _apply_effect_dict(ev.get("effect", {}), String(ev.get("label", ev.get("text", ""))))
	_report(msg)
	_log("◆ %s" % msg)

## 效果表 → 结果行文案(事件档 effect 与选项 opt_effect 共用一层)。
## 键: cult_pct_layer=该层占比修为; cult_pct=当前修为乘项; inner_years/inner_months=心魔;
##     qi=气血加减(钳于 0~上限); buff={kind,pct,months,name}=挂一条(正负皆可的)持续 buff/debuff。
func _apply_effect_dict(eff: Dictionary, msg: String) -> String:
	if eff.has("cult_pct_layer"):
		var g := layer_need() * float(eff.cult_pct_layer)
		_add_cult(g)
		msg += "(修为 +%s)" % _fmt(g)
	if eff.has("cult_pct"):
		run.cult = maxf(0.0, float(run.cult) * (1.0 + float(eff.cult_pct)))
		msg += "(修为%.0f%%)" % (float(eff.cult_pct) * 100.0)
	if eff.has("inner_years"):
		run.inner = maxi(int(run.inner), int(eff.inner_years) * 12)
		msg += "(心魔 %d 年)" % int(eff.inner_years)
	if eff.has("inner_months"):
		run.inner = maxi(int(run.inner), int(eff.inner_months))
		msg += "(心魔 %d 月)" % int(eff.inner_months)
	if eff.has("qi"):
		var dq := int(eff.qi)
		run.qi = clampi(_qi() + dq, 0, qi_max())
		msg += "(气血 %+d, 现 %d/%d)" % [dq, _qi(), qi_max()]
	if eff.has("buff"):
		var b: Dictionary = eff.buff
		var kind := String(b.get("kind", ""))
		var pct := float(b.get("pct", 0.0))
		var months := int(b.get("months", 1))
		var nm := String(b.get("name", ""))
		_buff_apply(kind, pct, months, nm)
		msg += "(%s %+.0f%% · %d 月)" % [nm if nm != "" else kind, pct * 100.0, months]
	return msg

func _ending(kind: String) -> void:
	if is_ended():
		return
	run.ended = true
	run.end_kind = kind
	speed = 0
	pending = {}
	var ord := int(realm().ordinal)
	var base := 0.0
	for r in range(1, ord + 1):
		base += 1.4 * r * r        # §11 道韵 = Σ(境界²×1.4)
	var bonds := sealed_count()
	base += int(run.secret) * 5.0 + float(bonds) * 50.0   # +羁绊×50(§11)
	var dao := int(base * float(ENDING_MULT.get(kind, 1.0)))
	meta.dao = int(meta.get("dao", 0)) + dao
	meta.lives = int(meta.get("lives", 0)) + 1
	if ord > int(meta.get("best_ord", 0)):
		meta.best_ord = ord
		meta.best_name = String(realm().name)
	var endings: Dictionary = meta.get("endings", {})
	endings[kind] = int(endings.get(kind, 0)) + 1
	meta.endings = endings
	SaveSystem.save_meta(meta)
	SaveSystem.save_run(run)
	var k := kpi_summary()
	var summary := {
		"kind": kind, "dao": dao, "total_dao": int(meta.dao), "lives": int(meta.lives),
		"years": (int(run.age_m) - START_AGE_M) / 12, "realm": String(realm().name),
		"origin": String(run.origin), "decisions": int(k.decisions), "bonds": bonds,
	}
	_log("")
	_log("═══ 第 %d 世落幕:【%s】═══" % [run.life, kind])
	_log("享年 %d 岁 · 止步%s · 印记羁绊 %d · 特殊事件 %d 次" % [summary.years, summary.realm, bonds, int(k.interrupts)])
	_log("结算道韵 +%d(×%.1f), 累计 %d 道韵" % [dao, float(ENDING_MULT.get(kind, 1.0)), int(meta.dao)])
	_log("魂魄印记、三生石与来世重逢(P2)—— 灰盒留白, 情感承诺已记账。")
	ended.emit(summary)
	changed.emit()

func _blocked(what: String) -> bool:
	if is_ended():
		_log("此世已了结(%s), 请转世再来" % String(run.get("end_kind", "落幕")))
		changed.emit()
		return true
	return false

## 闭关将养剩余月数(秘境善后选「退养」起算 24 月), 未在闭关为 0
func recover_months() -> int:
	return int(run.get("recover", 0))

## 闭关将养守卫: 赠礼/解契等出门缘分动作关内禁办, 出关再提
func _recover_guard(what: String) -> bool:
	if recover_months() > 0:
		_log("◇ 闭关注养中(余 %d 月) —— 「%s」候出关再办" % [recover_months(), what])
		changed.emit()
		return true
	return false

func _report(text: String) -> void:
	month_notes.append(text)

func _log(text: String, day := "") -> void:
	if muted:
		for p in MUTE_PASS:
			if text.begins_with(p):
				logged.emit(text, day if day != "" else calendar())
				return
		return
	logged.emit(text, day if day != "" else calendar())

static func _fmt(n: float) -> String:
	var a := absf(n)
	if a >= 1e8:
		return "%.1f亿" % (n / 1e8)
	if a >= 1e4:
		return "%.1f万" % (n / 1e4)
	return str(int(n))
