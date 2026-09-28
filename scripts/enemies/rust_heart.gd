class_name RustHeart
extends StaticBody3D
## 终章 Boss「锈蚀之心」：方舟星核里长出来的锈蚀源头。一颗发红光的核心，外面裹着一层体素锈壳（真的方块，能撞碎）。
## 三种形态各用一次，最后一击：
##   第一阶段：锈壳是锈铁——原地蓄力冲刺撞出一个洞，钻进去撞核心
##   第二阶段：它升到高处——从场边的弹射炮飞上去，用钻头形态从上面下砸，砸穿锈壳砸到核心
##   第三阶段：锈壳变成加固合金，打不动——它会朝你吐锈弹，用气泡形态的气浪把锈弹打回去
##   最后：锈壳碎了，核心掉到地上——撞它！
## 锈壳会慢慢长回来；地面上会扩散出一圈圈锈蚀波（跳过去）。

signal defeated(e: Node)
signal phase_changed(p: int)

var world: VoxelWorld
var floor_y := 0.0              ## 场地地面高度（米）
var home := Vector3.ZERO        ## 场地中心（地面上）
var arena_r := 9.0              ## 场地半径（米）
var active := false
var phase := 0                  ## 0 未开始 1..3 三个阶段 4 核心落地 5 结束
var dead := false
var waves_on := true           ## 测试时可以关掉地面锈蚀波

const SHELL_R := 3.4            ## 锈壳外半径（米）
const SHELL_T := 0.8            ## 锈壳厚度（米）
const CORE_R := 1.3

var _core: MeshInstance3D
var _core_mat: StandardMaterial3D
var _halo: MeshInstance3D
var _shell: Dictionary = {}     ## 格 -> 方块类型（当前阶段的锈壳）
var _shell_center := Vector3.ZERO
var _t := 0.0
var _regen_t := 0.0
var _wave_t := 4.0
var _bomb_t := 3.0
var _hit_cd := 0.0
var _waves: Array = []          ## [MeshInstance3D, 半径]
var _summons: Array = []
var _bar_fill: ColorRect
var _bar_layer: CanvasLayer
var _chunks: Array[Node3D] = []

func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 0
	collision_mask = 0
	world = get_tree().get_first_node_in_group("voxel_world") as VoxelWorld
	_core = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = CORE_R
	sm.height = CORE_R * 2.0
	_core.mesh = sm
	_core_mat = StandardMaterial3D.new()
	_core_mat.albedo_color = Color("ff5a3a")
	_core_mat.emission_enabled = true
	_core_mat.emission = Color("ff3a1a")
	_core_mat.emission_energy_multiplier = 3.0
	_core.material_override = _core_mat
	add_child(_core)
	_halo = MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = CORE_R * 1.6
	hm.height = CORE_R * 3.2
	_halo.mesh = hm
	var halo_m := StandardMaterial3D.new()
	halo_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_m.albedo_color = Color(1.0, 0.35, 0.2, 0.25)
	_halo.material_override = halo_m
	add_child(_halo)
	var l := OmniLight3D.new()
	l.light_color = Color("ff6a3a")
	l.light_energy = 3.0
	l.omni_range = 14.0
	add_child(l)
	# 绕着核心转的锈块
	var rust := StandardMaterial3D.new()
	rust.albedo_color = Color("8a4b32")
	for k in 8:
		var c := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * randf_range(0.4, 0.8)
		c.mesh = bm
		c.material_override = rust
		add_child(c)
		_chunks.append(c)

func start() -> void:
	if active:
		return
	active = true
	_make_bar()
	_set_phase(1)

func _heights() -> Array:
	return [0.0, 1.4, 7.5, 1.4, 1.4, 1.4]

func _set_phase(p: int) -> void:
	phase = p
	phase_changed.emit(p)
	_update_bar()
	_clear_shell(true)
	var h: float = _heights()[p]
	var target := home + Vector3.UP * h
	var tw := create_tween()
	tw.tween_property(self, "global_position", target, 1.6 if p > 1 else 0.01).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if p <= 3:
		tw.tween_callback(func() -> void: _grow_shell(Blocks.REINFORCED if p == 3 else Blocks.RUST, true))
	match p:
		1:
			GameState.say("锈蚀之心……它裹着一层锈壳。原地蓄力，冲刺撞出一个洞，再撞进去！")
		2:
			GameState.say("它升上去了！从场边的弹射炮飞上去，换钻头从上面砸下去！")
		3:
			GameState.say("锈壳变成合金了，撞不动……它在吐锈弹——换气泡，用气浪把锈弹打回去！")
		4:
			GameState.say("锈壳碎了——核心掉下来了！撞它！！")

# ================================================================ 锈壳

func _clear_shell(fx: bool) -> void:
	for c in _shell.keys():
		if world.get_block(c) != Blocks.AIR:
			if fx:
				world.break_fx_at(world.voxel_center(c), world.get_block(c), false)
			world.set_block(c, Blocks.AIR)
	_shell.clear()

## 以当前位置为中心长出锈壳：方块从核心往外飞出去拼成一个球壳
func _grow_shell(t: int, animate: bool) -> void:
	_shell_center = global_position
	var r_out := SHELL_R / VoxelWorld.CELL_M
	var r_in := (SHELL_R - SHELL_T) / VoxelWorld.CELL_M
	var cc := world.world_to_voxel(_shell_center)
	var rb: VoxelRebuilder = null
	if animate:
		rb = VoxelRebuilder.new()
		rb.world = world
		rb.pitch_base = 0.5
		get_parent().add_child(rb)
	var n := int(ceil(r_out)) + 1
	var i := 0
	for z in range(-n, n + 1):
		for y in range(-n, n + 1):
			for x in range(-n, n + 1):
				var d := Vector3(x, y, z).length()
				if d > r_out or d < r_in:
					continue
				var c := cc + Vector3i(x, y, z)
				if (world.voxel_center(c).y) < floor_y + 0.2:
					continue
				_shell[c] = t
				if rb:
					rb.add_cell(c, t, 0, world.voxel_center(c), _shell_center, randf_range(0.0, 0.8), 0.5)
				else:
					world.set_block(c, t)
				i += 1

## 锈壳慢慢长回来：每次补几块
func _regen(n: int) -> void:
	var missing: Array = []
	for c in _shell.keys():
		if world.get_block(c) == Blocks.AIR:
			missing.append(c)
	if missing.is_empty():
		return
	missing.shuffle()
	var rb := VoxelRebuilder.new()
	rb.world = world
	rb.pitch_base = 0.5
	get_parent().add_child(rb)
	for k in mini(n, missing.size()):
		var c: Vector3i = missing[k]
		rb.add_cell(c, int(_shell[c]), 0, world.voxel_center(c), _shell_center, k * 0.05, 0.5)

func shell_intact() -> float:
	if _shell.is_empty():
		return 0.0
	var n := 0
	for c in _shell.keys():
		if world.get_block(c) != Blocks.AIR:
			n += 1
	return float(n) / _shell.size()

# ================================================================ 更新

func _physics_process(delta: float) -> void:
	_t += delta
	# 外观：核心跳动，锈块绕着转
	var beat := 1.0 + 0.08 * sin(_t * 5.0) + (0.1 if phase == 4 else 0.0) * sin(_t * 14.0)
	_core.scale = Vector3.ONE * beat
	_halo.scale = Vector3.ONE * (1.0 + 0.15 * sin(_t * 2.5))
	for k in _chunks.size():
		var a := _t * (0.8 + k * 0.07) + k * TAU / _chunks.size()
		var rr := SHELL_R + 0.8 + 0.3 * sin(_t + k)
		_chunks[k].position = Vector3(cos(a) * rr, sin(_t * 0.7 + k) * 1.2, sin(a) * rr)
		_chunks[k].rotation = Vector3(_t + k, _t * 0.7, 0)
		_chunks[k].visible = phase >= 1 and phase <= 3
	if not active or dead:
		return
	_hit_cd -= delta
	# 锈壳再生
	if phase >= 1 and phase <= 2:
		_regen_t -= delta
		if _regen_t <= 0.0:
			_regen_t = 5.0
			_regen(14)
	# 地面锈蚀波
	_wave_t -= delta
	if _wave_t <= 0.0 and phase >= 1 and waves_on:
		_wave_t = 6.0 if phase < 3 else 4.5
		_spawn_wave()
	_update_waves(delta)
	# 第二阶段：放锈蜂
	if phase == 2:
		_summons = _summons.filter(func(x) -> bool: return is_instance_valid(x))
		if _summons.size() < 2 and fmod(_t, 7.0) < delta:
			var f := Rustfly.new()
			get_parent().add_child(f)
			f.global_position = global_position + Vector3(randf_range(-3, 3), -1.0, randf_range(-3, 3))
			f.sight = 16.0
			_summons.append(f)
	# 第三阶段：吐锈弹（能被气浪打回来）
	if phase == 3:
		_bomb_t -= delta
		if _bomb_t <= 0.0:
			_bomb_t = 2.6
			var p := GameState.player as Node3D
			if p:
				var from := global_position + (p.global_position - global_position).normalized() * (SHELL_R + 0.6)
				var tgt := p.global_position
				tgt.y = floor_y + 0.2
				RustBomb.launch(get_parent(), from, tgt, 1.6, self)
				Sfx.play("throw", global_position, 4.0, 0.0, 0.5)
	_check_player()

func _check_player() -> void:
	var p := GameState.player as MorphBall
	if p == null or _hit_cd > 0.0:
		return
	var d := p.global_position.distance_to(global_position)
	if d < CORE_R + 0.9 and (p.linear_velocity.length() > 2.5 or p.attack != ""):
		_hit(p)
		return
	# 满蓄力冲刺一头撞穿锈壳（第一阶段）、钻头从上面砸穿锈壳（第二阶段）：这一下就能震到核心
	if phase == 1 and p.charged_ram and d < SHELL_R + 0.8:
		_hit(p)
	elif phase == 2 and p.attack == "pound" and d < SHELL_R + 1.0 and p.global_position.y > global_position.y + 1.0:
		_hit(p)

func _hit(p: MorphBall) -> void:
	_hit_cd = 1.5
	GameState.shake.emit(0.9)
	GameState.hitstop(0.12)
	GameState.rumble(1.0, 1.0, 0.5)
	Sfx.play("impact_big", global_position, 8.0, 0.0, 0.5)
	Sfx.play("break_glass", global_position, 4.0, 0.0, 0.6)
	_core_mat.emission = Color("ffffff")
	var tw := create_tween()
	tw.tween_property(_core_mat, "emission", Color("ff3a1a"), 0.6)
	if p:
		var away := p.global_position - global_position
		away.y = 0.0
		p.linear_velocity = away.normalized() * 7.0 + Vector3.UP * 6.0
		p.launched(0.6)
	if phase >= 4:
		_die()
		return
	_set_phase(phase + 1)

# ================================================================ 锈蚀波

func _spawn_wave() -> void:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.92
	t.outer_radius = 1.0
	t.rings = 64
	t.ring_segments = 8
	mi.mesh = t
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("c0502a")
	m.emission_enabled = true
	m.emission = Color("ff5a2a")
	m.emission_energy_multiplier = 1.5
	mi.material_override = m
	get_parent().add_child(mi)
	mi.global_position = Vector3(home.x, floor_y + 0.15, home.z)
	mi.scale = Vector3(1.0, 5.0, 1.0)
	_waves.append([mi, 1.0])
	Sfx.play("enemy_windup", home, 2.0, 0.0, 0.7)

func _update_waves(delta: float) -> void:
	var p := GameState.player as MorphBall
	var keep: Array = []
	for w in _waves:
		var mi: MeshInstance3D = w[0]
		var r: float = float(w[1]) + delta * 6.0
		w[1] = r
		if r > arena_r + 2.0:
			mi.queue_free()
			continue
		mi.scale = Vector3(r, 5.0, r)
		keep.append(w)
		if p and not p.is_invulnerable():
			var dh := Vector2(p.global_position.x - home.x, p.global_position.z - home.z).length()
			if absf(dh - r) < 0.45 and p.global_position.y < floor_y + 0.9:
				p.hurt(Vector3(home.x, p.global_position.y, home.z))
	_waves = keep

# ================================================================ 结束

func _die() -> void:
	dead = true
	phase = 5
	for w in _waves:
		(w[0] as Node).queue_free()
	_waves.clear()
	for f in _summons:
		if is_instance_valid(f):
			f.call("defeat", true)
	if _bar_layer:
		_bar_layer.queue_free()
	_clear_shell(true)
	Sfx.play("rebuild_done", Vector3.INF, 2.0, 0.0, 0.5)
	var tw := create_tween()
	tw.tween_property(_core_mat, "albedo_color", Color("7de3ff"), 1.5)
	tw.parallel().tween_property(_core_mat, "emission", Color("5ad8ff"), 1.5)
	tw.tween_callback(func() -> void:
		GameState.enemies_defeated += 1
		defeated.emit(self))

func reflected_hit() -> void:
	if phase == 3 and _hit_cd <= 0.0:
		_hit(null)

## 敌人接口（气浪、下砸、道具……）：伤害都在 _check_player / 反弹锈弹里处理，这里什么都不做
func on_pound(_from: Vector3) -> void:
	pass

func on_wave(_from: Vector3) -> void:
	pass

func on_item(_item: Node3D) -> void:
	pass

func on_bubble(_s: Node3D) -> void:
	pass

func take_hit(_from: Vector3, _kind: String) -> void:
	pass

func _make_bar() -> void:
	_bar_layer = CanvasLayer.new()
	_bar_layer.layer = 5
	get_tree().current_scene.add_child(_bar_layer)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_CENTER_TOP)
	root.position = Vector2(-260, 96)
	root.custom_minimum_size = Vector2(520, 0)
	_bar_layer.add_child(root)
	var name_l := UIKit.label("锈蚀之心", 26, Color("ffb3a0"), true)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(name_l)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.2, 0.8)
	bg.custom_minimum_size = Vector2(520, 16)
	root.add_child(bg)
	_bar_fill = ColorRect.new()
	_bar_fill.color = Color("ff5a3a")
	_bar_fill.size = Vector2(520, 16)
	bg.add_child(_bar_fill)

func _update_bar() -> void:
	if _bar_fill:
		_bar_fill.size.x = 520.0 * clampf(1.0 - (phase - 1) / 4.0, 0.0, 1.0)

## 自动测试：直接打一下
func debug_hit() -> void:
	_hit_cd = 0.0
	_hit(null)
