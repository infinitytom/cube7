class_name VoxelRebuilder
extends MultiMeshInstance3D
## “重构”动画：一格格方块从起点（地下、PIX 身上……）划着弧线飞回原位，落地的瞬间写回体素世界。
## 用一个 MultiMesh 画所有在飞的方块，几千块同时飞也不卡。
##   · 重构塔点亮 → 被砸烂的地形一圈圈飞回来（VoxelWorld.restore_wave）
##   · 重构点 → 用攒下的物质把废墟重建起来（RebuildSite）

signal finished

const MAX := 4000
const SETTLE_TIME := 0.3

## 圆角方块：飞回来的地形块也是软软的（和平滑地形的画风一致）
static var _cube_mesh: ArrayMesh
static func _rounded_cube() -> ArrayMesh:
	if _cube_mesh:
		return _cube_mesh
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	bm.subdivide_width = 3
	bm.subdivide_height = 3
	bm.subdivide_depth = 3
	var arr := bm.get_mesh_arrays()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns := PackedVector3Array()
	ns.resize(vs.size())
	for i in vs.size():
		var v := vs[i]
		# 往球面收一点：棱角变圆，面还是平的
		var sph := v.normalized() * 0.62
		vs[i] = v.lerp(sph, 0.38)
		ns[i] = v.normalized().lerp(arr[Mesh.ARRAY_NORMAL][i], 0.4).normalized()
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_TANGENT] = null
	_cube_mesh = ArrayMesh.new()
	_cube_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return _cube_mesh

var world: VoxelWorld
var _items: Array = []        ## 每项：{"vox": [[p, t], ...], "to": Vector3, "from": Vector3, "start": float, "dur": float, "col": Color, "size": float}
var _time := 0.0
var _mm: MultiMesh
var _total := 0
var _landed := 0
var _tick_t := 0.0
var _started := false
var pitch_base := 0.9

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var bm := _rounded_cube()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.emission_enabled = true
	m.emission = Color(0.35, 0.9, 1.0)
	m.emission_energy_multiplier = 0.35
	m.roughness = 0.6
	bm.surface_set_material(0, m)
	_mm.mesh = bm
	_mm.instance_count = MAX
	_mm.visible_instance_count = 0
	multimesh = _mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 200.0

## vox：这一块落地时要写回的体素 [[Vector3i, type], ...]；to：飞到的世界坐标（块中心）
func add(vox: Array, to: Vector3, from: Vector3, delay: float, dur := 0.6, size := 0.5) -> void:
	var t: int = vox[0][1]
	_items.append({"vox": vox, "to": to, "from": from, "start": _time + delay, "dur": dur, "col": Blocks.colors[t], "size": size})
	_total += 1
	_started = true

## 整格（可以是斜坡）：落地时 set_ramp / set_block
func add_cell(cell: Vector3i, t: int, shape: int, to: Vector3, from: Vector3, delay: float, dur := 0.6) -> void:
	_items.append({"cell": cell, "t": t, "shape": shape, "to": to, "from": from, "start": _time + delay, "dur": dur, "col": Blocks.colors[t], "size": 0.5})
	_total += 1
	_started = true

func _process(delta: float) -> void:
	_time += delta
	_tick_t -= delta
	var n := 0
	var keep: Array = []
	var p := GameState.player as Node3D
	for it in _items:
		var k: float = (_time - float(it.start)) / float(it.dur)
		if k < 0.0:
			keep.append(it)
			continue
		if k >= 1.0:
			if it.get("landed", false):
				# 已经写回世界：在原位停留一小会儿、轻轻缩进去，盖住地形网格重建的那几帧（不会闪出空洞）
				var lk := (_time - float(it.land_t)) / SETTLE_TIME
				if lk < 1.0:
					keep.append(it)
					if n < MAX:
						var ss: float = float(it.size) * (0.95 - 0.25 * lk)
						_mm.set_instance_transform(n, Transform3D(Basis.from_scale(Vector3.ONE * ss), it.to))
						_mm.set_instance_color(n, (it.col as Color).lerp(Color(0.75, 1.0, 1.0), 0.25 * (1.0 - lk)))
						n += 1
				continue
			if not _land(it, p):
				# PIX 正好挡在那一格：等一下再落
				it.start = _time + 0.25 - float(it.dur)
				keep.append(it)
			else:
				it["landed"] = true
				it["land_t"] = _time
				keep.append(it)
			continue
		keep.append(it)
		if n >= MAX:
			continue
		var e := 1.0 - pow(1.0 - k, 3.0)
		var from: Vector3 = it.from
		var to: Vector3 = it.to
		var pos := from.lerp(to, e) + Vector3.UP * sin(k * PI) * minf(3.0, from.distance_to(to) * 0.35)
		var s: float = float(it.size) * (0.35 + 0.6 * e)
		var spin := (1.0 - e) * 6.0
		var b := Basis.from_euler(Vector3(spin, spin * 0.7, 0.0)).scaled(Vector3.ONE * s)
		_mm.set_instance_transform(n, Transform3D(b, pos))
		var c: Color = it.col
		_mm.set_instance_color(n, c.lerp(Color(0.6, 0.95, 1.0), (1.0 - k) * 0.6))
		n += 1
	_mm.visible_instance_count = n
	_items = keep
	if _started and _items.is_empty():
		_started = false
		finished.emit()
		queue_free()

func _land(it: Dictionary, p: Node3D) -> bool:
	var to: Vector3 = it.to
	# 别把方块直接砸进 PIX 身体里（球和这块的方盒真的重叠才等）
	if p:
		var hs := float(it.size) * 0.5
		var q := p.global_position
		var closest := Vector3(clampf(q.x, to.x - hs, to.x + hs), clampf(q.y, to.y - hs, to.y + hs), clampf(q.z, to.z - hs, to.z + hs))
		if closest.distance_to(q) < 0.42:
			return false
	_landed += 1
	if it.has("cell"):
		var c: Vector3i = it.cell
		if world.get_block(c) == Blocks.AIR:
			if int(it.shape) != 0:
				world.set_ramp(c, int(it.t), int(it.shape))
			else:
				world.set_block(c, int(it.t))
	for pair in it.get("vox", []):
		var q: Vector3i = pair[0]
		if world.vget(q) == Blocks.AIR:
			if pair.size() > 2 and int(pair[2]) != 0:
				world.vset_ramp(q, int(pair[1]), int(pair[2]))
			else:
				world.vset(q, int(pair[1]))
		world.damage.erase(q)
	if _tick_t <= 0.0:
		_tick_t = 0.045
		var prog := float(_landed) / maxf(1.0, float(_total))
		Sfx.play("rebuild", to, -8.0, 0.05, pitch_base + prog * 0.7)
	return true
