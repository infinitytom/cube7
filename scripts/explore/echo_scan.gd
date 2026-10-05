class_name EchoScan
extends Node3D
## 回声扫描（L2 / Q / 鼠标中键）：PIX 发出一圈声呐波，扫过的地方——
##   · 埋在地层里的回声晶核、种子方块、记忆碎片、宝箱，会隔着地形亮起标记
##   · 金矿、晶洞、共鸣晶簇这类“值得挖”的地层，会标出大致位置
##   · 支撑木架（承重点）会标成橙色：撞断它，上面的东西就会塌下来
## 探索的节奏因此变成：停下来 → 扫一下 → 想想从哪挖进去。

const COOLDOWN := 2.5
const WAVE_TIME := 1.4

var world: VoxelWorld
var _cd := 0.0
var _pulse: MeshInstance3D
var _pulse_mat: ShaderMaterial
var _pulse_t := -1.0
var _radius := 14.0
var _origin := Vector3.ZERO
var _markers: Array[Node3D] = []
var _tutorial_done := false
## 自动测试用：最近一次扫描标出的东西 [{kind, pos, label}]
var last_hits: Array = []

static var _mark_mats := {}

func _ready() -> void:
	add_to_group("echo_scan")
	_pulse = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 24
	sph.rings = 12
	_pulse.mesh = sph
	_pulse_mat = ShaderMaterial.new()
	_pulse_mat.shader = load("res://shaders/echo_pulse.gdshader")
	_pulse.material_override = _pulse_mat
	_pulse.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pulse.extra_cull_margin = 16384.0
	_pulse.visible = false
	add_child(_pulse)

func ready_to_scan() -> bool:
	return _cd <= 0.0

func _process(delta: float) -> void:
	_cd = maxf(_cd - delta, 0.0)
	var p := GameState.player as Node3D
	if p and Input.is_action_just_pressed("scan") and not get_tree().paused:
		scan()
	if _pulse_t >= 0.0:
		_pulse_t += delta
		var k := _pulse_t / WAVE_TIME
		_pulse_mat.set_shader_parameter("radius", _radius * (1.0 - pow(1.0 - minf(k, 1.0), 2.0)) + maxf(k - 1.0, 0.0) * _radius * 0.3)
		# 包住镜头的大球：跟着镜头走，保证每个像素都会跑一次着色器
		var cam := get_viewport().get_camera_3d()
		if cam:
			_pulse.global_position = cam.global_position
			_pulse.scale = Vector3.ONE * maxf(cam.near * 4.0, 0.5)
		if _pulse_t > WAVE_TIME * 1.35:
			_pulse_t = -1.0
			_pulse.visible = false

## 开局一会儿后，NOVA 提一句扫描（每个存档只提一次）
func tutorial_later() -> void:
	var flags: Dictionary = SaveGame.data.get("flags", {}) if not SaveGame.data.is_empty() else {}
	if flags.get("scan_tutorial", false) or GameState.echo_total == 0:
		return
	get_tree().create_timer(45.0).timeout.connect(func() -> void:
		if not is_inside_tree():
			return
		GameState.say("PIX，你的探测器能发回声了。按{scan}扫描一下——地层底下要是有东西，回声会告诉我们。这颗星球……好像在地底下藏了点什么。")
		if not SaveGame.data.is_empty():
			if not SaveGame.data.has("flags"):
				SaveGame.data["flags"] = {}
			SaveGame.data["flags"]["scan_tutorial"] = true
			SaveGame.write())

## 发一次扫描
func scan() -> void:
	if _cd > 0.0:
		return
	var p := GameState.player as Node3D
	if p == null:
		return
	if world == null:
		world = get_tree().get_first_node_in_group("voxel_world") as VoxelWorld
	_cd = COOLDOWN
	_radius = Evolutions.scan_radius()
	_origin = p.global_position
	_pulse_t = 0.0
	_pulse.visible = true
	_pulse_mat.set_shader_parameter("origin", _origin)
	_pulse_mat.set_shader_parameter("max_radius", _radius * 1.3)
	_pulse_mat.set_shader_parameter("radius", 0.0)
	Sfx.play("scan_ping", Vector3.INF, -3.0, 0.03)
	GameState.rumble(0.15, 0.0, 0.2)
	_clear_markers()
	last_hits.clear()
	_collect_nodes()
	_collect_voxels()

func _clear_markers() -> void:
	for m in _markers:
		if is_instance_valid(m):
			m.queue_free()
	_markers.clear()

## 关卡里的节点：晶核、种子方块、记忆碎片、宝箱
func _collect_nodes() -> void:
	var lst: Array = []
	for n in get_tree().get_nodes_in_group("scan_target"):
		lst.append(n)
	for n in get_tree().get_nodes_in_group("seed_cube"):
		lst.append(n)
	var lv := get_tree().current_scene
	if lv:
		for n in lv.find_children("*", "MemoryFragment", true, false):
			lst.append(n)
		for n in lv.find_children("*", "TreasureChest", true, false):
			lst.append(n)
	for n in lst:
		if not (n is Node3D) or not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		var pos := (n as Node3D).global_position
		if pos.distance_to(_origin) > _radius:
			continue
		var kind := "core"
		var label := "回声晶核"
		if n.has_method("scan_kind"):
			kind = n.call("scan_kind")
			label = n.call("scan_label")
		elif n is SeedCube:
			if n.get("opened"):
				continue
			kind = "seed"
			label = "种子方块"
		elif n is MemoryFragment:
			kind = "fragment"
			label = "记忆碎片"
		elif n is TreasureChest:
			if n.get("opened"):
				continue
			kind = "chest"
			label = "宝箱"
		_add_marker(kind, pos, label)

## 地层：金矿、晶洞、共鸣晶簇、支撑木架（每 2 米一格统计，够多才标）
func _collect_voxels() -> void:
	if world == null:
		return
	var c := world.to_v(_origin)
	var r := int(_radius / VoxelWorld.VOXEL)
	var bins := {}
	var kinds := {Blocks.ORE: "ore", Blocks.GEODE: "geode", Blocks.GEM_CHAIN: "geode", Blocks.SUPPORT: "support"}
	var r2 := r * r
	for z in range(-r, r + 1, 2):
		for y in range(-r, r + 1, 2):
			for x in range(-r, r + 1, 2):
				if x * x + y * y + z * z > r2:
					continue
				var p := c + Vector3i(x, y, z)
				var t := world.vget(p)
				if not kinds.has(t):
					continue
				var key := Vector3i(p.x >> 3, p.y >> 3, p.z >> 3)
				var k: String = kinds[t]
				if not bins.has(key):
					bins[key] = {}
				var b: Dictionary = bins[key]
				b[k] = int(b.get(k, 0)) + 1
	var added := 0
	var keys := bins.keys()
	keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return (a - c / 8).length_squared() < (b - c / 8).length_squared())
	for key: Vector3i in keys:
		if added >= 24:
			break
		var b: Dictionary = bins[key]
		for k: String in b:
			if int(b[k]) < 3:
				continue
			var pos := world.vcenter(key * 8 + Vector3i(4, 4, 4))
			var label: String = {"ore": "金矿", "geode": "晶簇", "support": "承重点"}[k]
			_add_marker(k, pos, label)
			added += 1

const KIND_COLOR := {
	"core": Color("8ff7ff"), "seed": Color("7dffc8"), "fragment": Color("c9a6ff"), "chest": Color("ffd166"),
	"ore": Color("ffcf5a"), "geode": Color("d49bff"), "support": Color("ff9a3c"),
}

func _add_marker(kind: String, pos: Vector3, label: String) -> void:
	last_hits.append({"kind": kind, "pos": pos, "label": label})
	var col: Color = KIND_COLOR.get(kind, Color.WHITE)
	if label.contains("需要进化"):
		col = Color(0.75, 0.78, 0.86)
	var m := Node3D.new()
	add_child(m)
	m.global_position = pos
	# 透视的光点：隔着地形也看得见
	var dot := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.22 if kind in ["core", "seed", "fragment", "chest"] else 0.14
	sp.height = sp.radius * 2.0
	sp.radial_segments = 12
	sp.rings = 6
	dot.mesh = sp
	dot.material_override = _mark_mat(col)
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.add_child(dot)
	var lb := Label3D.new()
	lb.text = label
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	lb.fixed_size = true
	lb.pixel_size = 0.0016
	lb.font_size = 40
	lb.outline_size = 12
	lb.modulate = col
	lb.outline_modulate = Color(0.05, 0.08, 0.16, 0.85)
	lb.position = Vector3.UP * 0.45
	lb.render_priority = 10
	lb.font = UIKit.font()
	m.add_child(lb)
	# 波前扫到它的时候再出现
	var delay := clampf(pos.distance_to(_origin) / _radius, 0.0, 1.0) * WAVE_TIME * 0.8
	m.scale = Vector3.ONE * 0.01
	var tw := m.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void: Sfx.play("echo_mark", pos, -10.0, 0.1))
	tw.tween_property(m, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(Evolutions.reveal_time())
	tw.tween_property(lb, "modulate:a", 0.0, 0.8)
	tw.parallel().tween_property(m, "scale", Vector3.ONE * 0.01, 0.8)
	tw.tween_callback(m.queue_free)
	_markers.append(m)

static func _mark_mat(c: Color) -> StandardMaterial3D:
	if _mark_mats.has(c):
		return _mark_mats[c]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.no_depth_test = true
	m.albedo_color = Color(c, 0.9)
	m.render_priority = 9
	_mark_mats[c] = m
	return m
