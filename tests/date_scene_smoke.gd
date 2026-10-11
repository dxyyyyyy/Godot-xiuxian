extends Node
## 十四景约会冒烟(细案《恋爱系统》§4.1 + 《性格系统》§4.3): 数据 schema + 选景门控 + 偏好加权 + 差分文本。
## 只读系: 不 new_game 不写档 —— _pick_date_scene/_date_flavor 为纯函数直测, 随机流先 debug_seed 固定。

var _fails := 0

func _chk(name: String, ok: bool) -> void:
	print(("PASS: " if ok else "FAIL: ") + name)
	if not ok:
		_fails += 1

const VALID_GRPS := ["biaoda", "dairen", "xingshi", "dongxin"]
const VALID_TAGS := ["guayan", "zuidu", "ruanruo", "xinruan", "manre", "zilaishu", "qinkuai", "lansan", "jiaozhen", "zhiqui", "kouyan", "xishui"]

func _ready() -> void:
	Game.debug_seed(20261011)
	var scenes: Array = DataManager.date_scenes
	# 1) schema: 恰 14 景、id 唯一、map 合法、段位门槛、文本池非空、偏好标签合法、占位符白名单({npc}/{ming})
	_chk("十四景数量=14", scenes.size() == 14)
	var ids := {}
	var schema_ok := true
	for s in scenes:
		var d: Dictionary = s
		var id := String(d.get("id", ""))
		if id == "" or ids.has(id):
			schema_ok = false
		ids[id] = true
		var mp := String(d.get("map", ""))
		if mp != "tianjing" and not Game.TRAVEL_MAPS.has(mp):
			schema_ok = false
		var st := int(d.get("stage_min", 0))
		if st < 2 or st > 5:
			schema_ok = false
		if (d.get("lines", []) as Array).is_empty():
			schema_ok = false
		for grp in (d.get("pref", {}) as Dictionary):
			if not VALID_GRPS.has(String(grp)):
				schema_ok = false
			for tag in (d.get("pref", {}).get(grp, []) as Array):
				if not VALID_TAGS.has(String(tag)):
					schema_ok = false
		var all_lines: Array = (d.get("lines", []) as Array).duplicate()
		for l in (d.get("pref_lines", {}) as Dictionary).values():
			all_lines.append(l)
		for l in (d.get("fixed", {}) as Dictionary).values():
			all_lines.append(l)
		for l in all_lines:
			var rest: String = String(l).replace("{npc}", "").replace("{ming}", "")
			if rest.contains("{"):
				schema_ok = false
	_chk("schema: id唯一/map/stage_min/文本池/偏好标签/占位符白名单", schema_ok)
	var map_of := {}
	for s in scenes:
		map_of[String(s.id)] = String(s.map)
	# 偏好四向落位(性格系统 §4.3): 自来熟→灯会夜市/懒散→炊烟台+茶摊/较真→膳经阁夜读/细水长流→雪村柴桥
	var pref_ok := true
	pref_ok = pref_ok and _has_pref(scenes, "denghuiyeshi", "dairen", "zilaishu")
	pref_ok = pref_ok and _has_pref(scenes, "chuiyantai", "xingshi", "lansan") and _has_pref(scenes, "chatanshuoke", "xingshi", "lansan")
	pref_ok = pref_ok and _has_pref(scenes, "shanjinggeyedu", "xingshi", "jiaozhen")
	pref_ok = pref_ok and _has_pref(scenes, "xuecunchaiqiao", "dongxin", "xishui")
	_chk("偏好四向落位(§4.3)", pref_ok)
	# 2) 选景门控(每次 60~400 掷, 随机流已固定 → 结果确定)
	#  2a 炼气月5(春) 心动段: 只落在百味宗/清溪村两图
	var pool0 := _rolls([{"stage": 3, "persona": {}}], 0, 5, false, 60)
	var pool0_total := 0
	for k in pool0:
		pool0_total += int(pool0[k])
	var map_ok := pool0_total == 60
	for k in pool0:
		if not ["baimenzong", "qingxicun"].has(String(map_of.get(String(k), ""))):
			map_ok = false
	_chk("炼气月5 只在百味宗/清溪村两图", map_ok)
	#  2b 灯会夜市仅正月(上元): 正月可抽到, 五月不可
	_chk("正月可抽到灯会夜市", _rolls([{"stage": 3, "persona": {}}], 0, 1, false, 80).has("denghuiyeshi"))
	_chk("五月抽不到灯会夜市", not pool0.has("denghuiyeshi"))
	#  2c 云梦泽金丹(2)解锁: 筑基月7 无雾湖泛舟/流萤苇荡, 金丹月7 有
	var p1 := _rolls([{"stage": 3, "persona": {}}], 1, 7, false, 80)
	var p2 := _rolls([{"stage": 3, "persona": {}}], 2, 7, false, 80)
	_chk("筑基月7 无云梦泽景", not p1.has("wuhufanzhou") and not p1.has("liuyingweidang"))
	_chk("金丹月7 可到雾湖泛舟/流萤苇荡", p2.has("wuhufanzhou") or p2.has("liuyingweidang"))
	#  2d 段位门槛: 心动段腊月无雪村柴桥(相恋门槛), 相恋段有
	var s3 := _rolls([{"stage": 3, "persona": {}}], 0, 12, false, 80)
	var s4 := _rolls([{"stage": 4, "persona": {}}], 0, 12, false, 80)
	_chk("心动段腊月无雪村柴桥", not s3.has("xuecunchaiqiao"))
	_chk("相恋段腊月可到雪村柴桥", s4.has("xuecunchaiqiao"))
	#  2e 坠星谷: 道侣段+年节月才可能, 且低权重(0.15)
	_chk("相恋段无坠星谷", not _rolls([{"stage": 4, "persona": {}}], 4, 1, false, 200).has("zhuixinggu"))
	_chk("道侣段正月可遇坠星谷(低概率)", _rolls([{"stage": 5, "persona": {}}], 4, 1, false, 400).has("zhuixinggu"))
	#  2f 天境镜台: 终章限定(渡劫后)
	_chk("非终章无天境镜台", not _rolls([{"stage": 5, "persona": {}}], 7, 1, false, 400).has("tianjingjingtai"))
	_chk("终章(渡劫)可到天境镜台", _rolls([{"stage": 5, "persona": {}}], 7, 1, true, 400).has("tianjingjingtai"))
	#  2g 兜底: 炼气心动段全年 12 月必有一景可约(炊烟台全时可去)
	var always := true
	for m in range(1, 13):
		if Game._pick_date_scene([{"stage": 3, "persona": {}}], 0, m, false).is_empty():
			always = false
	_chk("全年月月有景可约(兜底炊烟台)", always)
	# 3) 偏好加权: 懒散 NPC 在春月炼气池(春田埂+炊烟台)中, 炊烟台份额应明显过半(2/3)
	var lazy := {"stage": 3, "persona": {"biaoda": "guayan", "dairen": "xinruan", "xingshi": "lansan", "dongxin": "zhiqui"}}
	var pl := _rolls([lazy], 0, 5, false, 300)
	var plain := _rolls([{"stage": 3, "persona": {}}], 0, 5, false, 300)
	_chk("偏好加权: 懒散→炊烟台份额↑(%d vs %d)/300" % [int(pl.get("chuiyantai", 0)), int(plain.get("chuiyantai", 0))], int(pl.get("chuiyantai", 0)) > int(plain.get("chuiyantai", 0)) + 40)
	# 4) 差分文本: 六固定 NPC 各有招牌差分可取、随机 persona 走通用池、占位符替换干净
	var fixed_cov := 0
	for n in DataManager.npcs:
		var key := String(n.key)
		for s in scenes:
			if ((s as Dictionary).get("fixed", {}) as Dictionary).has(key):
				var line := Game._date_flavor(s, key, (n.get("persona", {}) as Dictionary))
				if line != "" and not line.contains("{"):
					fixed_cov += 1
				break
	_chk("六固定 NPC 各有招牌差分且替换干净", fixed_cov == 6)
	var rnd_line := Game._date_flavor(_by_id(scenes, "chuiyantai"), "rand_0001", {"biaoda": "ruanruo", "dairen": "xinruan", "xingshi": "qinkuai", "dongxin": "xishui"})
	_chk("随机 NPC 走通用池且替换干净", rnd_line != "" and not rnd_line.contains("{"))
	print("DATE_SCENE_SMOKE %s" % ("PASS" if _fails == 0 else "FAIL(%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)

func _rolls(cands: Array, realm_idx: int, month: int, final_realm: bool, n: int) -> Dictionary:
	var seen := {}   # id → 命中次数
	for i in range(n):
		var scn := Game._pick_date_scene(cands, realm_idx, month, final_realm)
		if not scn.is_empty():
			var sid := String(scn.id)
			seen[sid] = int(seen.get(sid, 0)) + 1
	return seen

func _by_id(scenes: Array, id: String) -> Dictionary:
	for s in scenes:
		if String(s.id) == id:
			return s
	return {}

func _has_pref(scenes: Array, id: String, grp: String, tag: String) -> bool:
	var pref: Dictionary = _by_id(scenes, id).get("pref", {})
	return (pref.get(grp, []) as Array).has(tag)
