extends RefCounted
## WorldSim(GDD §12 / 恋爱系统 §4.3): NPC 关系网月度 tick —— 成对/争风/介绍好友。
## 灰盒实现由 Game._worldsim_tick() 承载(需要 rng/_report/npcs 直通), 本对象保留月度心跳与统计, 供 P2 扩展。

var month_ticks := 0
var pairs := 0
var rivals := 0
var friends := 0

func month_tick(_game) -> void:
	month_ticks += 1

func note_pair() -> void:
	pairs += 1

func note_rival() -> void:
	rivals += 1

func note_friend() -> void:
	friends += 1
