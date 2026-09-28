class_name CrystalColossus
extends EnemyBase
## 第三章 Boss「晶簇巨像」：深渊底部被锈蚀唤醒的采矿巨像，全身包着坚硬的晶甲。
## 打不动晶甲——要用光：转动场地四周的晶面镜，把发射晶的光束引到它身上，照一会儿晶甲就会碎掉，
## 露出胸口的核心，趁它跪倒时冲撞 / 钻 / 下砸 / 踩。三下。每打一下，晶甲会重新长出来，另一台发射晶亮起。
## 招式：晶雨（地上的红圈，1.2 秒后砸下晶柱）、震地冲击波、第二阶段起召唤钻地鼹。

enum St { IDLE, WALK, RAIN, LEAP, SLAM, KNEEL }

signal phase_changed(hp: int)

var state := St.IDLE
var max_hp := 3
var active := false
var arena_center := Vector3.ZERO
var arena_radius := 7.0
var armor := 1.0              ## 1 = 完整；被光照到慢慢下降，到 0 碎掉
var _t := 0.0
var _pattern := 0
var _armor_parts: Array[MeshInstance3D] = []
var _armor_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _beam_t := 0.0
var _rain: Array = []          ## [位置, 剩余时间, 圈节点]
var _shock: MeshInstance3D
var _shock_r := 0.0
var _shock_on := false
var _leap_from := Vector3.ZERO
var _leap_to := Vector3.ZERO
var _bar_fill: ColorRect
var _armor_fill: ColorRect
var _bar_root: Control
var _summons: Array = []

func _build() -> void:
	hp = max_hp
	coins = 50
	energy = 10
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(2.2, 2.8, 2.0)
	shape.shape = b
	shape.position.y = 1.4
	add_child(shape)
	var rock := mat(Color("5b5470"), 0.0, 0.8)
	var rock2 := mat(Color("4a4560"), 0.0, 0.8)
	_core_mat = mat(Color("ff7ab8"), 0.8, 0.3)
	_eye_mat = mat(Color("9ff0ff"), 2.0, 0.3)
	_armor_mat = StandardMaterial3D.new()
	_armor_mat.albedo_color = Color(0.75, 0.55, 1.0, 0.85)
	_armor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_armor_mat.emission_enabled = true
	_armor_mat.emission = Color("c08cff")
	_armor_mat.emission_energy_multiplier = 1.0
	_armor_mat.roughness = 0.1
	_armor_mat.metallic = 0.4
	# 身体：宽大的岩石躯干 + 粗手臂 + 短腿
	box(Vector3(2.2, 1.6, 1.6), rock, Vector3(0, 1.9, 0))
	box(Vector3(1.6, 0.8, 1.3), rock2, Vector3(0, 0.8, 0))
	box(Vector3(1.0, 0.8, 1.0), rock, Vector3(0, 3.0, -0.1))
	for sx in [-0.25, 0.25]:
		box(Vector3(0.22, 0.14, 0.08), _eye_mat, Vector3(sx, 3.05, -0.62))
	for sx in [-1.45, 1.45]:
		box(Vector3(0.7, 1.8, 0.8), rock2, Vector3(sx, 1.6, 0))
		box(Vector3(0.9, 0.6, 0.9), rock, Vector3(sx, 0.55, 0))
	for sx in [-0.5, 0.5]:
		box(Vector3(0.6, 0.6, 0.7), rock2, Vector3(sx, 0.3, 0))
	# 胸口的核心（弱点）
	ball(0.35, _core_mat, Vector3(0, 1.9, -0.82))
	# 晶甲：胸前一大块 + 肩膀和背上的晶簇
	var plates := [
		[Vector3(1.6, 1.3, 0.35), Vector3(0, 1.9, -0.95), Vector3.ZERO],
		[Vector3(0.6, 1.1, 0.6), Vector3(-1.2, 2.9, 0.1), Vector3(0, 0, 0.4)],
		[Vector3(0.6, 1.3, 0.6), Vector3(1.2, 3.0, 0.0), Vector3(0, 0, -0.35)],
		[Vector3(0.5, 1.4, 0.5), Vector3(-0.4, 3.1, 0.7), Vector3(0.3, 0, 0.2)],
		[Vector3(0.5, 1.7, 0.5), Vector3(0.4, 3.2, 0.75), Vector3(0.35, 0, -0.2)],
	]
	for pl in plates:
		var mi := box(pl[0], _armor_mat, pl[1])
		mi.rotation = pl[2]
		_armor_parts.append(mi)
	var l := OmniLight3D.new()
	l.light_color = Color("c08cff")
	l.light_energy = 1.5
	l.omni_range = 6.0
	l.position.y = 2.5
	body.add_child(l)
	_shock = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 1.0
	tm.rings = 48
	_shock.mesh = tm
	var shm := StandardMaterial3D.new()
	shm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shm.albedo_color = Color(0.75, 0.55, 1.0, 0.85)
	shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shock.material_override = shm
	_shock.top_level = true
	_shock.visible = false
	add_child(_shock)

func _hit_size() -> Vector3:
	return Vector3(2.8, 3.2, 2.6)

func _can_trap() -> bool:
	return false

func _flip_lift() -> float:
	return 0.0

func _stompable() -> bool:
	return state == St.KNEEL

func vulnerable() -> bool:
	return state == St.KNEEL

func start() -> void:
	if active:
		return
	active = true
	_go(St.WALK)
	_make_bar()
	Sfx.play("impact_big", global_position, 4.0, 0.0, 0.5)
	GameState.shake.emit(0.5)

func _go(s: St) -> void:
	state = s
	_t = 0.0
	_eye_mat.albedo_color = Color("ff4d6d") if s == St.RAIN or s == St.LEAP else Color("9ff0ff")
	_eye_mat.emission = _eye_mat.albedo_color
	_core_mat.emission_energy_multiplier = 4.0 if s == St.KNEEL else 0.8

# ---------------------------------------------------------------- 光照晶甲

func on_beam(_beam: Node) -> void:
	if not active or state == St.KNEEL or dead:
		return
	_beam_t = 0.15
	armor -= get_physics_process_delta_time() * 0.9
	_armor_mat.emission_energy_multiplier = 3.0 + sin(_anim * 40.0) * 1.5
	body.position.x = sin(_anim * 50.0) * 0.04
	if armor <= 0.0:
		_shatter()
	_update_bar()

func _shatter() -> void:
	armor = 0.0
	for mi in _armor_parts:
		mi.visible = false
	_debris(Color("c08cff"), Color("e9d6ff"), 18)
	Sfx.play("break_glass", global_position, 6.0, 0.0, 0.7)
	Sfx.play("impact_big", global_position, 2.0, 0.0, 0.6)
	GameState.shake.emit(0.6)
	_go(St.KNEEL)
	body.rotation.x = 0.35
	body.position.y = -0.6
	FloatText.spawn(get_parent(), global_position + Vector3.UP * 3.6, "晶甲碎了！打它胸口的核心！", Color("ff7ab8"), 56, 1.6)

func _regrow() -> void:
	armor = 1.0
	for mi in _armor_parts:
		mi.visible = true
		mi.scale = Vector3.ONE * 0.2
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	body.rotation.x = 0.0
	body.position.y = 0.0
	Sfx.play("unlock", global_position, 2.0, 0.0, 0.6)
	_update_bar()

# ---------------------------------------------------------------- 行为

func _ai(delta: float) -> void:
	_t += delta
	_beam_t -= delta
	if _beam_t <= 0.0 and state != St.KNEEL:
		_armor_mat.emission_energy_multiplier = 1.0
		body.position.x = 0.0
		# 没被光照着时，晶甲慢慢长回来
		armor = minf(1.0, armor + delta * 0.08)
	var p := player()
	if not active or p == null:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var to_p := p.global_position - global_position
	to_p.y = 0.0
	var hv := Vector3.ZERO
	match state:
		St.WALK:
			face(to_p, delta, 1.5)
			var ahead := global_position - basis.z * 1.5
			if Vector2(ahead.x - arena_center.x, ahead.z - arena_center.z).length() < arena_radius - 1.0 and to_p.length() > 3.0:
				hv = -basis.z * 0.9
			if _t > 3.0:
				_pattern += 1
				if _pattern % 2 == 1:
					_go(St.RAIN)
				else:
					_leap_from = global_position
					_go(St.LEAP)
		St.RAIN:
			face(to_p, delta, 3.0)
			if _t < 0.05:
				_start_rain(p)
			if _t > 2.2:
				_go(St.WALK)
		St.LEAP:
			if _t < 0.05:
				var off := Vector3(p.global_position.x - arena_center.x, 0, p.global_position.z - arena_center.z)
				if off.length() > arena_radius - 2.0:
					off = off.normalized() * (arena_radius - 2.0)
				_leap_to = _leap_from.lerp(Vector3(arena_center.x + off.x, _leap_from.y, arena_center.z + off.z), 0.5)
				Sfx.play("jump_drill", global_position, 4.0, 0.0, 0.4)
			var k := clampf(_t / 1.1, 0.0, 1.0)
			var pos := _leap_from.lerp(_leap_to, k)
			pos.y = _leap_from.y + sin(k * PI) * 3.5
			global_position = pos
			velocity = Vector3.ZERO
			if k >= 1.0:
				_slam()
			return
		St.SLAM:
			if _t > 1.4:
				_go(St.WALK)
		St.KNEEL:
			if _t > 5.0:
				_regrow()
				_go(St.WALK)
	velocity.x = hv.x
	velocity.z = hv.z

func _start_rain(p: MorphBall) -> void:
	var n := 4 + (max_hp - hp) * 2
	for k in n:
		var at := p.global_position + Vector3(randf_range(-3.0, 3.0), 0, randf_range(-3.0, 3.0))
		if k == 0:
			at = p.global_position
		var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 6.0, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			continue
		var gp: Vector3 = hit.position
		var ring := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.9
		cm.bottom_radius = 0.9
		cm.height = 0.03
		ring.mesh = cm
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.albedo_color = Color(1.0, 0.3, 0.5, 0.35)
		ring.material_override = rm
		get_parent().add_child(ring)
		ring.global_position = gp + Vector3.UP * 0.05
		_rain.append([gp, 1.2 + k * 0.12, ring])
	Sfx.play("enemy_windup", global_position, 4.0, 0.0, 0.7)

func _process(delta: float) -> void:
	for r in _rain.duplicate():
		r[1] -= delta
		var ring: MeshInstance3D = r[2]
		ring.scale = Vector3.ONE * (0.6 + 0.4 * sin(_anim * 20.0) * 0.5 + 0.4)
		if r[1] <= 0.0:
			_rain.erase(r)
			ring.queue_free()
			_shard(r[0])
	if _shock_on:
		_shock_r += delta * 6.0
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

## 一根晶柱从天而降
func _shard(at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.7, 1.8, 0.7)
	mi.mesh = pm
	mi.material_override = _armor_mat
	mi.rotation.x = PI
	get_parent().add_child(mi)
	mi.global_position = at + Vector3.UP * 8.0
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position", at + Vector3.UP * 0.9, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		Sfx.play("break_glass", at, -2.0, 0.15)
		GameState.shake.emit(0.15)
		var p := player()
		if p and Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length() < 1.0 and p.global_position.y - at.y < 1.5 and not p.is_invulnerable():
			p.hurt(at)
		# 晶柱会砸碎易碎的东西
		var w := get_tree().get_first_node_in_group("voxel_world") as VoxelWorld
		if w:
			w.break_sphere(at, 0.6, "impact", 5.0, Vector3.DOWN)
		mi.queue_free()
		for k in 5:
			var b := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3.ONE * 0.18
			b.mesh = bm
			b.material_override = _armor_mat
			get_parent().add_child(b)
			b.global_position = at + Vector3.UP * 0.4
			var v := Vector3(randf_range(-1, 1), randf_range(0.6, 1.4), randf_range(-1, 1)) * 1.3
			var t2 := b.create_tween().set_parallel()
			t2.tween_property(b, "global_position", b.global_position + v, 0.4)
			t2.tween_property(b, "scale", Vector3.ZERO, 0.4)
			t2.chain().tween_callback(b.queue_free))

func _slam() -> void:
	_go(St.SLAM)
	GameState.shake.emit(0.7)
	Sfx.play("impact_big", global_position, 6.0, 0.0, 0.6)
	_shock.global_position = global_position + Vector3.UP * 0.15
	_shock_r = 1.2
	_shock_on = true
	_shock.visible = true
	if hp <= max_hp - 1:
		_summons = _summons.filter(func(e) -> bool: return is_instance_valid(e))
		if _summons.size() < 2:
			for k in 2 - _summons.size():
				var b := Burrower.new()
				get_parent().add_child(b)
				var a := randf() * TAU
				b.global_position = arena_center + Vector3(cos(a) * 4.5, 0.1, sin(a) * 4.5)
				b.roam = arena_radius
				_summons.append(b)

# ---------------------------------------------------------------- 受击

func _check_contact() -> void:
	var p := player()
	if p == null or not hit_area.overlaps_body(p):
		return
	if state == St.KNEEL:
		var stomp := p.linear_velocity.y < -1.5 and p.global_position.y > global_position.y + 2.0
		if stomp:
			p.stomp_bounce()
		if p.attack != "" or stomp or Vector3(p.linear_velocity.x, 0, p.linear_velocity.z).length() > 3.0:
			_boss_hit()
		return
	if not p.is_invulnerable():
		var away := p.global_position - global_position
		away.y = 0.0
		p.linear_velocity = away.normalized() * 6.0 + Vector3.UP * 3.0
		p.launched(0.3)
		if p.attack != "" and hurt_cd <= 0.0:
			hurt_cd = 1.2
			Sfx.play("clang", global_position, 0.0, 0.05, 1.3)
			FloatText.spawn(get_parent(), global_position + Vector3.UP * 3.4, "晶甲太硬了！用光照它", Color("d9c6ff"), 44, 1.2)

func take_hit(_from: Vector3, _kind: String) -> void:
	if state == St.KNEEL:
		_boss_hit()

func on_pound(_from: Vector3) -> void:
	if state == St.KNEEL:
		_boss_hit()

func on_wave(_from: Vector3) -> void:
	pass

func on_item(_item: Node3D) -> void:
	if state == St.KNEEL:
		_boss_hit()

func _boss_hit() -> void:
	if hurt_cd > 0.0 or dead:
		return
	hurt_cd = 1.0
	hp -= 1
	GameState.shake.emit(0.6)
	Sfx.play("break_hard", global_position, 4.0, 0.0, 0.7)
	Sfx.play("enemy_defeat", global_position, 2.0, 0.0, 0.5)
	var p := player()
	if p:
		var away := p.global_position - global_position
		away.y = 0.0
		p.linear_velocity = away.normalized() * 7.0 + Vector3.UP * 5.0
		p.launched(0.4)
	_update_bar()
	if hp <= 0:
		_die()
		return
	phase_changed.emit(hp)
	_regrow()
	_go(St.WALK)
	_t = -1.0
	GameState.say(["它又长出晶甲了……另一台发射晶亮了！重新转动镜子，把光引过去。", "最后一次！小心它叫来的钻地鼹！"][clampi(max_hp - hp - 1, 0, 1)])

func _die() -> void:
	dead = true
	for r in _rain:
		(r[2] as Node).queue_free()
	_rain.clear()
	_shock.visible = false
	_shock_on = false
	for e in _summons:
		if is_instance_valid(e):
			e.call("defeat", true)
	GameState.shake.emit(1.0)
	Sfx.play("break_glass", global_position, 8.0, 0.0, 0.5)
	var w := get_tree().get_first_node_in_group("voxel_world")
	var parent: Node = w if w else get_parent()
	for i in coins:
		PickupScript.spawn(parent, "coin", global_position + Vector3.UP * 1.5)
	for i in energy:
		PickupScript.spawn(parent, "energy", global_position + Vector3.UP * 1.5)
	_debris(Color("5b5470"), Color("c08cff"), 30)
	if _bar_root:
		_bar_root.get_parent().queue_free()
	GameState.enemies_defeated += 1
	defeated.emit(self)
	queue_free()

func _make_bar() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	get_tree().current_scene.add_child(layer)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_CENTER_TOP)
	root.position = Vector2(-260, 96)
	root.custom_minimum_size = Vector2(520, 0)
	root.add_theme_constant_override("separation", 5)
	layer.add_child(root)
	var name_l := UIKit.label("晶簇巨像", 26, Color("e9d6ff"), true)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(name_l)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.2, 0.8)
	bg.custom_minimum_size = Vector2(520, 16)
	root.add_child(bg)
	_bar_fill = ColorRect.new()
	_bar_fill.color = Color("ff7ab8")
	_bar_fill.size = Vector2(520, 16)
	bg.add_child(_bar_fill)
	var bg2 := ColorRect.new()
	bg2.color = Color(0.1, 0.1, 0.2, 0.6)
	bg2.custom_minimum_size = Vector2(520, 8)
	root.add_child(bg2)
	_armor_fill = ColorRect.new()
	_armor_fill.color = Color("c08cff")
	_armor_fill.size = Vector2(520, 8)
	bg2.add_child(_armor_fill)
	_bar_root = root

func _update_bar() -> void:
	if _bar_fill:
		_bar_fill.size.x = 520.0 * float(hp) / max_hp
	if _armor_fill:
		_armor_fill.size.x = 520.0 * clampf(armor, 0.0, 1.0)

func debug_break_armor() -> void:
	_shatter()
