class_name Blocks
extends RefCounted
## 方块类型表。所有数值都在这里调：颜色、谁能破坏、掉落什么。

enum {
	AIR, BEDROCK, GRASS, DIRT, SAND, GLASS, ROCK, ORE, METAL, CRYSTAL,
	CRATE, CRATE_ITEM, DOOR, SOURCE, RECEIVER, RECEIVER_ON, GATE, TILE, TRACK, GOAL, PLATE,
	WOOD, LEAVES, GEODE, HULL, CLIFF, PAVING, MOSS, LAMP, HULL_DARK, LOOSE, SUPPORT,
	COUNT,
}

enum Render { NONE, OPAQUE, GLASS, GLOW }

## impact：撞击破坏所需的最低速度（m/s），< 0 表示撞不碎
## drill：钻头能否破坏
## coins / energy：破坏后自动吸入的掉落
## item：破坏后留在场上的“可用物件”（只有它会保留）
const DEFS := {
	BEDROCK: {"name": "外星合金", "color": Color("343a52"), "render": Render.OPAQUE},
	GRASS: {"name": "草地", "color": Color("78d24f"), "drill": true},
	DIRT: {"name": "泥土", "color": Color("b07a4f"), "drill": true},
	SAND: {"name": "砂", "color": Color("e8cf8a"), "impact": 2.5, "drill": true, "falls": true, "soft": true},
	GLASS: {"name": "玻璃", "color": Color("9fe8ff"), "impact": 7.5, "drill": true, "render": Render.GLASS},
	ROCK: {"name": "岩石", "color": Color("b3a58c"), "drill": true},
	ORE: {"name": "金矿", "color": Color("c9a23a"), "drill": true, "coins": 5},
	METAL: {"name": "金属", "color": Color("b8c4d6"), "conductive": true},
	CRYSTAL: {"name": "能量水晶", "color": Color("46e0ff"), "render": Render.GLOW, "conductive": true},
	CRATE: {"name": "补给箱", "color": Color("d9893b"), "impact": 2.0, "drill": true, "coins": 1, "energy": 1},
	CRATE_ITEM: {"name": "物资箱", "color": Color("4fa8ff"), "impact": 2.0, "drill": true, "coins": 1, "item": "crystal"},
	DOOR: {"name": "能量门", "color": Color("ff6b8a"), "render": Render.GLOW},
	SOURCE: {"name": "能量源", "color": Color("ffe066"), "render": Render.GLOW, "conductive": true},
	RECEIVER: {"name": "接收器（未通电）", "color": Color("5a6178"), "conductive": true},
	RECEIVER_ON: {"name": "接收器（已通电）", "color": Color("7dffb0"), "render": Render.GLOW, "conductive": true},
	GATE: {"name": "压力闸门", "color": Color("ffaa3b"), "render": Render.GLOW},
	TILE: {"name": "实验室地砖", "color": Color("d7dce6")},
	TRACK: {"name": "平衡轨道", "color": Color("c98f5a")},
	GOAL: {"name": "终点信标", "color": Color("ffd84d"), "render": Render.GLOW},
	PLATE: {"name": "压力板", "color": Color("ff9f43")},
	WOOD: {"name": "木头", "color": Color("8a5a3c"), "drill": true},
	LEAVES: {"name": "树叶", "color": Color("58b84c"), "impact": 1.5, "drill": true},
	GEODE: {"name": "晶洞", "color": Color("7d6f9e"), "drill": true, "item": "crystal", "energy": 2},
	HULL: {"name": "飞船外壳", "color": Color("e9edf5")},
	CLIFF: {"name": "悬崖岩", "color": Color("9a8574")},
	PAVING: {"name": "铺路石", "color": Color("e3d9c6")},
	MOSS: {"name": "苔石", "color": Color("7f9a6a")},
	LAMP: {"name": "灯", "color": Color("ffe9a8"), "render": Render.GLOW},
	HULL_DARK: {"name": "飞船舱体", "color": Color("5b6784")},
	LOOSE: {"name": "松土", "color": Color("7a5236"), "drill": true, "soft": true},
	SUPPORT: {"name": "支撑木架", "color": Color("f2994a"), "impact": 2.0, "drill": true, "chain": true, "coins": 1},
}

static var colors := PackedColorArray()
static var render := PackedByteArray()
static var impact := PackedFloat32Array()
static var drill := PackedByteArray()
static var conductive := PackedByteArray()
static var falls := PackedByteArray()
static var soft := PackedByteArray()     ## 钻头能往下钻的方块（避免把自己困在坑里）
static var chain := PackedByteArray()    ## 连锁崩塌：一块被破坏，相连的同类方块依次崩塌

static func _static_init() -> void:
	colors.resize(COUNT)
	render.resize(COUNT)
	impact.resize(COUNT)
	drill.resize(COUNT)
	conductive.resize(COUNT)
	falls.resize(COUNT)
	soft.resize(COUNT)
	chain.resize(COUNT)
	for t in COUNT:
		var d: Dictionary = DEFS.get(t, {})
		colors[t] = d.get("color", Color.MAGENTA)
		render[t] = 0 if t == AIR else int(d.get("render", 1))
		impact[t] = float(d.get("impact", -1.0))
		drill[t] = 1 if d.get("drill", false) else 0
		conductive[t] = 1 if d.get("conductive", false) else 0
		falls[t] = 1 if d.get("falls", false) else 0
		soft[t] = 1 if d.get("soft", false) else 0
		chain[t] = 1 if d.get("chain", false) else 0

static func def(t: int) -> Dictionary:
	return DEFS.get(t, {})

## 用某种方式、以某个力度能否破坏该方块
static func can_break(t: int, tool: String, power: float) -> bool:
	if t == AIR:
		return false
	if tool == "drill":
		return drill[t] == 1
	if tool == "impact":
		return impact[t] >= 0.0 and power >= impact[t]
	return false
