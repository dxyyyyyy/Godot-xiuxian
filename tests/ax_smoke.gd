extends Node
## 暗线五碎片冒烟(8.3 v0.2 §0.2 缺口①②③实装): 弹框链推进/碎片落账/渡劫口四选一/开炉双结局/道韵碎片项/W 池上下线/灶火长明/deterministic 静默。
## ⚠ 会 new_game()/rebirth() 清档 —— 经 tools/run_tests.sh 隔离跑。

var _fails := 0

func _chk(name: String, ok: bool) -> void:
	print(("PASS: " if ok else "FAIL: ") + name)
	if not ok:
		_fails += 1

func _chain() -> Dictionary:
	return (Game.run.get("ax", {}) as Dictionary).get("chain", {})

func _drain(max_steps: int = 80) -> void:
	var guard := 0
	while not _chain().is_empty() and guard < max_steps:
		Game.resolve_option(0)
		guard += 1

func _find_qy(eid: String) -> Dictionary:
	for e in DataManager.qy:
		if String(e.get("id", "")) == eid:
			return e
	return {}

func _ready() -> void:
	const TG := preload("res://tests/test_guard.gd")
	if not TG.ensure_isolated("AX_SMOKE"):
		get_tree().quit(2)
		return
	Game.debug_seed(7)
	Game.new_game()

	# ═══ 1. 数据完整性 ═══
	var ids := {}
	var schema_ok := true
	for e in DataManager.ax:
		var eid := String(e.get("id", ""))
		ids[eid] = true
		if eid == "":
			schema_ok = false
			continue
		if bool(e.get("manual", false)):
			continue
		if (e.get("beats", []) as Array).is_empty() or (e.get("choices", []) as Array).is_empty():
			schema_ok = false
	for fid in ["AX-F1", "AX-F2", "AX-F3", "AX-F4", "AX-F5", "AX-KL0", "AX-KL1", "AX-KL2", "AX-ZHM"]:
		if not ids.has(fid):
			schema_ok = false
	_chk("1a 九条目齐且弹框链 schema 完整", schema_ok)
	var frag_ok := true
	for e in DataManager.ax:
		if String(e.get("id", "")).begins_with("AX-F") and not bool(e.get("fragment", false)):
			frag_ok = false
	_chk("1b 五碎片带 fragment 标记", frag_ok)
	var dao_leak := false
	for e in DataManager.ax:
		for c in (e.get("choices", []) as Array):
			var cc: Dictionary = c
			for eff in [(cc.get("effects", {}) as Dictionary), ((cc.get("success", {}) as Dictionary).get("effects", {}) as Dictionary), ((cc.get("fail", {}) as Dictionary).get("effects", {}) as Dictionary)]:
				if (eff as Dictionary).has("dao"):
					dao_leak = true   # 碎片×30 随结局结算(§0.3 不重复计), AX 效果禁即时 dao
	_chk("1c AX 效果零即时 dao", not dao_leak)

	# ═══ 2. F1 链: 逐拍推进 → 抉择 → 碎片落账 ═══
	Game._ax_start_id("AX-F1")
	Game._ax_resume()   # 设链头后须续播点火(弹窗统一走续播泵)
	_chk("2a 链开播(phase=beat)", String(_chain().get("phase", "")) == "beat" and String(_chain().get("eid", "")) == "AX-F1")
	var reached_choice := false
	for _i in 24:
		if String(_chain().get("phase", "")) == "choice":
			reached_choice = true
			break
		if _chain().is_empty():
			break
		Game.resolve_option(0)
	_chk("2b 逐拍推进到抉择", reached_choice)
	var frag0 := Game._qy_frag()
	Game.resolve_option(0)   # 选项 A 追问(得关键台词)
	_drain()
	_chk("2c 选项 A 得碎片+旗标", Game._qy_frag() == frag0 + 1 and Game._meta_flag("ax_f1") == 1)
	_chk("2d 链收尾清空+每世落账", _chain().is_empty() and int((Game.run.ax.use as Dictionary).get("AX-F1", 0)) == 1)
	_chk("2e 跨世补投账(ax_last_life)", int((Game.meta.get("ax_last_life", {}) as Dictionary).get("AX-F1", -1)) == int(Game.meta.get("lives", 0)))

	# ═══ 3. F2 门控/检定 + 新谓词 ═══
	var f2: Dictionary = Game._ax_entry("AX-F2")
	Game.run.realm = 2   # F2 需云梦泽(金丹解锁): 境界窗内才谈门槛
	_chk("3a F2 门槛 frag_gte:1 放行", Game._ax_trig_ok(f2.get("trigger", {})))
	Game._qy_apply_effects({"anxian": {"frag": -1}})
	_chk("3b frag=0 时 F2 拒", not Game._ax_trig_ok(f2.get("trigger", {})))
	Game._qy_apply_effects({"anxian": {"frag": 1}})
	_chk("3c 新谓词(旗标/痕迹/NPC好感)", Game._qy_cond_ok({"flag_gte": {"key": "ax_f1", "v": 1}}) and not Game._qy_cond_ok({"flag_gte": {"key": "ax_f1", "v": 2}}) and Game._qy_cond_ok({"flag_lt": {"key": "ax_f1", "v": 2}}) and not Game._qy_cond_ok({"flag_lt": {"key": "ax_f1", "v": 1}}) and Game._qy_cond_ok({"trace_gte": 0}) and not Game._qy_cond_ok({"trace_gte": 1}) and not Game._qy_cond_ok({"npc_aff_gte": {"key": "jianshu", "v": 100}}))
	Game.deterministic = true   # deterministic: 链全自动静默播完, 检定恒成(首选项)
	var frag1 := Game._qy_frag()
	Game._ax_start_id("AX-F2")
	Game._ax_resume()
	_chk("3d deterministic 整链静默播完并得碎片", _chain().is_empty() and Game._qy_frag() == frag1 + 1 and Game._meta_flag("ax_f2") == 1)
	Game.deterministic = false

	# ═══ 4. 渡劫口: F5 强制弹出 + 四选一面板 + 拖延 + 开炉 ═══
	Game.new_game()
	Game.deterministic = false
	Game._qy_apply_effects({"anxian": {"frag": 4}})
	Game.run.realm = 7
	Game.run.layer = int(Game.realm().layers) - 1
	Game.run.cult = float(Game.layer_need()) * 2.0
	Game._dujie_gate()
	_chk("4a 渡劫口先强制播 F5", String(_chain().get("eid", "")) == "AX-F5")
	_drain()
	_chk("4b F5 播完弹渡劫面板", String(Game.pending.get("kind", "")) == "dujie")
	_chk("4c 面板四选一(开炉已解锁)", (Game.pending.get("options", []) as Array).size() == 4)
	Game.resolve_option(1)   # 拖延蓄力
	_chk("4d 拖延落 cd 且不落幕", int(Game.run.get("dujie_panel_cd", -1)) > int(Game.run.age_m) and not Game.is_ended())
	Game._dujie_gate()
	_chk("4e cd 内渡劫口不弹不冲", Game.pending.is_empty() and not Game.is_ended())
	Game.run.dujie_panel_cd = -1
	Game._dujie_gate()
	_chk("4f F5 已得(ax_f5)直接面板", String(Game.pending.get("kind", "")) == "dujie")
	_chk("4g 碎片账=5(F5 链已授第 5 枚)", Game._qy_frag() == 5)
	Game.resolve_option(3)   # 开炉
	_chk("4h 开炉进前奏链", String(_chain().get("eid", "")) == "AX-KL0")
	_drain()
	_chk("4i 开炉结局落地", Game.is_ended() and String(Game.run.get("end_kind", "")) in ["开炉", "开炉·回甘"])
	_chk("4j 真结局倍率 ×2(与飞升同档)", float(Game.ENDING_MULT.get(String(Game.run.get("end_kind", "")), 0.0)) == 2.0)
	_chk("4k ax_kailu 旗标已盖", Game._meta_flag("ax_kailu") == 1)

	# ═══ 5. W 池上下线 + 好久不见 ═══
	var w1 := _find_qy("AX-W01")
	var hj1 := _find_qy("AX-HJ01")
	var ledx := {"use": {}, "cd": {}, "year": {}, "promoted": {}}
	var mfs: Dictionary = Game._flags_store(true)
	var saved_kailu := int(mfs.get("ax_kailu", 0))
	mfs["ax_kailu"] = 0
	_chk("5a 未开炉 W01 过门控", Game._qy_trig_ok(w1, ledx))
	_chk("5b 未开炉 HJ01 拒", not Game._qy_trig_ok(hj1, ledx))
	mfs["ax_kailu"] = 1
	_chk("5c 开炉后 W01 下线", not Game._qy_trig_ok(w1, ledx))
	_chk("5d 开炉后 HJ01 上线", Game._qy_trig_ok(hj1, ledx))
	mfs["ax_kailu"] = saved_kailu

	# ═══ 6. 回甘灶火长明: 来世开局演出 ═══
	var fsx: Dictionary = Game._flags_store(true)
	fsx["ax_zhaohuiming"] = 1
	Game.meta.zhaohuiming_life = int(Game.meta.get("lives", 0))   # 已落幕 lives 已 +1, 下一世 run.life = 戳+1
	Game.rebirth({}, 0, 0, {"n": 5, "els": []}, [], true)
	_chk("6a 转世保留 meta 旗标且世号=戳+1", Game._meta_flag("ax_zhaohuiming") == 1 and int(Game.run.life) == int(Game.meta.get("zhaohuiming_life", -9)) + 1)
	Game.tick_month()   # 首月: _ax_zhm_check 播开局演出
	_chk("6b 首月播灶火长明", String(_chain().get("eid", "")) == "AX-ZHM")
	_drain(20)
	_chk("6c 开局演出收尾", _chain().is_empty())

	# ═══ 7. deterministic 长跑 60 月: 零 AX 弹框 + 渡劫口等价旧自动冲关 ═══
	Game.new_game()
	Game.deterministic = true
	var ax_fired := false
	for _m in 60:
		Game.tick_month()
		if String(Game.pending.get("kind", "")) == "ax":
			ax_fired = true
		if not Game.pending.is_empty():
			Game.resolve_option(0)
		if Game.is_ended():
			break
	_chk("7a deterministic 60 月零 AX 弹框", not ax_fired)
	Game.run.realm = 7
	Game.run.layer = int(Game.realm().layers) - 1
	Game.run.cult = float(Game.layer_need()) * 2.0
	Game.tick_month()
	_chk("7b deterministic 渡劫口自动飞升(面板首项=飞升, 等价旧自动冲关)", Game.is_ended() and String(Game.run.get("end_kind", "")) == "飞升")
	Game.deterministic = false

	# ═══ 8. 三生石暗线图鉴数据 + 彩蛋帧回看(AX-CK) ═══
	Game.new_game()
	var stone: Dictionary = DataManager.ax_stone
	var stone_ids := {}
	for st in (stone.get("entries", []) as Array):
		stone_ids[String((st as Dictionary).get("id", ""))] = true
	var stone_ok := stone_ids.size() == 5
	for fid in ["AX-F1", "AX-F2", "AX-F3", "AX-F4", "AX-F5"]:
		if not stone_ids.has(fid):
			stone_ok = false
		var sent: Dictionary = {}
		for st2 in (stone.get("entries", []) as Array):
			if String((st2 as Dictionary).get("id", "")) == fid:
				sent = st2
		if sent.is_empty() or String(sent.get("unlock", "")) == "" or String(sent.get("reread", "")) == "":
			stone_ok = false
	_chk("8a 图鉴五词条齐(获取版+重读版)", stone_ok)
	var ck := Game._ax_entry("AX-CK")
	_chk("8b AX-CK 回看条目在册(manual 单拍)", not ck.is_empty() and bool(ck.get("manual", false)) and (ck.get("beats", []) as Array).size() == 1)
	Game._qy_apply_effects({"anxian": {"frag": 5}, "flags": [{"key": "ax_kailu", "meta": true}]})
	Game._ax_start_id("AX-CK")
	Game._ax_resume()
	Game.resolve_option(0)   # 单拍亦须玩家「▸ 继续」一次
	_chk("8c 回看单拍播完收尾", _chain().is_empty())
	Game._ax_start_id("AX-CK")
	Game._ax_resume()
	Game.resolve_option(0)
	_chk("8d 回看可重复(不限次)", _chain().is_empty())

	# ═══ 9. 无面人帖: 碎片事件帖次月上壁 + 怪谈族扩池 ═══
	Game.new_game()
	Game._queue_wall_event("ax_frag_AX-F3")
	Game.tick_month()
	var wall_ids := {}
	for p in (Game.run.wall.posts as Array):
		wall_ids[String((p as Dictionary).get("id", ""))] = true
	_chk("9a F3 次月闲话壁上帖(wall_045 求证)", wall_ids.has("wall_045"))
	var strange_count := 0
	for e in DataManager.wall:
		if String(e.get("family", "")) == "strange":
			strange_count += 1
	_chk("9b 怪谈族扩池到 7 帖(007/015+5)", strange_count == 7)

	# ═══ 10. 三生石 UI: 图鉴区块渲染 headless 断言 ═══
	Game.new_game()
	Game._qy_apply_effects({"anxian": {"frag": 1}, "flags": [{"key": "ax_f1", "meta": true}]})
	var stone_ui := Control.new()
	stone_ui.set_script(load("res://scripts/apps/app_lifestone.gd"))
	add_child(stone_ui)
	await get_tree().process_frame
	await get_tree().process_frame
	var labels := _collect_labels(stone_ui.get("_content"))
	var joined := "\n".join(labels)
	_chk("10a 图鉴区块: 标题+已解锁词条+未解锁占位", joined.contains("灶火的账本") and joined.contains("不灭灶火") and joined.contains("？？？"))
	Game._flags_store(true)["ax_f5"] = 1
	Game._flags_store(true)["ax_kailu"] = 1
	stone_ui.call("_rebuild")
	await get_tree().process_frame
	labels = _collect_labels(stone_ui.get("_content"))
	_chk("10b ax_kailu 后出现「再看一眼」入口", "\n".join(labels).contains("再看一眼"))
	stone_ui.queue_free()

	print("AX_SMOKE %s" % ("PASS" if _fails == 0 else "FAIL(%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)

func _collect_labels(node: Node) -> Array:
	var out: Array = []
	if node == null or not is_instance_valid(node):
		return out
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
			if c is Label:
				out.append((c as Label).text)
	return out
