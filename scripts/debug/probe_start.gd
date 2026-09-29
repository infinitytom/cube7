extends Node
## 开局检查：有没有敌人一出生就掉下去 / 死掉
func _ready() -> void:
	var init := {}
	for e in get_tree().get_nodes_in_group("enemy"):
		init[e] = (e as Node3D).global_position
	var dead := []
	for e in init:
		if e.has_signal("defeated"):
			e.defeated.connect(func(x: Node) -> void: dead.append([x.get_script().resource_path.get_file(), init[x]]))
	await get_tree().create_timer(3.0).timeout
	var fell := 0
	for e in init:
		if is_instance_valid(e) and (e as Node3D).global_position.y < init[e].y - 2.0:
			print("FELL ", e.get_script().resource_path.get_file(), " from ", init[e], " to ", (e as Node3D).global_position)
			fell += 1
	for d in dead:
		print("DIED ", d[0], " spawned at ", d[1])
	print("CH%d enemies=%d died=%d fell=%d" % [GameState.chapter, init.size(), dead.size(), fell])
	get_tree().quit()
