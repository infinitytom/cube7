class_name TalkTrigger
extends Zone
## 进入区域时 NOVA 说一次话。文字中的 {jump} {ability} 等会替换成当前设备的按键

@export_multiline var lines: PackedStringArray = []
var _done := false

func _on_player_entered() -> void:
	if _done:
		return
	_done = true
	for l in lines:
		GameState.say(l)
