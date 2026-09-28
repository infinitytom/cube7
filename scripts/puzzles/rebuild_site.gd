class_name RebuildSite
extends Node3D
## 重构点：一座被毁掉的建筑只剩下发光的“蓝图”（半透明的格子）。
## 拆东西攒下的重构物质够了，滚进地上的光圈——整座建筑一块块从 PIX 身上飞出去，拼回原样。
## 拆 → 攒物质 → 重建：破坏和重构是同一个循环。

signal rebuilt

var world: VoxelWorld
var site_id := ""
var title := "瞭望台"
var cost := 40
var pad_cell := Vector3i.ZERO
var blueprint: Array = []        ## [[格坐标, 方块类型], ...]，按建造顺序排好
## 体素级蓝图（体素坐标 -> 方块类型）：用于斜坡、小台阶这种不是整格的结构；设置了它 blueprint 会自动生成
var vox_blueprint: Dictionary = {}
var _vox_cells: Dictionary = {}  ## 格 -> [[体素, 类型], ...]
var done := false
## 重建前要清掉的区域（格，含两端）：蓝图范围里零星的石头、灌木
var clear_a := Vector3i.ZERO
var clear_b := Vector3i(-1, -1, -1)
var _ghost: MultiMeshInstance3D
var _ghost_mat: StandardMaterial3D
var _label: Label3D
var _pad: MeshInstance3D
var _pad_mat: StandardMaterial3D
var _t := 0.0
var _warn_t := 0.0
var _shown_matter := -1
static var _told := false

func _ready() -> void:
	add_to_group("rebuild_site")
	if not vox_blueprint.is_empty():
		for vp: Vector3i in vox_blueprint:
			var c := Vector3i(vp.x >> 1, vp.y >> 1, vp.z >> 1)
			if not _vox_cells.has(c):
				_vox_cells[c] = []
			var val = vox_blueprint[vp]
			(_vox_cells[c] as Array).append([vp, val[0], val[1]] if val is Array else [vp, val])
		blueprint.clear()
		var keys := _vox_cells.keys()
		keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.y < b.y if a.y != b.y else a.x + a.z < b.x + b.z)
		for c in keys:
			blueprint.append([c, int(_vox_cells[c][0][1]), 0])
	global_position = world.voxel_top(pad_cell + Vector3i.DOWN)
	if site_id != "" and SaveGame.flag("rb_" + site_id):
		_place_all()
		return
	_build_ghost()
	_build_pad()

## 读档 / 测试：直接放好
func _place_all() -> void:
	done = true
	_clear(false)
	if not _vox_cells.is_empty():
		for vp in vox_blueprint:
			var val = vox_blueprint[vp]
			if val is Array:
				world.vset_ramp(vp, int(val[0]), int(val[1]))
			else:
				world.vset(vp, int(val))
	else:
		for b in blueprint:
			_put(b)
	rebuilt.emit.call_deferred()

func _put(b: Array) -> void:
	var shape: int = b[2] if b.size() > 2 else 0
	if shape != 0:
		world.set_ramp(b[0], b[1], shape)
	else:
		world.set_block(b[0], b[1])

func _clear(fx: bool) -> void:
	if clear_b.x < clear_a.x:
		return
	for z in range(clear_a.z, clear_b.z + 1):
		for y in range(clear_a.y, clear_b.y + 1):
			for x in range(clear_a.x, clear_b.x + 1):
				var c := Vector3i(x, y, z)
				if world.get_block(c) == Blocks.AIR:
					continue
				if fx:
					world.break_fx_at(world.voxel_center(c), world.get_block(c), false)
				world.set_block(c, Blocks.AIR)

func _build_ghost() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * VoxelWorld.CELL_M * 0.92
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ghost_mat.albedo_color = Color(0.3, 0.85, 1.0, 0.24)
	_ghost_mat.no_depth_test = false
	bm.material = _ghost_mat
	mm.mesh = bm
	var list: Array = []
	for b in blueprint:
		if world.get_block(b[0]) == Blocks.AIR or _vox_cells.has(b[0]):
			list.append(b[0])
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, Transform3D(Basis(), world.voxel_center(list[i])))
	_ghost = MultiMeshInstance3D.new()
	_ghost.multimesh = mm
	_ghost.top_level = true
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)
	_ghost.global_transform = Transform3D.IDENTITY

func _build_pad() -> void:
	_pad = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.9
	cm.bottom_radius = 0.9
	cm.height = 0.06
	cm.radial_segments = 32
	_pad.mesh = cm
	_pad_mat = StandardMaterial3D.new()
	_pad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pad_mat.albedo_color = Color(0.4, 0.9, 1.0, 0.5)
	_pad.material_override = _pad_mat
	_pad.position.y = 0.04
	add_child(_pad)
	_label = Label3D.new()
	_label.font = UIKit.font(true)
	_label.font_size = 56
	_label.outline_size = 12
	_label.outline_modulate = Color("0b2a44")
	_label.modulate = Color("c8f4ff")
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.006
	_label.position.y = 1.8
	add_child(_label)
	_refresh_label()

func _refresh_label() -> void:
	if _label:
		_label.text = "重构 · %s\n◆ %d / %d" % [title, mini(GameState.matter, cost), cost]
		_label.modulate = Color("9dffcf") if GameState.matter >= cost else Color("c8f4ff")

func _process(delta: float) -> void:
	if done:
		return
	_t += delta
	_warn_t -= delta
	_ghost_mat.albedo_color.a = 0.2 + 0.08 * sin(_t * 2.2)
	_pad_mat.albedo_color.a = 0.35 + 0.2 * sin(_t * 4.0)
	if GameState.matter != _shown_matter:
		_shown_matter = GameState.matter
		_refresh_label()
	var p := GameState.player as MorphBall
	if p == null:
		return
	var d := p.global_position - global_position
	if not _told and d.length() < 8.0:
		_told = true
		GameState.say("地上那片发光的格子，是一座被毁掉的%s的蓝图。拆东西会攒下“重构物质”（左上角的小方块），够了就滚进光圈——把它重建起来！" % title)
	if Vector2(d.x, d.z).length() < 1.1 and absf(d.y) < 1.4:
		if GameState.matter >= cost:
			build(p.global_position)
		elif _warn_t <= 0.0:
			_warn_t = 3.0
			FloatText.spawn(get_parent(), global_position + Vector3.UP * 1.2, "物质不够（%d / %d）——去拆点东西！" % [GameState.matter, cost], Color("ffd166"), 40, 1.6)
			Sfx.play("ui_back", global_position, -6.0, 0.0)

func build(from: Vector3) -> void:
	if done:
		return
	done = true
	GameState.add_matter(-cost)
	if site_id != "":
		SaveGame.set_flag("rb_" + site_id)
	_label.visible = false
	var tw := create_tween()
	tw.tween_property(_pad_mat, "albedo_color:a", 0.0, 0.6)
	Sfx.play("energy", global_position, 0.0, 0.0, 0.8)
	GameState.shake.emit(0.15)
	_clear(true)
	var rb := VoxelRebuilder.new()
	rb.world = world
	rb.pitch_base = 0.8
	add_child(rb)
	var n := blueprint.size()
	var step := minf(0.045, 3.2 / maxf(1.0, float(n)))
	var i := 0
	for b in blueprint:
		var c: Vector3i = b[0]
		if _vox_cells.has(c):
			rb.add(_vox_cells[c], world.voxel_center(c), from + Vector3.UP * 0.4, i * step, 0.55)
		else:
			rb.add_cell(c, int(b[1]), int(b[2]) if b.size() > 2 else 0, world.voxel_center(c), from + Vector3.UP * 0.4, i * step, 0.55)
		i += 1
	rb.finished.connect(func() -> void:
		if is_instance_valid(_ghost):
			_ghost.queue_free()
		Sfx.play("rebuild_done", Vector3.INF, -3.0, 0.0)
		GameState.shake.emit(0.25)
		FloatText.spawn(get_parent(), global_position + Vector3.UP * 2.0, "重构完成！", Color("9dffcf"), 60, 1.6)
		rebuilt.emit())
	# 蓝图随建造进度渐隐
	var tw2 := create_tween()
	tw2.tween_property(_ghost_mat, "albedo_color:a", 0.0, n * step + 0.6)

# ================================================================ 蓝图

## 螺旋瞭望台：4×4 的塔芯，外面绕一圈 3 格宽的坡道（外侧一列矮墙）（每边 4 格坡道升 2 格，拐角是平台），顶上是塔芯平台。
## base：塔芯西北角的地面格（第一层空气）；h：塔高（格，取偶数）。返回 [蓝图, 平台中心格]
## 蓝图每项 [格, 方块, 形状]（形状 0 = 立方体，其余见 VoxelWorld.SHAPE_HEIGHTS）
static func tower(base: Vector3i, h := 12) -> Array:
	var bp: Array = []
	for y in h:
		for dz in 4:
			for dx in 4:
				var edge := dx == 0 or dx == 3 or dz == 0 or dz == 3
				bp.append([base + Vector3i(dx, y, dz), Blocks.CRYSTAL if (y % 4 == 3 and edge) else Blocks.HULL, 0])
	# 坡道：3 格宽，最外一列是矮墙（防止滚下去），里面两列是坡。北边往 +x、东边往 +z、南边往 -x、西边往 -z
	# 每边：[外侧起点格, 前进方向, 由外向内的方向, 两种坡形（下半格、上半格）]
	var sides := [
		[Vector2i(0, -3), Vector2i(1, 0), Vector2i(0, 1), 1, 5],
		[Vector2i(6, 0), Vector2i(0, 1), Vector2i(-1, 0), 3, 7],
		[Vector2i(3, 6), Vector2i(-1, 0), Vector2i(0, -1), 2, 6],
		[Vector2i(-3, 3), Vector2i(0, -1), Vector2i(1, 0), 4, 8],
	]
	var corners := [Vector2i(-3, -3), Vector2i(4, -3), Vector2i(4, 4), Vector2i(-3, 4)]
	var f := 0           ## 当前站立高度（相对 base.y）
	var k := 0
	while f < h:
		var sd: Array = sides[k % 4]
		var o: Vector2i = sd[0]
		var fw: Vector2i = sd[1]
		var sw: Vector2i = sd[2]
		for i in 4:
			var y := f + i / 2
			var shape: int = sd[3] if i % 2 == 0 else sd[4]
			for w in 3:
				var xz: Vector2i = o + fw * i + sw * w
				if y > 0:
					bp.append([base + Vector3i(xz.x, y - 1, xz.y), Blocks.HULL_DARK, 0])
				if w == 0:
					# 矮墙
					bp.append([base + Vector3i(xz.x, y, xz.y), Blocks.HULL, 0])
					bp.append([base + Vector3i(xz.x, y + 1, xz.y), Blocks.HULL if i % 2 else Blocks.LAMP, 0])
				else:
					bp.append([base + Vector3i(xz.x, y, xz.y), Blocks.TILE, shape])
		f += 2
		# 拐角平台（3×3，外侧两边有矮墙）
		var cn: Vector2i = corners[(k + 1) % 4]
		var ox := cn.x if cn.x < 0 else cn.x + 2
		var oz := cn.y if cn.y < 0 else cn.y + 2
		for dz in 3:
			for dx in 3:
				var x := cn.x + dx
				var z := cn.y + dz
				bp.append([base + Vector3i(x, f - 1, z), Blocks.TILE, 0])
				if x == ox or z == oz:
					bp.append([base + Vector3i(x, f, z), Blocks.LAMP if (x == ox and z == oz) else Blocks.HULL, 0])
		k += 1
	# 塔顶：四角的灯
	for c in [Vector2i(0, 0), Vector2i(3, 0), Vector2i(0, 3), Vector2i(3, 3)]:
		bp.append([base + Vector3i(c.x, h, c.y), Blocks.LAMP, 0])
	return [bp, base + Vector3i(1, h, 1)]

## 直桥：从 a 到 b（同一高度的两格，a/b 是桥面格），宽 w（两侧各一格是栏杆，中间 w-2 格能走）
static func bridge(a: Vector3i, b: Vector3i, w := 5) -> Array:
	var bp: Array = []
	var d := b - a
	var n := maxi(absi(d.x), absi(d.z))
	var along_x := absi(d.x) >= absi(d.z)
	for i in n + 1:
		var t := float(i) / maxf(1.0, float(n))
		var c := Vector3i(roundi(a.x + d.x * t), a.y + roundi(d.y * t), roundi(a.z + d.z * t))
		for s in range(-(w / 2), w - w / 2):
			var cc := c + (Vector3i(0, 0, s) if along_x else Vector3i(s, 0, 0))
			bp.append([cc, Blocks.TILE if i % 5 else Blocks.HULL, 0])
		if i % 3 == 0:
			var e1 := c + (Vector3i(0, 1, -(w / 2)) if along_x else Vector3i(-(w / 2), 1, 0))
			var e2 := c + (Vector3i(0, 1, w - w / 2 - 1) if along_x else Vector3i(w - w / 2 - 1, 1, 0))
			bp.append([e1, Blocks.LAMP if i % 6 == 0 else Blocks.HULL, 0])
			bp.append([e2, Blocks.LAMP if i % 6 == 0 else Blocks.HULL, 0])
	return [bp, b]
