class_name TerrainPalette
extends RefCounted
## 平滑地形的材质槽位（Voxel Tools 的 Transvoxel 最多 16 种材质混合）。
## 每种走平滑网格的方块对应一个槽位；着色器按槽位取颜色和“类别”（草、树冠、砂、打不坏）。

## 槽位顺序 = 着色器里的 slot 序号
const SLOTS := [
	Blocks.GRASS, Blocks.DIRT, Blocks.SAND, Blocks.ROCK, Blocks.ORE, Blocks.LEAVES, Blocks.GEODE, Blocks.CLIFF,
	Blocks.CLIFF_B, Blocks.CLIFF_C, Blocks.MOSS, Blocks.PINE, Blocks.BLOSSOM, Blocks.DARKROCK, Blocks.RUSTDUNE, Blocks.RUSTROCK,
]
## 颜色几乎一样的方块共用槽位
const ALIAS := {Blocks.LOOSE: Blocks.DIRT, Blocks.DARKROCK_B: Blocks.DARKROCK}

static var _slot := PackedByteArray()
static var _mat: ShaderMaterial

## 方块类型 → 槽位（不是平滑材质时返回 0）
static func table() -> PackedByteArray:
	if _slot.is_empty():
		_slot.resize(256)
		for i in SLOTS.size():
			_slot[SLOTS[i]] = i
		for a in ALIAS:
			_slot[a] = SLOTS.find(ALIAS[a])
	return _slot

static func slot_of(t: int) -> int:
	return table()[t]

## 所有平滑地形共用的材质
static func material() -> ShaderMaterial:
	if _mat != null:
		return _mat
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/voxel_terrain.gdshader")
	var cols := PackedVector3Array()
	var fam := PackedVector4Array()
	var spark := PackedFloat32Array()
	for t: int in SLOTS:
		var c := Blocks.colors[t].srgb_to_linear()
		cols.append(Vector3(c.r, c.g, c.b))
		var grass := 1.0 if t in [Blocks.GRASS, Blocks.MOSS] else 0.0
		var foliage := 1.0 if t in [Blocks.LEAVES, Blocks.PINE, Blocks.BLOSSOM] else 0.0
		var sand := 1.0 if t in [Blocks.SAND, Blocks.RUSTDUNE] else 0.0
		var hard := 1.0 if Blocks.impact[t] < 0.0 and Blocks.drill[t] == 0 else 0.0
		fam.append(Vector4(grass, foliage, sand, hard))
		spark.append(1.0 if t in [Blocks.ORE, Blocks.GEODE] else 0.0)
	_mat.set_shader_parameter("slot_colors", cols)
	_mat.set_shader_parameter("slot_fam", fam)
	_mat.set_shader_parameter("slot_spark", spark)
	return _mat

## 单一材质（权重 255）的 CUSTOM1 两个浮点数（按位打包）
static func packed_single(slot: int) -> Vector2:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_u32(0, slot)
	b.encode_u32(4, 255)
	return Vector2(b.decode_float(0), b.decode_float(4))
