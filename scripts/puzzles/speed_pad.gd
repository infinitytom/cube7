class_name SpeedPad
extends Zone
## 加速带（马里奥赛车的冲刺板）：滚上去瞬间被推到高速，顺着箭头方向冲出去。

@export var dir := Vector3(1, 0, 0)
@export var speed := 15.0
var _model: Node3D
var _cool := 0.0
var _t := 0.0

func _build() -> void:
	_model = Node3D.new()
	add_child(_model)
	for k in 2:
		var a := Kit.model("factory/arrow")
		var b := Kit.bounds(a)
		var s := 0.9 / maxf(b.size.x, b.size.z)
		a.scale = Vector3.ONE * s
		a.position = Vector3(0, -box_size.y * 0.5 - b.position.y * s + 0.02, (k - 0.5) * 0.7)
		_model.add_child(a)
	_model.basis = Basis.looking_at(Vector3(dir.x, 0, dir.z).normalized(), Vector3.UP) * Basis(Vector3.UP, -PI / 2.0)

func _process(delta: float) -> void:
	_t += delta
	_model.position.y = 0.02 * sin(_t * 8.0)

func _physics_process(delta: float) -> void:
	_cool -= delta
	if _cool > 0.0:
		return
	for b in get_overlapping_bodies():
		if b == GameState.player:
			var p := b as RigidBody3D
			var d := Vector3(dir.x, 0, dir.z).normalized()
			var vh := Vector3(p.linear_velocity.x, 0, p.linear_velocity.z)
			var along := maxf(vh.dot(d), 0.0)
			p.linear_velocity = d * maxf(speed, along) + Vector3.UP * maxf(p.linear_velocity.y, 0.0)
			if p.has_method("launched"):
				p.launched(0.2)
			_cool = 0.5
			Sfx.play("dash", global_position, 0.0, 0.05, 1.2)
			GameState.shake.emit(0.08)
