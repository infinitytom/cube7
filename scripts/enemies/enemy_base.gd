class_name EnemyBase
extends CharacterBody3D
## 新敌人的公共部分：受击接口、翻倒/晕眩、被泡泡困住、被踩、被扔的物件砸中、击破掉落。
## 所有敌人都在 "enemy" 组里，PIX 的各种攻击通过这些函数通知它们：
##   on_pound(from)   钻头下砸的震波
##   on_wave(from)    气泡的气浪
##   on_bubble(shot)  泡泡弹（困住，飘起来）
##   on_item(item)    被扔出去的物件砸中
## 子类实现 _ai(delta) 和 _contact(p)；用 hp 表示要打几下。

const GRAVITY := 22.0
const PickupScript := preload("res://scripts/voxel/pickup.gd")

var hp := 1
var dead := false
var flying := false            ## 飞行敌人不受重力
var stun_t := 0.0              ## 晕眩 / 翻倒剩余时间（> 0 时任何攻击都能击破）
var flipped := false
var trapped_t := 0.0           ## 被泡泡困住
var home := Vector3.ZERO
var ai := true
var coins := 3
var energy := 2
var knock := Vector3.ZERO
var hurt_cd := 0.0
var body: Node3D               ## 视觉根节点（翻倒、抖动都作用在它上面）
var hit_area: Area3D
var _home_set := false
var _bubble: MeshInstance3D
var _anim := 0.0
var _flip_amt := 0.0
var _hit_flash := 0.0
var _mats: Array[StandardMaterial3D] = []

func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 16
	collision_mask = 1 | 8
	body = Node3D.new()
	add_child(body)
	_build()
	hit_area = Area3D.new()
	hit_area.collision_layer = 0
	hit_area.collision_mask = 2
	var hs := CollisionShape3D.new()
	var hb := BoxShape3D.new()
	hb.size = _hit_size()
	hs.shape = hb
	hs.position.y = hb.size.y * 0.5 - 0.1
	hit_area.add_child(hs)
	add_child(hit_area)

## 子类：搭外观、碰撞体
func _build() -> void:
	pass

func _hit_size() -> Vector3:
	return Vector3(1.2, 1.0, 1.2)

func _ai(_delta: float) -> void:
	pass

## 子类：和 PIX 接触时怎么办（已经处理过通用的踩踏 / 晕眩 / 钻头）
func _contact(_p: MorphBall) -> void:
	pass

func mat(c: Color, emission := 0.0, rough := 0.6, metal := 0.1) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	_mats.append(m)
	return m

func box(size: Vector3, m: Material, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	(parent if parent else body).add_child(mi)
	return mi

func ball(r: float, m: Material, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = m
	mi.position = pos
	(parent if parent else body).add_child(mi)
	return mi

func player() -> MorphBall:
	return GameState.player as MorphBall

func vulnerable() -> bool:
	return stun_t > 0.0 or trapped_t > 0.0

func _physics_process(delta: float) -> void:
	if dead:
		return
	if not _home_set:
		_home_set = true
		home = global_position
	_anim += delta
	hurt_cd -= delta
	_hit_flash -= delta
	if trapped_t > 0.0:
		_update_trapped(delta)
		return
	if stun_t > 0.0:
		stun_t -= delta
		if stun_t <= 0.0:
			flipped = false
			_on_recover()
	if ai and stun_t <= 0.0:
		_ai(delta)
	elif not flying:
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
	# 翻倒动画
	var ft := PI if flipped else 0.0
	_flip_amt = lerpf(_flip_amt, ft, 1.0 - exp(-10.0 * delta))
	body.rotation.z = _flip_amt
	body.position.y = (_flip_amt / PI) * _flip_lift() + sin(_flip_amt) * 0.3
	knock = knock.move_toward(Vector3.ZERO, 14.0 * delta)
	var v := velocity
	v.x += knock.x
	v.z += knock.z
	if not flying or stun_t > 0.0:
		if is_on_floor():
			v.y = maxf(v.y, -1.0)
		else:
			v.y -= GRAVITY * delta
	velocity = v
	move_and_slide()
	velocity.x -= knock.x
	velocity.z -= knock.z
	if global_position.y < GameState.kill_y:
		defeat(false)
		return
	_check_contact()

func _flip_lift() -> float:
	return 0.8

func _on_recover() -> void:
	pass

# ---------------------------------------------------------------- 受击

func _check_contact() -> void:
	var p := player()
	if p == null or not hit_area.overlaps_body(p):
		return
	# 从上往下踩：任何形态落在头上都算（马里奥式），踩完弹起来
	if p.linear_velocity.y < -1.5 and p.global_position.y > global_position.y + _hit_size().y * 0.42 and _stompable():
		p.stomp_bounce()
		take_hit(p.global_position, "stomp")
		return
	var atk := p.attack
	if vulnerable() and (atk != "" or Vector3(p.linear_velocity.x, 0, p.linear_velocity.z).length() > 2.5):
		take_hit(p.global_position, atk if atk != "" else "bump")
		return
	_contact(p)

func _stompable() -> bool:
	return true

## 受到一次有效攻击
func take_hit(from: Vector3, kind: String) -> void:
	if dead or hurt_cd > 0.0:
		return
	hurt_cd = 0.3
	hp -= 1
	_hit_flash = 0.15
	Sfx.play("clang", global_position, -4.0, 0.1)
	GameState.shake.emit(0.16)
	GameState.rumble(0.35, 0.3, 0.1)
	if hp <= 0:
		defeat(true)
	else:
		_on_hurt(from, kind)

func _on_hurt(from: Vector3, _kind: String) -> void:
	var away := global_position - from
	away.y = 0.0
	knock = away.normalized() * 5.0
	stun(1.0, false)

func stun(t: float, flip: bool) -> void:
	stun_t = maxf(stun_t, t)
	if flip:
		flipped = true

func on_pound(from: Vector3) -> void:
	if dead:
		return
	var away := global_position - from
	away.y = 0.0
	knock = away.normalized() * 3.0
	velocity.y = 5.0
	stun(3.0, true)
	Sfx.play("clang", global_position, -4.0, 0.1)

func on_wave(from: Vector3) -> void:
	if dead:
		return
	var away := global_position - from
	away.y = 0.0
	knock = away.normalized() * 9.0
	velocity.y = 4.0
	stun(3.0, true)

func on_item(item: Node3D) -> void:
	if dead:
		return
	take_hit(item.global_position, "item")
	if not dead:
		stun(2.0, true)

## 泡泡弹困住：飘起来 3 秒，然后啪地破掉摔在地上（翻倒）
func on_bubble(_shot: Node3D) -> void:
	if dead or trapped_t > 0.0:
		return
	if not _can_trap():
		stun(1.5, false)
		return
	trapped_t = 3.0
	Sfx.play("jump_bubble", global_position, 0.0, 0.1)
	if _bubble == null:
		_bubble = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.85
		sm.height = 1.7
		_bubble.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.8, 0.7, 1.0, 0.3)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.rim_enabled = true
		m.rim = 1.0
		m.emission_enabled = true
		m.emission = Color("c9a6ff")
		m.emission_energy_multiplier = 0.5
		_bubble.material_override = m
		_bubble.position.y = 0.45
		add_child(_bubble)
	_bubble.visible = true

func _can_trap() -> bool:
	return true

func _update_trapped(delta: float) -> void:
	trapped_t -= delta
	velocity = Vector3(0, 0.9 if trapped_t > 1.2 else 0.0, 0)
	body.rotation.y += delta * 2.0
	_bubble.scale = Vector3.ONE * (1.0 + 0.05 * sin(_anim * 8.0))
	move_and_slide()
	_check_contact()
	if trapped_t <= 0.0 and not dead:
		_bubble.visible = false
		Sfx.play("wave", global_position, -6.0, 0.1)
		velocity = Vector3.ZERO
		stun(2.5, true)

func defeat(drops: bool) -> void:
	if dead:
		return
	dead = true
	Sfx.play("enemy_defeat", global_position, 0.0, 0.08)
	GameState.shake.emit(0.3)
	GameState.hitstop(0.05)
	GameState.rumble(0.5, 0.7, 0.18)
	GameState.enemies_defeated += 1
	GameState.add_combo(5)
	if drops:
		var w := get_tree().get_first_node_in_group("voxel_world")
		var parent: Node = w if w else get_parent()
		for i in coins:
			PickupScript.spawn(parent, "coin", global_position + Vector3.UP * 0.6)
		for i in energy:
			PickupScript.spawn(parent, "energy", global_position + Vector3.UP * 0.6)
	_debris()
	defeated.emit(self)
	queue_free()

signal defeated(e: Node)

func _debris(color_a := Color("8a4b32"), color_b := Color("3a2a26"), n := 8) -> void:
	for i in n:
		var b := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3.ONE * randf_range(0.12, 0.24)
		b.mesh = m
		var mm := StandardMaterial3D.new()
		mm.albedo_color = color_a if i % 2 == 0 else color_b
		b.material_override = mm
		get_parent().add_child(b)
		b.global_position = global_position + Vector3.UP * 0.4
		var v := Vector3(randf_range(-1, 1), randf_range(0.8, 1.6), randf_range(-1, 1)) * 1.6
		var tw := b.create_tween().set_parallel()
		tw.tween_property(b, "global_position", b.global_position + v, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "scale", Vector3.ZERO, 0.45).set_delay(0.1)
		tw.chain().tween_callback(b.queue_free)

func face(d: Vector3, delta: float, rate: float) -> void:
	d.y = 0.0
	if d.length() < 0.01:
		return
	var target := Basis.looking_at(d.normalized(), Vector3.UP)
	basis = basis.slerp(target, 1.0 - exp(-rate * delta)).orthonormalized()

func ground_ahead(d: Vector3, dist := 0.7) -> bool:
	var from := global_position + d * dist + Vector3.UP * 0.3
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.4, 1 | 8)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func bang(text := "!", color := Color("ffd166")) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.outline_size = 18
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position.y = 1.5
	l.visible = false
	add_child(l)
	return l
