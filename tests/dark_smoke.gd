extends Node
## 黑暗料理 6 道冒烟(图鉴 §黑暗料理): 三处入口解拦(烹/吃/赠) + 「？？？」揭晓制 + 猎奇反向 + winter_any 做实。
## ⚠ 会 new_game() 清档 —— 经 tools/run_tests.sh 隔离跑。

var _fails := 0
var _log_lines: Array = []

func _chk(name: String, ok: bool) -> void:
	print(("PASS: " if ok else "FAIL: ") + name)
	if not ok:
		_fails += 1

func _dark_ids() -> Array:
	var out: Array = []
	for r in DataManager.recipes:
		if String(r.get("tier", "")) == "dark":
			out.append(String(r.id))
	return out

func _grant(seed_id: String, n: int) -> void:
	Game._qy_apply_effects({"inv": {"seed": seed_id, "grade": "凡", "n": n}})

func _in_log(needle: String) -> bool:
	return _log_lines.any(func(t: String): return t.contains(needle))

func _cook_collect(rid: String) -> void:
	# 用料在调用方备齐: 起火 → 置熟 → 收取(收成入仓库并揭晓)
	Game.kitchen_cook(0, rid)
	Game._stoves()[0].age = Game.cook_months(Game._stove_dish(0))
	Game.kitchen_collect(0)

func _ready() -> void:
	const TG := preload("res://tests/test_guard.gd")
	if not TG.ensure_isolated("DARK_SMOKE"):
		get_tree().quit(2)
		return
	Game.logged.connect(func(t: String, _d: String) -> void: _log_lines.append(t))

	# ═══ 1. 数据完整性: dark_events 与 6 道 dark 谱一一对应, 字段齐(百味乱炖走 assemble 三池) ═══
	var ids := _dark_ids()
	_chk("1a recipes 恰 6 道 dark", ids.size() == 6)
	var probs: PackedStringArray = []
	var seen := {}
	for d in DataManager.dark:
		var did := String(d.get("id", ""))
		if did == "" or not ids.has(did):
			probs.append(did + "(不在 6 道之列)")
		if seen.has(did):
			probs.append(did + "(重复)")
		seen[did] = true
		if String(d.get("moxiu", "")) == "" or String(d.get("eat", "")) == "":
			probs.append(did + "(缺 moxiu/eat)")
		if String(d.get("text", "")) == "" and not d.has("assemble"):
			probs.append(did + "(缺 text/assemble)")
	for rid in ids:
		if not seen.has(rid):
			probs.append(rid + "(dark_events 缺文案)")
	_chk("1b dark_events 与菜谱一一对应且字段齐", probs.is_empty())
	var pools: Array = DataManager.dark_event("baiweiluandun").get("assemble", [])
	var pools_ok := pools.size() == 3
	for p in pools:
		if (p as Array).is_empty():
			pools_ok = false
	_chk("1c 百味乱炖三池拼装且池皆非空", pools_ok)

	# ═══ 2. 图鉴隐藏: 新档 dark 谱不随境界自动点亮 ═══
	Game.debug_seed(5)
	Game.new_game()
	GameState.sync_discoveries()
	var leak := []
	for rid in ids:
		if GameState.discovered_recipes.has(rid):
			leak.append(rid)
	_chk("2a 新档 6 道全隐藏", leak.is_empty())
	_chk("2b 普通低阶谱照常点亮", GameState.discovered_recipes.has("suchaochunjiu"))

	# ═══ 3. winter_any 做实: 只认冬播种子(全表仅雪里青) ═══
	_chk("3a 开局无冬播 → winter_any 为 0", Game._mat_available("winter_any") == 0)
	_grant("bingxincai", 2)
	_chk("3b 夏播冰心菜不顶冬播名额", Game._mat_available("winter_any") == 0)
	_grant("xueliqing", 1)
	_chk("3c 雪里青入账 winter_any=1", Game._mat_available("winter_any") == 1)

	# ═══ 4. 隐藏组合试错: 凑齐才亮「？？？」暗格 ═══
	_chk("4a 无料时三味苦汤不亮", not Game.dark_cookable().has("sanweikutang"))
	_grant("huiyuancao", 3)
	_chk("4b 回元草×3 凑齐即亮", Game.dark_cookable().has("sanweikutang"))
	_chk("4c 冬播已被占位外缺料时拔丝虚空不亮", not Game.dark_cookable().has("basikong"))

	# ═══ 5. 上灶: 起火扣料, 未揭晓灶面/月报只显「？？？」, 收取揭晓 + 黑历史 ═══
	Game.kitchen_cook(0, "sanweikutang")
	_chk("5a dark 谱可入灶", String(Game._stoves()[0].get("recipe", "")) == "sanweikutang")
	_chk("5b 用料照扣", Game._inv_seed_total("huiyuancao") == 0)
	_chk("5c 灶面未揭晓只显？？？", Game.dish_display_name(Game._stove_dish(0)) == "？？？")
	Game._stoves()[0].age = Game.cook_months(Game._stove_dish(0)) - 1
	var notes0 := Game.month_notes.size()
	Game._kitchen_tick()
	_chk("5d 月报行也只显？？？", Game.month_notes.size() > notes0 and Game.month_notes[notes0].contains("【？？？】"))
	Game.kitchen_collect(0)
	_chk("5e 收取入仓库 ×1", int(Game._dishes().get("sanweikutang", 0)) == 1)
	_chk("5f 黑历史记账 dark_found", Game.dark_found("sanweikutang"))
	_chk("5g 图鉴暗谱点亮", GameState.discovered_recipes.has("sanweikutang"))
	_chk("5h 月报有揭晓行", " ".join(Game.month_notes).contains("黑历史"))
	_chk("5i 纪事有揭晓行", _in_log("黑历史收藏 +1"))

	# ═══ 6. 自吃: 无 buff、不进 buff 计算, 只留喜剧纪事 ═══
	var cult0 := float(Game.run.cult)
	var buffs0: Dictionary = (Game.run.buffs as Dictionary).duplicate(true)
	Game.kitchen_eat("sanweikutang")
	_chk("6a 吃掉一份", not Game._dishes().has("sanweikutang"))
	_chk("6b 修为零变动", float(Game.run.cult) == cult0)
	_chk("6c buff 零变动", Game.run.buffs.hash() == buffs0.hash())
	_chk("6d 纪事有自吃喜剧行", _in_log("吃了【三味苦汤】"))

	# ═══ 7. 第二道暗谱: 未揭晓前灶面依旧「？？？」 ═══
	_grant("jiuzhuan", 1)
	_grant("chixueshen", 1)
	Game.kitchen_cook(0, "jiuzhuanheidan")
	_chk("7a 灶面？？？", Game.dish_display_name(Game._stove_dish(0)) == "？？？")
	Game._stoves()[0].age = Game.cook_months(Game._stove_dish(0))
	Game.kitchen_collect(0)
	_chk("7b 收取后揭晓", Game.dark_found("jiuzhuanheidan") and int(Game._dishes().get("jiuzhuanheidan", 0)) == 1)

	# ═══ 8. 赠礼·普通口味: 好感 −3 + 喜剧入月报/纪事 ═══
	Game._first_meet("yaoshi", "冒烟")
	Game.run.npcs["yaoshi"].stage = 1
	Game.run.focus = "yaoshi"
	Game.run.npcs["yaoshi"].gift_q = 0
	Game.run.npcs["yaoshi"].aff = 50.0   # 先垫好感: −3 要在正账上可见(0 处有地板)
	var aff0 := float(Game.run.npcs.yaoshi.aff)
	Game.kitchen_gift("jiuzhuanheidan")
	var d1 := float(Game.run.npcs.yaoshi.aff) - aff0
	_chk("8a 好感恰 −3(不放大不锁档)", absf(d1 + 3.0) < 0.001)
	_chk("8b 菜已送出", not Game._dishes().has("jiuzhuanheidan"))
	_chk("8c 月报有黑暗喜剧", " ".join(Game.month_notes).contains("黑暗喜剧"))
	_chk("8d 纪事有黑暗喜剧", _in_log("黑暗喜剧"))

	# ═══ 9. 焰心炭特例: 好感不降(aff=0), 喜剧照旧 ═══
	_grant("yanxinguo", 2)
	_cook_collect("yanxentan")
	Game.run.npcs["yaoshi"].gift_q = 0
	aff0 = float(Game.run.npcs.yaoshi.aff)
	Game.kitchen_gift("yanxentan")
	_chk("9a 焰心炭好感零变动", absf(float(Game.run.npcs.yaoshi.aff) - aff0) < 0.001)
	# 地板: 好感仅 1 时 −3 钳到 0, 永不为负(永不锁好感、永不罚数值)
	_grant("huiyuancao", 3)
	_cook_collect("sanweikutang")
	Game.run.npcs["yaoshi"].gift_q = 0
	Game.run.npcs["yaoshi"].aff = 1.0
	Game.kitchen_gift("sanweikutang")
	_chk("9b −3 钳于 0 永不为负", float(Game.run.npcs.yaoshi.aff) == 0.0)

	# ═══ 10. 猎奇口味(幽布衣): 黑暗料理当珍馐, 反向投喜 ═══
	_chk("10a 幽布衣口味=猎奇", Game.npc_taste_base("moxiu") == "猎奇")
	_grant("huoronggua", 1)
	_grant("ningshencao", 3)
	_cook_collect("basikong")
	Game._first_meet("moxiu", "冒烟")
	Game.run.npcs["moxiu"].stage = 1
	Game.run.focus = "moxiu"
	Game.run.npcs["moxiu"].gift_q = 0
	aff0 = float(Game.run.npcs.moxiu.aff)
	Game.kitchen_gift("basikong")
	_chk("10b 猎奇收黑暗料理好感为正", float(Game.run.npcs.moxiu.aff) - aff0 > 0.0)
	_chk("10c 纪事有猎奇专属反应", _in_log("黑暗喜剧"))

	# ═══ 11. 百味乱炖: 每世随机拼装(同世两次取词一致) ═══
	var line1 := Game.dark_comedy("baiweiluandun", "text", "某人")
	var line2 := Game.dark_comedy("baiweiluandun", "text", "某人")
	_chk("11a 拼装非空且不含占位符", line1 != "" and not line1.contains("{npc}"))
	_chk("11b 同世缓存同一句", line1 == line2)
	_chk("11c 猎奇反应可用", Game.dark_comedy("baiweiluandun", "moxiu", "幽布衣") != "")

	# ═══ 12. deterministic 六月长跑: 新链路全程无崩 ═══
	Game.deterministic = true
	for _m in 6:
		Game.tick_month()
		if not Game.pending.is_empty():
			Game.resolve_option(0)
		if Game.is_ended():
			break
	Game.deterministic = false
	_chk("12a 六月长跑存活", true)

	print("DARK_SMOKE %s" % ("PASS" if _fails == 0 else "FAIL(%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)
