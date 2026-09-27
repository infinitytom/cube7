class_name Scrapling
extends CharacterBody3D
## 第一种敌人「锈块兽」：被异变侵蚀的维护机器，方块身体，正面有一块合金盾。
## 行为（机制战斗，不拼手速）：
##   巡逻 → 发现 PIX（头顶“!”）→ 蓄力 0.7 秒（眼睛变红、抖动）→ 直线冲锋 → 撞墙或冲完后晕眩 1.2 秒
## 弱点（每种形态一种解法）：
##   滚球：正面冲撞会被盾弹开；绕到侧面/背后撞，或趁它晕眩时撞 → 击破
##   钻头：钻头无视盾牌；空中下砸会把附近的它震翻（翻倒时任何攻击都能击破）
##   气泡：气浪把它推开并掀翻；推下悬崖也算击破
## 只有冲锋会伤到 PIX；平时碰到只会被轻轻推开。

enum St { PATROL, NOTICE, WINDUP, CHARGE, DIZZY, FLIPPED, DEAD }

@export var patrol_radius := 3.0
@export var sight := 7.0
@export var charge_speed := 7.5
@export var walk_speed := 1.4

var state := St.PATROL
var home := Vector3.ZERO
var _t := 0.0
var _dir := Vector3.FORWARD
var _target := Vector3.ZERO
var _body: Node3D
var _eye_mat: StandardMaterial3D
var _legs: Array[Node3D] = []
var _bang: Label3D
var _hit_area: Area3D
var _flip_amt := 0.0
var _anim := 0.0
var _knock := Vector3.ZERO
var _home_set := false
var ai := true            ## 自动测试时可关掉 AI，只保留受击判定

const GRAVITY := 22.0
const EYE_CALM := Color("4dfcff")
const EYE_ANGRY := Color("ff4d4d")

func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 16
	collision_mask = 1 | 8
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 0.7, 0.8)
	shape.shape = box
	shape.position.y = 0.35
	add_child(shape)
	_build_visual()
	# 与 PIX 接触的检测区（比身体大一圈）
	_hit_area = Area3D.new()
	_hit_area.collision_layer = 0
	_hit_area.collision_mask = 2
	var hs := CollisionShape3D.new()
	var hb := BoxShape3D.new()
	hb.size = Vector3(1.25, 1.0, 1.25)
	hs.shape = hb
	hs.position.y = 0.4
	_hit_area.add_child(hs)
	add_child(_hit_area)


func _build_visual() -> void:
	_body = Node3D.new()
	add_child(_body)
	var rust := _mat(Color("8a4b32"), 0.0, 0.8)
	var dark := _mat(Color("3a2a26"), 0.0, 0.7)
	var steel := _mat(Color("b8c4d6"), 0.0, 0.35, 0.6)
	var core := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.8, 0.62, 0.8)
	core.mesh = bm
	core.material_override = rust
	core.position.y = 0.42
	_body.add_child(core)
	# 背上的锈块凸起
	for p in [Vector3(-0.18, 0.8, 0.15), Vector3(0.2, 0.78, 0.22), Vector3(0.05, 0.82, -0.05)]:
		var k := MeshInstance3D.new()
		var km := BoxMesh.new()
		km.size = Vector3.ONE * 0.22
		k.mesh = km
		k.material_override = dark
		k.position = p
		_body.add_child(k)
	# 正面的合金盾（朝 -Z）
	var shield := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.92, 0.66, 0.1)
	shield.mesh = sm
	shield.material_override = steel
	shield.position = Vector3(0, 0.44, -0.45)
	_body.add_child(shield)
	# 独眼（在盾牌上方的一条缝里）
	_eye_mat = _mat(EYE_CALM, 4.0)
	var eye := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(0.36, 0.08, 0.04)
	eye.mesh = em
	eye.material_override = _eye_mat
	eye.position = Vector3(0, 0.62, -0.51)
	_body.add_child(eye)
	# 四条小腿
	for x in [-0.28, 0.28]:
		for z in [-0.26, 0.26]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.14, 0.2, 0.14)
			leg.mesh = lm
			leg.material_override = dark
			leg.position = Vector3(x, 0.1, z)
			_body.add_child(leg)
			_legs.append(leg)
	_bang = Label3D.new()
	_bang.text = "!"
	_bang.font_size = 96
	_bang.outline_size = 18
	_bang.modulate = Color("ffd166")
	_bang.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bang.no_depth_test = true
	_bang.position.y = 1.35
	_bang.visible = false
	add_child(_bang)

func _mat(c: Color, emission := 0.0, rough := 0.7, metal := 0.1) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	return m

# ================================================================ 行为

func _pick_patrol() -> void:
	var a := randf() * TAU
	_target = home + Vector3(cos(a), 0, sin(a)) * randf_range(1.0, patrol_radius)

func _player() -> MorphBall:
	return GameState.player as MorphBall

func _physics_process(delta: float) -> void:
	if state == St.DEAD:
		return
	if not _home_set:
		_home_set = true
		home = global_position
		_pick_patrol()
	_t += delta
	_anim += delta
	var p := _player()
	var to_p := Vector3.ZERO
	if p:
		to_p = p.global_position - global_position
		to_p.y = 0.0
	var hv := Vector3.ZERO
	var st := state if ai or state == St.FLIPPED else -1
	match st:
		St.PATROL:
			var d := _target - global_position
			d.y = 0.0
			if d.length() < 0.3 or _t > 5.0 or not _ground_ahead(d.normalized()):
				_t = 0.0
				_pick_patrol()
			else:
				_face(d.normalized(), delta, 4.0)
				hv = -basis.z * walk_speed
			if p and to_p.length() < sight and absf(p.global_position.y - global_position.y) < 2.5:
				_set_state(St.NOTICE)
		St.NOTICE:
			_face(to_p.normalized(), delta, 12.0)
			if _t > 0.45:
				_set_state(St.WINDUP)
		St.WINDUP:
			_face(to_p.normalized(), delta, 8.0)
			_body.position.x = sin(_anim * 60.0) * 0.04
			if _t > 0.7:
				_body.position.x = 0.0
				_dir = -basis.z
				_set_state(St.CHARGE)
		St.CHARGE:
			hv = _dir * charge_speed
			if _t > 1.1 or (is_on_wall() and _t > 0.1) or not _ground_ahead(_dir):
				if is_on_wall():
					GameState.shake.emit(0.15)
					Sfx.play("thud", global_position, -4.0, 0.1)
				_set_state(St.DIZZY)
		St.DIZZY:
			_body.rotation.y = sin(_anim * 9.0) * 0.25
			if _t > 1.3:
				_body.rotation.y = 0.0
				_set_state(St.PATROL)
		St.FLIPPED:
			if _t > 3.0:
				_set_state(St.PATROL)
	# 翻倒动画
	var flip_target := PI if state == St.FLIPPED else 0.0
	_flip_amt = lerpf(_flip_amt, flip_target, 1.0 - exp(-10.0 * delta))
	_body.rotation.z = _flip_amt
	_body.position.y = (_flip_amt / PI) * 0.84 + sin(_flip_amt) * 0.35
	# 走路时小腿交替
	var walking := hv.length() > 0.1
	for i in _legs.size():
		_legs[i].position.y = 0.1 + (absf(sin(_anim * (18.0 if state == St.CHARGE else 9.0) + i * PI * 0.5)) * 0.06 if walking else 0.0)
	# 击退衰减
	_knock = _knock.move_toward(Vector3.ZERO, 14.0 * delta)
	velocity.x = hv.x + _knock.x
	velocity.z = hv.z + _knock.z
	if is_on_floor():
		velocity.y = maxf(velocity.y, -1.0)
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if global_position.y < GameState.kill_y:
		_defeat(false)
		return
	_check_contact(p)

func _face(d: Vector3, delta: float, rate: float) -> void:
	if d.length() < 0.01:
		return
	var target := Basis.looking_at(d, Vector3.UP)
	basis = basis.slerp(target, 1.0 - exp(-rate * delta)).orthonormalized()

func _ground_ahead(d: Vector3) -> bool:
	var from := global_position + d * 0.7 + Vector3.UP * 0.3
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.4, 1 | 8)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _set_state(s: St) -> void:
	state = s
	_t = 0.0
	_bang.visible = s == St.NOTICE or s == St.WINDUP
	var angry := s == St.WINDUP or s == St.CHARGE
	_eye_mat.albedo_color = EYE_ANGRY if angry else EYE_CALM
	_eye_mat.emission = _eye_mat.albedo_color
	match s:
		St.NOTICE:
			Sfx.play("enemy_notice", global_position, -2.0, 0.08)
			var tw := create_tween()
			tw.tween_property(_body, "position:y", 0.25, 0.1)
			tw.tween_property(_body, "position:y", 0.0, 0.12)
		St.WINDUP:
			Sfx.play("enemy_windup", global_position, -2.0, 0.05)
		St.CHARGE:
			Sfx.play("enemy_charge", global_position, -2.0, 0.05)
		St.FLIPPED:
			_eye_mat.albedo_color = Color(0.4, 0.4, 0.5)
			_eye_mat.emission = Color.BLACK

## 是否处于可以被任何攻击击破的状态
func vulnerable() -> bool:
	return state == St.DIZZY or state == St.FLIPPED

## 从 PIX 的方向看过来，是不是打在盾牌正面
func _hit_from_front(from: Vector3) -> bool:
	var d := from - global_position
	d.y = 0.0
	return d.normalized().dot(-basis.z) > 0.5

func _check_contact(p: MorphBall) -> void:
	if p == null or not _hit_area.overlaps_body(p):
		return
	var atk := p.attack
	if atk == "drill" or atk == "pound":
		_defeat(true)
		return
	if atk == "ram":
		if vulnerable() or not _hit_from_front(p.global_position):
			_defeat(true)
		else:
			# 盾牌挡住：双方弹开
			Sfx.play("clang", global_position, 0.0, 0.05)
			var away := p.global_position - global_position
			away.y = 0.0
			p.linear_velocity = away.normalized() * 7.0 + Vector3.UP * 3.5
			p.launched(0.3)
			p.attack = ""
			_knock = -away.normalized() * 3.0
			GameState.shake.emit(0.2)
			if state == St.PATROL:
				_set_state(St.NOTICE)
		return
	if vulnerable():
		# 翻倒 / 晕眩时，滚球随便碰一下都能击破
		if Vector3(p.linear_velocity.x, 0, p.linear_velocity.z).length() > 2.5:
			_defeat(true)
		return
	if state == St.CHARGE:
		p.hurt(global_position)
		_set_state(St.DIZZY)
	elif not p.is_invulnerable():
		# 平时碰到只是被推开
		var away2 := p.global_position - global_position
		away2.y = 0.0
		p.apply_central_impulse(away2.normalized() * 1.5 * p.mass)

## 钻头下砸震到
func on_pound(from: Vector3) -> void:
	if state == St.DEAD:
		return
	var away := global_position - from
	away.y = 0.0
	_knock = away.normalized() * 3.0
	velocity.y = 5.0
	_set_state(St.FLIPPED)
	Sfx.play("clang", global_position, -4.0, 0.1)

## 气泡气浪推到
func on_wave(from: Vector3) -> void:
	if state == St.DEAD:
		return
	var away := global_position - from
	away.y = 0.0
	_knock = away.normalized() * 9.0
	velocity.y = 4.0
	_set_state(St.FLIPPED)

func _defeat(drops: bool) -> void:
	if state == St.DEAD:
		return
	state = St.DEAD
	Sfx.play("enemy_defeat", global_position, 0.0, 0.08)
	GameState.shake.emit(0.2)
	GameState.enemies_defeated += 1
	if drops:
		var w := get_tree().get_first_node_in_group("voxel_world")
		var parent: Node = w if w else get_parent()
		for i in 3:
			PickupScript.spawn(parent, "coin", global_position + Vector3.UP * 0.6)
		for i in 2:
			PickupScript.spawn(parent, "energy", global_position + Vector3.UP * 0.6)
	# 碎成几块锈色小方块飞散
	for i in 7:
		var b := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3.ONE * randf_range(0.12, 0.22)
		b.mesh = m
		b.material_override = _mat(Color("8a4b32") if i % 2 == 0 else Color("3a2a26"))
		get_parent().add_child(b)
		b.global_position = global_position + Vector3.UP * 0.4
		var v := Vector3(randf_range(-1, 1), randf_range(0.8, 1.6), randf_range(-1, 1)) * 1.6
		var tw := b.create_tween().set_parallel()
		tw.tween_property(b, "global_position", b.global_position + v, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "scale", Vector3.ZERO, 0.45).set_delay(0.1)
		tw.chain().tween_callback(b.queue_free)
	queue_free()

const PickupScript := preload("res://scripts/voxel/pickup.gd")
