class_name PowerDoor
extends Node3D
## 电控门：一排能量门方块（格坐标）。通电打开，断电关上（inverted = true 时反过来，比如电网屏障）。
## 关门时如果主角正好站在门里，会等主角离开再关。

@export var inverted := false
var world: VoxelWorld
var cells: Array[Vector3i] = []
var power_cells: Array[Vector3i] = []   ## 挨着哪些格算“接上电”（通常是门框上的接收器）
var is_powered := false
var block := Blocks.DOOR
var _open := false
var _pending_close := false

func setup(w: VoxelWorld, door_cells: Array[Vector3i], power_at: Array[Vector3i]) -> void:
	world = w
	cells = door_cells
	power_cells = power_at
	for c in cells:
		world.set_block(c, block)

func set_powered(on: bool) -> void:
	is_powered = on
	var want_open := on != inverted
	if want_open and not _open:
		_open = true
		_pending_close = false
		for c in cells:
			world.try_break_any(c)
		Sfx.play("unlock", world.voxel_center(cells[0]), -2.0, 0.0)
		GameState.shake.emit(0.15)
	elif not want_open and _open:
		_pending_close = true

func _physics_process(_delta: float) -> void:
	if not _pending_close:
		return
	var pl := GameState.player as Node3D
	if pl:
		for c in cells:
			if world.voxel_center(c).distance_to(pl.global_position) < 0.9:
				return
	_pending_close = false
	_open = false
	for c in cells:
		world.set_block(c, block)
	Sfx.play("clang", world.voxel_center(cells[0]), -4.0, 0.05)
