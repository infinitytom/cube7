class_name EditorLevel
extends LevelBase
## 关卡编辑器用的“关卡”：按 LevelData 搭体素世界；试玩时把物件（敌人、金币、机关……）生成出来，退出试玩时全部清掉、世界还原。

signal goal_reached

var data: LevelData
var _play: Node3D
var _snapshot: PackedByteArray
var _snap_shapes: PackedByteArray

func build() -> void:
	world = get_node(world_path) as VoxelWorld
	GameState.reset_for_level([true, true, true] as Array[bool], true, -2.0, 0)
	GameState.seeds_total = 0
	decor = Decor.new()
	add_child(decor)
	decor.setup(world)
	Atmosphere.apply(self, "greenhouse")
	var sky := SkyWorld.new()
	sky.center = Vector3(LevelData.SIZE.x, 0, LevelData.SIZE.z) * VoxelWorld.CELL_M * 0.5
	sky.sea_height = -20.0
	add_child(sky)
	if data == null:
		data = LevelData.new_default()
	load_data(data)

func load_data(d: LevelData) -> void:
	data = d
	world.setup(LevelData.SIZE)
	for c: Vector3i in d.blocks:
		world.set_block(c, d.blocks[c])
	world.rebuild_all()

func spawn_position() -> Vector3:
	var i := data.find_object("spawn")
	var c: Vector3i = data.objects[i].cell if i >= 0 else Vector3i(LevelData.SIZE.x / 2, LevelData.BASE_Y, LevelData.SIZE.z / 2)
	return world.voxel_top(c + Vector3i.DOWN) + Vector3.UP * 0.55

# ================================================================ 试玩

func start_play() -> void:
	_snapshot = world.data.duplicate()
	_snap_shapes = world.shapes.duplicate()
	world.track_damage = false
	_play = Node3D.new()
	_play.name = "Play"
	add_child(_play)
	GameState.reset_for_level([true, true, true] as Array[bool], true, -2.0, 0)
	var seeds := 0
	for o in data.objects:
		var c: Vector3i = o.cell
		match str(o.id):
			"goal":
				var g := _zone(Zone, c + Vector3i(-1, 0, -1), c + Vector3i(1, 2, 1))
				g.player_entered.connect(func() -> void: goal_reached.emit())
				var beacon := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.1
				cm.bottom_radius = 0.6
				cm.height = 4.0
				beacon.mesh = cm
				var m := StandardMaterial3D.new()
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				m.albedo_color = Color(1.0, 0.85, 0.3, 0.5)
				beacon.material_override = m
				_play.add_child(beacon)
				beacon.global_position = world.voxel_top(c + Vector3i.DOWN) + Vector3.UP * 2.0
			"checkpoint":
				_zone(Checkpoint, c + Vector3i(-1, 0, -1), c + Vector3i(1, 2, 1))
			"coin":
				var sc := StaticCoin.new()
				_play.add_child(sc)
				sc.global_position = world.voxel_center(c) + Vector3.UP * 0.25
			"coin_ring":
				for k in 8:
					var a := k * TAU / 8.0
					var sc2 := StaticCoin.new()
					_play.add_child(sc2)
					sc2.global_position = world.voxel_center(c) + Vector3(cos(a), 0.25, sin(a)) * 1.2
			"chest":
				_zone(TreasureChest, c, c, {"coins": 20, "energy": 3})
			"seed":
				var s := SeedCube.new()
				s.seed_id = ""
				s.line_index = seeds % 4
				_play.add_child(s)
				s.global_position = world.voxel_top(c + Vector3i.DOWN)
				seeds += 1
			"bounce":
				_zone(BouncePad, c + Vector3i(-1, 0, -1), c + Vector3i(1, 1, 1), {"launch": Vector3(0, 13.0, 0)})
			"fan":
				_zone(Fan, c + Vector3i(-1, 0, -1), c + Vector3i(1, 12, 1), {"strength": 4.2, "max_rise_speed": 4.0})
			"scrapling":
				_enemy(Scrapling.new(), c)
			"rustfly":
				_enemy(Rustfly.new(), c, 2.0)
			"spikeshell":
				_enemy(Spikeshell.new(), c)
			"sentinel":
				_enemy(Sentinel.new(), c)
			"mortar":
				_enemy(Mortar.new(), c)
			"burrower":
				_enemy(Burrower.new(), c)
	GameState.seeds_total = seeds
	GameState.seeds_changed.emit(0)
	GameState.set_checkpoint(spawn_position())
	world.track_damage = true

func stop_play() -> void:
	if is_instance_valid(_play):
		_play.queue_free()
	for n in get_tree().get_nodes_in_group("projectile"):
		n.queue_free()
	for n in get_tree().get_nodes_in_group("usable_item"):
		n.queue_free()
	for c in world.get_children():
		if c is VoxelChunk or c is VoxelRebuilder:
			c.queue_free()
	world.track_damage = false
	world.damage.clear()
	# 世界还原成试玩前的样子（拆掉的、烧掉的都回来）
	if not _snapshot.is_empty():
		world.data = _snapshot
		world.shapes = _snap_shapes
		world.rebuild_all()

func _zone(script: GDScript, a: Vector3i, b: Vector3i, props := {}) -> Node:
	var z := zone(script, a, b, props)
	z.reparent(_play)
	return z

func _enemy(e: Node3D, c: Vector3i, lift := 0.0) -> void:
	_play.add_child(e)
	e.global_position = world.voxel_top(c + Vector3i.DOWN) + Vector3.UP * (0.05 + lift)
	e.rotation.y = randf() * TAU
