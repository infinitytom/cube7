class_name StaticCoin
extends Node3D
## 场景里摆放的金币：沿路线摆成一串，既是奖励也是“引路面包屑”。靠近后自动飞入。

const PickupScript := preload("res://scripts/voxel/pickup.gd")
const RANGE := 1.3
var _t := 0.0

func _ready() -> void:
	var mi := MeshInstance3D.new()
	var cm := Kit.mesh(Kit.COIN)
	mi.mesh = cm
	var ab := cm.get_aabb()
	mi.scale = Vector3.ONE * (0.4 / maxf(ab.size.x, ab.size.y))
	mi.position = -ab.get_center() * mi.scale.x
	add_child(mi)
	_t = randf() * TAU

func _process(delta: float) -> void:
	_t += delta
	rotation.y = _t * 2.5
	var pl: Node3D = GameState.player
	if pl and pl.global_position.distance_to(global_position) < RANGE:
		PickupScript.spawn(get_parent(), "coin", global_position)
		queue_free()
