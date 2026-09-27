class_name ObjectiveZone
extends Zone
## 进入区域时推进目标（只会前进，不会倒退）

@export var index := 0
@export var text := ""
@export var marker := Vector3.INF

func _on_player_entered() -> void:
	GameState.set_objective(index, text, marker)
