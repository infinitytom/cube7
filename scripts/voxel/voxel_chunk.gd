class_name VoxelChunk
extends RigidBody3D
## 断开的体素碎块：破坏后和地面失去连接的一小团方块，会整块掉落、翻滚，
## 落地（或 1.6 秒后）再碎成小方块并吐出掉落物——体素世界的“真实感”。

const LIFETIME := 1.6

var world: VoxelWorld
var blocks: Array = []        # [[本地坐标 Vector3, 方块类型 int], ...]
var _age := 0.0
var _done := false
static var _box: BoxMesh
static var _mats := {}

func _ready() -> void:
	collision_layer = 32
	collision_mask = 1
	contact_monitor = true
	max_contacts_reported = 4
	gravity_scale = 1.3
	if _box == null:
		_box = BoxMesh.new()
		_box.size = Vector3.ONE * VoxelWorld.VOXEL * 0.97
	var shape_box := BoxShape3D.new()
	shape_box.size = Vector3.ONE * VoxelWorld.VOXEL * 0.95
	for b in blocks:
		var lp: Vector3 = b[0]
		var t: int = b[1]
		var mi := MeshInstance3D.new()
		mi.mesh = _box
		mi.material_override = _mat(t)
		mi.position = lp
		add_child(mi)
		var cs := CollisionShape3D.new()
		cs.shape = shape_box
		cs.position = lp
		add_child(cs)
	mass = maxf(0.4 * blocks.size(), 0.5)

static func _mat(t: int) -> StandardMaterial3D:
	if not _mats.has(t):
		var m := StandardMaterial3D.new()
		m.albedo_color = Blocks.colors[t]
		m.roughness = 0.8
		_mats[t] = m
	return _mats[t]

func _physics_process(delta: float) -> void:
	_age += delta
	if _done:
		return
	# 落地撞击（速度骤减）或超时就碎掉
	if _age > LIFETIME or (_age > 0.35 and get_contact_count() > 0 and linear_velocity.length() < 2.5):
		crumble()

func crumble() -> void:
	if _done:
		return
	_done = true
	for b in blocks:
		var wp := to_global(b[0])
		if world:
			world.break_fx_at(wp, b[1], true)
	queue_free()
