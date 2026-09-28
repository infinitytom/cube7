class_name RustAirship
extends Node3D
## 第四章 Boss「锈蚀巡逻艇」：以前的城防飞艇，现在绕着议会广场上空打转，一路往下扔锈弹。
## 飞艇在高处够不着——广场四周有弹射炮：滚进炮口会被高高弹起，看准飞艇从头顶经过的时候发射，
## 撞上它的发动机（三台，两侧和尾部）就能把它撞坏。三台都坏了，飞艇就掉下来了。
## 第二阶段起会放出锈蜂；第三阶段扔弹更密。地上的影子标出飞艇的位置。

signal defeated(e: Node)
signal engine_lost(left: int)

var center := Vector3.ZERO
var radius := 9.0
var height := 9.5
var ang_speed := 0.32
var active := false
var dead := false
var _ang := 0.0
var _engines: Array[Node3D] = []
var _engine_areas: Array[Area3D] = []
var _hull_area: Area3D
var _t := 0.0
var _bomb_t := 2.0
var _shadow: MeshInstance3D
var _summons: Array = []
var _props: Array[Node3D] = []
var _bar_fill: ColorRect
var _bar_root: Control
var _hit_cd := 0.0
var _drone: AudioStreamPlayer3D

func _ready() -> void:
	var balloon := StandardMaterial3D.new()
	balloon.albedo_color = Color("c9d6ea")
	balloon.roughness = 0.6
	var rust := StandardMaterial3D.new()
	rust.albedo_color = Color("b5653e")
	rust.roughness = 0.7
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("3d4659")
	dark.metallic = 0.4
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("ffb347")
	glow.emission_enabled = true
	glow.emission = Color("ff8a3d")
	glow.emission_energy_multiplier = 2.0
	# 气囊：几节方块拼成的长条（体素风）
	for k in 7:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var t := 1.0 - absf(k - 3) / 4.0
		bm.size = Vector3(1.0, 1.6 + 1.4 * t, 1.6 + 1.4 * t)
		mi.mesh = bm
		mi.material_override = balloon if k % 2 == 0 else rust
		mi.position = Vector3(-3.0 + k, 1.6, 0)
		add_child(mi)
	# 尾翼
	for r in [0.0, PI / 2.0]:
		var fin := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(1.2, 1.8, 0.15)
		fin.mesh = fm
		fin.material_override = rust
		fin.position = Vector3(-3.6, 1.6, 0)
		fin.rotation.x = r
		add_child(fin)
	# 吊舱
	var g := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(2.6, 0.8, 1.2)
	g.mesh = gm
	g.material_override = dark
	add_child(g)
	for k in 4:
		var w := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(0.3, 0.25, 0.05)
		w.mesh = wm
		w.material_override = glow
		w.position = Vector3(-0.9 + k * 0.6, 0.1, 0.62)
		add_child(w)
	# 三台发动机：左、右、尾
	for pos in [Vector3(0.3, 1.0, 2.0), Vector3(0.3, 1.0, -2.0), Vector3(-4.4, 1.6, 0.0)]:
		var eng := Node3D.new()
		eng.position = pos
		add_child(eng)
		var body := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.5
		cm.bottom_radius = 0.55
		cm.height = 1.0
		body.mesh = cm
		body.material_override = dark
		body.rotation.z = PI / 2.0
		eng.add_child(body)
		var core := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.35
		sm.height = 0.7
		core.mesh = sm
		core.material_override = glow
		core.position.x = -0.45
		eng.add_child(core)
		var prop := Node3D.new()
		prop.position.x = 0.55
		eng.add_child(prop)
		for b in 3:
			var blade := MeshInstance3D.new()
			var bm2 := BoxMesh.new()
			bm2.size = Vector3(0.05, 1.3, 0.2)
			blade.mesh = bm2
			blade.material_override = rust
			blade.rotation.x = b * TAU / 3.0
			prop.add_child(blade)
		_props.append(prop)
		_engines.append(eng)
		var a := Area3D.new()
		a.collision_layer = 0
		a.collision_mask = 2
		var cs := CollisionShape3D.new()
		var ss := SphereShape3D.new()
		ss.radius = 1.4
		cs.shape = ss
		a.add_child(cs)
		eng.add_child(a)
		_engine_areas.append(a)
	_hull_area = Area3D.new()
	_hull_area.collision_layer = 0
	_hull_area.collision_mask = 2
	var hc := CollisionShape3D.new()
	var hs := CapsuleShape3D.new()
	hs.radius = 1.9
	hs.height = 8.0
	hc.shape = hs
	hc.rotation.z = PI / 2.0
	hc.position.y = 1.2
	_hull_area.add_child(hc)
	add_child(_hull_area)
	_shadow = MeshInstance3D.new()
	var sh := CylinderMesh.new()
	sh.top_radius = 2.6
	sh.bottom_radius = 2.6
	sh.height = 0.02
	_shadow.mesh = sh
	var shm := StandardMaterial3D.new()
	shm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shm.albedo_color = Color(0.1, 0.05, 0.2, 0.35)
	_shadow.material_override = shm
	_shadow.top_level = true
	add_child(_shadow)
	_drone = AudioStreamPlayer3D.new()
	_drone.stream = load("res://audio/sfx/drill.ogg")
	_drone.pitch_scale = 0.45
	_drone.volume_db = -6.0
	_drone.max_distance = 60.0
	_drone.bus = "SFX"
	add_child(_drone)
	_place()

func engines_left() -> int:
	var n := 0
	for e in _engines:
		if e.visible:
			n += 1
	return n

func start() -> void:
	if active:
		return
	active = true
	_drone.play()
	_make_bar()

func _place() -> void:
	var p := center + Vector3(cos(_ang) * radius, height, sin(_ang) * radius)
	global_position = p + Vector3.UP * sin(_t * 0.8) * 0.4
	# 机头朝飞行方向（切线）
	var tangent := Vector3(-sin(_ang), 0, cos(_ang))
	look_at(global_position + tangent, Vector3.UP)
	rotate_object_local(Vector3.UP, PI / 2.0)
	_shadow.global_position = Vector3(global_position.x, center.y + 0.06, global_position.z)

func _process(delta: float) -> void:
	if dead:
		return
	_t += delta
	_hit_cd -= delta
	for k in _props.size():
		if _engines[k].visible:
			_props[k].rotate_x(delta * 18.0)
	if not active:
		_place()
		return
	var left := engines_left()
	_ang += delta * ang_speed * (1.0 + (3 - left) * 0.18)
	_place()
	# 扔弹：沿航线在身后撒一串
	_bomb_t -= delta
	if _bomb_t <= 0.0:
		_bomb_t = 3.2 - (3 - left) * 0.7
		var n := 2 + (3 - left)
		var p := GameState.player as Node3D
		for k in n:
			var tgt := Vector3(global_position.x, center.y, global_position.z)
			if p and k == 0:
				tgt = Vector3(p.global_position.x, center.y, p.global_position.z)
			else:
				tgt += Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
			RustBomb.launch(get_parent(), global_position + Vector3.DOWN * 0.5, tgt, 1.4 + k * 0.15, null)
		Sfx.play("throw", global_position, 2.0, 0.1, 0.6)
	_check_hits()

func _check_hits() -> void:
	var p := GameState.player as MorphBall
	if p == null or _hit_cd > 0.0:
		return
	var fast := p.linear_velocity.length() > 5.0
	for k in _engine_areas.size():
		if _engines[k].visible and _engine_areas[k].overlaps_body(p) and fast:
			_break_engine(k, p)
			return
	if _hull_area.overlaps_body(p) and fast:
		# 撞到艇身：离得最近的一台发动机算被撞坏
		var best := -1
		var bd := 1e9
		for k in _engines.size():
			if _engines[k].visible:
				var d := _engines[k].global_position.distance_to(p.global_position)
				if d < bd:
					bd = d
					best = k
		if best >= 0:
			_break_engine(best, p)

func _break_engine(k: int, p: MorphBall) -> void:
	_hit_cd = 1.5
	var e := _engines[k]
	e.visible = false
	_engine_areas[k].monitoring = false
	GameState.shake.emit(0.7)
	Sfx.play("impact_big", e.global_position, 6.0, 0.0, 0.7)
	Sfx.play("break_hard", e.global_position, 4.0, 0.0, 0.8)
	_burst(e.global_position)
	# PIX 被弹开，落回广场
	var away := p.global_position - global_position
	away.y = 0.0
	p.linear_velocity = away.normalized() * 5.0 + Vector3.UP * 4.0
	p.launched(0.5)
	var left := engines_left()
	engine_lost.emit(left)
	_update_bar()
	if left == 0:
		_crash()
		return
	height -= 1.2
	var smoke := CPUParticles3D.new()
	smoke.amount = 20
	smoke.lifetime = 2.0
	smoke.local_coords = false
	smoke.direction = Vector3.UP
	smoke.gravity = Vector3(0, 1.0, 0)
	smoke.initial_velocity_min = 0.5
	smoke.initial_velocity_max = 1.5
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.25, 0.22, 0.25, 0.6)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = smat
	smoke.mesh = sm
	e.get_parent().add_child(smoke)
	smoke.position = e.position
	if left == 2:
		GameState.say("撞坏一台！它开始往下掉了……小心，它在放锈蜂！")
	else:
		GameState.say("还剩最后一台发动机！")
	if left <= 2:
		_summons = _summons.filter(func(x) -> bool: return is_instance_valid(x))
		for i in 2 - _summons.size():
			var f := Rustfly.new()
			get_parent().add_child(f)
			f.global_position = global_position + Vector3(randf_range(-2, 2), -1.0, randf_range(-2, 2))
			f.sight = 14.0
			_summons.append(f)

func _burst(at: Vector3) -> void:
	for i in 10:
		var b := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3.ONE * randf_range(0.15, 0.3)
		b.mesh = m
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color("b5653e") if i % 2 else Color("3d4659")
		b.material_override = mm
		get_parent().add_child(b)
		b.global_position = at
		var v := Vector3(randf_range(-1, 1), randf_range(-0.5, 1.2), randf_range(-1, 1)) * 3.0
		var tw := b.create_tween().set_parallel()
		tw.tween_property(b, "global_position", at + v, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "scale", Vector3.ZERO, 0.7).set_delay(0.2)
		tw.chain().tween_callback(b.queue_free)

## 三台发动机都坏了：冒着烟打着旋掉到广场外面，撞碎一大片东西
func _crash() -> void:
	dead = true
	_drone.stop()
	for f in _summons:
		if is_instance_valid(f):
			f.call("defeat", true)
	if _bar_root:
		_bar_root.get_parent().queue_free()
	GameState.say("它掉下去了——！")
	var target := center + Vector3(cos(_ang + 0.6) * (radius + 3.0), 0.0, sin(_ang + 0.6) * (radius + 3.0))
	var tw := create_tween()
	tw.set_parallel()
	tw.tween_property(self, "global_position", target + Vector3.UP * 1.0, 2.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "rotation:y", rotation.y + TAU * 0.75, 2.2)
	tw.tween_property(self, "rotation:z", 0.5, 2.2)
	tw.chain().tween_callback(func() -> void:
		GameState.shake.emit(1.0)
		Sfx.play("impact_big", global_position, 8.0, 0.0, 0.5)
		Sfx.play("break_hard", global_position, 6.0, 0.0, 0.6)
		var w := get_tree().get_first_node_in_group("voxel_world") as VoxelWorld
		if w:
			w.break_sphere(global_position, 2.6, "impact", 30.0, Vector3.DOWN)
		var parent: Node = w if w else get_parent()
		for i in 45:
			PickupScript.spawn(parent, "coin", global_position + Vector3.UP * 1.5)
		for i in 8:
			PickupScript.spawn(parent, "energy", global_position + Vector3.UP * 1.5)
		_burst(global_position)
		_burst(global_position + Vector3.UP)
		GameState.enemies_defeated += 1
		defeated.emit(self)
		queue_free())

func _make_bar() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	get_tree().current_scene.add_child(layer)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_CENTER_TOP)
	root.position = Vector2(-260, 96)
	root.custom_minimum_size = Vector2(520, 0)
	layer.add_child(root)
	var name_l := UIKit.label("锈蚀巡逻艇", 26, Color("ffd9a8"), true)
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
	_bar_root = root

func _update_bar() -> void:
	if _bar_fill:
		_bar_fill.size.x = 520.0 * engines_left() / 3.0

## 自动测试：直接撞坏一台发动机
func debug_break(p: MorphBall) -> void:
	for k in _engines.size():
		if _engines[k].visible:
			_hit_cd = 0.0
			_break_engine(k, p)
			return

const PickupScript := preload("res://scripts/voxel/pickup.gd")
