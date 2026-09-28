class_name ElectricField
extends Zone
## 电网陷阱：通电时区域里噼啪放电，碰到就受伤。把导线钻断、或者把给它供电的水晶拿走，就能关掉。

var power_cells: Array[Vector3i] = []
var is_powered := false
var _ps: CPUParticles3D
var _t := 0.0

func _build() -> void:
	_ps = CPUParticles3D.new()
	_ps.amount = 50
	_ps.lifetime = 0.25
	_ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_ps.emission_box_extents = box_size * 0.5
	_ps.gravity = Vector3.ZERO
	_ps.spread = 180.0
	_ps.initial_velocity_min = 1.0
	_ps.initial_velocity_max = 3.0
	var m := BoxMesh.new()
	m.size = Vector3(0.03, 0.22, 0.03)
	m.material = _glow_mat(Color("9ff4ff"), 4.0)
	_ps.mesh = m
	_ps.emitting = false
	add_child(_ps)

func set_powered(on: bool) -> void:
	is_powered = on
	_ps.emitting = on
	if not on:
		Sfx.play("clang", global_position, -6.0, 0.05, 0.6)

func _physics_process(delta: float) -> void:
	if not is_powered:
		return
	_t -= delta
	if _t <= 0.0:
		_t = 0.5
		Sfx.play("drill", global_position, -18.0, 0.3, 2.2)
	for b in get_overlapping_bodies():
		if b is MorphBall and not (b as MorphBall).is_invulnerable():
			(b as MorphBall).hurt(global_position, 1)
			GameState.say("电网通着电！找找是哪条线在给它供电。")
