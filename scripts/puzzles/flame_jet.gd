class_name FlameJet
extends Zone
## 喷火口：熔炉管道周期性地喷出火焰（喷 on_time 秒、停 off_time 秒），碰到会受伤。
## 气泡的气浪能把它吹熄一阵子（snuff_time 秒）。

@export var on_time := 1.4
@export var off_time := 1.4
@export var phase := 0.0
@export var dir := Vector3.UP
var snuff_time := 5.0
var _t := 0.0
var _snuffed := 0.0
var _on := false
var _ps: CPUParticles3D
var _light: OmniLight3D

func _build() -> void:
	add_to_group("flame_jet")
	_t = phase
	_ps = CPUParticles3D.new()
	_ps.amount = 70
	_ps.lifetime = 0.45
	_ps.local_coords = false
	_ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	var ext := box_size * 0.35
	_ps.emission_box_extents = Vector3(ext.x, 0.05, ext.z) if absf(dir.y) > 0.5 else Vector3(0.05, ext.y, ext.z) if absf(dir.x) > 0.5 else Vector3(ext.x, ext.y, 0.05)
	_ps.position = -dir * (box_size.dot(dir.abs()) * 0.5)
	_ps.direction = dir
	_ps.spread = 12.0
	_ps.gravity = Vector3.UP * 2.0
	var len := box_size.dot(dir.abs())
	_ps.initial_velocity_min = len / 0.45 * 0.7
	_ps.initial_velocity_max = len / 0.45
	var m := QuadMesh.new()
	m.size = Vector2.ONE * 0.35
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.material = mat
	_ps.mesh = m
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	g.set_color(1, Color(1.0, 0.25, 0.05, 0.0))
	_ps.color_ramp = g
	_ps.emitting = false
	add_child(_ps)
	_light = OmniLight3D.new()
	_light.light_color = Color("ff8a3d")
	_light.omni_range = 5.0
	_light.light_energy = 0.0
	add_child(_light)

func snuff() -> void:
	_snuffed = snuff_time
	_set_on(false)
	Sfx.play("wave", global_position, -6.0, 0.1, 0.6)

func _set_on(v: bool) -> void:
	if v == _on:
		return
	_on = v
	_ps.emitting = v
	_light.light_energy = 2.0 if v else 0.0
	if v:
		Sfx.play("dash", global_position, -10.0, 0.2, 0.5)

func _physics_process(delta: float) -> void:
	if _snuffed > 0.0:
		_snuffed -= delta
		return
	_t += delta
	var cyc := fmod(_t, on_time + off_time)
	_set_on(cyc < on_time)
	if not _on:
		return
	for b in get_overlapping_bodies():
		if b is MorphBall and not (b as MorphBall).is_invulnerable():
			(b as MorphBall).hurt(global_position, 1)
			GameState.say("喷火口有节奏——等它停下再冲过去。有了气泡，气浪还能把它吹熄一会儿。")
		elif b is UsableItem and (b as UsableItem).item_id == "ember":
			pass
