extends Node
## 关注冒烟: 关注名单上限 10 / 「喜欢」默认入关注 / 取关「喜欢」联动清喜欢 /
## 老档 follows 迁移 / 日程「一世纪事」关注过滤(月报拆段/单行整滤/池内未入册者亦滤/无关条目保留)。
## 运行: Godot --headless --path . res://tests/follow_smoke.tscn

var _fails := 0


func _ready() -> void:
	Game.debug_seed(7)
	Game._start_life(DataManager.origins[0], 0)
	Game.speed = 0

	# 备 12 名已入册 NPC(随机档快照带名字, npc_name 可查)
	var keys: Array[String] = []
	for i in 12:
		var k := "rand_t%02d" % i
		var np := Game._npc_init()
		np.met = true
		np.name = "测士%s" % String("ABCDEFGHIJKL"[i])
		Game.run.npcs[k] = np
		keys.append(k)

	# 1) 名单上限 10: 满员后第 11 人被拒; 取关一位可再补
	var ok := true
	for i in 10:
		ok = ok and Game.set_follow(keys[i], true)
	_check(ok and Game.follows().size() == 10, "关注 10 人全部成功")
	_check(not Game.set_follow(keys[10], true), "名单满时第 11 人被拒")
	_check(Game.set_follow(keys[3], false), "取关成功")
	_check(Game.follows().size() == 9, "取关后名单 9 人")
	_check(Game.set_follow(keys[10], true), "腾位后可关注他人")
	_check(Game.set_follow(keys[0], true), "重复关注幂等成功")
	_check(Game.set_follow(keys[11], false), "取关未关注者幂等成功")
	_check(not Game.is_followed(keys[11]), "未关注者不在关注之列")

	# 2) 喜欢默认为关注; 取关「喜欢」对象联动清喜欢
	for k in Game.follows().duplicate():
		Game.set_follow(String(k), false)
	Game.set_focus(keys[0])
	_check(Game.follows().has(keys[0]) and Game.is_followed(keys[0]), "喜欢默认入关注名单")
	Game.set_follow(keys[0], false)
	_check(String(Game.run.get("focus", "")) != keys[0], "取关喜欢对象联动清空喜欢")
	_check(not Game.is_followed(keys[0]), "取关后脱离关注之列")

	# 3) 名单满时喜欢: 挤不进列表也恒视为已关注
	for k in Game.follows().duplicate():
		Game.set_follow(String(k), false)
	for i in 10:
		Game.set_follow(keys[i], true)
	Game.set_focus(keys[11])
	_check(not Game.follows().has(keys[11]) and Game.is_followed(keys[11]), "满员名单的喜欢恒视为关注")

	# 4) 老档迁移: 缺 follows 时按 focus 补齐(指向已入册者), 否则空表
	Game.run.erase("follows")
	Game.run.focus = keys[2]
	Game._ensure_run()
	_check(Array(Game.follows()) == Array([keys[2]]), "老档已设喜欢 → follows 补 [focus]")
	Game.run.erase("follows")
	Game.run.focus = "ghost_not_exist"
	Game._ensure_run()
	_check(Game.follows().is_empty(), "老档喜欢指向不存在者 → 空名单")

	# 5) 日程过滤: keys[0..1] 已关注; keys[10] 在册未关注; 池内未入册者亦算未关注; 与 NPC 无关条目原样
	Game.run.focus = ""
	Game.run.follows = [keys[0], keys[1]]
	var a := String(Game.npc_name(keys[0]))
	var b := String(Game.npc_name(keys[10]))
	var wp := Game._npc_init()
	wp.name = "测池A"
	Game.run.world_npcs["rand_w00"] = wp
	var w := "测池A"
	var month := "第1年·3月 · 【%s】突破炼气 · 【%s】下山采买 · 垦了半亩灵田" % [a, b]
	_check(Game.filter_chronicle_for_follows(month) == "第1年·3月 · 【%s】突破炼气 · 垦了半亩灵田" % a,
		"月报拆段: 未关注者的段被滤, 其余保留")
	_check(Game.filter_chronicle_for_follows("◇ 方案切换: 闭关") == "◇ 方案切换: 闭关", "与 NPC 无关条目原样保留")
	_check(Game.filter_chronicle_for_follows("◆ 初遇【%s】于山道" % b) == "", "单行提未关注者整条滤除")
	_check(Game.filter_chronicle_for_follows("◆ 初遇【%s】于山道" % a) == "◆ 初遇【%s】于山道" % a, "单行提已关注者保留")
	_check(Game.filter_chronicle_for_follows("◆ 坊市一景: 【%s】在巷口追鸡" % w) == "", "单行提未入册池人整条滤除")
	_check(Game.filter_chronicle_for_follows("第1年·4月 · 【%s】突破炼气 · 【%s】结为夫妻 · 垦了半亩灵田" % [a, w])
		== "第1年·4月 · 【%s】突破炼气 · 垦了半亩灵田" % a,
		"月报拆段: 未入册池人的段被滤")
	Game.run.follows = []
	_check(Game.filter_chronicle_for_follows("◇ 引气入体") == "◇ 引气入体", "空名单下无关条目仍显示")
	_check(Game.filter_chronicle_for_follows("【%s】送来了新茶" % a) == "", "空名单下在册未关注者条目滤除")
	_check(Game.filter_chronicle_for_follows("◆ 讣闻: 【%s】寿元耗尽" % w) == "", "空名单下池人条目仍滤除")

	print("== follow_smoke: %s (%d FAIL) ==" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fails += 1
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
