extends Node
## 一次性探针(验完即删): 各固定 NPC 名字在纪事中的出现条数分布。

func _ready() -> void:
	Game.new_game()
	Game.deterministic = true
	for _m in 48:
		Game.tick_month()
		while not Game.pending.is_empty():
			Game.resolve_option(0)
		if Game.is_ended():
			break
	var names := {"jianshu": "季忘川", "yaoshi": "温半夏", "shanjun": "顾青嶂", "moxiu": "幽布衣", "shushu": "书页", "huzhu": "白屠苏"}
	for k in names:
		print(String(names[k]), " = ", Game.chronicle_of(String(k)).size())
	print("chronicle 总条数 = ", GameState.chronicle.size())
	get_tree().quit()
