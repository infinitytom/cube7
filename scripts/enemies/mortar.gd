class_name Mortar
extends EnemyBase
## 锈炮台：固定在地上，每隔几秒朝 PIX 抛一颗慢慢飞的锈弹（地上有红色落点提示）。
## 解法：
##   · 边躲炮弹边冲过去撞它（它背后没有装甲，从哪边撞都行，但炮口正面要撞两下）
##   · 气浪把飞来的锈弹原路打回去，炸它自己
##   · 钻头 / 下砸
##   · 扔物件砸它

var _t := 0.0
var _barrel: Node3D
var _eye: StandardMaterial3D
var interval := 3.0
var reach := 13.0
var _bang: Label3D

func _build() -> void:
	hp = 2
	coins = 6
	energy = 2
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(0.9, 0.8, 0.9)
	shape.shape = b
	shape.position.y = 0.4
	add_child(shape)
	var base := mat(Color("8e6ee0"), 0.0, 0.5)
	var hull := mat(Color("f28b6c"), 0.0, 0.5)
	var dark := mat(Color("3d4659"), 0.0, 0.4, 0.3)
	box(Vector3(1.0, 0.3, 1.0), base, Vector3(0, 0.15, 0))
	ball(0.42, hull, Vector3(0, 0.55, 0))
	_barrel = Node3D.new()
	_barrel.position = Vector3(0, 0.7, 0)
	body.add_child(_barrel)
	var tube := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.17
	cm.bottom_radius = 0.2
	cm.height = 0.6
	tube.mesh = cm
	tube.material_override = dark
	tube.position = Vector3(0, 0.22, -0.12)
	tube.rotation.x = -0.5
	_barrel.add_child(tube)
	_eye = mat(Color("2e3270"), 1.2, 0.3)
	ball(0.1, _eye, Vector3(0, 0.62, -0.38))
	_bang = bang()

func _hit_size() -> Vector3:
	return Vector3(1.3, 1.2, 1.3)

func _can_trap() -> bool:
	return false      # 太重，泡泡困不住，只会被打晕一下

func _ai(delta: float) -> void:
	_t += delta
	velocity.x = 0.0
	velocity.z = 0.0
	var p := player()
	if p == null:
		return
	var to_p := p.global_position - global_position
	var dist := Vector2(to_p.x, to_p.z).length()
	if dist > reach or absf(to_p.y) > 6.0:
		_t = minf(_t, interval - 0.8)
		_bang.visible = false
		return
	face(to_p, delta, 5.0)
	# 开炮前 0.6 秒：眼睛变红、炮管抖动
	var warn := _t > interval - 0.6
	_bang.visible = warn
	_eye.albedo_color = Color("ff4d4d") if warn else Color("2e3270")
	_eye.emission = _eye.albedo_color
	_barrel.position.y = 0.7 + (sin(_anim * 50.0) * 0.03 if warn else 0.0)
	if _t > interval:
		_t = 0.0
		_fire(p)

func _fire(p: MorphBall) -> void:
	# 预判一点点：瞄准 PIX 前方 0.4 秒的位置
	var target := p.global_position + Vector3(p.linear_velocity.x, 0, p.linear_velocity.z) * 0.4 + Vector3.DOWN * 0.3
	var from := global_position + Vector3.UP * 1.1 + (-basis.z) * 0.4
	RustBomb.launch(get_parent(), from, target, 1.35, self)
	Sfx.play("throw", global_position, 0.0, 0.1)
	var tw := create_tween()
	tw.tween_property(_barrel, "scale", Vector3(1.2, 0.7, 1.2), 0.06)
	tw.tween_property(_barrel, "scale", Vector3.ONE, 0.2)

func _contact(p: MorphBall) -> void:
	var atk := p.attack
	if atk == "drill" or atk == "pound" or atk == "ram":
		take_hit(p.global_position, atk)
	elif not p.is_invulnerable():
		var away := p.global_position - global_position
		away.y = 0.0
		p.apply_central_impulse(away.normalized() * 1.5 * p.mass)

func _on_hurt(from: Vector3, _kind: String) -> void:
	stun(1.5, false)
	_t = 0.0
	var away := global_position - from
	away.y = 0.0
	knock = away.normalized() * 1.5
