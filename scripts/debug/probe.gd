extends Node
func _ready() -> void:
	var P: MorphBall = get_parent().player
	for i in 16:
		await get_tree().create_timer(0.5).timeout
		print("t=%.1f pos=%s grounded=%s chunks=%d" % [i * 0.5, P.global_position, P.grounded, get_parent().world.get_child_count()])
	get_tree().quit()
