class_name Lift
extends AnimatableBody3D
## 升降台：通电时在 A、B 两点间往返（到站停 1.2 秒），断电时回到 A 停着。

var a := Vector3.ZERO
var b := Vector3.ZERO
var size := Vector3(2.0, 0.3, 2.0)
var speed := 2.2
var power_cells: Array[Vector3i] = []
var is_powered := false
var always_on := false
var _to_b := true
var _wait := 0.0
var _mat: StandardMaterial3D

func _ready() -> void:
	sync_to_physics = false
	collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("a9b2bd")
	m.metallic = 0.4
	m.roughness = 0.4
	bm.material = m
	mi.mesh = bm
	add_child(mi)
	# 边上一圈指示灯：通电发青光，断电暗红
	var strip := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(size.x + 0.04, 0.08, size.z + 0.04)
	_mat = StandardMaterial3D.new()
	_mat.emission_enabled = true
	sm.material = _mat
	strip.mesh = sm
	strip.position.y = size.y * 0.5 - 0.04
	add_child(strip)
	global_position = a
	_update_look()
	if always_on:
		is_powered = true

func set_powered(on: bool) -> void:
	is_powered = on
	_update_look()
	if on:
		Sfx.play("unlock", global_position, -6.0, 0.05, 0.8)

func _update_look() -> void:
	if _mat == null:
		return
	var c := Color("5ff2ff") if is_powered else Color("7a3a3a")
	_mat.albedo_color = c
	_mat.emission = c
	_mat.emission_energy_multiplier = 2.0 if is_powered else 0.3

func _physics_process(delta: float) -> void:
	var target := (b if _to_b else a) if is_powered else a
	if _wait > 0.0:
		_wait -= delta
		return
	var to := target - global_position
	if to.length() < 0.02:
		if is_powered:
			_to_b = not _to_b
			_wait = 1.2
		return
	global_position += to.normalized() * minf(speed * delta, to.length())
