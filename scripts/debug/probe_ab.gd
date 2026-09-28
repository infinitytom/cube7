extends Node
func _ready() -> void:
	var main := get_parent()
	var W: VoxelWorld = main.world
	await get_tree().create_timer(0.5).timeout
	for z in [70, 71, 72]:
		var col := []
		for y in range(10, 40):
			col.append("%d:%d" % [y, W.get_block(Vector3i(115, y, z))])
		print("z=", z, " ", " ".join(col))
	get_tree().quit()
