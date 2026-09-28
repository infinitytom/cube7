class_name UsableItem
extends RigidBody3D
## “可用物件”：破坏后唯一会留在场上的东西（能量晶块等）。可被抓起、投掷、放进插槽。
## 发光描边与普通碎屑区分；掉出世界会回到原处，避免谜题卡死。

@export var item_id := "crystal"
@export var color := Color("46e0ff")

var held := false
var home := Vector3.ZERO
## 火种：刚扔出去 / 放下的几秒内会点燃碰到的可燃物
var _hot_t := 0.0
var _ign_t := 0.0
var _hit_cd := 0.0
var _thrown_t := 0.0
var _outline: MeshInstance3D
var _t := 0.0

func _ready() -> void:
	add_to_group("usable_item")
	mass = 1.2
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 8
	continuous_cd = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * 0.45
	cs.shape = box
	add_child(cs)
	var core := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.45
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.6
	bm.material = m
	core.mesh = bm
	add_child(core)
	# 描边：略大的半透明外壳，呼吸闪烁
	_outline = MeshInstance3D.new()
	var om := BoxMesh.new()
	om.size = Vector3.ONE * 0.6
	var o := StandardMaterial3D.new()
	o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	o.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	o.albedo_color = Color(1, 1, 1, 0.25)
	o.cull_mode = BaseMaterial3D.CULL_FRONT
	om.material = o
	_outline.mesh = om
	add_child(_outline)
	if home == Vector3.ZERO:
		home = global_position
	# 火种：表面是一闪一闪的炭火
	if item_id == "ember":
		m.albedo_color = Color("5a1206")
		m.emission = Color("ff6a1a")
		m.emission_energy_multiplier = 2.2
		var l := OmniLight3D.new()
		l.light_color = Color("ff8a3d")
		l.light_energy = 0.8
		l.omni_range = 2.5
		add_child(l)

func _process(delta: float) -> void:
	_t += delta
	_outline.scale = Vector3.ONE * (1.0 + 0.06 * sin(_t * 5.0))

func _physics_process(delta: float) -> void:
	if item_id == "ember" and not held and _hot_t > 0.0:
		_hot_t -= delta
		_ign_t -= delta
		if _ign_t <= 0.0:
			_ign_t = 0.15
			var w := get_tree().get_first_node_in_group("voxel_world") as VoxelWorld
			if w and w.fire.ignite_sphere(global_position, 0.6) > 0:
				# 火种点着东西以后就“用掉了”：缩小消失（补给点会再生成一个）
				_hot_t = 0.0
				var tw := create_tween()
				tw.tween_property(self, "scale", Vector3.ONE * 0.05, 0.4)
				tw.tween_callback(queue_free)
	# 扔出去砸中敌人
	_hit_cd -= delta
	_thrown_t -= delta
	if not held and _thrown_t > 0.0 and _hit_cd <= 0.0 and linear_velocity.length() > 2.5:
		for e in get_tree().get_nodes_in_group("enemy"):
			var en := e as Node3D
			if (en.global_position + Vector3.UP * 0.4).distance_to(global_position) < 0.85:
				_hit_cd = 0.8
				e.call("on_item", self)
				linear_velocity = -linear_velocity * 0.3 + Vector3.UP * 2.0
				FloatText.spawn(get_parent(), global_position + Vector3.UP * 0.5, "砸中！", Color("ffe066"), 44, 1.0)
				break
	if not held and global_position.y < GameState.kill_y:
		global_position = home
		linear_velocity = Vector3.ZERO
		GameState.say("晶块掉下去了，我把它传送回原处。" if item_id != "ember" else "火种掉下去了——炉子那边会再生成一个。")
		if item_id == "ember":
			queue_free()

func set_held(v: bool) -> void:
	held = v
	if not v:
		_hot_t = 3.0
		_thrown_t = 2.0
	freeze = v
	collision_layer = 0 if v else 4
	collision_mask = 0 if v else (1 | 2 | 4 | 8)
