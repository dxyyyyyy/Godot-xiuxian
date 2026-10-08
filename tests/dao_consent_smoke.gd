extends Node
## 道侣之约冒烟: stage4 情缘满闸满 → 弹「道侣之约」框(时钟暂停)由主角应允/婉拒;
## 婉拒零惩罚、闸重置可再提; 应允即成道侣(不掷骰); 道侣位已占走原静默路径;
## deterministic 回归档静默自动应允不挂起。
## 安全: 不调 new_game、不碰真实存档 —— run 副本上合成名册并停时钟。

var _fails := 0


func _chk(name: String, ok: bool) -> void:
	print(("PASS: " if ok else "FAIL: ") + name)
	if not ok:
		_fails += 1


## 合成一名入册成年男 NPC(节点只对男性弹, 随机性别会漏, 一律置男)
func _make_npc(fid: String) -> String:
	var e := Game._npc_init()
	e.merge(Game.npc_generator.generate(Game.rng, Game.run.npcs, [fid]), true)
	e.met = true
	e.gender = "male"
	e.love = 1000.0
	e.stage = 4
	e.gate = int(Game.tune("gate_months", 24))   # 闸长随 tuning(拉长恋爱线后 24→48), 不硬编码
	var key := String(e.key)
	Game.run.npcs[key] = e
	Game._npc_vitals_backfill(e, key)
	return key


func _asked() -> bool:
	return not Game.pending.is_empty() and String(Game.pending.kind) == "node" and bool(Game.pending.data.get("dao_ask", false))


func _ready() -> void:
	Game.set_process(false)   # 停时钟: 无 tick、无自动存盘
	Game.run = Game.run.duplicate(true)
	Game.run.npcs = {}   # 清场: 只留本测合成者, 防真实档 NPC 抢先触发事件
	var male := _make_npc("tongming")
	Game.speed = 5

	# ① 弹框挂起: kind=node + dao_ask, 时钟暂停
	Game._npc_prompt_check()
	_chk("道侣之约弹框挂起", _asked())
	_chk("弹框暂停时钟", Game.speed == 0)

	# ② 婉拒: 零惩罚, 闸重置, 时钟恢复
	var love_before := float(Game.run.npcs[male].love)
	Game.resolve_option(1)
	_chk("婉拒不结道侣", int(Game.run.npcs[male].stage) == 4 and not bool(Game.run.npcs[male].get("dao_lu", false)))
	_chk("婉拒不扣情分", is_equal_approx(float(Game.run.npcs[male].love), love_before))
	_chk("婉拒时光闸重置", int(Game.run.npcs[male].gate) == 0)
	_chk("婉拒后时钟恢复", Game.speed == 5 and Game.pending.is_empty())

	# ③ 再提再应允: 即成道侣(不掷骰)
	Game.run.npcs[male].gate = int(Game.tune("gate_months", 24))
	Game._npc_prompt_check()
	var re_ask := _asked()
	_chk("婉拒后可再度提起", re_ask)
	if re_ask:
		Game.resolve_option(0)
	_chk("应允即成道侣", int(Game.run.npcs[male].stage) == 5 and bool(Game.run.npcs[male].get("dao_lu", false)))
	_chk("应允后时钟恢复", Game.speed == 5 and Game.pending.is_empty())

	# ④ 道侣位已占: 另一 NPC 达阈走原静默路径(不弹框, 唯一位守卫拒绝推进)
	var other := _make_npc("fangshi")
	Game._npc_prompt_check()
	_chk("唯位时不弹道侣之约", Game.pending.is_empty())
	_chk("唯位时另一人推进被拒", int(Game.run.npcs[other].stage) == 4 and not bool(Game.run.npcs[other].get("dao_lu", false)))

	# ⑤ deterministic 回归档: 静默自动应允, 不挂起
	Game.deterministic = true
	Game.run.npcs = {}
	var det := _make_npc("jianpai")
	Game._npc_prompt_check()
	_chk("deterministic静默自动应允", Game.pending.is_empty() and int(Game.run.npcs[det].stage) == 5 and bool(Game.run.npcs[det].get("dao_lu", false)))
	Game.deterministic = false

	print("DAO_CONSENT " + ("PASS" if _fails == 0 else "FAIL(%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)
