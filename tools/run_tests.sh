#!/usr/bin/env bash
# 百味长生冒烟统一入口: 把 APPDATA 重定向到临时目录 + 打隔离标记, 测试进程绝不碰真实存档。
# 用法:  bash tools/run_tests.sh              # 跑全部 tests/*_smoke
#        bash tools/run_tests.sh root trait   # 只跑指定(省略 _smoke.tscn 后缀)
#        GODOT=/c/.../Godot_console.exe bash tools/run_tests.sh   # 指定引擎路径
# SimReport(重回归)与 *_probe/_tmp 调试工具不在默认集, 需要时显式点名。
set -u
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/e/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64_console.exe}"
export BAIWEI_TEST_ISOLATED=1

if [ $# -gt 0 ]; then
	files=(); for n in "$@"; do
		# 兼容文档口径: 可省略 _smoke 后缀(场景名两种写法都试)
		if [ -f "$PROJ/tests/${n}.tscn" ]; then
			files+=("$PROJ/tests/${n}.tscn")
		elif [ -f "$PROJ/tests/${n}_smoke.tscn" ]; then
			files+=("$PROJ/tests/${n}_smoke.tscn")
		else
			echo "找不到测试场景: tests/${n}(.tscn 或 _smoke.tscn)"; exit 3
		fi
	done
else
	files=("$PROJ"/tests/*_smoke.tscn)
fi

fail=0
for f in "${files[@]}"; do
	t="$(basename "$f" .tscn)"
	# 每测独立 user://: 同批测试互不读到上一个造的世道(共享目录会让读档系测试隐性耦合)
	ISO="$(mktemp -d "$PROJ/.test_userdata.XXXXXX")"
	out="$(APPDATA="$(cygpath -w "$ISO")" BAIWEI_TEST_ISOLATED=1 "$GODOT" --headless --path "$PROJ" --quit-after 1500 "res://tests/${t}.tscn" 2>&1)"
	rc=$?
	rm -rf "$ISO"
	if [ "$rc" -eq 2 ]; then
		echo "== $t SKIP(隔离守卫拒跑: 未设 BAIWEI_TEST_ISOLATED/APPDATA)"
		continue
	fi
	# 退出码为准(冒烟脚本自觉 quit(0/1)), 文本 grep 兜住 Godot 不置码的 SCRIPT ERROR
	if [ "$rc" -ne 0 ] || printf '%s' "$out" | grep -qE ": FAIL|FAIL\(|FAIL: |SCRIPT ERROR"; then
		echo "== $t FAIL(rc=$rc)"; printf '%s' "$out" | grep -E ": FAIL|FAIL\(|FAIL: |SCRIPT ERROR" | head -6; fail=1
	else
		echo "== $t PASS"
	fi
done
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
