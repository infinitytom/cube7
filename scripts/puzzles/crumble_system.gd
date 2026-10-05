class_name CrumbleSystem
extends Node
## 碎裂石板：PIX 滚上去（或落在上面）0.45 秒后，那一格就裂开掉下去；过一会儿（PIX 走远了）再长回来。
## 挂在关卡里一个就够。

var world: VoxelWorld
var delay := 0.45
var regrow := 7.0
var _pending := {}      ## 格 -> 剩余时间
var _gone := {}         ## 格 -> 距离重生的时间

func _physics_process(delta: float) -> void:
	if world == null:
		return
	var p := GameState.player as MorphBall
	if p and not p.freeze:
		var base := world.world_to_voxel(p.global_position + Vector3.DOWN * 0.6)
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var c := base + Vector3i(dx, 0, dz)
				if _pending.has(c) or world.get_block(c) != Blocks.CRUMBLE:
					continue
				# 只算 PIX 真的压在上面的格
				var cc := world.voxel_center(c)
				if absf(cc.x - p.global_position.x) < 0.55 and absf(cc.z - p.global_position.z) < 0.55:
					_pending[c] = delay
					_shake(c)
	for c in _pending.keys():
		_pending[c] -= delta
		if _pending[c] <= 0.0:
			_pending.erase(c)
			_drop(c)
	for c in _gone.keys():
		_gone[c] -= delta
		if _gone[c] <= 0.0:
			var pp := world.voxel_center(c)
			if p and p.global_position.distance_to(pp) < 2.0:
				_gone[c] = 1.0
				continue
			_gone.erase(c)
			if world.get_block(c) == Blocks.AIR:
				world.set_block(c, Blocks.CRUMBLE)
				world._spawn_debris(pp, Blocks.CRUMBLE)

func _shake(c: Vector3i) -> void:
	world._spawn_debris(world.voxel_center(c) + Vector3.UP * 0.2, Blocks.CRUMBLE)
	Sfx.play("break_soft", world.voxel_center(c), -10.0, 0.2, 0.8)

func _drop(c: Vector3i) -> void:
	var vox: Array[Vector3i] = []
	var b := c * VoxelWorld.CELL
	for dy in VoxelWorld.CELL:
		for dz in VoxelWorld.CELL:
			for dx in VoxelWorld.CELL:
				var q := b + Vector3i(dx, dy, dz)
				if world.vget(q) == Blocks.CRUMBLE:
					vox.append(q)
	if vox.is_empty():
		return
	world._spawn_chunk(vox)
	Sfx.play("break_hard", world.voxel_center(c), -6.0, 0.15)
	_gone[c] = regrow
