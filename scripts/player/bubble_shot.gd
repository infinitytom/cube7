class_name BubbleShot
extends Node3D
## 泡泡弹（气泡形态蓄力发射）：慢慢往前飘，碰到敌人就把它困在泡泡里飘起来；
## 碰到锈弹会把它包住、安全地戳破；碰到火会把火吹灭。

var vel := Vector3.ZERO
var power := 1.0
var _t := 0.0
var _mi: MeshInstance3D
const LIFE := 1.6

func _ready() -> void:
	_mi = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.6
	_mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.75, 1.0, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.rim_enabled = true
	m.rim = 1.0
	m.emission_enabled = true
	m.emission = Color("c9a6ff")
	m.emission_energy_multiplier = 0.8
	_mi.material_override = m
	add_child(_mi)
	scale = Vector3.ONE * (0.8 + power * 0.5)

func _physics_process(delta: float) -> void:
	_t += delta
	vel = vel.move_toward(Vector3(0, 0.6, 0), 3.0 * delta)
	var from := global_position
	var to := from + vel * delta
	_mi.scale = Vector3.ONE * (1.0 + 0.08 * sin(_t * 14.0))
	for e in get_tree().get_nodes_in_group("enemy"):
		var en := e as Node3D
		if en.global_position.distance_to(global_position) < 0.9 * scale.x + 0.3 or (en.global_position + Vector3.UP * 0.4).distance_to(global_position) < 0.9 * scale.x:
			e.call("on_bubble", self)
			_pop()
			return
	for b in get_tree().get_nodes_in_group("projectile"):
		if (b as Node3D).global_position.distance_to(global_position) < 0.8 * scale.x:
			FloatText.spawn(get_parent(), global_position + Vector3.UP * 0.5, "包住了！", Color("d9c6ff"), 40, 1.0)
			b.queue_free()
			_pop()
			return
	var q := PhysicsRayQueryParameters3D.create(from, to + vel.normalized() * 0.25, 1 | 8)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var w := get_tree().get_first_node_in_group("voxel_world") as VoxelWorld
		if w and w.fire:
			w.fire.extinguish_sphere(hit.position, 1.0)
		_pop()
		return
	global_position = to
	if _t > LIFE:
		_pop()

func _pop() -> void:
	Sfx.play("wave", global_position, -8.0, 0.15)
	var tw := create_tween()
	tw.tween_property(_mi, "scale", Vector3.ONE * 1.8, 0.12)
	tw.parallel().tween_property(_mi.material_override, "albedo_color:a", 0.0, 0.12)
	tw.tween_callback(queue_free)
	set_physics_process(false)
