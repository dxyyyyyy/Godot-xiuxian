extends Node
const TestGuard := preload("res://tests/test_guard.gd")
## 功法冒烟: 残页→合成→研习(藏经阁研速切回)→研通→装备写 run.tech 活乘数;
## 聚灵/武力两公式即刻受益; 防御(残页不足/未研通/研席唯一/重复合成); 老档兼容(_ensure_run 补档归一);
## relic 事件残页键; 坊市购页/整卷; 开垦吃自种灵植/突破丹叠购; 道韵残卷跨世携带; 月度 tick 接线。
## 运行: Godot --headless --path . res://tests/gongfa_smoke.tscn

var _fails := 0


func _ready() -> void:
	if not TestGuard.ensure_isolated("GONGFA_SMOKE"):
		get_tree().quit(2)
		return
	Game.debug_seed(7)
	Game._start_life(DataManager.origins[0], 0)
	Game.speed = 0
	Game.deterministic = true

	# 0) 新世档案: 空功法, tech=1.0(死乘数退役后的干净起点)
	_check(String(Game.gongfa().get("equipped", "")) == "" and absf(float(Game.run.tech) - 1.0) < 1e-6, "新世: 无装备功法, run.tech=1.0")
	var eff0 := Game.efficiency()
	var wu0 := Game.wu_li()

	# 1) 合成防御: 残页不足拒绝; 够数则 −页入册(未研通)并顺手开研席
	Game.gongfa_synthesize("qingmu")
	_check(not ("qingmu" in Array(Game.gongfa().get("owned", []))), "残页不足: 合成被拒")
	Game.gongfa_pages_add(2)
	Game.gongfa_synthesize("qingmu")
	_check("qingmu" in Array(Game.gongfa().get("owned", [])) and int(Game.gongfa().get("pages", 0)) == 0, "合成: −2 页入册(残卷态)")
	_check(String(Game.gongfa().get("studying", "")) == "qingmu", "合成后研席顺手开研")
	Game.gongfa_synthesize("qingmu")
	_check(int(Game.gongfa().get("pages", 0)) == 0, "已持有不可重复合成")

	# 2) 未研通不可装备: tech 不动, 聚灵/武力基线不变
	Game.gongfa_equip("qingmu")
	_check(String(Game.gongfa().get("equipped", "")) == "" and absf(float(Game.run.tech) - 1.0) < 1e-6, "未研通装备被拒, tech 仍 1.0")

	# 3) 研习: 藏经阁 0 级 ×1.0 逐月推进; 升 3 级切回 ×1.7; 研速 buff 叠乘; 研满 4 有效研月研通
	Game._gongfa_tick()
	_check(absf(float((Game.gongfa().get("prog", {}) as Dictionary).get("qingmu", 0.0)) - 1.0) < 1e-6, "研席逐月 ×1.0(藏经阁 0 级)")
	Game.run.facilities.cangjingge = 3
	_check(absf(Game.research_mult() - 1.7) < 1e-6, "藏经阁研速 ×1.7(灰盒顿悟折算退役切回)")
	Game._gongfa_tick()
	_check(absf(float((Game.gongfa().get("prog", {}) as Dictionary).get("qingmu", 0.0)) - 2.7) < 1e-6, "研速生效: 1.0+1.7=2.7")
	Game._buff_apply("research", 0.25, 3)
	_check(absf(Game.research_mult() - 2.125) < 1e-6, "研速 buff(悟性料理)叠乘 ×1.25")
	Game._gongfa_tick()
	_check(Game.gongfa_mastered("qingmu"), "研满 4 有效研月 → 研通(进度钳满)")

	# 4) 装备写 run.tech: 聚灵/武力两公式即刻受益(×1.2)
	Game.gongfa_equip("qingmu")
	_check(String(Game.gongfa().get("equipped", "")) == "qingmu" and absf(float(Game.run.tech) - 1.2) < 1e-6, "装备青木餐霞功: run.tech=1.2")
	_check(absf(Game.efficiency() / maxf(1e-9, eff0) - 1.2) < 1e-4, "聚灵效率 ×1.2 即刻生效")
	_check(absf(Game.wu_li() / maxf(1e-9, wu0) - 1.2) < 1e-4, "武力 gear +20% 即刻生效(§5.4)")

	# 5) 研席唯一: 研通后研席不自动让位, 手动可换(进度各自保留)
	Game.gongfa_pages_add(2)
	Game.gongfa_synthesize("chihuo")
	_check("chihuo" in Array(Game.gongfa().get("owned", [])) and String(Game.gongfa().get("studying", "")) == "qingmu", "研席不自动让位(仍研青木)")
	Game.gongfa_study("chihuo")
	_check(String(Game.gongfa().get("studying", "")) == "chihuo", "手动换研席")

	# 6) relic 事件改残页: _apply_effect_dict pages 键
	var pages0 := int(Game.gongfa().get("pages", 0))
	var msg := Game._apply_effect_dict({"pages": 1}, "残页入手")
	_check(int(Game.gongfa().get("pages", 0)) == pages0 + 1 and msg.contains("功法残页"), "relic 事件效果走残页键")

	# 7) 坊市: 购残页 + 整卷购入(残卷态)
	Game.farm().stones = 100000
	pages0 = int(Game.gongfa().get("pages", 0))
	Game.gongfa_page_buy()
	_check(int(Game.gongfa().get("pages", 0)) == pages0 + 1, "坊市购残页 +1(价 %d 灵石)" % Game.gongfa_page_price())
	Game.gongfa_market_buy("zaohuo")
	_check("zaohuo" in Array(Game.gongfa().get("owned", [])), "坊市整卷购入灶火纯青功(残卷态)")

	# 8) 老档兼容: 旧版本档形(完整结构、仅缺新键 gongfa) → _ensure_run 补默认, tech 原值(恒 1.0)不动
	var saved_run: Dictionary = Game.run
	var old_shape: Dictionary = saved_run.duplicate(true)
	old_shape.erase("gongfa")
	old_shape.tech = 1.0
	Game.run = old_shape
	Game._ensure_run()
	_check(Game.run.has("gongfa") and absf(float(Game.run.tech) - 1.0) < 1e-6, "老档兼容: 补 gongfa 且 tech 原值不动")
	Game.run = saved_run

	# 9) 道韵残卷跨世: rebirth 扣 50 韵, 新世开局残页 ×5
	Game.meta.dao = 500
	Game.rebirth({}, 0, 0, {}, [], true, Game.SCROLL_PAGES)
	_check(int(Game.meta.dao) == 500 - Game.SCROLL_COST, "道韵残卷: 转世扣 %d 韵" % Game.SCROLL_COST)
	_check(int(Game.gongfa().get("pages", 0)) == Game.SCROLL_PAGES, "新世开局自带残页 ×%d" % Game.SCROLL_PAGES)
	_check(absf(float(Game.run.tech) - 1.0) < 1e-6, "新世 tech 复位 1.0(功法一世清零, 靠残卷接力)")

	# 10) 月度 tick 接线: tick_month 内研席逐月推进(新世重新合成开研)
	Game.gongfa_synthesize("qingmu")
	Game.gongfa_study("qingmu")
	var prog0 := float((Game.gongfa().get("prog", {}) as Dictionary).get("qingmu", 0.0))
	Game.tick_month()
	_check(absf(float((Game.gongfa().get("prog", {}) as Dictionary).get("qingmu", 0.0)) - (prog0 + Game.research_mult())) < 1e-6, "月度 tick 推进研席(+%.2f 有效研月)" % Game.research_mult())

	# 11) 坊市杂货(v2.9.6): 开垦吃自种灵植(「灵材」设定取消, 便宜先扣); 设施回纯灵石价; 突破丹不限购叠购
	Game.farm().stones = 100000
	Game.run.realm = 2   # 金丹: 地块上限 3 —— 开得动第 2 块
	var sid_c := String(DataManager.seeds[0].id)
	var sid_d := String(DataManager.seeds[1].id)
	if float(DataManager.seeds[1].price) < float(DataManager.seeds[0].price):
		sid_c = String(DataManager.seeds[1].id)
		sid_d = String(DataManager.seeds[0].id)
	Game.farm().inv = {sid_c: {"凡": 2}, sid_d: {"凡": 2}}
	var plots0 := Game.farm_open_count()
	var cost0 := Game.farm_reclaim_cost()   # 先捕获价档: 开垦后已开块数+1, 再取会跳档
	var stones0 := int(Game.farm().stones)
	Game.farm_reclaim()
	_check(Game.farm_open_count() == plots0 + 1 and int(Game.farm().stones) == stones0 - cost0 and Game.farm_inv_total() == 2, "开垦吃灵植: 扣灵石 %d + 自种灵植 %d 株" % [cost0, Game.farm_reclaim_crops()])
	_check(int((Game.farm().inv.get(sid_c, {}) as Dictionary).get("凡", 0)) == 0 and int((Game.farm().inv.get(sid_d, {}) as Dictionary).get("凡", 0)) == 2, "便宜品种先扣光, 贵品种保留")
	Game.farm().inv = {sid_d: {"凡": 1}}
	Game.farm_reclaim()
	_check(Game.farm_open_count() == plots0 + 1, "灵植不足: 开垦被挡(存 1 < 需 %d)" % Game.farm_reclaim_crops())
	Game.farm().inv = {}
	var lv0 := int(Game.run.facilities.julingzhen)
	Game.cave_upgrade("julingzhen")
	_check(int(Game.run.facilities.julingzhen) == lv0 + 1, "设施升级回纯灵石价(灵材设定取消)")
	Game.farm().stones = 0
	Game.cave_upgrade("julingzhen")
	_check(int(Game.run.facilities.julingzhen) == lv0 + 1, "灵石不足: 设施升级被挡")
	Game.farm().stones = 100000
	Game.run.buffs.erase("check_pct")   # 清场: 单变量验证突破丹
	var pp0 := Game.pill_price()
	_check(pp0 > int(Game.econ("pill_price", 500)), "丹价随境界水涨: 金丹 %d > 炼气基价 %d" % [pp0, int(Game.econ("pill_price", 500))])
	var stones1 := int(Game.farm().stones)
	var bc1 := Game.break_chance()
	Game.pill_buy()
	var bc2 := Game.break_chance()
	_check(int(Game.farm().stones) == stones1 - pp0, "购突破丹按境界价扣灵石(%d)" % pp0)
	_check(absf((bc2 - bc1) - float(Game.econ("pill_bonus", 0.10))) < 1e-6, "购突破丹: +%.0f%% 进突破率" % (float(Game.econ("pill_bonus", 0.10)) * 100.0))
	var stones2 := int(Game.farm().stones)
	Game.pill_buy()
	_check(int(Game.farm().stones) == stones2 - pp0 and absf(Game._buff_pct("check_pct") - 2.0 * float(Game.econ("pill_bonus", 0.10))) < 1e-6, "不限购: 第二枚照价扣款, buff 叠至 +%.0f%%" % (2.0 * float(Game.econ("pill_bonus", 0.10)) * 100.0))
	var realm0 := int(Game.run.realm)
	Game._do_breakthrough()   # deterministic → 必成
	_check(int(Game.run.realm) == realm0 + 1 and not Game.run.buffs.has("check_pct"), "冲关成功: 消费检定 buff(已叠各枚一并清算)")
	_check(Game.pill_price() > pp0, "破境后丹价再涨: 元婴 %d > 金丹 %d" % [Game.pill_price(), pp0])

	# 12) UI 冒烟: 五 App 实例化构建(库房功法栏/坊市货架/图鉴功法位/藏经阁文案/转世卡残卷柜)不崩
	var apps := {
		"storage": preload("res://scripts/apps/app_storage.gd"),
		"market": preload("res://scripts/apps/app_market.gd"),
		"codex": preload("res://scripts/apps/app_codex.gd"),
		"cave": preload("res://scripts/apps/app_cave.gd"),
		"lifestone": preload("res://scripts/apps/app_lifestone.gd"),
	}
	for app_id in apps:
		var page: Control = (apps[app_id] as GDScript).new()
		page.setup(String(app_id), String(app_id), ["storage", "market", "codex", "cave", "lifestone"])
		add_child(page)   # 入树即 _ready → _build_content(含功法各区块)
		page.free()
	_check(true, "五 App 构建不崩(功法栏/货架/图鉴/藏经阁/转世卡)")

	print("== gongfa_smoke: %s (%d FAIL) ==" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fails += 1
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
