class_name EnergyCircuit
extends Node
## 能量回路：能量源通过相邻的导电方块（水晶/金属）连到接收器时，打开能量门。
## 通电后门保持打开，避免把玩家关在里面（防挫败）。

signal powered

var world: VoxelWorld
var source := Vector3i.ZERO
var receiver := Vector3i.ZERO
var door_blocks: Array[Vector3i] = []
var opened := false
var _queued := false

func setup(w: VoxelWorld, src: Vector3i, rcv: Vector3i, doors: Array[Vector3i]) -> void:
	world = w
	source = src
	receiver = rcv
	door_blocks = doors
	world.block_changed.connect(_on_changed)

func _on_changed(_p: Vector3i, _o: int, _n: int) -> void:
	if not opened and not _queued:
		_queued = true
		_check.call_deferred()

func _check() -> void:
	_queued = false
	if opened or not is_connected_path():
		return
	opened = true
	world.set_block(receiver, Blocks.RECEIVER_ON)
	for p in door_blocks:
		world.try_break_any(p)
	GameState.shake.emit(0.3)
	GameState.say("回路接通！能量门打开了。")
	powered.emit()

## 在能量源与接收器的包围盒内做广度优先搜索
func is_connected_path() -> bool:
	var lo := Vector3i(mini(source.x, receiver.x), mini(source.y, receiver.y), mini(source.z, receiver.z)) - Vector3i.ONE * 8
	var hi := Vector3i(maxi(source.x, receiver.x), maxi(source.y, receiver.y), maxi(source.z, receiver.z)) + Vector3i.ONE * 8
	var seen := {source: true}
	var queue: Array[Vector3i] = [source]
	while not queue.is_empty():
		var p: Vector3i = queue.pop_back()
		if p == receiver:
			return true
		for d in VoxelWorld.DIRS:
			var q: Vector3i = p + d
			if seen.has(q) or q.x < lo.x or q.y < lo.y or q.z < lo.z or q.x > hi.x or q.y > hi.y or q.z > hi.z:
				continue
			seen[q] = true
			if Blocks.conductive[world.get_block(q)] == 1:
				queue.append(q)
	return false
