class_name BeamMirror
extends StaticBody3D
## 可转动的晶面镜：立在一个小底座上，撞它（冲撞 / 钻 / 高速碰）就顺时针转 45°。
## 光束打到镜面上按镜面法线反射；打到背面（深色的底板）就被挡住。
## 朝向用 facing 表示（0..7，每档 45°），镜面法线 = 水平方向 facing × 45°。

signal turned(facing: int)

@export var facing := 0
var locked := false
var _pivot: Node3D
var _cd := 0.0
var _area: Area3D
var _glow: StandardMaterial3D

func _ready() -> void:
	add_to_group("beam_mirror")
	collision_layer = 1
	collision_mask = 0
	var base := CollisionShape3D.new()
	var bb := BoxShape3D.new()
	bb.size = Vector3(0.9, 0.5, 0.9)
	base.shape = bb
	base.position.y = 0.25
	add_child(base)
	var mb := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.5, 0.9)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color("5b5470")
	bmat.roughness = 0.6
	bm.material = bmat
	mb.mesh = bm
	mb.position.y = 0.25
	add_child(mb)
	_pivot = Node3D.new()
	_pivot.position.y = 0.5
	add_child(_pivot)
	# 镜面：一块发光的晶板（正面亮青色，背面深紫）
	var front := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(1.0, 1.0, 0.08)
	_glow = StandardMaterial3D.new()
	_glow.albedo_color = Color("bff6ff")
	_glow.emission_enabled = true
	_glow.emission = Color("6fe3ff")
	_glow.emission_energy_multiplier = 0.8
	_glow.metallic = 0.6
	_glow.roughness = 0.1
	fm.material = _glow
	front.mesh = fm
	front.position = Vector3(0, 0.5, -0.03)
	_pivot.add_child(front)
	var back := MeshInstance3D.new()
	var bk := BoxMesh.new()
	bk.size = Vector3(1.06, 1.06, 0.08)
	var bkm := StandardMaterial3D.new()
	bkm.albedo_color = Color("3d3552")
	bk.material = bkm
	back.mesh = bk
	back.position = Vector3(0, 0.5, 0.05)
	_pivot.add_child(back)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.0, 0.2)
	cs.shape = box
	cs.position = Vector3(0, 1.0, 0)
	cs.name = "Plate"
	add_child(cs)
	_plate = cs
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	var acs := CollisionShape3D.new()
	var ab := BoxShape3D.new()
	ab.size = Vector3(1.6, 1.6, 1.6)
	acs.shape = ab
	acs.position.y = 0.7
	_area.add_child(acs)
	add_child(_area)
	_apply(false)

var _plate: CollisionShape3D

## 镜面法线（世界空间，水平）
func normal() -> Vector3:
	var a := facing * PI / 4.0
	return Vector3(-sin(a), 0, -cos(a))

func _apply(anim: bool) -> void:
	var yaw := facing * PI / 4.0
	_plate.rotation.y = yaw
	if anim:
		var tw := create_tween()
		tw.tween_property(_pivot, "rotation:y", yaw, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_pivot.rotation.y = yaw

func turn(step := 1) -> void:
	if locked:
		return
	var old_yaw := _pivot.rotation.y
	facing = posmod(facing + step, 8)
	# 保持补间连续（不绕一大圈）
	_pivot.rotation.y = old_yaw
	var target := old_yaw + step * PI / 4.0
	_plate.rotation.y = facing * PI / 4.0
	var tw := create_tween()
	tw.tween_property(_pivot, "rotation:y", target, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("clang", global_position, -4.0, 0.05, 1.4)
	turned.emit(facing)

func lit(on: bool) -> void:
	_glow.emission_energy_multiplier = 2.5 if on else 0.8

func _physics_process(delta: float) -> void:
	_cd -= delta
	if _cd > 0.0 or locked:
		return
	var p := GameState.player as MorphBall
	if p == null or not _area.overlaps_body(p):
		return
	var sp := Vector3(p.linear_velocity.x, 0, p.linear_velocity.z).length()
	if p.attack != "" or sp > 3.5:
		_cd = 0.6
		turn(1)
		# 把 PIX 轻轻弹开，免得一直贴着连转
		var away := p.global_position - global_position
		away.y = 0.0
		p.linear_velocity = away.normalized() * 3.5 + Vector3.UP * 2.0
		p.launched(0.2)
