extends Node
## NPC 家庭冒烟: 恋爱六段→成婚→添丁→遗传→成年 全链路。⚠ 会 new_game() 清档, 跑前备份 user://。

const NG := preload("res://sim/NpcGenerator.gd")

var _fails := 0


func _chk(name: String, ok: bool) -> void:
	print(("PASS: " if ok else "FAIL: ") + name)
	if not ok:
		_fails += 1


func _ready() -> void:
	Game.new_game()
	Game.deterministic = true   # 冒烟免弹框: 打断类事件短路
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
		var male := Game.npc_male(String(k))
		for slot in NG.SLOTS:
			if NG.entry(male, String(slot), String((e.get("appearance", {}) as Dictionary).get(slot, ""))).is_empty():
				kid_ok = false
	_chk("有孩子出生", kids > 0)
	_chk("孩子亲缘互指+容貌目录合法", kid_ok)
	# 未成年: 不修炼(cult 无/0)、未恋爱(无 spouse)、无 grown 标
	var minor_ok := true
	for k in all:
		var e2: Dictionary = all[k]
		if e2.has("born_m") and Game._npc_is_minor(String(k)):
			if float(e2.get("cult", 0.0)) > 0.0 or String(e2.get("spouse", "")) != "":
				minor_ok = false
	_chk("未成年不修炼不恋爱", minor_ok)
	# 成年礼: 有孩子满 12 岁则 grown=true
	var any_adult := false
	for k in all:
		var e3: Dictionary = all[k]
		if e3.has("born_m") and bool(e3.get("grown", false)):
			any_adult = true
	_chk("有孩子成年入轨(400月足够)", any_adult)
	print("NPC_FAMILY_SMOKE %s" % ("PASS" if _fails == 0 else "FAIL(%d)" % _fails))
	get_tree().quit()
