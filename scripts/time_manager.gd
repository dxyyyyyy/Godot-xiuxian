extends Node
## 游戏时钟：1x 速度下现实 1 秒 = 游戏 1 分钟。
## 所有计时玩法（灵田/烹饪/日程）都以此为准。自动加载单例。

signal minute_ticked

const HOURS_PER_REAL_SECOND := 1.0 / 60.0

var speed := 1.0
var game_hours := 6.0  # 从第 1 天 06:00 开始

var _last_minute := -1


func _process(delta: float) -> void:
	game_hours += delta * speed * HOURS_PER_REAL_SECOND
	var minute := int(game_hours * 60.0)
	if minute != _last_minute:
		_last_minute = minute
		minute_ticked.emit()


func set_speed(v: float) -> void:
	speed = v


func day() -> int:
	return int(game_hours / 24.0) + 1


func clock_text() -> String:
	var t := fmod(game_hours, 24.0)
	return "第 %d 天 %02d:%02d" % [day(), int(t), int(fmod(t, 1.0) * 60.0)]
