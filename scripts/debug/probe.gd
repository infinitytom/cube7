extends Node
func _ready() -> void:
	var W: VoxelWorld = get_parent().world
	var G := 20
	get_parent().player.debug_override = true
	await get_tree().create_timer(0.5).timeout
	var sup := 0
	for z in range(60, 72):
		for x in range(50, 63):
			if W.get_block(Vector3i(x, G - 1, z)) == Blocks.SUPPORT:
				sup += 1
	print("support before: ", sup)
	W.try_break(Vector3i(51, G, 70), "impact", 10.0)
	for t in [1.0, 3.0, 8.0]:
		await get_tree().create_timer(t - (0.0)).timeout
		var sup2 := 0
		var sand := 0
		for z in range(55, 87):
			for x in range(50, 63):
				if W.get_block(Vector3i(x, G - 1, z)) == Blocks.SUPPORT:
					sup2 += 1
				for y in range(G - 4, G + 7):
					if W.get_block(Vector3i(x, y, z)) == Blocks.SAND:
						sand += 1
		print("t~%.0f support=%d sand_total=%d falling=%d" % [t, sup2, sand, W._falling.size()])
	for z in range(60, 73):
		var row := "z%d " % z
		for y in range(G - 4, G + 3):
			var s := ""
			for x in range(52, 62):
				s += "S" if W.get_block(Vector3i(x, y, z)) == Blocks.SAND else "."
			row += s + " "
		print(row)
	get_tree().quit()
