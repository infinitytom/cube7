class_name BouncePad
extends Zone
## 弹跳垫：把球弹向指定方向。关卡里用来代替自由跳跃，由设计决定能去哪里。

@export var launch := Vector3(0, 9, 0)
var _pad: MeshInstance3D
var _cool := 0.0

func _build() -> void:
	_pad = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = minf(box_size.x, box_size.z) * 0.45
	cm.bottom_radius = cm.top_radius
	cm.height = 0.1
	cm.material = _glow_mat(Color("ff7bd5"), 1.5)
	_pad.mesh = cm
	_pad.position.y = -box_size.y * 0.5 + 0.06
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
			_cool = 0.4
			GameState.shake.emit(0.1)
			Sfx.play("boing", global_position, -3.0)
			var tw := create_tween()
			_pad.scale = Vector3(1.3, 1, 1.3)
			tw.tween_property(_pad, "scale", Vector3.ONE, 0.3)
