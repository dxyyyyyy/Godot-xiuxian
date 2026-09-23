extends Node
## NPC 家庭冒烟: 恋爱六段→成婚→添丁→遗传→成年 全链路。⚠ 会 new_game() 清档, 跑前备份 user://。

const NG := preload("res://sim/NpcGenerator.gd")
const Portrait := preload("res://scripts/portrait.gd")

var _fails := 0
var _broke_seen := 0   # 全程 logged 里 NPC 破境行数(纪事 200 条滚动上限会挤掉早年线, 故计数而非查窗)
var _preg_seen := 0    # 喜脉(受孕)行数
var _first_preg_m := -1
var _first_birth_m := -1
var _death_seen := 0   # 讣闻(坐化)行数


func _chk(name: String, ok: bool) -> void:
	print(("PASS: " if ok else "FAIL: ") + name)
	if not ok:
		_fails += 1


func _on_logged(t: String, _d: String) -> void:
	if t.contains("破境「"):
		_broke_seen += 1
	if t.contains("喜脉"):
		_preg_seen += 1
		if _first_preg_m < 0:
			_first_preg_m = int(Game.run.age_m)
	if t.contains("◆ 添丁") and _first_birth_m < 0:
		_first_birth_m = int(Game.run.age_m)
	if t.contains("讣闻"):
		_death_seen += 1


func _ready() -> void:
	Game.new_game()
	Game.deterministic = true   # 冒烟免弹框: 打断类事件短路
	Game.logged.connect(_on_logged)
	for _m in 400:
		Game.tick_month()
		while not Game.pending.is_empty():
			Game.resolve_option(0)
		if Game.is_ended():
			break
	var rom: Dictionary = Game.run.get("npc_romance", {})
	_chk("出现恋爱边", not rom.is_empty())
	var married := 0
	var max_stage := 0
	for pk in rom:
		var r: Dictionary = rom[pk]
		max_stage = maxi(max_stage, int(r.get("stage", 0)))
		if bool(r.get("married", false)):
			married += 1
	_chk("恋爱按段推进(最高段≥2)", max_stage >= 2)
	_chk("有人成婚", married > 0)
	# spouse 互指一致
	var spouse_ok := true
	for pk in rom:
		var r: Dictionary = rom[pk]
		if not bool(r.get("married", false)):
			continue
		var ps: PackedStringArray = String(pk).split("|")
		var ea: Dictionary = Game._npc_entry(String(ps[0]))
		var eb: Dictionary = Game._npc_entry(String(ps[1]))
		if String(ea.get("spouse", "")) != String(ps[1]) or String(eb.get("spouse", "")) != String(ps[0]):
			print("  MISMATCH pk=", pk, " ea_spouse=", String(ea.get("spouse", "<none>")), " eb_spouse=", String(eb.get("spouse", "<none>")), " ea_empty=", ea.is_empty(), " eb_empty=", eb.is_empty())
			spouse_ok = false
	_chk("spouse 双向一致", spouse_ok)
	# 孩子: parents/children 互指 + 槽位在子女性别目录内
	var kids := 0
	var kid_ok := true
	var all: Dictionary = Game.run.npcs.duplicate()
	all.merge(Game.run.world_npcs, true)
	for k in all:
		var e: Dictionary = all[k]
		if not e.has("parents"):
			continue
		kids += 1
		var ps2: Array = e.get("parents", [])
		for p in ps2:
			if not (Game._npc_entry(String(p)) as Dictionary).get("children", []).has(String(k)):
				kid_ok = false
			# 方向称谓: 娃看长辈=父亲/母亲, 长辈看娃=儿子/女儿
			var want_p := "父亲" if Game.npc_male(String(p)) else "母亲"
			var want_c := "儿子" if Game.npc_male(String(k)) else "女儿"
			if String(Game.relation_between(String(k), String(p)).get("tag", "")) != want_p:
				print("  TAG BAD ", k, "→", p, " = ", Game.relation_between(String(k), String(p)).get("tag", ""))
				kid_ok = false
			if String(Game.relation_between(String(p), String(k)).get("tag", "")) != want_c:
				print("  TAG BAD ", p, "→", k, " = ", Game.relation_between(String(p), String(k)).get("tag", ""))
				kid_ok = false
		var male := Game.npc_male(String(k))
		for slot in NG.SLOTS:
			if NG.entry(male, String(slot), String((e.get("appearance", {}) as Dictionary).get(slot, ""))).is_empty():
				kid_ok = false
		var kl: Dictionary = e.get("kid_look", {}) as Dictionary
		if kl.is_empty():
			kid_ok = false   # breed_child 应掷出幼儿相
		else:
			for slot in NG.SLOTS:
				if NG.entry_kit("kid", String(slot), String(kl.get(slot, ""))).is_empty():
					kid_ok = false
	_chk("有孩子出生", kids > 0)
	_chk("孩子亲缘互指+容貌目录合法(成年相+kid_look)", kid_ok)
	# 怀胎五年: 有喜脉纪事, 且首胎临盆距首孕不早于整孕期(添丁未必出自首孕母, 但全局首添必≥全局首孕+孕期)
	_chk("有喜脉纪事(按率受孕)", _preg_seen >= 1)
	var ges_ok := _first_preg_m >= 0 and _first_birth_m >= 0
	if ges_ok:
		ges_ok = _first_birth_m - _first_preg_m >= int(Game.tune("npc_gestation_years", 5)) * 12
	_chk("临盆距受孕≥孕期", ges_ok)
	# 孕期守卫: 在册/池中没有过期未产或凭空挂着的产期(要么未到期、要么当月至多一人补上)
	var preg_ok := true
	for k in all:
		var d: int = int((all[k] as Dictionary).get("preg_due_m", 0))
		if d > 0 and int(Game.run.age_m) >= d:
			preg_ok = false   # 家族 tick 先于本检查跑, 到期还挂着=结算漏了
	_chk("到期产期均已结算", preg_ok)
	# 四柱(与主角同口径): 全员灵根 1~5 行且皆五行字、气血在 [0, 上限]、寿元上限>0、武力非负
	var pillars_ok := true
	for k in all:
		var r: Array = Game.npc_roots(String(k))
		if r.is_empty() or r.size() > NG.ELEMENTS.size():
			pillars_ok = false
		for e in r:
			if not (String(e) in NG.ELEMENTS):
				pillars_ok = false
		var qi := Game.npc_qi(String(k))
		if qi < 0 or qi > Game.npc_qi_max(String(k)):
			pillars_ok = false
		if Game.npc_lifespan_cap(String(k)) <= 0 or Game.npc_wu_li(String(k)) < 0.0:
			pillars_ok = false
	_chk("全员四柱合法(灵根/气血/寿元/武力)", pillars_ok)
	# 未成年: 不修炼(cult 无/0)、未恋爱(无 spouse)、无 grown 标
	var minor_ok := true
	for k in all:
		var e2: Dictionary = all[k]
		if e2.has("born_m") and Game._npc_is_minor(String(k)):
			if float(e2.get("cult", 0.0)) > 0.0 or String(e2.get("spouse", "")) != "":
				minor_ok = false
	_chk("未成年不修炼不恋爱", minor_ok)
	# 幼儿相: 成年礼后回落性别套; 再把已成年孩子出生月拨回(重新未成年)真叠绘脸A —— 400 月窗口内可能无幼儿样本, 故自造
	var grown_kit_ok := true
	var sample := ""
	for k in all:
		var kit := Game.npc_kit(String(k))
		if bool((all[k] as Dictionary).get("grown", false)):
			if kit != "male" and kit != "female":
				grown_kit_ok = false
			if sample == "":
				sample = String(k)
	# 成年礼: 有孩子满 npc_adult_years 岁则 grown=true(须在下面自造幼儿清空 grown 标记之前查)
	var any_adult := false
	for k in all:
		var e3: Dictionary = all[k]
		if e3.has("born_m") and bool(e3.get("grown", false)):
			any_adult = true
	_chk("有孩子成年入轨(400月足够)", any_adult)
	var kid_face_ok := false
	if sample != "":
		var se: Dictionary = Game._npc_entry(sample)
		se.grown = false   # grown 守卫: 已成年者不回退, 自造幼儿需先清成年礼标记
		se.born_m = int(Game.run.age_m) - 24   # 拨回 24 个月大 → 重新未成年
		var pc := Portrait.build_for(sample, 44)
		kid_face_ok = Game.npc_kit(sample) == "kid" and pc != null and pc.get_child_count() >= 4
	_chk("未成年上幼儿脸(脸A 套)", kid_face_ok)
	_chk("成年礼后套件回落性别套", grown_kit_ok)
	# 幼儿捏脸页(测试页入口): 选人 → 全槽 ‹› 轮换 → 应用 → kid_look 写回且件仍在脸A目录, 头像仍真叠绘
	if sample != "":
		var app := Control.new()
		app.set_script(load("res://scripts/apps/app_face_age.gd"))
		app.setup("kidface", "幼儿捏脸", [])
		add_child(app)
		await get_tree().process_frame
		app._enter_edit(sample)
		await get_tree().process_frame
		for slot in NG.SLOTS:
			app._cycle(String(slot), 1)
		# 随机: 全槽+调色重掷, 气质不动(与捏脸工坊同规)
		var aura_keep := String(app._work.get("aura", ""))
		app._randomize_look()
		await get_tree().process_frame
		_chk("幼儿捏脸随机: 气质保留", String(app._work.get("aura", "")) == aura_keep)
		for slot in NG.SLOTS:
			if NG.entry_kit("kid", String(slot), String(app._work.get(slot, ""))).is_empty():
				_chk("幼儿捏脸随机: 槽位仍在脸A目录 " + String(slot), false)
		for k in NG.COLOR_IDENTITY:
			if not app._work.has(k):
				_chk("幼儿捏脸随机: 调色键齐 " + String(k), false)
		app._apply()
		var kl2: Dictionary = (Game._npc_entry(sample) as Dictionary).get("kid_look", {})
		var app_ok := true
		for slot in NG.SLOTS:
			if NG.entry_kit("kid", String(slot), String(kl2.get(slot, ""))).is_empty():
				app_ok = false
		var pc2 := Portrait.build_for(sample, 44)
		if pc2 == null or pc2.get_child_count() < 4:
			app_ok = false
		_chk("幼儿捏脸: 轮换+应用写回 kid_look", app_ok)
	# 坐化: 拨一位在世凡人(rand_)的生辰过寿限 → tick 两处 → dead 标、婚约/恋爱边清、修炼停、讣闻入纪事
	var allnow: Dictionary = Game.run.npcs.duplicate()
	allnow.merge(Game.run.world_npcs, true)
	var vd := ""
	for k in allnow:
		if String(k).begins_with("rand_") and not bool((allnow[k] as Dictionary).get("dead", false)):
			vd = String(k)
			break
	var dead_ok := false
	if vd != "":
		var ent: Dictionary = Game._npc_entry(vd)
		var sp0 := String(ent.get("spouse", ""))
		ent.born_m = int(Game.run.age_m) - (Game.npc_lifespan_cap(vd) + 2) * 12
		var d0 := _death_seen
		Game.tick_month()
		while not Game.pending.is_empty():
			Game.resolve_option(0)
		var cult1 := float(Game._npc_entry(vd).get("cult", 0.0))
		Game.tick_month()
		while not Game.pending.is_empty():
			Game.resolve_option(0)
		var ed: Dictionary = Game._npc_entry(vd)
		var rom_left := false
		for pk in (Game.run.get("npc_romance", {}) as Dictionary).keys():
			var ps: PackedStringArray = String(pk).split("|")
			if String(ps[0]) == vd or String(ps[1]) == vd:
				rom_left = true
		dead_ok = bool(ed.get("dead", false)) and not rom_left and _death_seen > d0
		dead_ok = dead_ok and float(ed.get("cult", 0.0)) == cult1   # 第二个 tick 不再涨修为
		if sp0 != "":
			dead_ok = dead_ok and String(ed.get("spouse", "")) == "" and String(Game._npc_entry(sp0).get("spouse", "")) != vd
	else:
		print("  NO rand_ sample for death test")
	_chk("坐化: dead 标 · 婚约边清 · 修炼停 · 讣闻入纪事", dead_ok)
	# 未关注 NPC 特殊事件入纪事(2026-09-22): 全程未设 focus → 破境行必须入纪事。
	# 固定 NPC 境界高(渡劫/元婴/化神), 400 月内到不了末层圆满 → 把开局在册的季忘川拨回炼气八层, 再 tick 逼出破境。
	var js: Dictionary = Game.run.npcs["jianshu"]
	js.realm_ord = 0
	js.realm = "炼气"
	js.nlayer = 8
	js.cult = 3300.0
	js.born_m = int(Game.run.age_m) - 30 * 12   # 四柱上线后必钉: 境界骤降则寿限骤降(80), 回填高龄会被坐化先收
	for _m in 3:
		Game.tick_month()
		while not Game.pending.is_empty():
			Game.resolve_option(0)
	# 纪事有 200 条滚动上限(早年线会被挤掉), 故按全程 logged 计数, 不依赖末窗
	_chk("未关注NPC破境入纪事(全程≥1行)", _broke_seen >= 1)
	print("NPC_FAMILY_SMOKE %s" % ("PASS" if _fails == 0 else "FAIL(%d)" % _fails))
	get_tree().quit()
