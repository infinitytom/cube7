class_name Rustfly
extends EnemyBase
## 锈蜂：被锈蚀的巡检无人机，在空中嗡嗡地盘旋。
## 行为：盘旋 → 发现 PIX 后飞到头顶 → 抖动蓄力（地上出现红色落点圈）→ 俯冲 → 扎进地里卡住 1.5 秒 → 飞回去
## 解法：
##   · 趁它扎在地上时撞它（任何形态都行）
##   · 跳起来撞 / 从上面踩它（滚球跳跃攻击）
##   · 气浪或泡泡弹把它打下来（掉在地上晕眩）
##   · 扔物件砸它
## 只有俯冲会伤到 PIX。

enum St { HOVER, CHASE, AIM, DIVE, STUCK, RISE }

var state := St.HOVER
var _t := 0.0
var _dive_dir := Vector3.DOWN
var _target := Vector3.ZERO
var _wings: Array[Node3D] = []
var _eye: StandardMaterial3D
var _ring: MeshInstance3D
var _bang: Label3D
var _buzz: AudioStreamPlayer3D
var hover_h := 2.6
var sight := 9.0

func _build() -> void:
	flying = true
	hp = 1
	coins = 3
	energy = 1
	var shape := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.32
	shape.shape = s
	shape.position.y = 0.3
	add_child(shape)
	var shell := mat(Color("f2a65a"), 0.0, 0.5)
	var dark := mat(Color("5b4a8a"), 0.0, 0.5)
	var glass := mat(Color("e9f4ff"), 0.0, 0.2)
	box(Vector3(0.5, 0.36, 0.56), shell, Vector3(0, 0.3, 0))
	# 蜜蜂一样的两道深色条纹 + 一根天线
	for zz in [0.02, 0.18]:
		box(Vector3(0.52, 0.38, 0.07), dark, Vector3(0, 0.3, zz))
	box(Vector3(0.04, 0.22, 0.04), dark, Vector3(0.1, 0.58, -0.18))
	ball(0.05, mat(Color("ffd166"), 1.5), Vector3(0.1, 0.7, -0.18))
	box(Vector3(0.3, 0.2, 0.3), dark, Vector3(0, 0.1, 0.12))
	# 尖尖的钻针（朝下偏前）
	var sting := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.09
	cm.bottom_radius = 0.0
	cm.height = 0.34
	sting.mesh = cm
	sting.material_override = dark
	sting.position = Vector3(0, -0.02, 0.05)
	body.add_child(sting)
	ball(0.13, glass, Vector3(0, 0.36, -0.28))
	_eye = mat(Color("2e3270"), 1.0, 0.3)
	ball(0.07, _eye, Vector3(0, 0.37, -0.37))
	for sx in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(sx * 0.22, 0.5, 0.05)
		body.add_child(pivot)
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.9, 0.95, 1.0, 0.55)
		wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wm.cull_mode = BaseMaterial3D.CULL_DISABLED
		box(Vector3(0.62, 0.02, 0.34), wm, Vector3(sx * 0.31, 0, 0), pivot)
		_wings.append(pivot)
	# 俯冲落点提示圈
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.45
	tm.outer_radius = 0.55
	_ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(1.0, 0.3, 0.3, 0.7)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring.material_override = rm
	_ring.top_level = true
	_ring.visible = false
	add_child(_ring)
	_bang = bang()
	_buzz = AudioStreamPlayer3D.new()
	var st := load("res://audio/sfx/drill.ogg") as AudioStream
	_buzz.stream = st
	_buzz.volume_db = -26.0
	_buzz.pitch_scale = 2.4
	_buzz.max_distance = 14.0
	_buzz.bus = "SFX"
	add_child(_buzz)

func _hit_size() -> Vector3:
	return Vector3(1.0, 0.9, 1.0)

func _can_trap() -> bool:
	return true

func _go(s: St) -> void:
	state = s
	_t = 0.0
	_bang.visible = s == St.AIM
	_eye.albedo_color = Color("ff4d4d") if s == St.AIM or s == St.DIVE else Color("2e3270")
	_eye.emission = _eye.albedo_color
	_ring.visible = s == St.AIM or s == St.DIVE
	match s:
		St.AIM:
			Sfx.play("enemy_windup", global_position, -2.0, 0.05)
		St.DIVE:
			Sfx.play("enemy_charge", global_position, -2.0, 0.05)

func _process(delta: float) -> void:
	var flap := 30.0 if state != St.STUCK and stun_t <= 0.0 else 0.0
	for i in _wings.size():
		_wings[i].rotation.z = sin(_anim * flap) * 0.6 * (1.0 if i == 0 else -1.0)
	if _buzz and not _buzz.playing and not dead and flap > 0.0 and state != St.STUCK:
		_buzz.play()
	elif _buzz and (flap == 0.0) and _buzz.playing:
		_buzz.stop()

func _ground_y(at: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.0, at + Vector3.DOWN * 12.0, 1 | 8)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit.position as Vector3).y if not hit.is_empty() else at.y - 3.0

func _ai(delta: float) -> void:
	_t += delta
	var p := player()
	var to_p := Vector3.ZERO
	if p:
		to_p = p.global_position - global_position
	var hv := Vector3.ZERO
	match state:
		St.HOVER:
			var a := _anim * 0.6
			var goal := home + Vector3(cos(a) * 1.5, sin(_anim * 1.7) * 0.25, sin(a) * 1.5)
			hv = (goal - global_position) * 2.0
			if p and Vector2(to_p.x, to_p.z).length() < sight and absf(to_p.y) < 5.0:
				Sfx.play("enemy_notice", global_position, -4.0, 0.08)
				_go(St.CHASE)
		St.CHASE:
			var goal := p.global_position + Vector3.UP * hover_h if p else home
			hv = (goal - global_position).limit_length(3.2)
			face(to_p, delta, 8.0)
			if _t > 1.2 and (goal - global_position).length() < 1.2:
				_go(St.AIM)
				_target = p.global_position
			elif p and Vector2(to_p.x, to_p.z).length() > sight * 1.8:
				_go(St.RISE)
		St.AIM:
			# 盯着 PIX 抖动，落点圈跟着 PIX 走（最后 0.25 秒锁定）
			if p and _t < 0.55:
				_target = p.global_position
			var gy := _ground_y(_target)
			_ring.global_position = Vector3(_target.x, gy + 0.05, _target.z)
			_ring.scale = Vector3.ONE * (1.4 - _t * 0.6)
			body.position.x = sin(_anim * 70.0) * 0.05
			hv = Vector3.ZERO
			if _t > 0.8:
				body.position.x = 0.0
				_dive_dir = (Vector3(_target.x, gy + 0.3, _target.z) - global_position).normalized()
				_go(St.DIVE)
		St.DIVE:
			hv = _dive_dir * 11.0
			face(Vector3(_dive_dir.x, 0, _dive_dir.z), delta, 12.0)
			if (is_on_floor() or is_on_wall()) and _t > 0.05 or _t > 1.0:
				GameState.shake.emit(0.12)
				Sfx.play("thud", global_position, -4.0, 0.1)
				_go(St.STUCK)
		St.STUCK:
			hv = Vector3.ZERO
			body.rotation.x = -0.6
			body.position.x = sin(_anim * 30.0) * 0.02
			if _t > 1.6:
				body.rotation.x = 0.0
				_go(St.RISE)
		St.RISE:
			var goal := home
			hv = (goal - global_position).limit_length(3.0)
			if (goal - global_position).length() < 0.5 or _t > 4.0:
				_go(St.HOVER)
	velocity = hv

func vulnerable() -> bool:
	return super.vulnerable() or state == St.STUCK

func _contact(p: MorphBall) -> void:
	if state == St.DIVE:
		p.hurt(global_position)
		_go(St.STUCK)
		return
	# 空中撞它：滚球冲撞 / 高速碰到 / 钻头都能打下来
	if p.attack != "" and p.attack != "pound":
		take_hit(p.global_position, p.attack)
	elif not p.is_invulnerable():
		var away := p.global_position - global_position
		p.apply_central_impulse(away.normalized() * 1.2 * p.mass)

## 被气浪 / 震波打中：掉到地上晕眩
func on_wave(from: Vector3) -> void:
	if dead:
		return
	var away := global_position - from
	away.y = 0.0
	knock = away.normalized() * 6.0
	stun(3.0, true)
	_go(St.STUCK)
	_ring.visible = false

func on_pound(from: Vector3) -> void:
	# 飞在空中的它不怕地面震波；卡在地上时会被震翻
	if state == St.STUCK:
		super.on_pound(from)

func _on_recover() -> void:
	_go(St.RISE)
	body.rotation.x = 0.0

func _flip_lift() -> float:
	return 0.5

func defeat(drops: bool) -> void:
	_ring.queue_free()
	super.defeat(drops)
