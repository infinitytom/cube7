class_name LightBeam
extends Node3D
## 光束：从发射晶（聚光的巨大水晶）射出一道光，在晶面镜之间反射。
## 打到「受光晶」→ 受光晶变成能量源，给挨着它的导电方块和设备供电（接进 PowerGrid）；光移开就断电。
## 打到能烧的东西（木头、荆棘……）→ 慢慢点着。打到共鸣晶簇 → 照一会儿就震碎。
## 打到敌人 → 调用 on_beam（Boss 的晶甲会被光照碎）。PIX 挡在光路上会把光挡住（不受伤）。

signal lens_changed(cell: Vector3i, lit: bool)

@export var active := true
var dir := Vector3(1, 0, 0)
var color := Color(1.0, 0.95, 0.6)
var max_len := 60.0
var world: VoxelWorld
var lenses := {}               ## 当前被照亮的受光晶（格坐标 -> true）
var _segments: Array[MeshInstance3D] = []
var _hit_fx: MeshInstance3D
var _t := 0.0
var _heat := {}                ## 照在同一格上的累计时间（点火 / 震碎用）
var _mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _lit_mirrors: Array = []
var last_path: Array[Vector3] = []

func _ready() -> void:
	add_to_group("light_beam")
	if world == null:
		world = get_tree().get_first_node_in_group("voxel_world") as VoxelWorld
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.albedo_color = Color(color, 0.55)
	_mat.disable_fog = true
	_core_mat = _mat.duplicate() as StandardMaterial3D
	_core_mat.albedo_color = Color(1, 1, 1, 0.8)
	_hit_fx = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.6
	_hit_fx.mesh = sm
	_hit_fx.material_override = _mat
	_hit_fx.top_level = true
	add_child(_hit_fx)
	# 发射晶：一大块发光的水晶
	var em := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.8, 1.2, 0.8)
	em.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(color, 1.0)
	gm.emission_enabled = true
	gm.emission = color
	gm.emission_energy_multiplier = 2.5
	em.material_override = gm
	em.position.y = 0.2
	add_child(em)
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 1.5
	l.omni_range = 5.0
	add_child(l)

func _physics_process(delta: float) -> void:
	_t += delta
	if not active:
		_clear()
		return
	_trace(delta)

func _clear() -> void:
	for s in _segments:
		s.visible = false
	_hit_fx.visible = false
	for c in lenses.keys():
		_set_lens(c, false)
	lenses.clear()
	last_path.clear()

var _last_hit_cell := Vector3i(-999, 0, 0)
var _last_hit_kind := ""

func _trace(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var p := global_position + Vector3.UP * 0.2
	var d := dir.normalized()
	var path: Array[Vector3] = [p]
	var exclude: Array[RID] = []
	var hit_lenses := {}
	var mirrors_lit: Array = []
	_last_hit_kind = ""
	for bounce in 12:
		var q := PhysicsRayQueryParameters3D.create(p, p + d * max_len, 1 | 2 | 16)
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			path.append(p + d * max_len)
			break
		var hp: Vector3 = hit.position
		path.append(hp)
		var col = hit.collider
		if col is BeamMirror:
			var m := col as BeamMirror
			var n := m.normal()
			if d.dot(n) < -0.05:
				mirrors_lit.append(m)
				d = (d - 2.0 * d.dot(n) * n).normalized()
				d.y = 0.0
				d = d.normalized()
				p = hp + d * 0.05
				exclude = [m.get_rid()]
				continue
			break
		if col is Node and (col as Node).is_in_group("enemy"):
			if (col as Node).has_method("on_beam"):
				col.call("on_beam", self)
			_last_hit_kind = "enemy"
			break
		if col == GameState.player:
			_last_hit_kind = "player"
			break
		# 体素：看看打到的是什么
		if world:
			var cell := world.world_to_voxel(hp - (hit.normal as Vector3) * 0.1)
			var t := world.get_block(cell)
			if t == Blocks.LENS or lenses.has(cell):
				hit_lenses[cell] = true
			else:
				_last_hit_cell = cell
				_last_hit_kind = "block"
		break
	last_path = path
	# 受光晶开关
	for c in hit_lenses.keys():
		if not lenses.has(c):
			lenses[c] = true
			_set_lens(c, true)
	for c in lenses.keys():
		if not hit_lenses.has(c):
			lenses.erase(c)
			_set_lens(c, false)
	for m in _lit_mirrors:
		if is_instance_valid(m) and not mirrors_lit.has(m):
			m.lit(false)
	for m in mirrors_lit:
		m.lit(true)
	_lit_mirrors = mirrors_lit
	_draw(path)
	_heat_tick(delta)

## 照在同一格可燃物 / 共鸣晶簇上一段时间：点着 / 震碎
func _heat_tick(delta: float) -> void:
	if _last_hit_kind != "block" or world == null:
		_heat.clear()
		return
	var c := _last_hit_cell
	var t := world.get_block(c)
	var h: float = _heat.get(c, 0.0) + delta
	_heat = {c: h}
	if Blocks.burn[t] > 0.0 and h > 0.8 and world.fire:
		world.fire.ignite_sphere(world.voxel_center(c), 0.45)
		_heat[c] = 0.0
	elif t == Blocks.GEM_CHAIN and h > 0.6:
		world.try_break(c, "impact", 99.0)
		_heat[c] = 0.0

func _set_lens(c: Vector3i, on: bool) -> void:
	if world == null:
		return
	world.set_block(c, Blocks.SOURCE if on else Blocks.LENS)
	lens_changed.emit(c, on)
	if on:
		Sfx.play("energy", world.voxel_center(c), -4.0, 0.0, 1.3)

func _draw(path: Array[Vector3]) -> void:
	var n := path.size() - 1
	while _segments.size() < n * 2:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.0
		cm.bottom_radius = 1.0
		cm.height = 1.0
		cm.radial_segments = 8
		cm.rings = 1
		cm.cap_top = false
		cm.cap_bottom = false
		mi.mesh = cm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.top_level = true
		add_child(mi)
		_segments.append(mi)
	var pulse := 1.0 + 0.15 * sin(_t * 20.0)
	for i in _segments.size():
		var s := _segments[i]
		var k := i / 2
		if k >= n:
			s.visible = false
			continue
		var a := path[k]
		var b := path[k + 1]
		var len := a.distance_to(b)
		if len < 0.01:
			s.visible = false
			continue
		s.visible = true
		var core := i % 2 == 1
		s.material_override = _core_mat if core else _mat
		var r := (0.05 if core else 0.14) * pulse
		var up := (b - a) / len
		var side := up.cross(Vector3.UP)
		if side.length() < 0.01:
			side = Vector3.RIGHT
		side = side.normalized()
		var fwd := side.cross(up).normalized()
		s.global_transform = Transform3D(Basis(side * r, up * len, fwd * r), (a + b) * 0.5)
	_hit_fx.visible = n > 0
	if n > 0:
		_hit_fx.global_position = path[n]
		_hit_fx.scale = Vector3.ONE * (0.8 + 0.3 * sin(_t * 25.0))
