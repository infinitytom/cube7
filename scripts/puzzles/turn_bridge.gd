class_name TurnBridge
extends AnimatableBody3D
## 旋转桥：架在两座浮岛之间的长桥，中间有一个转盘。撞一下转盘上的发光转钮，整座桥转 90°。
## 桥只有转到对的方向才能连通两边；有时候要先转过去当“跳板”，再转回来。

signal turned(dir: int)

var length := 12.0
var width := 2.0
var dir := 0                 ## 0 = 沿 x，1 = 沿 z
var locked := false
var _knob: Area3D
var _cd := 0.0
var _knob_mat: StandardMaterial3D
var _turning := false
var _cs: CollisionShape3D
var _vis: Node3D

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(length, 0.4, width)
	cs.shape = bs
	add_child(cs)
	_cs = cs
	_vis = Node3D.new()
	add_child(_vis)
	var deck := StandardMaterial3D.new()
	deck.albedo_color = Color("e9edf2")
	deck.roughness = 0.5
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color("5b7bd6")
	trim.emission_enabled = true
	trim.emission = Color("7de3ff")
	trim.emission_energy_multiplier = 0.6
	# 一节节的桥板（体素风）
	var n := int(length / 0.5)
	for i in n:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.48, 0.4, width)
		mi.mesh = bm
		mi.material_override = deck if i % 4 != 0 else trim
		mi.position = Vector3(-length * 0.5 + 0.25 + i * 0.5, 0, 0)
		_vis.add_child(mi)
	for sz in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(length, 0.3, 0.12)
		rail.mesh = rm
		rail.material_override = trim
		rail.position = Vector3(0, 0.35, sz * (width * 0.5 - 0.06))
		_vis.add_child(rail)
	# 中间的转盘和转钮
	var hub := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.1
	cm.bottom_radius = 1.2
	cm.height = 0.3
	hub.mesh = cm
	hub.material_override = trim
	hub.position.y = 0.3
	_vis.add_child(hub)
	var knob := MeshInstance3D.new()
	var km := SphereMesh.new()
	km.radius = 0.35
	km.height = 0.7
	knob.mesh = km
	_knob_mat = StandardMaterial3D.new()
	_knob_mat.albedo_color = Color("ffd166")
	_knob_mat.emission_enabled = true
	_knob_mat.emission = Color("ffd166")
	_knob_mat.emission_energy_multiplier = 1.5
	knob.material_override = _knob_mat
	knob.position.y = 0.75
	_vis.add_child(knob)
	_knob = Area3D.new()
	_knob.collision_layer = 0
	_knob.collision_mask = 2
	var kc := CollisionShape3D.new()
	var ks := SphereShape3D.new()
	ks.radius = 0.9
	kc.shape = ks
	kc.position.y = 0.8
	_knob.add_child(kc)
	add_child(_knob)
	sync_to_physics = true
	# 桥身本体不转（这个物理体直接设朝向会被同步覆盖），转的是碰撞形状和网格
	_cs.rotation.y = dir * PI / 2.0
	_vis.rotation.y = _cs.rotation.y

func set_dir(d: int) -> void:
	dir = d
	if _cs:
		_cs.rotation.y = d * PI / 2.0
		_vis.rotation.y = _cs.rotation.y

func turn() -> void:
	if locked or _turning:
		return
	_turning = true
	dir = 1 - dir
	Sfx.play("unlock", global_position, 0.0, 0.0, 0.7)
	GameState.shake.emit(0.2)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_cs, "rotation:y", _cs.rotation.y + PI / 2.0, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_vis, "rotation:y", _cs.rotation.y + PI / 2.0, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.set_parallel(false)
	tw.tween_callback(func() -> void:
		_turning = false
		turned.emit(dir))

func _physics_process(delta: float) -> void:
	_cd -= delta
	_knob_mat.emission_energy_multiplier = 1.0 + 0.6 * sin(Time.get_ticks_msec() / 200.0)
	if _cd > 0.0 or locked:
		return
	var p := GameState.player as MorphBall
	if p and _knob.overlaps_body(p):
		var sp := Vector3(p.linear_velocity.x, 0, p.linear_velocity.z).length()
		if p.attack != "" or sp > 3.5:
			_cd = 1.6
			turn()
			var away := p.global_position - global_position
			away.y = 0.0
			p.linear_velocity = away.normalized() * 0.6 + Vector3.UP * 3.5   # 轻轻弹起，落回转盘上，不会被甩下桥
			p.launched(0.2)
