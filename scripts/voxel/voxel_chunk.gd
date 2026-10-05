class_name VoxelChunk
extends RigidBody3D
## 断开的体素碎块：破坏后和地面失去连接的一团方块，会整块掉落、翻滚，
## 落地（或 1.6 秒后）再碎成小方块并吐出掉落物——体素世界的“真实感”。
## 体素很细（0.25 米），一团可能有几百个：网格合并成一个，碰撞按“格”（0.5 米）合并成盒子。

const LIFETIME := 1.6
const SETTLE_MIN := 24   ## 至少这么多体素的碎块落地后会固定下来
const MAX_ALIVE := 14    ## 同时存在的碎块上限（再多就直接碎成粒子）

static var alive := 0

var world: VoxelWorld
var blocks: Array = []        # [[本地坐标 Vector3, 方块类型 int], ...]
var spawn_origin := Vector3.ZERO   ## 生成时的中心（世界体素空间里的位置，用来对齐碰撞盒）
## 撞击崩飞的裂块：掉落已经结算过，落地只碎成碎屑，不会长回地形
var fragment := false
var _age := 0.0
var _done := false
static var _mat: StandardMaterial3D

func _enter_tree() -> void:
	alive += 1

func _exit_tree() -> void:
	alive -= 1

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
	var n_smooth := 0
	for b in blocks:
		occupied[Vector3i((b[0] / V).round())] = true
		if Blocks.smooth[b[1]] == 1:
			n_smooth += 1
	var mi := MeshInstance3D.new()
	# 自然材质（岩、土）的碎块用平滑网格——看起来像一块石头，而不是一摞小方块
	if n_smooth * 2 >= blocks.size():
		mi.mesh = _smooth_mesh(occupied)
	else:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for b in blocks:
			var lp: Vector3 = b[0]
			var key := Vector3i((lp / V).round())
			var col: Color = Blocks.colors[b[1]]
			for f in 6:
				var n: Vector3i = VoxelWorld.DIRS[f]
				if occupied.has(key + n):
					continue
				_face(st, lp, Vector3(n), V * 0.5, col * (0.8 + 0.2 * Vector3(n).dot(Vector3(0.3, 0.9, 0.3))))
		mi.mesh = st.commit()
		mi.material_override = _mat
	add_child(mi)
	if blocks.size() < 6:
		# 很小的碎块：球形碰撞（凸包点太少会退化）
		var sp := SphereShape3D.new()
		sp.radius = V * (0.6 + 0.15 * blocks.size())
		var cs0 := CollisionShape3D.new()
		cs0.shape = sp
		add_child(cs0)
	elif fragment or blocks.size() < 40:
		# 小碎块：凸包碰撞，会像石头一样滚
		var pts := PackedVector3Array()
		for b in blocks:
			pts.append(b[0])
		var hull := ConvexPolygonShape3D.new()
		hull.points = pts
		hull.margin = 0.03
		var cs := CollisionShape3D.new()
		cs.shape = hull
		add_child(cs)
	else:
		# 大块（桥板、墙）：碰撞按 0.5 米的格合并（按世界网格对齐，免得盒子伸出体素外面）
		var cells := {}
		for b in blocks:
			var lp: Vector3 = b[0]
			cells[Vector3i(((lp + spawn_origin) / VoxelWorld.CELL_M).floor())] = true
		var shape_box := BoxShape3D.new()
		shape_box.size = Vector3.ONE * VoxelWorld.CELL_M * 0.96
		for c in cells:
			var cs := CollisionShape3D.new()
			cs.shape = shape_box
			cs.position = (Vector3(c) + Vector3.ONE * 0.5) * VoxelWorld.CELL_M - spawn_origin
			add_child(cs)
	mass = maxf(0.05 * blocks.size(), 0.5)

## 碎块的平滑网格：把体素放进一个小数组，交给 TerrainMesher（Voxel Tools / Surface Nets）
func _smooth_mesh(occupied: Dictionary) -> ArrayMesh:
	var V := VoxelWorld.VOXEL
	var lo := Vector3i(1 << 20, 1 << 20, 1 << 20)
	var hi := -lo
	for k: Vector3i in occupied:
		lo = Vector3i(mini(lo.x, k.x), mini(lo.y, k.y), mini(lo.z, k.z))
		hi = Vector3i(maxi(hi.x, k.x), maxi(hi.y, k.y), maxi(hi.z, k.z))
	var dims := hi - lo + Vector3i.ONE
	var types := PackedByteArray()
	types.resize(dims.x * dims.y * dims.z)
	for b in blocks:
		var k := Vector3i(((b[0] as Vector3) / V).round()) - lo
		types[k.x + dims.x * (k.y + dims.y * k.z)] = b[1]
	var mesh := ArrayMesh.new()
	var r := TerrainMesher.build_grid(types, dims)
	if r.is_empty():
		return mesh
	# 下标 k 的体素中心 = (lo + k) * V + 小数偏移（所有体素共享同一个偏移）
	var b0: Vector3 = blocks[0][0]
	var frac := b0 - (b0 / V).round() * V
	TerrainMesher.grid_surface(mesh, r, V, Vector3(lo) * V + frac)
	return mesh

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

## 只有“底下被托住”（接触法线朝上）才算落地；侧面蹭到东西不算
var _floor_contact := false

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	_floor_contact = false
	for i in state.get_contact_count():
		if state.get_contact_local_normal(i).y > 0.6:
			_floor_contact = true
			return

var _crushed := {}

## 砸下来的碎块会压伤敌人：撞塌地形、把岩石崩到敌人头上，都是体素世界里的“武器”
func _crush_enemies() -> void:
	if blocks.size() < 3 or linear_velocity.length() < 3.0:
		return
	var reach := 0.45 + pow(float(blocks.size()), 1.0 / 3.0) * VoxelWorld.VOXEL * 0.6
	for e in get_tree().get_nodes_in_group("enemy"):
		if _crushed.has(e) or not (e is Node3D) or not is_instance_valid(e) or e.get("dead"):
			continue
		if (e as Node3D).global_position.distance_to(global_position) > reach + 0.5:
			continue
		_crushed[e] = true
		if int(e.get("hp") if e.get("hp") != null else 1) <= 3 and e.has_method("take_hit"):
			e.call("take_hit", global_position, "crush")
			if e.has_method("stun") and is_instance_valid(e):
				e.call("stun", 1.5, true)
		elif e.has_method("on_pound"):
			e.call("on_pound", global_position)

func _physics_process(delta: float) -> void:
	_age += delta
	if _done:
		return
	_crush_enemies()
	# 大块的结构（比如烧断支撑后塌下来的木桥）落地后“重新长回”体素世界，可以当新的路走；
	# 小碎块落地（或超时）就碎掉
	var landed := _age > 0.35 and _floor_contact and linear_velocity.length() < 2.5
	# 大块要真正停稳（几乎不动）才固定下来
	if not fragment and landed and blocks.size() >= SETTLE_MIN and linear_velocity.length() < 0.6 and angular_velocity.length() < 0.8:
		settle()
	elif fragment and (_age > 2.2 or (landed and _age > 0.9)):
		crumble()
	elif _age > (LIFETIME * 4.0 if blocks.size() >= SETTLE_MIN else LIFETIME) or (landed and blocks.size() < SETTLE_MIN):
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
			if fragment:
				world._spawn_debris(to_global(b[0]), b[1])
			else:
				world.break_fx_at(to_global(b[0]), b[1], first)
		k += 1
	queue_free()
