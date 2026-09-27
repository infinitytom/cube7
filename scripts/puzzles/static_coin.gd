class_name StaticCoin
extends Node3D
## 场景里摆放的金币：沿路线摆成一串，既是奖励也是“引路面包屑”。靠近后自动飞入。

const PickupScript := preload("res://scripts/voxel/pickup.gd")
const RANGE := 1.3
var _t := 0.0

func _ready() -> void:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 0.18
	m.bottom_radius = 0.18
	m.height = 0.05
	m.radial_segments = 16
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("ffd23f")
	mat.metallic = 0.6
	mat.roughness = 0.25
	mat.emission_enabled = true
	mat.emission = Color("ffb400")
	mat.emission_energy_multiplier = 0.6
	m.material = mat
	mi.mesh = m
	mi.rotation_degrees.x = 90.0
	add_child(mi)
	_t = randf() * TAU

func _process(delta: float) -> void:
	_t += delta
	rotation.y = _t * 2.5
	var pl: Node3D = GameState.player
	if pl and pl.global_position.distance_to(global_position) < RANGE:
		PickupScript.spawn(get_parent(), "coin", global_position)
		queue_free()
