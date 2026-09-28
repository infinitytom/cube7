class_name ChapterLevel
extends LevelBase
## 第三章起的关卡公共部分：地面高度表、收集品、敌人、存档恢复、目标与终点。
## 子类实现 _build_world()（搭地形和机关）、_logic()（放敌人、对话、目标）、spawn_cell()。

var heights := {}
var backdrop := false
var enemies: Array[Node3D] = []
var fragments := {}
var seeds := {}
var vista: Vista
var form_core: Node
var chapter_id := ""
var fragment_count := 3
var seed_count := 4
var forms_at_start: Array[bool] = [true, true, true]
var kill_height := 1.0
var _beams: Array[Node3D] = []

func spawn_cell() -> Vector3i:
	return Vector3i.ZERO

func spawn_position() -> Vector3:
	return world.voxel_top(spawn_cell() + Vector3i.DOWN) + Vector3.UP * 0.55

func build() -> void:
	world = get_node(world_path) as VoxelWorld
	if not backdrop:
		GameState.reset_for_level(forms_at_start, true, kill_height, fragment_count)
		GameState.seeds_total = seed_count
	decor = Decor.new()
	add_child(decor)
	decor.setup(world)
	_build_world()
	if backdrop:
		return
	_logic()
	var marker := ObjectiveMarker.new()
	marker.name = "ObjectiveMarker"
	add_child(marker)
	Music.set_default("explore")
	Music.set_override("")
	Music.play_area(Chapters.info(GameState.chapter).music)
	GameState.set_checkpoint(spawn_position())

func _build_world() -> void:
	pass

func _logic() -> void:
	pass

# ---------------------------------------------------------------- 地形工具

func h_at(x: int, z: int) -> int:
	return heights.get(Vector2i(x, z), -1)

func _set_h(x: int, z: int, h: int) -> void:
	heights[Vector2i(x, z)] = h

## 一列：从 bottom 到 top-1 填实，top 是第一层空气
func column(x: int, z: int, bottom: int, top: int, t_top: int, t_mid: int, t_deep: int, mid_depth := 3) -> void:
	world.fill_column(x, z, maxi(bottom, 0), top - mid_depth - 1, t_deep)
	world.fill_column(x, z, maxi(bottom, top - mid_depth), top - 2, t_mid)
	world.fill_column(x, z, top - 1, top - 1, t_top)

func _v(c: Vector3i) -> Vector3:
	return world.voxel_top(c + Vector3i.DOWN)

func objective(i: int, text: String, cell: Vector3i, a: Vector3i, b: Vector3i) -> void:
	zone(ObjectiveZone, a, b, {"index": i, "text": text, "marker": _v(cell)})

func fragment(id: String, cell: Vector3i, text: String) -> void:
	var f := zone(MemoryFragment, cell, cell + Vector3i(0, 1, 0), {"log_text": text})
	f.set("frag_id", id)
	fragments[id] = f

func seed_at(id: String, cell: Vector3i, line: int) -> void:
	var sc := SeedCube.new()
	sc.seed_id = id
	sc.line_index = line
	add_child(sc)
	sc.global_position = world.voxel_top(cell + Vector3i.DOWN)
	seeds[id] = sc

func spawn_enemy(e: Node3D, cell: Vector3i, lift := 0.0) -> Node3D:
	add_child(e)
	e.global_position = world.voxel_top(cell + Vector3i.DOWN) + Vector3.UP * (0.05 + lift)
	e.rotation.y = rng.randf() * TAU
	enemies.append(e)
	return e

func checkpoint(a: Vector3i, b: Vector3i) -> void:
	zone(Checkpoint, a, b)

## 光束发射晶：放在格 cell 的地面上，朝 dir 发光
func beam(cell: Vector3i, dir: Vector3, color := Color(1.0, 0.95, 0.6)) -> LightBeam:
	var b := LightBeam.new()
	b.world = world
	b.dir = dir
	b.color = color
	add_child(b)
	b.global_position = world.voxel_top(cell + Vector3i.DOWN) + Vector3.UP * 0.6
	_beams.append(b)
	return b

func mirror(cell: Vector3i, facing: int) -> BeamMirror:
	var m := BeamMirror.new()
	m.facing = facing
	add_child(m)
	m.global_position = world.voxel_top(cell + Vector3i.DOWN)
	return m

## 塔顶光柱
func tower_beam(top_cell: Vector3i) -> void:
	if vista:
		vista.add_beam(world.voxel_center(top_cell) + Vector3.UP * 0.3, Color(0.45, 1.0, 0.8), 500.0, 0.9)

# ---------------------------------------------------------------- 存档

func apply_save(d: Dictionary) -> void:
	var forms: Array = d.get("forms", [])
	if forms.size() == GameState.unlocked_forms.size():
		for i in forms.size():
			GameState.unlocked_forms[i] = bool(forms[i]) or forms_at_start[i]
	GameState.coins = int(d.get("coins", 0))
	GameState.coins_changed.emit(GameState.coins)
	for id in (d.get("fragments", []) as Array):
		if fragments.has(id) and is_instance_valid(fragments[id]):
			fragments[id].queue_free()
			GameState.fragments += 1
	GameState.fragments_changed.emit(GameState.fragments)
	for id in (d.get("seeds", []) as Array):
		if seeds.has(id) and is_instance_valid(seeds[id]):
			seeds[id].queue_free()
			GameState.seeds += 1
	GameState.seeds_changed.emit(GameState.seeds)
	_apply_flags(d.get("flags", {}))
	var obj := int(d.get("objective", -1))
	if obj >= 0:
		GameState.objective_index = -1
		GameState.set_objective(obj, str(d.get("objective_text", "")), AreaGreenhouse._vec(d.get("objective_pos", null)))

func _apply_flags(_flags: Dictionary) -> void:
	pass
