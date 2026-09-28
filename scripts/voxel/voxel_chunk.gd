class_name VoxelChunk
extends RigidBody3D
## 断开的体素碎块：破坏后和地面失去连接的一团方块，会整块掉落、翻滚，
## 落地（或 1.6 秒后）再碎成小方块并吐出掉落物——体素世界的“真实感”。
## 体素很细（0.25 米），一团可能有几百个：网格合并成一个，碰撞按“格”（0.5 米）合并成盒子。

const LIFETIME := 1.6
const SETTLE_MIN := 24   ## 至少这么多体素的碎块落地后会固定下来

var world: VoxelWorld
var blocks: Array = []        # [[本地坐标 Vector3, 方块类型 int], ...]
var _age := 0.0
var _done := false
static var _mat: StandardMaterial3D

func _ready() -> void:
	collision_layer = 32
	collision_mask = 1
	contact_monitor = true
	max_contacts_reported = 4
	gravity_scale = 1.3
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.roughness = 0.85
	var V := VoxelWorld.VOXEL
	var occupied := {}
	for b in blocks:
		occupied[Vector3i((b[0] / V).round())] = true
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cells := {}
	for b in blocks:
		var lp: Vector3 = b[0]
		var key := Vector3i((lp / V).round())
		var col: Color = Blocks.colors[b[1]]
		for f in 6:
			var n: Vector3i = VoxelWorld.DIRS[f]
			if occupied.has(key + n):
				continue
			_face(st, lp, Vector3(n), V * 0.5, col * (0.8 + 0.2 * Vector3(n).dot(Vector3(0.3, 0.9, 0.3))))
		# 碰撞按 0.5 米的格合并
		cells[Vector3i((lp / VoxelWorld.CELL_M).floor())] = true
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat
	add_child(mi)
	var shape_box := BoxShape3D.new()
	shape_box.size = Vector3.ONE * VoxelWorld.CELL_M * 0.92
	for c in cells:
		var cs := CollisionShape3D.new()
		cs.shape = shape_box
		cs.position = (Vector3(c) + Vector3.ONE * 0.5) * VoxelWorld.CELL_M
		add_child(cs)
	mass = maxf(0.05 * blocks.size(), 0.5)

func _face(st: SurfaceTool, c: Vector3, n: Vector3, h: float, col: Color) -> void:
	var u := Vector3(n.y, n.z, n.x)
	var v := n.cross(u)
	var q := [c + (n - u - v) * h, c + (n + u - v) * h, c + (n + u + v) * h, c + (n - u + v) * h]
	st.set_color(col)
	st.set_normal(n)
	# 顺序按法线自动调整为正面
	var a: Vector3 = q[0]
	var b: Vector3 = q[1]
	var cc: Vector3 = q[2]
	var tri := [0, 1, 2, 0, 2, 3] if (b - a).cross(cc - a).dot(n) < 0.0 else [0, 2, 1, 0, 3, 2]
	for k in tri:
		st.add_vertex(q[k])

func _physics_process(delta: float) -> void:
	_age += delta
	if _done:
		return
	# 大块的结构（比如烧断支撑后塌下来的木桥）落地后“重新长回”体素世界，可以当新的路走；
	# 小碎块落地（或超时）就碎掉
	var landed := _age > 0.35 and get_contact_count() > 0 and linear_velocity.length() < 2.5
	if landed and blocks.size() >= SETTLE_MIN:
		settle()
	elif _age > (LIFETIME * 2.5 if blocks.size() >= SETTLE_MIN else LIFETIME) or (landed and blocks.size() < SETTLE_MIN):
		crumble()

func settle() -> void:
	if _done or world == null:
		return
	_done = true
	var placed := 0
	var k := 0
	for b in blocks:
		var p := world.to_v(to_global(b[0]))
		if b[1] == Blocks.FIRE:
			pass
		elif world.vget(p) == Blocks.AIR:
			world.vset(p, b[1])
			placed += 1
		elif k % 5 == 0:
			world.break_fx_at(to_global(b[0]), b[1], false)
		k += 1
	GameState.shake.emit(minf(0.1 + placed * 0.002, 0.4))
	Sfx.play("impact_big", global_position, -8.0, 0.1, 1.4)
	queue_free()

func crumble() -> void:
	if _done:
		return
	_done = true
	# 每 0.5 米的格只结算一次掉落，碎屑也只取一部分
	var seen := {}
	var k := 0
	for b in blocks:
		var cell := Vector3i((b[0] / VoxelWorld.CELL_M).floor())
		var first := not seen.has(cell)
		seen[cell] = true
		if world and (first or k % 6 == 0):
			world.break_fx_at(to_global(b[0]), b[1], first)
		k += 1
	queue_free()
