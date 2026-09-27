class_name MusicZone
extends Zone
## 音乐区域：玩家在区域内时切换音乐状态（例如解谜时淡出旋律），离开后恢复

@export var state := "puzzle"

func _build() -> void:
	body_exited.connect(func(body: Node3D) -> void:
		if body == GameState.player:
			Music.set_override(""))

func _on_player_entered() -> void:
	Music.set_override(state)
