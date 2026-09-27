class_name UsableItem
extends RigidBody3D
## “可用物件”：破坏后唯一会留在场上的东西（能量晶块等）。可被抓起、投掷、放进插槽。
## 发光描边与普通碎屑区分；掉出世界会回到原处，避免谜题卡死。

@export var item_id := "crystal"
@export var color := Color("46e0ff")

var held := false
var home := Vector3.ZERO
var _outline: MeshInstance3D
var _t := 0.0

func _ready() -> void:
	add_to_group("usable_item")
	mass = 1.2
	collision_layer = 4
	collision_mask = 1 | 2 | 4
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

func _process(delta: float) -> void:
	_t += delta
	_outline.scale = Vector3.ONE * (1.0 + 0.06 * sin(_t * 5.0))

func _physics_process(_delta: float) -> void:
	if not held and global_position.y < GameState.KILL_Y:
		global_position = home
		linear_velocity = Vector3.ZERO
		GameState.say("晶块掉下去了，我把它传送回原处。")

func set_held(v: bool) -> void:
	held = v
	freeze = v
	collision_layer = 0 if v else 4
	collision_mask = 0 if v else (1 | 2 | 4)
