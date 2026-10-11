extends Node
const TestGuard := preload("res://tests/test_guard.gd")
## 三生石转世卡冒烟: 铸体/天道眷顾柜位接通(落幕文案「可炼灵根、铸体、纳眷顾」补齐) ——
## 步进落账、预算链(+ 钳制同步扣除炼灵根/特质费)、每次转世限购 5、提交扣款与属性落账、
## rebirth 柜位钳制兜底(超 5/负数收到 [0,5])。
## 运行: bash tools/run_tests.sh lifestone(会写盘, 必须经隔离入口)。

var _fails := 0


func _ready() -> void:
	if not TestGuard.ensure_isolated("LIFESTONE_SMOKE"):
		get_tree().quit(2)
		return
	Game.debug_seed(71)
	Game.new_game()
	Game.speed = 0
	Game.deterministic = false
	GameState.fresh_start = true          # 开始界面同款: 三生石落到转世卡(入世·第 1 世)
	var app: Control = load("res://scripts/apps/app_lifestone.gd").new()
	add_child(app)
	await get_tree().process_frame

	# 1) 卡上六个 + 钮(铸体/灵窍/悟道/寿基/田诀/眷顾), 开局 100 韵(五行根免费/无特质)各起价皆可加
	var plus := _plus_btns(app)
	_check(plus.size() == 6, "转世卡六个 + 钮: 铸体+永久位四货架+眷顾(实得 %d)" % plus.size())
	_check(_all_enabled(plus), "开局 100 韵: 六行起价 20/80/50/80/60/50 皆 ≤100, + 均可用")

	# 2) 预算链: 铸体×1+眷顾×1=70 → 眷顾再 +(120>100)置灰、铸体 +(90≤100)可用; 铸体加到 ×2(90)后双双置灰
	app._step_forge(1)
	app._step_bless(1)
	plus = _plus_btns(app)
	_check(not plus[0].disabled, "70/100: 铸体 + 可用(90≤100)")
	_check(plus[5].disabled, "70/100: 眷顾 + 置灰(120>100)")
	app._step_forge(1)
	plus = _plus_btns(app)
	_check(plus[0].disabled and plus[5].disabled, "90/100: 铸体/眷顾 + 均置灰(再任加即超支)")
	app._step_forge(-1)
	plus = _plus_btns(app)
	_check(not plus[0].disabled and plus[5].disabled, "退一格: 铸体 + 复活, 眷顾 + 仍锁")

	# 3) 特质费入链(预算链与炼灵根同构): 订剑骨 60 → 130>100, 各 + 与转世钮全灰; 退订恢复
	app._toggle_trait("jian")
	plus = _plus_btns(app)
	_check(plus[0].disabled and plus[5].disabled, "订剑骨 60 → 合计 130: 铸体/眷顾 + 置灰")
	var go := _go_btn(app)
	_check(go != null and go.disabled, "超支时转世钮置灰")
	app._toggle_trait("jian")
	plus = _plus_btns(app)
	go = _go_btn(app)
	_check(not plus[0].disabled and go != null and not go.disabled, "退订剑骨: 转世钮复活")

	# 4) 限购 5: 道韵管够时铸体连点 7 次止于 5, + 钮封顶置灰; 步进函数自钳不过 5
	Game.meta.dao = 600
	app._rebuild()
	for i in 7:
		app._step_forge(1)
	_check(app._forge_n == 5, "铸体限购 5(连点 7 次止于 5, 实得 %d)" % app._forge_n)
	plus = _plus_btns(app)
	_check(plus[0].disabled, "铸体 ×5 封顶: + 置灰")
	_check(not plus[5].disabled, "眷顾未封顶: + 可用")

	# 5) 提交: 眷顾再 +1 → 入世; 扣款 5×20+2×50=200, 灵根系数 0.65+0.50, 眷顾累计 +4%, 订购清零
	app._step_bless(1)
	_check(app._bless_n == 2, "眷顾 ×2 待提交")
	app._enter_world()
	_check(int(Game.meta.dao) == 400, "扣款 100+100=200 → 余 400(实得 %d)" % int(Game.meta.dao))
	_check(absf(float(Game.run.root) - 1.15) < 1e-6, "铸体×5 落账: 灵根系数 0.65+0.50=1.15(实得 %.2f)" % float(Game.run.root))
	_check(absf(float(Game.meta.bless_pct) - 0.04) < 1e-9, "眷顾×2 落账: 永久冲关率 +4%")
	_check(app._forge_n == 0 and app._bless_n == 0, "提交后订购清零")

	# 6) rebirth 柜位钳制兜底: 超 5 与负数都收到 [0,5]
	Game.meta.dao = 2000
	Game.rebirth(DataManager.origins[0], 99, 99)
	_check(int(Game.meta.dao) == 1650, "99/99 钳到 5/5: 扣 350 → 余 1650(实得 %d)" % int(Game.meta.dao))
	_check(absf(float(Game.run.root) - 1.15) < 1e-6, "铸体×5: 灵根系数 1.15")
	_check(absf(float(Game.meta.bless_pct) - 0.14) < 1e-9, "眷顾累计 2+5 次 → +14%")
	Game.rebirth(DataManager.origins[0], -3, -2)
	_check(int(Game.meta.dao) == 1650 and absf(float(Game.meta.bless_pct) - 0.14) < 1e-9, "负数钳到 0: 分文不动")

	# 7) 永久位货架落账: 灵窍×2 阶梯价 80+120=200 → 提交层数 +2、聚灵乘区 +20%、暂存清零
	Game.meta.dao = 500
	app._rebuild()
	app._step_meta("lingqiao", 2)
	_check(int(app._meta_n["lingqiao"]) == 2 and app._meta_pending() == 200, "灵窍×2 暂存: 阶梯价 80+120=200(实得 %d)" % app._meta_pending())
	app._enter_world()
	_check(Game.meta_bought("lingqiao") == 2, "灵窍×2 落账: 层数 2")
	_check(int(Game.meta.dao) == 300, "扣款 200 → 余 300(实得 %d)" % int(Game.meta.dao))
	_check(int(app._meta_n["lingqiao"]) == 0, "提交后永久位暂存清零")
	_check(absf(Game.meta_fx("lingqiao") - 0.20) < 1e-9, "灵窍效果换算: 聚灵 +20%")

	# 8) 封顶与跨世保留: meta_buys 全 99 → 各钳 10 层(+100%/+20 年), 扣款=满层阶梯总价; 负数分文不动
	Game.meta.dao = 99999
	var expect := 0
	for k in Game.META_SHELF_ORDER:
		expect += Game.meta_price_batch(String(k), Game.meta_cap(String(k)) - Game.meta_bought(String(k)))   # 各货架补到满层的阶梯总价
	Game.rebirth(DataManager.origins[0], 0, 0, {}, [], true, 0, {"lingqiao": 99, "wudao": 99, "shouyuan": 99, "tianchan": 99})
	for k in Game.META_SHELF_ORDER:
		_check(Game.meta_bought(String(k)) == 10, "%s 满 10 层(实得 %d)" % [String(Game.META_SHELF_NAME[String(k)]), Game.meta_bought(String(k))])
	_check(int(Game.meta.dao) == 99999 - expect, "满层扣款 %d → 余 %d(实得 %d)" % [expect, 99999 - expect, int(Game.meta.dao)])
	_check(absf(Game.meta_fx("wudao") - 1.0) < 1e-9 and absf(Game.meta_fx("shouyuan") - 20.0) < 1e-9, "效果封顶: 悟道 +100% / 寿基 +20 年")
	app._rebuild()
	_check(not app._meta_can_plus("lingqiao"), "满层后 + 钳制: can_plus=false")
	app._step_meta("lingqiao", 1)
	_check(int(app._meta_n["lingqiao"]) == 0, "满层步进自钳: 暂存仍 0")
	Game.rebirth(DataManager.origins[0], 0, 0, {}, [], true, 0, {"lingqiao": -3})
	_check(Game.meta_bought("lingqiao") == 10 and int(Game.meta.dao) == 99999 - expect, "负数再订: 分文不动、层数不降")

	print("== lifestone_smoke: %s (%d FAIL) ==" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


## 深度收集转世卡上的 + 钮(铸体行先加入树, 眷顾行在后)。
func _plus_btns(root: Node) -> Array:
	var out: Array = []
	_walk(root, func(n: Node) -> void:
		if n is Button and (n as Button).text == "+":
			out.append(n))
	return out


func _go_btn(root: Node) -> Button:
	var hit: Array = []
	_walk(root, func(n: Node) -> void:
		if n is Button and ((n as Button).text.begins_with("入世") or (n as Button).text.begins_with("转世")):
			hit.append(n))
	return null if hit.is_empty() else (hit[0] as Button)


func _walk(n: Node, cb: Callable) -> void:
	for c in n.get_children():
		cb.call(c)
		_walk(c, cb)


func _all_enabled(btns: Array) -> bool:
	for b in btns:
		if (b as Button).disabled:
			return false
	return true


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fails += 1
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
