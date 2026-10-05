class_name RootHulk
extends Scrapling
## 第一章 Boss「锈根兽」：一只背着岩甲、长满锈根的大号锈块兽。
## 它是体素战斗的教学：岩甲撞不动、钻不动、踩不翻——
##   扫描找到场地边的“承重点”（木架托着的落石）→ 引它冲到木架下 → 撞断木架，落石砸中它
##   → 岩甲裂开、四脚朝天 4 秒 → 这时撞它 / 钻它 / 下砸都算一击。三击打倒。
## 落石用完了，场地会把木架和石头一格格重构回来（RootHulkArena）。

signal hp_changed(hp: int)

var max_hp := 3
var hp := 3
var active := false
var _final := false
var _bar: Control
var _bar_fill: ColorRect
var _armor_cd := 0.0
const SIZE := 2.0

func _ready() -> void:
	super._ready()
	sight = 12.0
	charge_speed = 6.5
	walk_speed = 1.1
	ai = false
	_body.scale = Vector3.ONE * SIZE
	for c in get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			var b := ((c as CollisionShape3D).shape as BoxShape3D).duplicate() as BoxShape3D
			b.size *= SIZE * 0.9
			(c as CollisionShape3D).shape = b
			(c as CollisionShape3D).position *= SIZE
	for c in _hit_area.get_children():
		if c is CollisionShape3D:
			var hb := ((c as CollisionShape3D).shape as BoxShape3D).duplicate() as BoxShape3D
			hb.size *= SIZE
			(c as CollisionShape3D).shape = hb
			(c as CollisionShape3D).position *= SIZE
	# 背上的岩甲：几块灰色的圆石
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("8f949e")
	mat.roughness = 0.9
	for i in 5:
		var rock := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = randf_range(0.16, 0.24)
		sm.height = sm.radius * 1.6
		sm.radial_segments = 7
		sm.rings = 4
		rock.mesh = sm
		rock.material_override = mat
		rock.position = Vector3(randf_range(-0.28, 0.28), 0.72 + randf_range(0.0, 0.08), randf_range(-0.2, 0.3))
		rock.name = "Armor%d" % i
		_body.add_child(rock)

func start() -> void:
	if active:
		return
	active = true
	ai = true
	_make_bar()
	Sfx.play("enemy_notice", global_position, 4.0, 0.0, 0.6)
	GameState.shake.emit(0.4)

func _physics_process(delta: float) -> void:
	_armor_cd = maxf(_armor_cd - delta, 0.0)
	super._physics_process(delta)
	# 被砸翻以后多躺一会儿（基类翻倒 3 秒）
	if state == St.FLIPPED and _t > 4.2:
		_set_state(St.PATROL)

## 落石砸中（VoxelChunk 的“压伤”）：岩甲裂开，四脚朝天
func take_hit(_from: Vector3, kind: String) -> void:
	if state == St.DEAD or not active:
		return
	if kind == "crush":
		_set_state(St.FLIPPED)
		_t = -1.0
		velocity.y = 4.0
		Sfx.play("break_hard", global_position, 2.0, 0.0, 0.7)
		GameState.shake.emit(0.5)
		FloatText.spawn(get_parent(), global_position + Vector3.UP * 2.2, "岩甲裂开了！快撞它！", Color("ffe066"), 52, 1.6)
		for i in 5:
			var a := _body.get_node_or_null("Armor%d" % i) as Node3D
			if a:
				a.visible = randf() < 0.4

func _armor_clang(p: MorphBall) -> void:
	Sfx.play("clang", global_position, 0.0, 0.05)
	var away := p.global_position - global_position
	away.y = 0.0
	p.linear_velocity = away.normalized() * 7.5 + Vector3.UP * 4.0
	p._jumped_now = true
	p.launched(0.3)
	p.attack = ""
	GameState.shake.emit(0.2)
	if _armor_cd <= 0.0:
		_armor_cd = 4.0
		FloatText.spawn(get_parent(), global_position + Vector3.UP * 2.2, "岩甲太硬了……用落石砸它", Color("c8d0e0"), 40, 1.4)

func _check_contact(p: MorphBall) -> void:
	if p == null or not _hit_area.overlaps_body(p) or not active:
		return
	if vulnerable():
		var hit := p.attack != "" or Vector3(p.linear_velocity.x, 0, p.linear_velocity.z).length() > 2.5 \
			or (p.linear_velocity.y < -1.5 and p.global_position.y > global_position.y + 1.0)
		if hit:
			if p.linear_velocity.y < -1.5:
				p.stomp_bounce()
			_hurt(p.global_position)
		return
	if p.attack != "" or (p.linear_velocity.y < -1.5 and p.global_position.y > global_position.y + 1.0):
		_armor_clang(p)
		return
	if state == St.CHARGE:
		p.hurt(global_position)
		_set_state(St.DIZZY)
	elif not p.is_invulnerable():
		var away2 := p.global_position - global_position
		away2.y = 0.0
		p.apply_central_impulse(away2.normalized() * 2.0 * p.mass)

func _hurt(from: Vector3) -> void:
	hp -= 1
	hp_changed.emit(hp)
	_update_bar()
	Sfx.play("enemy_defeat", global_position, 2.0, 0.0, 0.7)
	GameState.shake.emit(0.35)
	GameState.rumble(0.6, 0.6, 0.25)
	if hp <= 0:
		_final = true
		if _bar:
			_bar.get_parent().queue_free()
		_defeat(true)
		return
	var away := global_position - from
	away.y = 0.0
	_knock = away.normalized() * 6.0
	_set_state(St.PATROL)
	for i in 5:
		var a := _body.get_node_or_null("Armor%d" % i) as Node3D
		if a:
			a.visible = true

func _defeat(drops: bool) -> void:
	if _final:
		super._defeat(drops)
		return
	# 掉下浮岛：不会就这么死掉，回到场地中央
	if global_position.y < GameState.kill_y:
		global_position = home + Vector3.UP * 1.0
		velocity = Vector3.ZERO
		_set_state(St.PATROL)

## 普通的翻倒手段对它都没用（岩甲）
func on_pound(_from: Vector3) -> void:
	if active and not vulnerable():
		_knock = (global_position - _from).normalized() * 2.0

func on_wave(from: Vector3) -> void:
	if active and not vulnerable():
		var away := global_position - from
		away.y = 0.0
		_knock = away.normalized() * 3.0

func on_item(_item: Node3D) -> void:
	pass

func on_bubble(_shot: Node3D) -> void:
	pass

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
	var name_l := UIKit.label("锈根兽", 26, Color("ffd9a8"), true)
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
		tw.tween_property(_bar_fill, "size:x", 520.0 * float(maxi(hp, 0)) / max_hp, 0.3)

## 只有被落石砸翻的时候才打得动（冲墙晕眩时岩甲还在）
func vulnerable() -> bool:
	return state == St.FLIPPED
