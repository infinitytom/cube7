class_name WindZone
extends Zone
## 高空的侧风：区域里的刚体被一阵一阵地往 dir 方向推（越轻推得越远——气泡最怕风，钻头几乎不受影响）。
## gust = true 时是阵风：吹 2.5 秒、停 2 秒，吹之前风线会先变密提示。

@export var dir := Vector3(1, 0, 0)
@export var strength := 3.0
@export var gust := true
@export var on_time := 2.5
@export var off_time := 2.0
var _t := 0.0
var _ps: CPUParticles3D
var blowing := true

func _build() -> void:
	_ps = CPUParticles3D.new()
	_ps.amount = 36
	_ps.lifetime = 1.0
	_ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_ps.emission_box_extents = box_size * 0.5
	_ps.direction = dir.normalized()
	_ps.spread = 3.0
	_ps.gravity = Vector3.ZERO
	_ps.initial_velocity_min = 8.0
	_ps.initial_velocity_max = 11.0
	var m := BoxMesh.new()
	m.size = Vector3(0.03, 0.03, 0.9)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.45)
	m.material = mat
	_ps.mesh = m
	_ps.particle_flag_align_y = false
	_ps.local_coords = false
	add_child(_ps)
	# 风线沿风向摆放
	var d := dir.normalized()
	if absf(d.y) < 0.9:
		_ps.rotation.y = atan2(d.x, d.z)
		_ps.direction = Vector3(0, 0, 1)

func _physics_process(delta: float) -> void:
	_t += delta
	if gust:
		var cyc := fmod(_t, on_time + off_time)
		blowing = cyc < on_time
		_ps.emitting = cyc < on_time or cyc > on_time + off_time - 0.6
	if not blowing:
		return
	for b in get_overlapping_bodies():
		if b is RigidBody3D and not b.freeze:
			var rb := b as RigidBody3D
			var along := rb.linear_velocity.dot(dir.normalized())
			if along < strength * 2.2:
				# 越轻越受影响：力按 1/质量 放大（钻头 3.0 几乎吹不动，气泡 0.3 被吹得很远）
				rb.apply_central_force(dir.normalized() * strength * 1.8 / maxf(rb.mass, 0.3) * rb.mass * 0.9)
