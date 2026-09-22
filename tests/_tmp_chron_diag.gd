extends Node
## 复现诊断: 随机 NPC 纪事为空 —— 实时跑 96 个月, 逐个随机 NPC(在册+池内)看 chronicle_of 计数与原始纪事提及数。
## ⚠ 清档, 跑前备份 user://。

func _ready() -> void:
	print("DIAG_READY")
	Game.new_game()
	for _i in 96:
		if not Game.pending.is_empty():
			Game.resolve_option(0)
		Game.tick_month()
		if _i % 24 == 23:
			print("DIAG_TICKED=", _i + 1)
	var chron: Array = GameState.chronicle
	print("CHRONICLE_SIZE=", chron.size())
	var mentions := 0
	for e in chron:
		if String(e.get("text", "")).contains("【rand") or String(e.get("text", "")).contains("坊市一景") or String(e.get("text", "")).contains("游历"):
			mentions += 1
	print("RANDISH_LINES=", mentions)
	# 打几行含随机 NPC 名【】的样例
	var shown := 0
	for e in chron:
		var t := String(e.get("text", ""))
		if t.contains("游历") and shown < 6:
			print("SAMPLE: ", t.substr(0, 120))
			shown += 1
	for key in Game.run.npcs:
		var ks := String(key)
		if ks.begins_with("rand_"):
			var n := Game.npc_name(ks)
			var entries: Array = Game.chronicle_of(ks)
			var raw := 0
			for e in chron:
				if String(e.get("text", "")).contains("【%s】" % n):
					raw += 1
			print("RANPC ", ks, " name=", n, " of=", entries.size(), " raw=", raw)
	var pool_shown := 0
	for key in Game.run.get("world_npcs", {}):
		if pool_shown >= 5:
			break
		var ks2 := String(key)
		var n2: String = Game.npc_name(ks2)
		var entries2: Array = Game.chronicle_of(ks2)
		var raw2 := 0
		for e in chron:
			if String(e.get("text", "")).contains("【%s】" % n2):
				raw2 += 1
		print("POOL  ", ks2, " name=", n2, " of=", entries2.size(), " raw=", raw2)
		pool_shown += 1
	Game.muted = true
	get_tree().quit(0)
