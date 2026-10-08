extends Node
## 称谓规约冒烟(GDD §8.1 称名即亲密): {xingming}/{ming} 占位与空名回退「你」;
## 照壁主角帖以全名入帖(无「主角」术语、无化名「那位」); 道侣之约私密称名。
## 安全: run 副本 + 停时钟, 不写盘。

var _fails := 0


func _chk(name: String, ok: bool) -> void:
	print(("PASS: " if ok else "FAIL: ") + name)
	if not ok:
		_fails += 1


func _ready() -> void:
	Game.set_process(false)
	Game.run = Game.run.duplicate(true)
	Game.set_player_name_parts("沈", "知味")

	# ① 占位符替换
	_chk("xingming=全名", Game._wall_sub("百味宗的{xingming}结道侣了", {}) == "百味宗的沈知味结道侣了")
	_chk("ming=只称名", Game._wall_sub("{ming}，灶上的羹给你温着", {}) == "知味，灶上的羹给你温着")
	_chk("player_ming", Game.player_ming() == "知味")

	# ② 空名回退「你」(未命名档不崩不露怯)
	Game.set_player_name_parts("", "")
	_chk("空名裸占位回退那位", Game._wall_sub("{xingming}上榜了", {}) == "那位上榜了")
	_chk("空名ming回退你", Game.player_ming() == "你")
	Game.set_player_name_parts("沈", "知味")

	# ③ 照壁数据: protagonist 帖无设计术语「主角」; 代称后必须括注全名(称名即亲密 · 公共全名格式)
	var bad_term := ""
	var bad_fmt := ""
	var has_xingming := 0
	for w in DataManager.wall:
		if String((w as Dictionary).get("family", "")) != "protagonist":
			continue
		var blob := _post_blob(w as Dictionary)
		if "主角" in blob:
			bad_term = String((w as Dictionary).get("id", "?"))
		if "那位" in blob and "（{xingming}）" not in blob:
			bad_fmt = String((w as Dictionary).get("id", "?"))
		if "{xingming}" in blob:
			has_xingming += 1
	_chk("protagonist 帖无「主角」术语", bad_term == "")
	_chk("代称后括注全名", bad_fmt == "")
	_chk("protagonist 帖以 {xingming} 入帖", has_xingming >= 4)

	# ③b 闲话壁称全名开关: 默认开=括注展开; 关/未命名=括注整段收起只称代称
	_chk("开关默认开=括注展开", Game._wall_sub("百味宗那位（{xingming}）结道侣了", {}) == "百味宗那位（沈知味）结道侣了")
	GameState.set_wall_full_name(false)
	_chk("开关关=括注收起只称代称", Game._wall_sub("百味宗那位（{xingming}）结道侣了", {}) == "百味宗那位结道侣了")
	Game.set_player_name_parts("", "")
	_chk("未命名亦收起不露空括号", Game._wall_sub("百味宗那位（{xingming}）结道侣了", {}) == "百味宗那位结道侣了")
	Game.set_player_name_parts("沈", "知味")
	GameState.set_wall_full_name(true)
	_chk("开关恢复=括注展开", Game._wall_sub("百味宗那位（{xingming}）结道侣了", {}) == "百味宗那位（沈知味）结道侣了")

	# ④ 私密弹层称名: 道侣之约正文呼「知味」而非「你」
	var gen := Game.npc_generator
	var e := Game._npc_init()
	e.merge(gen.generate(Game.rng, Game.run.npcs, ["tongming"]), true)
	e.met = true
	e.gender = "male"
	e.love = 1000.0
	e.stage = 4
	e.gate = int(Game.tune("gate_months", 24))   # 闸长随 tuning, 不硬编码
	var key := String(e.key)
	Game.run.npcs[key] = e
	Game.run.npcs.erase("moxiu")   # 防幽布衣首月自动首遇干扰
	Game._npc_prompt_check()
	var txt := String(Game.pending.get("text", ""))
	_chk("结契之问私密称名", "知味缔结道侣之契" in txt)
	Game.pending = {}

	print("NAME_ADDRESS " + ("PASS" if _fails == 0 else "FAIL(%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


func _post_blob(w: Dictionary) -> String:
	var s := String(w.get("title", "")) + String(w.get("report_line", ""))
	var op: Dictionary = w.get("op", {})
	s += String(op.get("text", ""))
	for r in w.get("replies", []):
		s += String((r as Dictionary).get("text", ""))
	return s
