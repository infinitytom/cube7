class_name Burrower
extends EnemyBase
## 钻地鼹：躲在地下，地面上只看得见一道拱起来的土包在追你。
## 追到你脚下会停住、地面震动冒土（预兆 0.8 秒）→ 从地里猛地钻出来（被顶到会受伤）→ 露在外面喘气 2 秒 → 钻回去。
## 解法：
##   · 它露出来喘气的时候撞它、踩它
##   · 钻头下砸震它：躲在地下的它会被震出来，四脚朝天
##   · 气浪、泡泡弹、扔东西（露出来的时候）

enum St { HIDDEN, TELL, POP, EXPOSED, DIVE }

var state := St.HIDDEN
var _t := 0.0
var _mound: Node3D
var _dust: CPUParticles3D
var _shape: CollisionShape3D
var speed := 2.2
var roam := 7.0
var sight := 9.0

func _build() -> void:
	hp = 1
	coins = 4
	energy = 2
	_shape = CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(0.8, 0.7, 0.8)
	_shape.shape = b
	_shape.position.y = 0.35
	add_child(_shape)
	var fur := mat(Color("8e6ee0"), 0.0, 0.8)
	var belly := mat(Color("ffd9a8"), 0.0, 0.8)
	var nose := mat(Color("ff7ab8"), 0.6, 0.4)
	var claw := mat(Color("e4e7ff"), 0.0, 0.3, 0.3)
	ball(0.42, fur, Vector3(0, 0.42, 0))
	ball(0.28, belly, Vector3(0, 0.36, -0.2))
	ball(0.09, nose, Vector3(0, 0.46, -0.44))
	var eye := mat(Color("2e3270"), 0.5, 0.3)
	for sx in [-0.14, 0.14]:
		ball(0.05, eye, Vector3(sx, 0.6, -0.34))
	# 钻头一样的爪子
	for sx in [-0.34, 0.34]:
		var c := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.1
		cm.height = 0.28
		c.mesh = cm
		c.material_override = claw
		c.position = Vector3(sx, 0.3, -0.3)
		c.rotation.x = -1.2
		body.add_child(c)
	# 地面上的土包（躲着时唯一能看到的东西）
	_mound = Node3D.new()
	add_child(_mound)
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color("9a6a48")
	for k in 5:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * randf_range(0.18, 0.3)
		mi.mesh = bm
		mi.material_override = dirt
		mi.position = Vector3(randf_range(-0.3, 0.3), 0.05, randf_range(-0.3, 0.3))
		mi.rotation = Vector3(randf(), randf(), randf())
		_mound.add_child(mi)
	_dust = CPUParticles3D.new()
	_dust.amount = 16
	_dust.lifetime = 0.6
	_dust.emitting = false
	_dust.direction = Vector3.UP
	_dust.spread = 40.0
	_dust.initial_velocity_min = 1.0
	_dust.initial_velocity_max = 2.5
	var dm := BoxMesh.new()
	dm.size = Vector3.ONE * 0.08
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color("b98a62")
	dm.material = dmat
	_dust.mesh = dm
	add_child(_dust)
	_go(St.HIDDEN)

func _hit_size() -> Vector3:
	return Vector3(1.1, 1.0, 1.1)

func _go(s: St) -> void:
	state = s
	_t = 0.0
	var hidden := s == St.HIDDEN or s == St.TELL
	body.visible = not hidden
	_mound.visible = hidden
	_shape.disabled = hidden
	flying = hidden
	if hidden:
		velocity.y = 0.0
	_dust.emitting = s == St.TELL or s == St.POP
	if s == St.POP:
		Sfx.play("break_soft", global_position, 0.0, 0.1, 0.8)
		GameState.shake.emit(0.15)
	elif s == St.TELL:
		Sfx.play("drill", global_position, -8.0, 0.1, 0.6)

func vulnerable() -> bool:
	return super.vulnerable() or state == St.EXPOSED

func _can_trap() -> bool:
	return state == St.EXPOSED

func _stompable() -> bool:
	return state == St.EXPOSED or state == St.DIVE

func _ai(delta: float) -> void:
	_t += delta
	var p := player()
	var hv := Vector3.ZERO
	match state:
		St.HIDDEN:
			_mound.rotation.y += delta * 6.0
			if p:
				var to_p := p.global_position - global_position
				to_p.y = 0.0
				var from_home := (p.global_position - home)
				from_home.y = 0.0
				if to_p.length() < sight and from_home.length() < roam + 2.0 and absf(p.global_position.y - global_position.y) < 2.0:
					if to_p.length() < 0.5 and _t > 0.8:
						_go(St.TELL)
					else:
						hv = to_p.normalized() * speed
				else:
					var back := home - global_position
					back.y = 0.0
					if back.length() > 0.3:
						hv = back.normalized() * speed * 0.6
			if not ground_ahead(hv.normalized() if hv.length() > 0.01 else Vector3.FORWARD, 0.5):
				hv = Vector3.ZERO
		St.TELL:
			_mound.position.x = sin(_anim * 60.0) * 0.05
			if _t > 0.8:
				_mound.position.x = 0.0
				_go(St.POP)
				velocity.y = 6.0
		St.POP:
			body.rotation.y += delta * 8.0
			if _t > 0.25:
				_go(St.EXPOSED)
		St.EXPOSED:
			body.rotation.z = sin(_anim * 5.0) * 0.1
			if _t > 2.2:
				body.rotation.z = 0.0
				_go(St.DIVE)
		St.DIVE:
			body.position.y = -_t * 2.0
			if _t > 0.4:
				body.position.y = 0.0
				_go(St.HIDDEN)
	velocity.x = hv.x
	velocity.z = hv.z

func _check_contact() -> void:
	if state == St.HIDDEN or state == St.TELL:
		return
	var p := player()
	if p and state == St.POP and hit_area.overlaps_body(p) and not p.is_invulnerable():
		p.hurt(global_position)
		return
	super._check_contact()

func on_pound(from: Vector3) -> void:
	if dead:
		return
	if state == St.HIDDEN or state == St.TELL:
		_go(St.EXPOSED)
		velocity.y = 5.0
		stun(3.0, true)
		FloatText.spawn(get_parent(), global_position + Vector3.UP * 1.0, "震出来了！", Color("ffb03b"), 44, 1.0)
		return
	super.on_pound(from)

func on_wave(from: Vector3) -> void:
	if state == St.EXPOSED or state == St.DIVE:
		super.on_wave(from)

func on_item(item: Node3D) -> void:
	if state == St.EXPOSED or state == St.DIVE:
		super.on_item(item)

func _on_recover() -> void:
	_go(St.DIVE)
