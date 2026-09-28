class_name PowerGrid
extends Node
## 电网：能量源（SOURCE）沿着相连的导电方块（金属、铜导线、能量水晶、接收器）把电送出去。
## 挨着通电方块的“用电设备”（能量门、升降台、风扇、电网陷阱、灯……）会被接通。
## 导线被钻断、水晶被放进插槽、金属块被推开……网络都会实时重新计算。
## 设备接口：var power_cells: Array[Vector3i]（格坐标），func set_powered(on: bool)

signal changed

var world: VoxelWorld
var lo := Vector3i.ZERO           ## 计算范围（格坐标）
var hi := Vector3i.ZERO
var devices: Array[Node] = []
var powered := {}                 ## 通电的导电格
var _sources := {}
var _queued := false
var _lit := {}

func setup(w: VoxelWorld, region_lo: Vector3i, region_hi: Vector3i) -> void:
	world = w
	lo = region_lo
	hi = region_hi
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var c := Vector3i(x, y, z)
				if world.get_block(c) == Blocks.SOURCE:
					_sources[c] = true
	world.cell_changed.connect(_on_cell_changed)
	_queue()

func add_device(d: Node) -> void:
	devices.append(d)
	_queue()

func _inside(c: Vector3i) -> bool:
	return c.x >= lo.x and c.y >= lo.y and c.z >= lo.z and c.x <= hi.x and c.y <= hi.y and c.z <= hi.z

func _on_cell_changed(c: Vector3i, old: int, new: int) -> void:
	if not _inside(c):
		return
	if new == Blocks.SOURCE:
		_sources[c] = true
	if Blocks.conductive[old] != Blocks.conductive[new] or old == Blocks.SOURCE or new == Blocks.SOURCE:
		_queue()

func _queue() -> void:
	if not _queued:
		_queued = true
		_recompute.call_deferred()

func _recompute() -> void:
	_queued = false
	var seen := {}
	var queue: Array[Vector3i] = []
	for s in _sources.keys():
		if world.get_block(s) == Blocks.SOURCE:
			seen[s] = true
			queue.append(s)
	while not queue.is_empty():
		var p: Vector3i = queue.pop_back()
		for d in VoxelWorld.DIRS:
			var q: Vector3i = p + d
			if seen.has(q) or not _inside(q):
				continue
			if Blocks.conductive[world.get_block(q)] == 1:
				seen[q] = true
				queue.append(q)
	powered = seen
	# 接收器方块：通电时亮起
	for c in seen.keys():
		if world.get_block(c) == Blocks.RECEIVER:
			world.set_block(c, Blocks.RECEIVER_ON)
			_lit[c] = true
	for c in _lit.keys():
		if not seen.has(c):
			_lit.erase(c)
			if world.get_block(c) == Blocks.RECEIVER_ON:
				world.set_block(c, Blocks.RECEIVER)
	for d in devices:
		if not is_instance_valid(d):
			continue
		var on := false
		for c: Vector3i in d.get("power_cells"):
			if seen.has(c):
				on = true
				break
			for dd in VoxelWorld.DIRS:
				if seen.has(c + dd):
					on = true
					break
			if on:
				break
		if bool(d.get("is_powered")) != on:
			d.call("set_powered", on)
	changed.emit()

func is_powered(c: Vector3i) -> bool:
	return powered.has(c)
