extends Node
## QA 临时探针: 复现 yaoguai_smoke 赠礼场景, 打印实际好感增量与气质修正(跑完即删)

func _ready() -> void:
	Game.debug_seed(31)
	Game._start_life(DataManager.origins[0], 0)
	Game.speed = 0
	Game.deterministic = false
	Game.run.qi = Game.qi_max()
	Game.farm().yaodan = 3
	var key := ""
	for k in Game.run.npcs:
		key = String(k)
		break
	Game.run.npcs[key].met = true
	Game.run.npcs[key].stage = 1
	Game.run.npcs[key].gift_q = 0
	Game.run.focus = key
	var aff0 := float(Game.run.npcs[key].aff)
	var arch_aura := "?"
	var arch: Dictionary = Game.npc_arch(key)
	var appr: Variant = arch.get("appearance", null)
	if appr is Dictionary:
		arch_aura = String((appr as Dictionary).get("aura", ""))
	print("PROBE first_npc_key=", key)
	print("PROBE arch_aura=", arch_aura)
	print("PROBE aura_npc_aff=", Game.aura_npc_aff(key), " aura_self_aff=", Game.aura_self("aff"), " relation_halo=", Game.relation_halo(key))
	print("PROBE econ_gift_yaodan=", Game.econ("gift_yaodan", 60))
	Game.farm_gift_yaodan()
	var aff1 := float(Game.run.npcs[key].aff)
	print("PROBE aff0=", aff0, " aff1=", aff1, " delta=", aff1 - aff0)
	print("PROBE yaodan_after=", int(Game.farm().yaodan))
	print("PROBE aura_def_清冷=", var_to_str(DataManager.aura_def("清冷")))
	get_tree().quit()
