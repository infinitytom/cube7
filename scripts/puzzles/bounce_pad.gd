class_name BouncePad
extends Zone
## 弹跳垫：把球弹向指定方向。关卡里用来代替自由跳跃，由设计决定能去哪里。

@export var launch := Vector3(0, 9, 0)
var _pad: MeshInstance3D
var _cool := 0.0

var _spring: Node3D

func _build() -> void:
	# Kenney 弹簧：被踩下时压扁再弹起
	_spring = Kit.model("platformer/spring")
	var b := Kit.bounds(_spring)
	var s := minf(box_size.x, box_size.z) * 0.8 / maxf(b.size.x, b.size.z)
	_spring.scale = Vector3.ONE * s
	_spring.position.y = -box_size.y * 0.5 - b.position.y * s
	add_child(_spring)
	_pad = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = minf(box_size.x, box_size.z) * 0.5
	cm.bottom_radius = cm.top_radius
	cm.height = 0.02
	cm.material = _glow_mat(Color("ff9ad5"), 0.8, 0.5)
	_pad.mesh = cm
	_pad.position.y = -box_size.y * 0.5 + 0.02
	add_child(_pad)

func _physics_process(delta: float) -> void:
	_cool -= delta
	if _cool > 0.0:
		return
	for b in get_overlapping_bodies():
		if b is RigidBody3D and not b.freeze:
			if b.has_method("launched"):
				b.launched(0.6)
			b.linear_velocity = Vector3(b.linear_velocity.x * 0.3, 0, b.linear_velocity.z * 0.3) + launch
			if b is MorphBall:
				(b as MorphBall)._jumped_now = true
			_cool = 0.4
			GameState.shake.emit(0.1)
			Sfx.play("boing", global_position, -3.0)
			var tw := create_tween()
			var base := _spring.scale
			_spring.scale = Vector3(base.x * 1.3, base.y * 0.5, base.z * 1.3)
			tw.tween_property(_spring, "scale", base, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
