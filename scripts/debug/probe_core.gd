extends Node
const K = preload("res://scripts/levels/area_core.gd")
func _ready() -> void:
	var W: VoxelWorld = get_parent().world
	await get_tree().create_timer(0.5).timeout
	for i in 12:
		var f := 0.395 + i * 0.005
		var yv := 40 + int(round(f * 56))
		var line := "f=%.3f yv=%d " % [f, yv]
		for r in [13.0, 14.0, 15.0, 15.8, 16.4, 17.0, 17.6]:
			var a: float = K.A0 + f * TAU
			var vx := int(floor((K.C.x + cos(a) * r) * 2))
			var vz := int(floor((K.C.y + sin(a) * r) * 2))
			var col := ""
			for y in range(yv - 2, yv + 5):
				var p := Vector3i(vx, y, vz)
				var t := W.vget(p)
				var sh := W.shapes[p.x + W.size.x * (p.y + W.size.y * p.z)]
				col += "." if t == 0 else ("R" if t == Blocks.RUST else ("C" if t == Blocks.CRATE else ("T" if t == Blocks.TILE else ("H" if t == Blocks.HULL else ("D" if t == Blocks.HULL_DARK else "?")))))
				if sh != 0 and t != 0:
					col += str(sh)
			line += " r%.1f:%s" % [r, col]
		print(line)
	get_tree().quit()
