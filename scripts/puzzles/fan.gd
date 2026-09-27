class_name Fan
extends Zone
## 上升气流：对区域内刚体施加恒定向上的力，越轻飞得越高（气泡形态专用）

@export var strength := 3.2
@export var max_rise_speed := 3.0   ## 上升速度上限，防止冲出场外

func _build() -> void:
	var ps := CPUParticles3D.new()
	ps.amount = 40
	ps.lifetime = 1.6
	ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	ps.emission_box_extents = Vector3(box_size.x * 0.45, 0.1, box_size.z * 0.45)
	ps.direction = Vector3.UP
	ps.spread = 5.0
	ps.gravity = Vector3.ZERO
	ps.initial_velocity_min = box_size.y / 1.6 * 0.8
	ps.initial_velocity_max = box_size.y / 1.6
	var m := BoxMesh.new()
	m.size = Vector3(0.04, 0.3, 0.04)
	m.material = _glow_mat(Color("bfefff"), 1.5, 0.6)
	ps.mesh = m
	ps.position = Vector3(0, -box_size.y * 0.5, 0)
	add_child(ps)

func _physics_process(_delta: float) -> void:
	for b in get_overlapping_bodies():
		if b is RigidBody3D and not b.freeze and b.linear_velocity.y < max_rise_speed:
			b.apply_central_force(Vector3.UP * strength)
