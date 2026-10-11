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

	# 1) 卡上有铸体/眷顾两个 + 钮, 开局 100 韵(五行根免费/无特质)两者皆可加
	var plus := _plus_btns(app)
	_check(plus.size() == 2, "转世卡铸体/眷顾两个 + 钮(实得 %d)" % plus.size())
	_check(_all_enabled(plus), "开局 100 韵: 铸体/眷顾 + 均可用")

	# 2) 预算链: 铸体×1+眷顾×1=70 → 眷顾再 +(120>100)置灰、铸体 +(90≤100)可用; 铸体加到 ×2(90)后双双置灰
	app._step_forge(1)
	app._step_bless(1)
	plus = _plus_btns(app)
	_check(not plus[0].disabled, "70/100: 铸体 + 可用(90≤100)")
	_check(plus[1].disabled, "70/100: 眷顾 + 置灰(120>100)")
	app._step_forge(1)
	plus = _plus_btns(app)
	_check(plus[0].disabled and plus[1].disabled, "90/100: 两 + 均置灰(再任加即超支)")
	app._step_forge(-1)
	plus = _plus_btns(app)
	_check(not plus[0].disabled and plus[1].disabled, "退一格: 铸体 + 复活, 眷顾 + 仍锁")

	# 3) 特质费入链(预算链与炼灵根同构): 订剑骨 60 → 130>100, 两 + 与转世钮全灰; 退订恢复
	app._toggle_trait("jian")
	plus = _plus_btns(app)
	_check(plus[0].disabled and plus[1].disabled, "订剑骨 60 → 合计 130: 两 + 置灰")
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
	_check(not plus[1].disabled, "眷顾未封顶: + 可用")

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
