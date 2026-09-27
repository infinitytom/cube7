class_name Blocks
extends RefCounted
## 方块类型表。所有数值都在这里调：颜色、谁能破坏、掉落什么。

enum {
	AIR, BEDROCK, GRASS, DIRT, SAND, GLASS, ROCK, ORE, METAL, CRYSTAL,
	CRATE, CRATE_ITEM, DOOR, SOURCE, RECEIVER, RECEIVER_ON, GATE, TILE, TRACK, GOAL, PLATE,
	COUNT,
}

enum Render { NONE, OPAQUE, GLASS, GLOW }

## impact：撞击破坏所需的最低速度（m/s），< 0 表示撞不碎
## drill：钻头能否破坏
## coins / energy：破坏后自动吸入的掉落
## item：破坏后留在场上的“可用物件”（只有它会保留）
const DEFS := {
	BEDROCK: {"name": "外星合金", "color": Color("343a52"), "render": Render.OPAQUE},
	GRASS: {"name": "草地", "color": Color("6cc24a"), "drill": true},
	DIRT: {"name": "泥土", "color": Color("9a6b45"), "drill": true},
	SAND: {"name": "砂", "color": Color("e8cf8a"), "impact": 2.5, "drill": true, "falls": true},
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
}

static var colors := PackedColorArray()
static var render := PackedByteArray()
static var impact := PackedFloat32Array()
static var drill := PackedByteArray()
static var conductive := PackedByteArray()
static var falls := PackedByteArray()

static func _static_init() -> void:
	colors.resize(COUNT)
	render.resize(COUNT)
	impact.resize(COUNT)
	drill.resize(COUNT)
	conductive.resize(COUNT)
	falls.resize(COUNT)
	for t in COUNT:
		var d: Dictionary = DEFS.get(t, {})
		colors[t] = d.get("color", Color.MAGENTA)
		render[t] = Render.NONE if t == AIR else int(d.get("render", Render.OPAQUE))
		impact[t] = float(d.get("impact", -1.0))
		drill[t] = 1 if d.get("drill", false) else 0
		conductive[t] = 1 if d.get("conductive", false) else 0
		falls[t] = 1 if d.get("falls", false) else 0

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
