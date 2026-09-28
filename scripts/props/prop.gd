class_name Prop
extends StaticBody3D
## 场景道具（Kenney 模型）：树、蘑菇、石头、木箱……
## 可破坏的道具被高速滚撞 / 冲撞 / 钻 / 下砸碰到时会“啵”地弹飞，掉出金币——和体素方块一样好拆。
## 脚下的地面方块被拆掉时，道具也会跟着消失。

@export var model_path := ""
@export var height := 1.0          ## 目标高度（米），按模型包围盒缩放
@export var breakable := true
@export var coins := 1
@export var solid := "trunk"       ## "trunk" 只有中间一根柱子挡路（树）；"box" 整个包围盒；"none" 不挡路
@export var pop_sound := "break_wood"

const PickupScript := preload("res://scripts/voxel/pickup.gd")

var ground_cell := Vector3i(-1, -1, -1)
var _model: Node3D
var _area: Area3D
var _popped := false
var _wobble := 0.0

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_model = Kit.model(model_path)
	add_child(_model)
	var b := Kit.bounds(_model)
	# 扁平的道具（花丛、石头）按最大边长缩放，高的道具（树）按高度缩放
	var ref := b.size.y if solid == "trunk" else maxf(b.size.y, maxf(b.size.x, b.size.z))
	var s := height / maxf(ref, 0.01)
	_model.scale = Vector3.ONE * s
	_model.position.y = -b.position.y * s
	_model.rotation.y = randf() * TAU
	var size := b.size * s
	if solid != "none":
		var cs := CollisionShape3D.new()
		if solid == "trunk":
			var cyl := CylinderShape3D.new()
			cyl.radius = clampf(minf(size.x, size.z) * 0.18, 0.12, 0.35)
			cyl.height = size.y
			cs.shape = cyl
		else:
			var box := BoxShape3D.new()
			box.size = Vector3(size.x * 0.85, size.y, size.z * 0.85)
			cs.shape = box
		cs.position.y = size.y * 0.5
		add_child(cs)
	if breakable:
		_area = Area3D.new()
		_area.collision_layer = 0
		_area.collision_mask = 2
		var as_ := CollisionShape3D.new()
		var ab := BoxShape3D.new()
		ab.size = Vector3(maxf(size.x * 0.6, 0.9), size.y, maxf(size.z * 0.6, 0.9))
		as_.shape = ab
		as_.position.y = size.y * 0.5
		_area.add_child(as_)
		add_child(_area)
	var w := get_tree().get_first_node_in_group("voxel_world") as VoxelWorld
	if w:
		w.cell_changed.connect(_on_block_changed)

func _physics_process(delta: float) -> void:
	if _wobble > 0.0:
		_wobble = maxf(_wobble - delta * 3.0, 0.0)
		_model.rotation.z = sin(_wobble * 30.0) * _wobble * 0.12
	if not breakable or _popped or _area == null:
		return
	var p := GameState.player as MorphBall
	if p == null or not _area.overlaps_body(p):
		return
	if p.attack != "":
		pop(p.global_position)
	elif _wobble <= 0.0 and p.linear_velocity.length() > 2.0:
		_wobble = 1.0   # 慢速碰到只是晃一晃

func _on_block_changed(cell: Vector3i, _o: int, n: int) -> void:
	if n == Blocks.AIR and cell == ground_cell:
		pop(global_position)

## 弹飞：缩放 + 碎片 + 掉金币
func pop(from: Vector3) -> void:
	if _popped:
		return
	_popped = true
	Sfx.play(pop_sound, global_position, -2.0, 0.1)
	GameState.blocks_broken += 1
	var parent := get_parent()
	for i in coins:
		PickupScript.spawn(parent, "coin", global_position + Vector3.UP * 0.6)
	var away := global_position - from
	away.y = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(_model, "scale", _model.scale * 1.25, 0.08)
	tw.chain().tween_property(_model, "scale", Vector3.ZERO, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "position", position + away.normalized() * 0.3 + Vector3.UP * 0.3, 0.3)
	collision_layer = 0
	_burst()
	tw.chain().tween_callback(queue_free)

func _burst() -> void:
	var ps := CPUParticles3D.new()
	var m := SphereMesh.new()
	m.radius = 0.08
	m.height = 0.16
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("66daa3") if model_path.contains("tree") else Color("ffd769")
	mat.roughness = 0.6
	m.material = mat
	ps.mesh = m
	ps.amount = 14
	ps.one_shot = true
	ps.explosiveness = 1.0
	ps.lifetime = 0.6
	ps.spread = 180.0
	ps.direction = Vector3.UP
	ps.initial_velocity_min = 2.0
	ps.initial_velocity_max = 4.5
	ps.gravity = Vector3(0, -12, 0)
	ps.scale_amount_min = 0.6
	ps.scale_amount_max = 1.4
	get_parent().add_child(ps)
	ps.global_position = global_position + Vector3.UP * height * 0.5
	ps.emitting = true
	get_tree().create_timer(1.0).timeout.connect(ps.queue_free)
