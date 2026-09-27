class_name ItemSocket
extends Area3D
## 插槽：放入对应物件后，在指定体素位置生成方块（例如补上能量回路的缺口）

signal filled

@export var accepts := "crystal"
@export var voxel_pos := Vector3i.ZERO
@export var fill_block: int = Blocks.CRYSTAL

var world: VoxelWorld
var done := false
var _hint: MeshInstance3D
var _t := 0.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 4
	monitoring = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 2.0, 1.6)
	cs.shape = box
	add_child(cs)
	_hint = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.5
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.3, 0.9, 1.0, 0.35)
	bm.material = m
	_hint.mesh = bm
	add_child(_hint)

func setup(w: VoxelWorld, p: Vector3i) -> void:
	world = w
	voxel_pos = p
	global_position = w.voxel_center(p) + Vector3.UP * 0.5
	_hint.global_position = w.voxel_center(p)

func _process(delta: float) -> void:
	_t += delta
	if _hint.visible:
		_hint.scale = Vector3.ONE * (0.9 + 0.12 * sin(_t * 4.0))

const ATTRACT_RANGE := 2.4

func _physics_process(_delta: float) -> void:
	if done:
		return
	# 吸附：附近没被抓着的对应物件会被慢慢拉进插槽
	var target := world.voxel_center(voxel_pos) + Vector3.UP * 0.4
	for n in get_tree().get_nodes_in_group("usable_item"):
		var it := n as UsableItem
		if it.held or it.item_id != accepts:
			continue
		var to := target - it.global_position
		if to.length() < ATTRACT_RANGE:
			it.apply_central_force(to.normalized() * 14.0 * it.mass - it.linear_velocity * 2.0 * it.mass)
	for b in get_overlapping_bodies():
		if b is UsableItem and not b.held and b.item_id == accepts:
			done = true
			b.queue_free()
			world.set_block(voxel_pos, fill_block)
			_hint.visible = false
			GameState.shake.emit(0.2)
			Sfx.play("success", Vector3.INF, -2.0, 0.0)
			filled.emit()
			return
