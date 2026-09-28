extends SceneTree
func _init():
	var b = load("res://scripts/puzzles/turn_bridge.gd").new()
	b.dir = 1
	root.add_child(b)
	print("after ", b.rotation.y)
	quit()
