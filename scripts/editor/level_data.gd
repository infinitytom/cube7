class_name LevelData
extends RefCounted
## 关卡编辑器的数据：方块（稀疏字典）+ 物件列表。存成 JSON；分享码 = gzip 压缩的 JSON 转 base64，前缀 CUBE7:
## 坐标单位：格（0.5 米）。

const SIZE := Vector3i(72, 48, 72)
const BASE_Y := 10                   ## 初始地面高度（第一层空气）
const DIR := "user://levels"

## 方块调色板：[方块, 名称]
const BLOCKS := [
	[Blocks.GRASS, "草地"], [Blocks.DIRT, "泥土"], [Blocks.SAND, "砂（会塌）"], [Blocks.ROCK, "岩石"], [Blocks.CLIFF, "崖壁"],
	[Blocks.TILE, "地砖"], [Blocks.PAVING, "铺路石"], [Blocks.HULL, "白色外壳"], [Blocks.HULL_DARK, "深色外壳"], [Blocks.METAL, "金属"],
	[Blocks.GLASS, "玻璃"], [Blocks.CRYSTAL, "能量水晶"], [Blocks.LAMP, "灯"], [Blocks.WOOD, "木头"], [Blocks.LEAVES, "树叶"],
	[Blocks.BLOSSOM, "花冠"], [Blocks.PLANK, "木板"], [Blocks.CRATE, "补给箱"], [Blocks.ORE, "金矿"], [Blocks.LOOSE, "松土"],
	[Blocks.RUST, "锈铁"], [Blocks.REINFORCED, "加固墙"], [Blocks.CRUMBLE, "碎裂石板"], [Blocks.GEM_CHAIN, "共鸣晶簇"], [Blocks.BARREL, "燃料桶"],
	[Blocks.SCAFFOLD, "木脚手架"], [Blocks.MOSS, "苔石"], [Blocks.RUSTDUNE, "锈砂丘"],
]

## 物件调色板：[id, 名称, 颜色]（颜色用在编辑器里的标记上）
const OBJECTS := [
	["spawn", "出生点", Color("46c3ff")],
	["goal", "终点", Color("ffd84d")],
	["checkpoint", "检查点", Color("7dffc0")],
	["coin", "金币", Color("ffc93d")],
	["coin_ring", "一圈金币", Color("ffc93d")],
	["chest", "宝箱", Color("d9a066")],
	["seed", "噗噗种子方块", Color("7dffc8")],
	["bounce", "弹跳垫", Color("ff7ab8")],
	["fan", "上升气流", Color("bfefff")],
	["scrapling", "锈块兽", Color("b5653e")],
	["rustfly", "锈蜂", Color("e08a4a")],
	["spikeshell", "刺壳", Color("8a6a5a")],
	["sentinel", "锈哨兵", Color("e9edf2")],
	["mortar", "锈炮台", Color("6c7385")],
	["burrower", "钻地鼹", Color("9a6a48")],
]

var name := "我的关卡"
var blocks := {}          ## Vector3i -> 方块类型
var objects: Array = []   ## [{"id": String, "cell": Vector3i, "yaw": float}]

static func new_default() -> LevelData:
	var d := LevelData.new()
	for z in range(16, 56):
		for x in range(16, 56):
			d.blocks[Vector3i(x, BASE_Y - 1, z)] = Blocks.GRASS
			d.blocks[Vector3i(x, BASE_Y - 2, z)] = Blocks.DIRT
			d.blocks[Vector3i(x, BASE_Y - 3, z)] = Blocks.CLIFF
	d.objects.append({"id": "spawn", "cell": Vector3i(24, BASE_Y, 36), "yaw": 0.0})
	d.objects.append({"id": "goal", "cell": Vector3i(48, BASE_Y, 36), "yaw": 0.0})
	return d

func find_object(id: String) -> int:
	for i in objects.size():
		if objects[i].id == id:
			return i
	return -1

func object_at(cell: Vector3i) -> int:
	for i in objects.size():
		if objects[i].cell == cell:
			return i
	return -1

# ================================================================ 存取

func to_dict() -> Dictionary:
	# 方块按行程编码压缩：同一行（x 方向）连续的同种方块记成一段
	var rows := {}
	for c: Vector3i in blocks:
		var key := "%d,%d" % [c.y, c.z]
		if not rows.has(key):
			rows[key] = []
		(rows[key] as Array).append([c.x, blocks[c]])
	var runs: Array = []
	for key: String in rows:
		var list: Array = rows[key]
		list.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var yz := key.split(",")
		var i := 0
		while i < list.size():
			var x0: int = list[i][0]
			var t: int = list[i][1]
			var n := 1
			while i + n < list.size() and list[i + n][0] == x0 + n and list[i + n][1] == t:
				n += 1
			runs.append([x0, int(yz[0]), int(yz[1]), n, t])
			i += n
	var objs: Array = []
	for o in objects:
		objs.append([o.id, o.cell.x, o.cell.y, o.cell.z, snappedf(float(o.get("yaw", 0.0)), 0.01)])
	return {"v": 1, "name": name, "runs": runs, "objs": objs}

static func from_dict(d: Dictionary) -> LevelData:
	var ld := LevelData.new()
	ld.name = str(d.get("name", "未命名关卡"))
	for r in d.get("runs", []):
		for k in int(r[3]):
			var c := Vector3i(int(r[0]) + k, int(r[1]), int(r[2]))
			if c.x >= 0 and c.y >= 0 and c.z >= 0 and c.x < SIZE.x and c.y < SIZE.y and c.z < SIZE.z:
				ld.blocks[c] = clampi(int(r[4]), 1, Blocks.COUNT - 1)
	for o in d.get("objs", []):
		ld.objects.append({"id": str(o[0]), "cell": Vector3i(int(o[1]), int(o[2]), int(o[3])), "yaw": float(o[4]) if o.size() > 4 else 0.0})
	return ld

func share_code() -> String:
	var bytes := JSON.stringify(to_dict()).to_utf8_buffer()
	var z := bytes.compress(FileAccess.COMPRESSION_GZIP)
	return "CUBE7:%d:%s" % [bytes.size(), Marshalls.raw_to_base64(z)]

static func from_share_code(code: String) -> LevelData:
	code = code.strip_edges()
	if not code.begins_with("CUBE7:"):
		return null
	var parts := code.split(":", false, 2)
	if parts.size() < 3:
		return null
	var raw := Marshalls.base64_to_raw(parts[2])
	var bytes := raw.decompress(int(parts[1]), FileAccess.COMPRESSION_GZIP)
	if bytes.is_empty():
		return null
	var d = JSON.parse_string(bytes.get_string_from_utf8())
	if not (d is Dictionary):
		return null
	return from_dict(d)

static func slot_path(i: int) -> String:
	return "%s/level_%d.json" % [DIR, i]

func save_slot(i: int) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(slot_path(i), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict()))
	return true

static func load_slot(i: int) -> LevelData:
	if not FileAccess.file_exists(slot_path(i)):
		return null
	var d = JSON.parse_string(FileAccess.get_file_as_string(slot_path(i)))
	return from_dict(d) if d is Dictionary else null

static func slot_name(i: int) -> String:
	if not FileAccess.file_exists(slot_path(i)):
		return ""
	var d = JSON.parse_string(FileAccess.get_file_as_string(slot_path(i)))
	return str(d.get("name", "未命名")) if d is Dictionary else ""
