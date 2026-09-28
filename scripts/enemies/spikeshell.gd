class_name Spikeshell
extends EnemyBase
## 刺壳虫：背着一身尖刺的锈蚀清扫机，慢慢地朝 PIX 爬过来。
## 尖刺竖起时碰它（包括冲撞、踩它）都会被扎；尖刺每隔几秒会缩回去喘口气（先抖一抖提示）。
## 解法：
##   · 趁尖刺缩回时冲撞它（要撞两下）
##   · 钻头无视尖刺，直接钻穿外壳
##   · 下砸 / 气浪把它掀翻，翻过来肚皮朝上时随便打
##   · 扔物件砸它

var _t := 0.0
var spikes_up := true
var _spikes: Array[Node3D] = []
var _rattle := false
var _eye: StandardMaterial3D
var speed := 1.1
var sight := 8.0

func _build() -> void:
	hp = 2
	coins = 5
	energy = 2
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(0.9, 0.6, 1.0)
	shape.shape = b
	shape.position.y = 0.3
	add_child(shape)
	var shell := mat(Color("7fc8a9"), 0.0, 0.55)
	var belly := mat(Color("ffd9a8"), 0.0, 0.7)
	var spike_m := mat(Color("f25f5c"), 0.3, 0.4, 0.2)
	box(Vector3(0.95, 0.42, 1.05), shell, Vector3(0, 0.36, 0))
	box(Vector3(0.8, 0.16, 0.9), belly, Vector3(0, 0.1, 0))
	# 脸
	box(Vector3(0.6, 0.3, 0.12), belly, Vector3(0, 0.3, -0.55))
	_eye = mat(Color("2e3270"), 1.0, 0.3)
	for sx in [-0.14, 0.14]:
		ball(0.07, _eye, Vector3(sx, 0.34, -0.62))
	# 背上的尖刺（能缩回去）
	for x in [-0.3, 0.0, 0.3]:
		for z in [-0.3, 0.05, 0.38]:
			var pivot := Node3D.new()
			pivot.position = Vector3(x, 0.55, z)
			body.add_child(pivot)
			var sp := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = 0.1
			cm.height = 0.36
			cm.radial_segments = 6
			sp.mesh = cm
			sp.material_override = spike_m
			sp.position.y = 0.16
			pivot.add_child(sp)
			_spikes.append(pivot)
	# 小短腿
	for x in [-0.36, 0.36]:
		for z in [-0.3, 0.3]:
			box(Vector3(0.14, 0.14, 0.14), belly, Vector3(x, 0.02, z))

func _hit_size() -> Vector3:
	return Vector3(1.3, 1.1, 1.4)

func _stompable() -> bool:
	return not spikes_up

func _process(delta: float) -> void:
	for sp in _spikes:
		var target := 1.0 if spikes_up or flipped else 0.15
		sp.scale.y = lerpf(sp.scale.y, target, 1.0 - exp(-14.0 * delta))
		sp.rotation.z = sin(_anim * 60.0) * 0.12 if _rattle else 0.0

func _ai(delta: float) -> void:
	_t += delta
	# 尖刺节奏：竖起 3.2 秒（最后 0.7 秒抖动提示）→ 缩回 1.8 秒
	if spikes_up:
		_rattle = _t > 2.5
		if _t > 3.2:
			spikes_up = false
			_rattle = false
			_t = 0.0
			Sfx.play("unlock", global_position, -10.0, 0.1)
	else:
		if _t > 1.8:
			spikes_up = true
			_t = 0.0
			Sfx.play("clang", global_position, -8.0, 0.1)
	var p := player()
	var hv := Vector3.ZERO
	if p:
		var to_p := p.global_position - global_position
		to_p.y = 0.0
		if to_p.length() < sight and absf(p.global_position.y - global_position.y) < 2.5:
			face(to_p, delta, 3.0)
			var fwd := -basis.z
			if ground_ahead(fwd) and to_p.length() > 0.8:
				hv = fwd * speed * (0.4 if not spikes_up else 1.0)
		else:
			var d := home - global_position
			d.y = 0.0
			if d.length() > 0.5:
				face(d, delta, 3.0)
				hv = -basis.z * speed * 0.6
	velocity.x = hv.x
	velocity.z = hv.z

func _contact(p: MorphBall) -> void:
	var atk := p.attack
	if atk == "drill" or atk == "pound":
		take_hit(p.global_position, atk)
		if not dead:
			take_hit(p.global_position, atk)   # 钻头一下就钻穿
		return
	if spikes_up:
		# 被扎到：弹开 + 受伤
		if not p.is_invulnerable():
			p.hurt(global_position)
		return
	if atk == "ram":
		take_hit(p.global_position, atk)
	elif not p.is_invulnerable():
		var away := p.global_position - global_position
		away.y = 0.0
		p.apply_central_impulse(away.normalized() * 1.5 * p.mass)

func _on_hurt(from: Vector3, kind: String) -> void:
	super._on_hurt(from, kind)
	spikes_up = true
	_t = 1.0

func _on_recover() -> void:
	spikes_up = true
	_t = 0.0
