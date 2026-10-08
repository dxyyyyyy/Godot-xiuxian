extends Node
## 修罗场概率数学冒烟(只读系: 不 new_game 不写档): 验证 v2.7 量纲修复 ——
## 性格修正表值单位为百分点(±5), 进概率前必须 ÷100; 旧代码原样相加致检定恒真/恒假。

var _fails := 0

func _chk(name: String, ok: bool) -> void:
	print(("PASS: " if ok else "FAIL: ") + name)
	if not ok:
		_fails += 1

func _ready() -> void:
	var tbl: Dictionary = Game.tune("luochang_tag_fix", {})
	# 1) 表口径: 修正值是个位数量级的百分点(±9 内), 出现 ≥10 即量纲再被写错
	var unit_ok := true
	for k in tbl:
		if absf(float(tbl[k])) > 9.0:
			unit_ok = false
	_chk("tag_fix 表单位为百分点(±9 内)", unit_ok)
	# 2) 组装公式: 基础 55% + 现段位 +5pp
	_chk("零修正 p=0.60(55+5)", is_equal_approx(Game._luochang_p(0.0), 0.60))
	# 3) 两枚 +5(如 心软+软糯) → +10pp
	_chk("双正修正 p=0.70", is_equal_approx(Game._luochang_p(10.0), 0.70))
	# 4) 两枚 −5(如 直球+嘴毒) → −10pp
	_chk("双负修正 p=0.50", is_equal_approx(Game._luochang_p(-10.0), 0.50))
	# 5) 极端输入被钳在 [0,1]: 旧 bug 在此给出 10.05 / −4.4 之类的非法概率
	_chk("极端正钳到 1.0", Game._luochang_p(999.0) <= 1.0)
	_chk("极端负钳到 0.0", Game._luochang_p(-999.0) >= 0.0)
	# 6) 真实档案查表: 温半夏(嘴毒 −5 + 口嫌体正直 0) → fix=−5, p=0.55
	var fx := Game.luochang_fix("yaoshi")
	_chk("档案查表 fix=−5", is_equal_approx(fx, -5.0))
	_chk("经查表 p=0.55", is_equal_approx(Game._luochang_p(fx), 0.55))
	print("LUOCHANG_MATH_SMOKE %s" % ("PASS" if _fails == 0 else "FAIL(%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)
