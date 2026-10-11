extends Node
## 交谈台词池冒烟(细案《恋爱系统》§1.2 + chat_texts.json / node_events.json): 数据 schema + 取词优先级
## + 道侣段并池 + 占位符替换 + 门槛事件文案外置。只读系: 不 new_game 不写档 ——
## _chat_line/_node_tpl 为纯取词直测, 随机流先 debug_seed 固定(run 态由 autoload 兜底新世提供)。

var _fails := 0

func _chk(name: String, ok: bool) -> void:
	print(("PASS: " if ok else "FAIL: ") + name)
	if not ok:
		_fails += 1

const VALID_TAGS := ["guayan", "zuidu", "ruanruo", "xinruan", "manre", "zilaishu", "qinkuai", "lansan", "jiaozhen", "zhiqui", "kouyan", "xishui"]
const FIXED_KEYS := ["jianshu", "yaoshi", "shanjun", "moxiu", "shushu", "huzhu"]
const STAGES := ["0", "1", "2", "3", "4", "5"]
const NODE_PH := ["{npc}", "{ming}", "{stage_name}", "{aff}", "{love}", "{moe}", "{scene}"]

func _ready() -> void:
	Game.debug_seed(20261011)
	var ct: Dictionary = DataManager.chat_texts
	# 1) schema: generic 六段全非空 / persona 恰 12 标签全非空 / fixed 六人齐且 0~5+daily 全非空(daily=8)
	var schema_ok := true
	for st in STAGES:
		if ((ct.get("generic", {}) as Dictionary).get(st, []) as Array).is_empty():
			schema_ok = false
	var per: Dictionary = ct.get("persona", {}) as Dictionary
	if per.size() != 12:
		schema_ok = false
	for tag in VALID_TAGS:
		if (per.get(tag, []) as Array).is_empty():
			schema_ok = false
	for k in FIXED_KEYS:
		var fx: Dictionary = (ct.get("fixed", {}) as Dictionary).get(k, {})
		if (fx as Dictionary).is_empty():
			schema_ok = false
			continue
		for st in STAGES:
			if (fx.get(st, []) as Array).is_empty():
				schema_ok = false
		if (fx.get("daily", []) as Array).size() != 8:
			schema_ok = false
	_chk("schema: generic六段/persona十二标签/fixed六人分段+日常8条", schema_ok)
	# 2) 占位符白名单: 全池仅 {npc}/{ming}
	var ph_ok := true
	for lines in _all_line_groups(ct):
		for l in (lines as Array):
			var rest: String = String(l).replace("{npc}", "").replace("{ming}", "")
			if rest.contains("{") or rest.contains("}"):
				ph_ok = false
	_chk("占位符白名单: 仅 {npc}/{ming}", ph_ok)
	# 3) 取词优先级: fixed 段位池 > persona 语气池 > generic 段位池(期望池先做与 _chat_line 同款占位替换)
	var js2: Array = _sub(((ct.get("fixed", {}) as Dictionary).get("jianshu", {}) as Dictionary).get("2", []) as Array, "jianshu")
	var hit_fixed := true
	for i in range(30):
		if not js2.has(Game._chat_line("jianshu", 2, {"biaoda": "zuidu", "dairen": "xinruan", "xingshi": "qinkuai", "dongxin": "kouyan"})):
			hit_fixed = false
	_chk("取词优先级: 固定 NPC 命中本人段位池(不落 persona/generic)", hit_fixed)
	var zuidu: Array = _sub(per.get("zuidu", []) as Array, "rand_0001")
	var hit_persona := true
	for i in range(30):
		if not zuidu.has(Game._chat_line("rand_0001", 2, {"biaoda": "zuidu", "dairen": "manre", "xingshi": "lansan", "dongxin": "zhiqui"})):
			hit_persona = false
	_chk("取词优先级: 随机 NPC 命中 biaoda 语气池", hit_persona)
	var gen3: Array = _sub((ct.get("generic", {}) as Dictionary).get("3", []) as Array, "rand_0001")
	var hit_generic := true
	for i in range(30):
		if not gen3.has(Game._chat_line("rand_0001", 3, {})):
			hit_generic = false
	_chk("取词优先级: 无 persona 命中落通用段位池", hit_generic)
	# 4) 道侣段(5)取词 = 段位池 ∪ daily 专属日常, 且抽取不改写数据池({ming} 替换由 5) 的无花括号断言兜住)
	var js5: Dictionary = (ct.get("fixed", {}) as Dictionary).get("jianshu", {}) as Dictionary
	var merged: Array = _sub(js5.get("5", []) as Array, "jianshu") + _sub(js5.get("daily", []) as Array, "jianshu")
	var merge_ok := true
	for i in range(120):
		if not merged.has(Game._chat_line("jianshu", 5, {})):
			merge_ok = false
	_chk("道侣段并池: 5段∪daily 全命中(120 抽)", merge_ok)
	var pool_intact: bool = (js5.get("5", []) as Array).size() == 4 and (js5.get("daily", []) as Array).size() == 8
	_chk("数据池不可变: 并池抽取后 5 段仍 4 条/daily 仍 8 条", pool_intact)
	# 5) 占位替换: 六固定 NPC × 六段位多轮抽样 —— 非空且无残留花括号({npc}/{ming} 替净; 纯旁白句不带名属正常)
	var replace_ok := true
	for k in FIXED_KEYS:
		for st in range(6):
			for i in range(12):
				var line := Game._chat_line(k, st, {})
				if line == "" or line.contains("{"):
					replace_ok = false
	_chk("占位替换: 六人×六段多轮抽样非空且替净", replace_ok)
	# 6) 门槛事件文案外置(node_events.json): 三块齐 / opts=2 / 占位符白名单
	var ne: Dictionary = DataManager.node_events
	var ne_ok := true
	for blk in ["node", "dao_ask", "focus_mile"]:
		var b: Dictionary = ne.get(blk, {}) as Dictionary
		if String(b.get("title", "")) == "" or String(b.get("body", "")) == "" or (b.get("opts", []) as Array).size() != 2:
			ne_ok = false
		for t in [String(b.get("title", "")), String(b.get("body", ""))]:
			var rest: String = String(t)
			for ph in NODE_PH:
				rest = rest.replace(ph, "")
			if rest.contains("{"):
				ne_ok = false
	_chk("node_events schema: 三块齐/opts=2/占位符白名单", ne_ok)
	# 7) _node_fmt/_node_tpl 直测: 模板格式化干净(moe 替入选项、body 不残留花括号) + 内嵌兜底可用
	var moe := "记不住脸"
	var tpl: Array = Game._node_tpl(ne.get("node", {}) as Dictionary, {}, "rand_0002", 1, moe)
	var fmt_ok: bool = String(tpl[0]).contains("缘分节点") and not String(tpl[1]).contains("{") \
		and String((tpl[2] as Array)[0].t).contains(moe) and not String((tpl[2] as Array)[0].t).contains("{")
	var tpl2: Array = Game._node_tpl({}, {"title": "兜底标题", "body": "兜底正文", "opts": [{"t": "甲", "need": "n", "result": "r"}]}, "rand_0002", 1, "")
	_chk("_node_tpl: 格式化干净 + 内嵌兜底可用", ne_ok and fmt_ok and String(tpl2[0]) == "兜底标题" and (tpl2[2] as Array).size() == 1)

	print("CHAT_TEXTS_SMOKE %s" % ("PASS" if _fails == 0 else "FAIL(%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)

func _all_line_groups(ct: Dictionary) -> Array:
	var out: Array = []
	var gen: Dictionary = ct.get("generic", {}) as Dictionary
	for st in gen:
		out.append(gen.get(st, []))
	var per: Dictionary = ct.get("persona", {}) as Dictionary
	for tag in per:
		out.append(per.get(tag, []))
	var fx_all: Dictionary = ct.get("fixed", {}) as Dictionary
	for k in fx_all:
		var fx: Dictionary = fx_all.get(k, {}) as Dictionary
		for st in fx:
			out.append(fx.get(st, []))
	return out

## 与 Game._chat_line 同款占位替换 —— 期望池先替换再比对(池内存的是带占位符的原文)
func _sub(lines: Array, key: String) -> Array:
	return (lines as Array).map(func(l): return String(l).replace("{npc}", Game.npc_name(key)).replace("{ming}", Game.player_ming()))
