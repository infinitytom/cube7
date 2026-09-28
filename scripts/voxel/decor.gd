class_name Decor
extends Node3D
## 地表装饰：草丛与小花（MultiMesh 批量绘制，随风摆动）。
## 下面的方块被破坏时，对应的装饰会隐藏。

var world: VoxelWorld
var _mm := {}           # 名称 -> MultiMeshInstance3D
var _slots := {}        # 体素坐标（装饰所在的地面方块）-> [名称, 下标]
var _pending := {}      # 名称 -> Array[Transform3D]
var _pending_cells := {}

const KINDS := {
	"grass": {"tip": Color("b5d86a"), "base": Color("4f8f3c")},
	"flower_red": {"tip": Color("ff7aa8"), "base": Color("4f8f3c")},
	"flower_yellow": {"tip": Color("ffd769"), "base": Color("4f8f3c")},
	"flower_white": {"tip": Color("fdf6ff"), "base": Color("4f8f3c")},
	"flower_blue": {"tip": Color("9aa8ff"), "base": Color("4f8f3c")},
}

func setup(w: VoxelWorld) -> void:
	world = w
	world.cell_changed.connect(_on_block_changed)

## 在地面方块 cell 的顶上放一个装饰
func add(kind: String, cell: Vector3i, rng: RandomNumberGenerator) -> void:
	var top := world.voxel_top(cell)
	var off := Vector3(rng.randf_range(-0.15, 0.15), 0.0, rng.randf_range(-0.15, 0.15))
	var s := rng.randf_range(0.75, 1.1)
	var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), top + off)
	if not _pending.has(kind):
		_pending[kind] = []
		_pending_cells[kind] = []
	_pending[kind].append(t)
	_pending_cells[kind].append(cell)

func commit() -> void:
	for kind in _pending:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _make_mesh(kind)
		var list: Array = _pending[kind]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			_slots[_pending_cells[kind][i]] = [kind, i]
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_mm[kind] = mmi
	_pending.clear()
	_pending_cells.clear()

func _on_block_changed(p: Vector3i, _o: int, n: int) -> void:
	if n == Blocks.AIR and _slots.has(p):
		var slot: Array = _slots[p]
		_slots.erase(p)
		var mm: MultiMesh = (_mm[slot[0]] as MultiMeshInstance3D).multimesh
		mm.set_instance_transform(slot[1], Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))

func _make_mesh(kind: String) -> ArrayMesh:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grass_tuft.gdshader")
	mat.set_shader_parameter("tip_color", KINDS[kind].tip)
	mat.set_shader_parameter("base_color", KINDS[kind].base)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if kind == "grass":
		# 三片交叉的草叶
		for k in 3:
			var a := k * PI / 3.0
			var d := Vector3(cos(a), 0, sin(a)) * 0.09
			_blade(st, -d, d, 0.2 + 0.05 * k)
	else:
		# 茎 + 花头（四片小花瓣）
		_blade(st, Vector3(-0.015, 0, 0), Vector3(0.015, 0, 0), 0.24)
		for k in 4:
			var a := k * PI / 2.0 + PI / 4.0
			var c := Vector3(cos(a) * 0.05, 0.25, sin(a) * 0.05)
			_petal(st, c, 0.055)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	return mesh

func _blade(st: SurfaceTool, a: Vector3, b: Vector3, h: float) -> void:
	var tip := (a + b) * 0.5 + Vector3(0, h, 0)
	st.set_color(Color.WHITE)
	st.set_uv(Vector2(0, 1)); st.add_vertex(a)
	st.set_uv(Vector2(1, 1)); st.add_vertex(b)
	st.set_uv(Vector2(0.5, 0)); st.add_vertex(tip)

func _petal(st: SurfaceTool, c: Vector3, r: float) -> void:
	st.set_color(Color.WHITE)
	var pts := [c + Vector3(-r, 0, 0), c + Vector3(0, 0, -r), c + Vector3(r, 0, 0), c + Vector3(0, 0, r)]
	for tri in [[0, 1, 2], [0, 2, 3]]:
		for k in tri:
			st.set_uv(Vector2(0.5, 0))
			st.add_vertex(pts[k])
