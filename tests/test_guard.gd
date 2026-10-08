extends RefCounted
## 测试隔离守卫: 会写盘的冒烟必须经 tools/run_tests.sh 运行(APPDATA 重定向临时目录 + BAIWEI_TEST_ISOLATED=1)。
## 裸跑会覆盖真实存档 —— 直接拒绝并提示(2026-10-07 存档被毁教训)。

static func ensure_isolated(test_name: String) -> bool:
	if OS.get_environment("BAIWEI_TEST_ISOLATED") == "1":
		return true
	print("%s FAIL: 未经隔离运行 —— 本测会写真实存档, 请用 tools/run_tests.sh" % test_name)
	return false
