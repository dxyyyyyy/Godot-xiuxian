extends Node
const TestGuard := preload("res://tests/test_guard.gd")
## 坊市布局探针(调试工具, 不在默认集): 以真实视口宽(448×960, ScrollContainer 横向滚动已禁用)
## 实例化坊市页, 逐 Control 检查右缘是否越出屏宽 —— 复现/回归「最右买入按钮被挤出界」。
## 最坏文案态: 已加持检定 buff(丹药行描述最长)。
## 运行: bash tools/run_tests.sh market_layout_probe

func _ready() -> void:
	if not TestGuard.ensure_isolated("MARKET_LAYOUT_PROBE"):
		get_tree().quit(2)
		return
	Game.debug_seed(7)
	Game._start_life(DataManager.origins[0], 0)
	Game.speed = 0
	Game.deterministic = true
	Game.farm().stones = 100000
	Game.pill_buy()                # 已加持检定 buff → 丹药行描述最长

	var host := Control.new()
	host.size = get_viewport().get_visible_rect().size
	add_child(host)
	var page: Control = preload("res://scripts/apps/app_market.gd").new()
	page.setup("market", "坊市", ["market"])
	host.add_child(page)
	await get_tree().process_frame
	await get_tree().process_frame

	var limit := host.size.x
	var offenders: Array = []
	_scan(page, limit, offenders)
	var fail := ""
	if not offenders.is_empty():
		fail = "展开态 %d 个控件右缘越界(屏宽 %.0f)" % [offenders.size(), limit]
		for o in offenders:
			print("  - %s right=%.0f「%s」" % [o.cls, o.right, o.text])
	# 折叠全部分类再扫: 折叠重建不崩、4 个内容体隐藏、隐藏体不计越界
	for k in ["ledger", "seeds", "scroll", "pill"]:
		page._folded[k] = true
	page._rebuild()
	await get_tree().process_frame
	await get_tree().process_frame
	var hidden := _count_hidden(page)
	var offenders2: Array = []
	_scan(page, limit, offenders2)
	if not offenders2.is_empty():
		fail += "折叠态 %d 个可见控件右缘越界" % offenders2.size()
	if hidden != 4:
		fail += "折叠后隐藏内容体 %d ≠ 4" % hidden
	if fail == "":
		print("MARKET_LAYOUT_PROBE PASS: 展开/折叠两态均无越界(屏宽 %.0f), 4 区块可折叠" % limit)
		get_tree().quit(0)
	else:
		print("MARKET_LAYOUT_PROBE FAIL: %s" % fail)
		get_tree().quit(1)


func _scan(node: Node, limit: float, out: Array) -> void:
	for c in node.get_children():
		var ctrl := c as Control
		if ctrl != null and ctrl.is_visible_in_tree():
			var right := ctrl.global_position.x + ctrl.size.x
			if right > limit + 1.0:
				var txt := ""
				var lbl := ctrl as Label
				if lbl != null:
					txt = lbl.text
				elif ctrl is Button:
					txt = (ctrl as Button).text
				out.append({"cls": ctrl.get_class(), "right": right, "text": txt})
		_scan(c, limit, out)


func _count_hidden(node: Node) -> int:
	var n := 0
	for c in node.get_children():
		var ctrl := c as Control
		if ctrl != null and not ctrl.visible and ctrl is VBoxContainer:
			n += 1
		n += _count_hidden(c)
	return n
