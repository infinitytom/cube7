class_name Sentinel
extends EnemyBase
## 锈哨兵：城里的旧治安探照灯，站在原地来回扫视。
## 被它的光照到 0.6 秒 → 拉响警报（光变红）→ 从背后的仓里放出两只锈蜂；警报 6 秒后解除。
## 解法：
##   · 躲着光走（光在地上有一块亮斑）
##   · 从光照不到的背后或侧面撞它、踩它
##   · 钻头 / 下砸随时都能打
##   · 气浪、扔东西会把它打晕一会儿（灯灭掉）

var sweep := 70.0             ## 左右扫视的角度（度）
var sweep_speed := 0.55
var reach := 10.0
var cone := 16.0              ## 光锥半角（度）
var _t := 0.0
var _seen := 0.0
var alarm := 0.0
var _head: Node3D
var _lamp: SpotLight3D
var _cone_mi: MeshInstance3D
var _cone_mat: StandardMaterial3D
var _spot: MeshInstance3D
var _spawned: Array = []
var _base_yaw := 0.0
var _siren: AudioStreamPlayer3D

func _build() -> void:
	hp = 1
	coins = 5
	energy = 2
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(0.8, 1.6, 0.8)
	shape.shape = b
	shape.position.y = 0.8
	add_child(shape)
	var hull := mat(Color("e9edf2"), 0.0, 0.4, 0.2)
	var dark := mat(Color("3d4659"), 0.0, 0.4, 0.3)
	var rust := mat(Color("b5653e"), 0.0, 0.7)
	box(Vector3(1.0, 0.3, 1.0), dark, Vector3(0, 0.15, 0))
	box(Vector3(0.5, 1.1, 0.5), hull, Vector3(0, 0.8, 0))
	box(Vector3(0.52, 0.2, 0.52), rust, Vector3(0, 0.6, 0))
	_head = Node3D.new()
	_head.position.y = 1.5
	body.add_child(_head)
	box(Vector3(0.7, 0.45, 0.6), hull, Vector3.ZERO, _head)
	var lens := mat(Color("fff3b0"), 2.5, 0.2)
	ball(0.18, lens, Vector3(0, 0, -0.3), _head)
	box(Vector3(0.3, 0.3, 0.3), dark, Vector3(0, 0.1, 0.35), _head)
	_lamp = SpotLight3D.new()
	_lamp.light_color = Color("fff3b0")
	_lamp.light_energy = 3.0
	_lamp.spot_range = reach + 2.0
	_lamp.spot_angle = cone
	_lamp.shadow_enabled = false
	_lamp.position = Vector3(0, 0, -0.35)
	_head.add_child(_lamp)
	# 看得见的光锥
	_cone_mi = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.1
	cm.bottom_radius = tan(deg_to_rad(cone)) * reach
	cm.height = reach
	cm.radial_segments = 16
	cm.cap_top = false
	cm.cap_bottom = false
	_cone_mi.mesh = cm
	_cone_mat = StandardMaterial3D.new()
	_cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cone_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cone_mat.albedo_color = Color(1.0, 0.95, 0.6, 0.12)
	_cone_mi.material_override = _cone_mat
	_cone_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_head.add_child(_cone_mi)
	_head.rotation.x = -deg_to_rad(18.0)
	_cone_mi.rotation.x = PI / 2.0
	_cone_mi.position = Vector3(0, 0, -reach * 0.5)
	_siren = AudioStreamPlayer3D.new()
	_siren.stream = load("res://audio/sfx/enemy_windup.ogg")
	_siren.bus = "SFX"
	_siren.volume_db = -2.0
	add_child(_siren)

func _hit_size() -> Vector3:
	return Vector3(1.3, 2.0, 1.3)

func _can_trap() -> bool:
	return false

func _stompable() -> bool:
	return true

func _flip_lift() -> float:
	return 0.0

func _ai(delta: float) -> void:
	_t += delta
	velocity = Vector3.ZERO
	if _t < 0.1:
		_base_yaw = rotation.y
	var p := player()
	if alarm > 0.0:
		alarm -= delta
		_cone_mat.albedo_color = Color(1.0, 0.25, 0.2, 0.16 + 0.08 * sin(_anim * 20.0))
		_lamp.light_color = Color(1.0, 0.3, 0.25)
		if p:
			var to_p := p.global_position - global_position
			var want := atan2(-to_p.x, -to_p.z) - rotation.y
			_head.rotation.y = lerp_angle(_head.rotation.y, want, 1.0 - exp(-4.0 * delta))
		if alarm <= 0.0:
			_cone_mat.albedo_color = Color(1.0, 0.95, 0.6, 0.12)
			_lamp.light_color = Color("fff3b0")
		return
	_head.rotation.y = sin(_t * sweep_speed) * deg_to_rad(sweep)
	if p == null:
		return
	# 光锥检测：距离、角度、视线
	var eye := _head.global_position
	var fwd := -_head.global_basis.z
	var to := p.global_position - eye
	var dist := to.length()
	var seen := false
	if dist < reach and fwd.angle_to(to) < deg_to_rad(cone + 4.0):
		var q := PhysicsRayQueryParameters3D.create(eye, p.global_position, 1)
		seen = get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	_seen = _seen + delta if seen else maxf(0.0, _seen - delta * 2.0)
	_cone_mat.albedo_color = Color(1.0, lerpf(0.95, 0.5, _seen / 0.6), lerpf(0.6, 0.3, _seen / 0.6), 0.12 + _seen * 0.1)
	if _seen > 0.6:
		_seen = 0.0
		_raise_alarm()

func _raise_alarm() -> void:
	alarm = 6.0
	_siren.play()
	FloatText.spawn(get_parent(), global_position + Vector3.UP * 2.4, "警报！", Color("ff4d4d"), 56, 1.2)
	Sfx.play("enemy_notice", global_position, 2.0, 0.0, 1.2)
	_spawned = _spawned.filter(func(e) -> bool: return is_instance_valid(e))
	for k in 2 - _spawned.size():
		var f := Rustfly.new()
		get_parent().add_child(f)
		f.global_position = global_position + Vector3(randf_range(-1, 1), 2.4, randf_range(-1, 1))
		f.sight = 14.0
		f.coins = 1
		f.energy = 0
		_spawned.append(f)

func _contact(p: MorphBall) -> void:
	var atk := p.attack
	if atk == "drill" or atk == "pound":
		take_hit(p.global_position, atk)
		return
	# 正面（灯照着的方向）撞会被弹开；侧面、背后一撞就碎
	var to_p := p.global_position - global_position
	to_p.y = 0.0
	var front := (-_head.global_basis.z).dot(to_p.normalized()) > 0.6 and alarm <= 0.0
	if atk == "ram" and not front:
		take_hit(p.global_position, atk)
	elif atk == "ram":
		Sfx.play("clang", global_position, 0.0, 0.05)
		p.linear_velocity = to_p.normalized() * 6.0 + Vector3.UP * 3.0
		p.launched(0.3)
		_raise_alarm()
	elif not p.is_invulnerable():
		p.apply_central_impulse(to_p.normalized() * 1.5 * p.mass)

func on_wave(_from: Vector3) -> void:
	stun(3.0, false)
	_lamp.visible = false
	_cone_mi.visible = false

func _on_recover() -> void:
	_lamp.visible = true
	_cone_mi.visible = true
