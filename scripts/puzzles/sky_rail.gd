class_name SkyRail
extends Node3D
## 空中轨道：云顶之城各座浮岛之间的磁悬浮轨道。
## PIX 碰到轨道就会被吸住，沿着轨道高速滑行（按住加速更快，按跳跃可以随时跳下来）。
## 轨道可以有断口：在断口前跳起来，落到下一段轨道上会重新吸住。
## 轨道由若干段 Curve3D 组成；每段是一条独立的 SkyRail 节点。

signal ridden
signal finished

@export var speed := 9.0
var curve := Curve3D.new()
var powered := true
var power_cells: Array[Vector3i] = []
var is_powered := true
var color := Color("7de3ff")
var _len := 0.0
var _rider: MorphBall
var _off := 0.0
var _cd := 0.0
var _dir := 1.0
var _mat: StandardMaterial3D
var _sparks: CPUParticles3D
var _hum: AudioStreamPlayer3D
var _baked: PackedVector3Array

func _ready() -> void:
	add_to_group("sky_rail")

func build_visual() -> void:
	_len = curve.get_baked_length()
	_baked = curve.get_baked_points()
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = color
	_mat.emission_enabled = true
	_mat.emission = color
	_mat.emission_energy_multiplier = 1.4 if powered else 0.1
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dark := StandardMaterial3D.new()
	dark.cull_mode = BaseMaterial3D.CULL_DISABLED
	dark.albedo_color = Color("3d4659")
	dark.metallic = 0.5
	dark.roughness = 0.4
	# 轨道本体：沿曲线每 0.5 米一节（方块风：一节节的轨枕 + 发光的导轨）
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 0.5
	var d := 0.0
	while d < _len:
		var p := curve.sample_baked(d)
		var p2 := curve.sample_baked(minf(d + step, _len))
		var fwd := (p2 - p).normalized() if p2.distance_to(p) > 0.001 else Vector3.FORWARD
		var side := fwd.cross(Vector3.UP).normalized()
		if side.length() < 0.1:
			side = Vector3.RIGHT
		var up := side.cross(fwd).normalized()
		var basis := Basis(side, up, -fwd)
		_box(st2, Transform3D(basis, p + Vector3.DOWN * 0.18), Vector3(0.7, 0.1, 0.28))
		_box(st, Transform3D(basis, p + Vector3.DOWN * 0.08 + side * 0.22), Vector3(0.08, 0.08, step))
		_box(st, Transform3D(basis, p + Vector3.DOWN * 0.08 - side * 0.22), Vector3(0.08, 0.08, step))
		d += step
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat
	add_child(mi)
	var mi2 := MeshInstance3D.new()
	mi2.mesh = st2.commit()
	mi2.material_override = dark
	add_child(mi2)
	_sparks = CPUParticles3D.new()
	_sparks.amount = 24
	_sparks.lifetime = 0.35
	_sparks.emitting = false
	_sparks.local_coords = false
	_sparks.spread = 60.0
	_sparks.initial_velocity_min = 1.5
	_sparks.initial_velocity_max = 3.0
	var sm := BoxMesh.new()
	sm.size = Vector3.ONE * 0.05
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color("bff6ff")
	sm.material = smat
	_sparks.mesh = sm
	add_child(_sparks)
	_hum = AudioStreamPlayer3D.new()
	_hum.stream = load("res://audio/sfx/roll.ogg")
	_hum.bus = "SFX"
	_hum.pitch_scale = 1.8
	_hum.volume_db = -8.0
	add_child(_hum)

func _box(st: SurfaceTool, xf: Transform3D, size: Vector3) -> void:
	var h := size * 0.5
	var corners := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var faces := [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]
	for f in faces:
		var a: Vector3 = xf * corners[f[0]]
		var b: Vector3 = xf * corners[f[1]]
		var c: Vector3 = xf * corners[f[2]]
		var dd: Vector3 = xf * corners[f[3]]
		var n := (b - a).cross(c - a).normalized()
		st.set_normal(-n)
		for v in [a, c, b, a, dd, c]:
			st.add_vertex(v)

func set_powered(on: bool) -> void:
	powered = on
	is_powered = on
	if _mat:
		_mat.emission_energy_multiplier = 1.4 if on else 0.1

func is_riding() -> bool:
	return _rider != null

func _physics_process(delta: float) -> void:
	_cd -= delta
	if _rider:
		_ride(delta)
		return
	if not powered or _cd > 0.0:
		return
	var p := GameState.player as MorphBall
	if p == null or p.freeze or p.get_meta("riding", false):
		return
	var lp := to_local(p.global_position)
	var off := curve.get_closest_offset(lp)
	var cp := curve.sample_baked(off)
	if cp.distance_to(lp) < 0.75 and p.linear_velocity.y < 3.0:
		_attach(p, off)

func _attach(p: MorphBall, off: float) -> void:
	_rider = p
	_off = off
	p.set_meta("riding", true)
	# 顺着来的方向滑：速度和轨道方向同向就正着走
	var t := (curve.sample_baked(minf(off + 0.5, _len)) - curve.sample_baked(maxf(off - 0.5, 0.0))).normalized()
	_dir = 1.0 if p.linear_velocity.dot(global_basis * t) >= -0.5 else -1.0
	if off < 1.0:
		_dir = 1.0
	elif off > _len - 1.0:
		_dir = -1.0
	p.freeze = true
	_sparks.emitting = true
	_hum.play()
	Sfx.play("grab", p.global_position, -2.0, 0.05, 1.5)
	ridden.emit()

func _ride(delta: float) -> void:
	var p := _rider
	var boost := Input.is_action_pressed("boost") if not p.debug_override else p.debug_boost
	var v := speed * (1.35 if boost else 1.0)
	# 下坡快一点、上坡慢一点
	var a := curve.sample_baked(_off)
	var b := curve.sample_baked(clampf(_off + _dir * 0.5, 0.0, _len))
	var slope := (b.y - a.y) / 0.5
	v *= clampf(1.0 - slope * 0.4, 0.7, 1.4)
	_off += _dir * v * delta
	var pos := to_global(curve.sample_baked(clampf(_off, 0.0, _len))) + Vector3.UP * 0.35
	p.global_position = pos
	_sparks.global_position = pos + Vector3.DOWN * 0.3
	_hum.global_position = pos
	var jump := Input.is_action_just_pressed("jump") if not p.debug_override else p.debug_jump_pressed
	if p.debug_override:
		p.debug_jump_pressed = false
	var tangent := (to_global(b) - to_global(a)).normalized()
	if jump:
		_detach(tangent * v * 0.9 + Vector3.UP * 5.5)
		Sfx.play("jump_ball", pos, -4.0, 0.05)
		return
	if _off <= 0.0 or _off >= _len:
		_detach(tangent * v + Vector3.UP * 1.5)
		finished.emit()

func _detach(vel: Vector3) -> void:
	var p := _rider
	_rider = null
	_sparks.emitting = false
	_hum.stop()
	_cd = 0.5
	if not is_instance_valid(p):
		return
	p.freeze = false
	p.set_meta("riding", false)
	p.linear_velocity = vel
	p.launched(0.4)

## 被锈蜂撞到 / 受伤：从轨道上掉下来
func knock_off() -> void:
	if _rider:
		_detach(Vector3(0, 3, 0))
