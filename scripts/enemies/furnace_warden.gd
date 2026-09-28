class_name FurnaceWarden
extends EnemyBase
## 第二章 Boss「熔炉守卫」：守着第二座重构塔的巨型锈蚀机器人，背上有一口烧得通红的熔炉核心。
## 招式（每一招都有明显的预兆，机制战斗，不拼手速）：
##   · 冲锋：跺脚、喷蒸汽 1 秒 → 朝 PIX 直线冲过去。撞到场边的石柱会把柱子撞碎，自己也晕头转向 3 秒
##   · 震地：高高跳起砸地 → 一圈冲击波沿地面扩散。跳起来（或用气泡飘着）就能躲开
##   · 第二阶段起：砸地后放出两只锈蜂；第三阶段：连续抛三颗锈弹（气浪能打回去炸它）
## 弱点：晕眩时背后的熔炉核心露出来——冲撞 / 钻 / 下砸 / 踩头都能打中。打三下。

enum St { IDLE, STALK, WIND, CHARGE, DIZZY, LEAP, SLAM, VOLLEY, DEAD }

signal hp_changed(hp: int, max_hp: int)

var state := St.IDLE
var max_hp := 3
var arena_center := Vector3.ZERO
var arena_radius := 6.0
var active := false
var _t := 0.0
var _dir := Vector3.FORWARD
var _core_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _legs: Array[Node3D] = []
var _steam: CPUParticles3D
var _bar: Control
var _bar_fill: ColorRect
var _pattern := 0
var _leap_from := Vector3.ZERO
var _leap_to := Vector3.ZERO
var _shock: MeshInstance3D
var _shock_r := 0.0
var _shock_on := false
var _summons: Array = []
var _volley_n := 0

const SIZE := 2.0

func _build() -> void:
	hp = max_hp
	coins = 40
	energy = 8
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(1.9, 1.9, 1.9)
	shape.shape = b
	shape.position.y = 0.95
	add_child(shape)
	var hull := mat(Color("6c7385"), 0.0, 0.5, 0.3)
	var rust := mat(Color("b5653e"), 0.0, 0.6)
	var dark := mat(Color("3d4659"), 0.0, 0.4, 0.3)
	# 身体：一个大铁箱子，锈斑，正面一张“脸”
	box(Vector3(2.0, 1.5, 1.8), hull, Vector3(0, 1.15, 0))
	box(Vector3(2.1, 0.3, 1.9), rust, Vector3(0, 1.95, 0))
	box(Vector3(1.4, 0.5, 0.1), dark, Vector3(0, 1.2, -0.92))
	_eye_mat = mat(Color("ffb347"), 2.0, 0.3)
	for sx in [-0.35, 0.35]:
		box(Vector3(0.36, 0.2, 0.08), _eye_mat, Vector3(sx, 1.3, -0.97))
	# 肩上的烟囱
	for sx in [-0.7, 0.7]:
		var st := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.18
		cm.bottom_radius = 0.22
		cm.height = 0.7
		st.mesh = cm
		st.material_override = dark
		st.position = Vector3(sx, 2.3, 0.4)
		body.add_child(st)
	# 背后的熔炉核心（弱点）
	_core_mat = mat(Color("ff6a1a"), 1.2, 0.3)
	box(Vector3(1.0, 0.8, 0.2), _core_mat, Vector3(0, 1.15, 0.95))
	box(Vector3(1.2, 0.1, 0.25), dark, Vector3(0, 1.6, 0.95))
	box(Vector3(1.2, 0.1, 0.25), dark, Vector3(0, 0.7, 0.95))
	# 粗短的腿
	for sx in [-0.6, 0.6]:
		var leg := Node3D.new()
		leg.position = Vector3(sx, 0.35, 0)
		body.add_child(leg)
		box(Vector3(0.6, 0.7, 0.9), dark, Vector3.ZERO, leg)
		_legs.append(leg)
	_steam = CPUParticles3D.new()
	_steam.amount = 24
	_steam.lifetime = 0.9
	_steam.emitting = false
	_steam.direction = Vector3.UP
	_steam.spread = 20.0
	_steam.initial_velocity_min = 2.0
	_steam.initial_velocity_max = 3.5
	_steam.gravity = Vector3(0, 1, 0)
	_steam.scale_amount_min = 0.4
	_steam.scale_amount_max = 0.9
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(1, 1, 1, 0.5)
	sm.material = smat
	_steam.mesh = sm
	_steam.position = Vector3(0, 2.6, 0.4)
	body.add_child(_steam)
	# 冲击波圈
	_shock = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 1.0
	tm.rings = 48
	_shock.mesh = tm
	var shm := StandardMaterial3D.new()
	shm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shm.albedo_color = Color(1.0, 0.55, 0.25, 0.85)
	shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shm.emission_enabled = true
	_shock.material_override = shm
	_shock.top_level = true
	_shock.visible = false
	add_child(_shock)

func _hit_size() -> Vector3:
	return Vector3(2.6, 2.4, 2.6)

func _can_trap() -> bool:
	return false

func _flip_lift() -> float:
	return 0.0

func _stompable() -> bool:
	return state == St.DIZZY

## 触发战斗（进入场地时由关卡调用）
func start() -> void:
	if active:
		return
	active = true
	_go(St.STALK)
	_make_bar()
	Sfx.play("enemy_notice", global_position, 4.0, 0.0, 0.6)
	GameState.shake.emit(0.4)

func _go(s: St) -> void:
	state = s
	_t = 0.0
	_steam.emitting = s == St.WIND or s == St.DIZZY
	var angry := s == St.WIND or s == St.CHARGE or s == St.LEAP
	_eye_mat.albedo_color = Color("ff3b3b") if angry else Color("ffb347")
	_eye_mat.emission = _eye_mat.albedo_color
	_core_mat.emission_energy_multiplier = 4.0 if s == St.DIZZY else 1.2
	match s:
		St.WIND:
			Sfx.play("enemy_windup", global_position, 4.0, 0.0, 0.6)
		St.CHARGE:
			Sfx.play("enemy_charge", global_position, 4.0, 0.0, 0.6)
		St.DIZZY:
			Sfx.play("thud", global_position, 6.0, 0.0, 0.6)

func vulnerable() -> bool:
	return state == St.DIZZY

func _ai(delta: float) -> void:
	_t += delta
	var p := player()
	if not active or p == null:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var to_p := p.global_position - global_position
	to_p.y = 0.0
	var hv := Vector3.ZERO
	var legs_speed := 0.0
	match state:
		St.STALK:
			face(to_p, delta, 3.0)
			hv = -basis.z * 1.3
			legs_speed = 6.0
			if not _ground_safe(-basis.z):
				hv = Vector3.ZERO
			if _t > 1.8:
				_pattern += 1
				if hp <= 1 and _pattern % 3 == 0:
					_go(St.VOLLEY)
				elif _pattern % 2 == 1:
					_go(St.WIND)
				else:
					_leap_from = global_position
					_go(St.LEAP)
		St.WIND:
			face(to_p, delta, 6.0)
			body.position.x = sin(_anim * 50.0) * 0.06
			if _t > 1.0:
				body.position.x = 0.0
				_dir = -basis.z
				_go(St.CHARGE)
		St.CHARGE:
			hv = _dir * 9.0
			legs_speed = 20.0
			if _t > 0.15 and is_on_wall():
				_crash()
			elif not _ground_safe(_dir) or _t > 2.2:
				# 冲到场边刹住：短暂喘气，不露出核心太久
				Sfx.play("thud", global_position, 0.0, 0.1)
				_go(St.STALK)
				_t = -0.6
		St.DIZZY:
			body.rotation.y = sin(_anim * 7.0) * 0.18
			if _t > 3.2:
				body.rotation.y = 0.0
				_go(St.STALK)
		St.LEAP:
			# 原地起跳，落在 PIX 附近（不会跳出场地）
			if _t < 0.05:
				var tgt := p.global_position
				var off := Vector3(tgt.x - arena_center.x, 0, tgt.z - arena_center.z)
				if off.length() > arena_radius - 1.5:
					off = off.normalized() * (arena_radius - 1.5)
				_leap_to = Vector3(arena_center.x + off.x, global_position.y, arena_center.z + off.z)
				_leap_to = _leap_from.lerp(_leap_to, 0.6)
				Sfx.play("jump_drill", global_position, 4.0, 0.0, 0.5)
			var k := clampf(_t / 1.0, 0.0, 1.0)
			var pos := _leap_from.lerp(_leap_to, k)
			pos.y = _leap_from.y + sin(k * PI) * 4.0
			global_position = pos
			velocity = Vector3.ZERO
			if k >= 1.0:
				_slam()
			return
		St.SLAM:
			if _t > 1.2:
				_go(St.STALK)
		St.VOLLEY:
			face(to_p, delta, 6.0)
			if _t > 0.6 + _volley_n * 0.7 and _volley_n < 3:
				_volley_n += 1
				var tgt2 := p.global_position + Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2))
				RustBomb.launch(get_parent(), global_position + Vector3.UP * 2.6, tgt2, 1.5, self)
				Sfx.play("throw", global_position, 2.0, 0.1, 0.7)
			if _volley_n >= 3 and _t > 3.0:
				_volley_n = 0
				_go(St.STALK)
	for i in _legs.size():
		_legs[i].position.y = 0.35 + (absf(sin(_anim * legs_speed + i * PI)) * 0.12 if legs_speed > 0.0 else 0.0)
	velocity.x = hv.x
	velocity.z = hv.z

func _process(delta: float) -> void:
	if _shock_on:
		_shock_r += delta * 6.5
		_shock.scale = Vector3(_shock_r, 1.0, _shock_r)
		var p := player()
		if p:
			var d := Vector2(p.global_position.x - _shock.global_position.x, p.global_position.z - _shock.global_position.z).length()
			var above := p.global_position.y - _shock.global_position.y
			if absf(d - _shock_r) < 0.45 and above < 0.7 and not p.is_invulnerable():
				p.hurt(_shock.global_position)
		if _shock_r > arena_radius + 3.0:
			_shock_on = false
			_shock.visible = false

func _ground_safe(d: Vector3) -> bool:
	var ahead := global_position + d.normalized() * 1.6
	var off := Vector2(ahead.x - arena_center.x, ahead.z - arena_center.z)
	# 场地是平的：只要还在场地半径里就一定有地面（前方被石柱挡住时射线会从柱子里面打，不能用射线判断）
	return off.length() < arena_radius

## 撞上柱子：柱子碎掉，自己晕 3 秒
func _crash() -> void:
	GameState.shake.emit(0.6)
	Sfx.play("impact_big", global_position, 4.0, 0.1)
	var w := get_tree().get_first_node_in_group("voxel_world") as VoxelWorld
	if w:
		w.break_sphere(global_position + _dir * 1.4 + Vector3.UP * 1.0, 1.6, "impact", 30.0, _dir)
	knock = -_dir * 3.0
	_go(St.DIZZY)
	FloatText.spawn(get_parent(), global_position + Vector3.UP * 2.8, "核心露出来了！", Color("ffb347"), 56, 1.4)

func _slam() -> void:
	_go(St.SLAM)
	GameState.shake.emit(0.7)
	Sfx.play("impact_big", global_position, 6.0, 0.0, 0.7)
	Sfx.play("break_hard", global_position, 2.0, 0.0, 0.6)
	_shock.global_position = global_position + Vector3.UP * 0.15
	_shock_r = 1.0
	_shock_on = true
	_shock.visible = true
	# 第二阶段起：放出锈蜂
	if hp <= max_hp - 1:
		_summons = _summons.filter(func(e: Node) -> bool: return is_instance_valid(e))
		if _summons.size() < 2:
			for k in 2 - _summons.size():
				var f := Rustfly.new()
				get_parent().add_child(f)
				var a := randf() * TAU
				f.global_position = arena_center + Vector3(cos(a) * 4.0, 3.0, sin(a) * 4.0)
				f.sight = 12.0
				_summons.append(f)
			Sfx.play("enemy_notice", global_position, 0.0, 0.1, 1.4)

## 受击：只有晕眩时打得动
func _check_contact() -> void:
	var p := player()
	if p == null or not hit_area.overlaps_body(p):
		return
	if state == St.DIZZY:
		var from_back := (p.global_position - global_position).normalized().dot(basis.z) > -0.2
		var stomp := p.linear_velocity.y < -1.5 and p.global_position.y > global_position.y + 1.8
		if stomp:
			p.stomp_bounce()
		if p.attack != "" or stomp or from_back and Vector3(p.linear_velocity.x, 0, p.linear_velocity.z).length() > 3.0:
			_boss_hit(p.global_position)
			return
	# 冲锋撞到 PIX
	if state == St.CHARGE and not p.is_invulnerable():
		p.hurt(global_position)
		return
	# 平时碰到：被弹开（它太重了）
	if not p.is_invulnerable():
		var away := p.global_position - global_position
		away.y = 0.0
		p.linear_velocity = away.normalized() * 6.0 + Vector3.UP * 3.0
		p.launched(0.3)
		if p.attack != "":
			Sfx.play("clang", global_position, 0.0, 0.05)
			if hurt_cd <= 0.0:
				hurt_cd = 1.0
				FloatText.spawn(get_parent(), global_position + Vector3.UP * 2.6, "打不动！等它撞晕", Color("c4c8ee"), 44, 1.2)

func take_hit(from: Vector3, kind: String) -> void:
	# 被自己的锈弹炸到：直接晕倒
	if kind == "bomb" and state != St.DIZZY and not dead:
		_go(St.DIZZY)
		FloatText.spawn(get_parent(), global_position + Vector3.UP * 2.8, "炸晕了！", Color("9fe8ff"), 56, 1.4)
		return
	if state == St.DIZZY:
		_boss_hit(from)

func _boss_hit(from: Vector3) -> void:
	if hurt_cd > 0.0 or dead:
		return
	hurt_cd = 1.0
	hp -= 1
	hp_changed.emit(hp, max_hp)
	_update_bar()
	GameState.shake.emit(0.5)
	Sfx.play("break_hard", global_position, 4.0, 0.0, 0.8)
	Sfx.play("enemy_defeat", global_position, 2.0, 0.0, 0.6)
	var p := player()
	if p:
		var away := p.global_position - global_position
		away.y = 0.0
		p.linear_velocity = away.normalized() * 7.0 + Vector3.UP * 5.0
		p.launched(0.4)
	if hp <= 0:
		_die()
		return
	GameState.say(["呜——它被激怒了！小心，它会叫来锈蜂。", "最后一下！它开始乱扔锈弹了——用气浪打回去！"][clampi(max_hp - hp - 1, 0, 1)])
	if hp <= 1:
		Music.set_override("bright")
	_go(St.STALK)
	_t = -0.8

func on_pound(from: Vector3) -> void:
	if state == St.DIZZY:
		_boss_hit(from)

func on_wave(_from: Vector3) -> void:
	pass

func on_item(item: Node3D) -> void:
	if state == St.DIZZY:
		_boss_hit(item.global_position)

func _die() -> void:
	dead = true
	_shock_on = false
	_shock.visible = false
	for e in _summons:
		if is_instance_valid(e):
			e.call("defeat", true)
	GameState.shake.emit(1.0)
	Sfx.play("impact_big", global_position, 6.0, 0.0, 0.5)
	var w := get_tree().get_first_node_in_group("voxel_world")
	var parent: Node = w if w else get_parent()
	for i in coins:
		PickupScript.spawn(parent, "coin", global_position + Vector3.UP * 1.2)
	for i in energy:
		PickupScript.spawn(parent, "energy", global_position + Vector3.UP * 1.2)
	_debris(Color("6c7385"), Color("ff6a1a"), 24)
	if _bar:
		_bar.get_parent().queue_free()
	GameState.enemies_defeated += 1
	defeated.emit(self)
	queue_free()

# ---------------------------------------------------------------- 血条

func _make_bar() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	get_tree().current_scene.add_child(layer)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_CENTER_TOP)
	root.position = Vector2(-260, 96)
	root.custom_minimum_size = Vector2(520, 0)
	root.add_theme_constant_override("separation", 6)
	layer.add_child(root)
	var name_l := UIKit.label("熔炉守卫", 26, Color("ffd9a8"), true)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(name_l)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.2, 0.8)
	bg.custom_minimum_size = Vector2(520, 16)
	root.add_child(bg)
	_bar_fill = ColorRect.new()
	_bar_fill.color = Color("ff7a3d")
	_bar_fill.size = Vector2(520, 16)
	bg.add_child(_bar_fill)
	_bar = root

func _update_bar() -> void:
	if _bar_fill:
		var tw := create_tween()
		tw.tween_property(_bar_fill, "size:x", 520.0 * float(hp) / max_hp, 0.3)

## 自动测试：直接把它撞晕
func debug_daze() -> void:
	_go(St.DIZZY)
