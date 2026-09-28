class_name RustBomb
extends Node3D
## 锈弹：炮台抛出来的慢速炸弹（抛物线），落地爆炸：伤到附近的 PIX、炸碎易碎的方块。
## 气浪能把它原路打回去（反弹后会炸炮台自己）。

var vel := Vector3.ZERO
var owner_enemy: Node3D
var reflected := false
var _t := 0.0
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _shadow: MeshInstance3D
const G := 12.0
const RADIUS := 1.3

func _ready() -> void:
	add_to_group("projectile")
	_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	_mesh.mesh = sm
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color("5a3a4a")
	_mat.emission_enabled = true
	_mat.emission = Color("ff5a3a")
	_mat.emission_energy_multiplier = 0.6
	_mesh.material_override = _mat
	add_child(_mesh)
	var fuse := CPUParticles3D.new()
	fuse.amount = 10
	fuse.lifetime = 0.4
	fuse.local_coords = false
	fuse.gravity = Vector3(0, 1, 0)
	fuse.initial_velocity_min = 0.2
	fuse.initial_velocity_max = 0.6
	var fm := SphereMesh.new()
	fm.radius = 0.05
	fm.height = 0.1
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color("ffb347")
	fm.material = fmat
	fuse.mesh = fm
	fuse.position.y = 0.22
	add_child(fuse)
	# 地面上的落点影子
	_shadow = MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = RADIUS
	tm.bottom_radius = RADIUS
	tm.height = 0.02
	_shadow.mesh = tm
	var shm := StandardMaterial3D.new()
	shm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shm.albedo_color = Color(1, 0.25, 0.2, 0.25)
	_shadow.material_override = shm
	_shadow.top_level = true
	add_child(_shadow)

## 计算一条抛物线：flight 秒后落到 target
static func launch(parent: Node, from: Vector3, target: Vector3, flight: float, src: Node3D) -> RustBomb:
	var b := RustBomb.new()
	var d := target - from
	b.vel = Vector3(d.x / flight, d.y / flight + 0.5 * G * flight, d.z / flight)
	b.owner_enemy = src
	parent.add_child(b)
	b.global_position = from
	return b

func reflect(from: Vector3) -> void:
	if reflected:
		return
	reflected = true
	Sfx.play("boing", global_position, -2.0, 0.1)
	_mat.emission = Color("9fe8ff")
	_mat.emission_energy_multiplier = 1.5
	var target := global_position + (global_position - from).normalized() * 4.0
	if is_instance_valid(owner_enemy):
		target = owner_enemy.global_position + Vector3.UP * 0.5
	var flight := 1.0
	var d := target - global_position
	vel = Vector3(d.x / flight, d.y / flight + 0.5 * G * flight, d.z / flight)

func _physics_process(delta: float) -> void:
	_t += delta
	vel.y -= G * delta
	var from := global_position
	var to := from + vel * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 8 | 16)
	if owner_enemy and not reflected:
		q.exclude = [owner_enemy.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	# 地面影子
	var sq := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 30.0, 1 | 8)
	var sh := get_world_3d().direct_space_state.intersect_ray(sq)
	if not sh.is_empty():
		_shadow.global_position = (sh.position as Vector3) + Vector3.UP * 0.04
		_shadow.visible = true
	# 直接砸中 PIX
	var p := GameState.player as MorphBall
	if p and p.global_position.distance_to(global_position) < 0.6 and not reflected:
		_explode()
		return
	if not hit.is_empty():
		global_position = hit.position
		_explode()
		return
	global_position = to
	if _t > 6.0 or global_position.y < GameState.kill_y:
		queue_free()

func _explode() -> void:
	var pos := global_position
	Sfx.play("impact_big", pos, -6.0, 0.1)
	Sfx.play("break_hard", pos, -4.0, 0.1)
	GameState.shake.emit(0.25)
	var w := get_tree().get_first_node_in_group("voxel_world") as VoxelWorld
	if w:
		w.break_sphere(pos, 0.9, "impact", 6.0, Vector3.DOWN)
	var p := GameState.player as MorphBall
	if p and p.global_position.distance_to(pos) < RADIUS and not reflected:
		p.hurt(pos)
	# 打回去的锈弹砸中了大块头的发射者（Boss 的锈壳）
	if reflected and is_instance_valid(owner_enemy) and owner_enemy.has_method("reflected_hit") and pos.distance_to(owner_enemy.global_position) < 5.5:
		owner_enemy.call("reflected_hit")
	for e in get_tree().get_nodes_in_group("enemy"):
		if (e as Node3D).global_position.distance_to(pos) < RADIUS + (0.6 if reflected else 0.0):
			if reflected:
				e.call("take_hit", pos, "bomb")
			elif e != owner_enemy:
				e.call("on_wave", pos)
	_flash(pos)
	queue_free()

func _flash(pos: Vector3) -> void:
	var parent := get_parent()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.6, 0.3, 0.8)
	mi.material_override = m
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.3
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE * RADIUS, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(mi.queue_free)
