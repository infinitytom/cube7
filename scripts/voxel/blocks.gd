class_name Blocks
extends RefCounted
## 方块类型表。所有数值都在这里调：颜色、谁能破坏、掉落什么。

enum {
	AIR, BEDROCK, GRASS, DIRT, SAND, GLASS, ROCK, ORE, METAL, CRYSTAL,
	CRATE, CRATE_ITEM, DOOR, SOURCE, RECEIVER, RECEIVER_ON, GATE, TILE, TRACK, GOAL, PLATE,
	WOOD, LEAVES, GEODE, HULL, CLIFF, PAVING, MOSS, LAMP, HULL_DARK, LOOSE, SUPPORT,
	CLIFF_B, CLIFF_C, PINE, BLOSSOM,
	FIRE, EMBER, COPPER, BARREL, REINFORCED, SCAFFOLD, VENT, BRAMBLE,
	PLANK, RUST,
	CRUMBLE, GEM_CHAIN, LENS, DARKROCK, GLOWSHROOM, DARKROCK_B,
	COUNT,
}

enum Render { NONE, OPAQUE, GLASS, GLOW }

## impact：撞击破坏所需的最低速度（m/s），< 0 表示撞不碎
##   地形分三档（v0.9 破坏感）：草/土/苔/木板 ≈ 冲刺就碎；锈铁/铺路石 ≈ 蓄力冲刺才碎；岩石/崖壁/深渊岩/合金 = 地基，撞不碎
## drill：钻头能否破坏
## coins / energy：破坏后自动吸入的掉落
## item：破坏后留在场上的“可用物件”（只有它会保留）
const DEFS := {
	BEDROCK: {"name": "外星合金", "color": Color("4a4f63"), "render": Render.OPAQUE},
	GRASS: {"name": "草地", "color": Color("6cae4f"), "drill": true, "burn": 0.8, "burn_to": DIRT, "catch": 0.08, "impact": 10.5},
	DIRT: {"name": "泥土", "color": Color("8b5e3c"), "drill": true, "impact": 10.5},
	SAND: {"name": "砂", "color": Color("e2c58f"), "impact": 2.5, "drill": true, "falls": true, "soft": true},
	GLASS: {"name": "玻璃", "color": Color("b9e3f5"), "impact": 7.5, "drill": true, "render": Render.GLASS},
	ROCK: {"name": "岩石", "color": Color("8a8f98"), "drill": true},
	ORE: {"name": "金矿", "color": Color("e0ad3a"), "drill": true, "coins": 5, "impact": 10.5},
	METAL: {"name": "金属", "color": Color("a9b2bd"), "conductive": true},
	CRYSTAL: {"name": "能量水晶", "color": Color("6fe3ff"), "render": Render.GLOW, "conductive": true},
	CRATE: {"name": "补给箱", "color": Color("b8773f"), "impact": 2.0, "drill": true, "coins": 1, "energy": 1, "burn": 2.5},
	CRATE_ITEM: {"name": "物资箱", "color": Color("5b7bd6"), "impact": 2.0, "drill": true, "coins": 1, "item": "crystal", "burn": 2.5},
	DOOR: {"name": "能量门", "color": Color("ff7ab8"), "render": Render.GLOW},
	SOURCE: {"name": "能量源", "color": Color("ffd24a"), "render": Render.GLOW, "conductive": true},
	RECEIVER: {"name": "接收器（未通电）", "color": Color("6b7285"), "conductive": true},
	RECEIVER_ON: {"name": "接收器（已通电）", "color": Color("7dffc0"), "render": Render.GLOW, "conductive": true},
	GATE: {"name": "压力闸门", "color": Color("ffb347"), "render": Render.GLOW},
	TILE: {"name": "实验室地砖", "color": Color("d9dce4")},
	TRACK: {"name": "平衡轨道", "color": Color("c98a5e")},
	GOAL: {"name": "终点信标", "color": Color("ffd84d"), "render": Render.GLOW},
	PLATE: {"name": "压力板", "color": Color("e38b3a")},
	WOOD: {"name": "木头", "color": Color("7a4f31"), "drill": true, "burn": 5.0, "catch": 0.5, "impact": 11.0},
	LEAVES: {"name": "树叶", "color": Color("4d9444"), "impact": 1.5, "drill": true, "burn": 1.2},
	GEODE: {"name": "晶洞", "color": Color("8a63d2"), "drill": true, "item": "crystal", "energy": 2, "impact": 10.5},
	HULL: {"name": "飞船外壳", "color": Color("e9edf2")},
	CLIFF: {"name": "悬崖岩", "color": Color("b3896a")},
	PAVING: {"name": "铺路石", "color": Color("cfc6b4"), "impact": 13.0},
	MOSS: {"name": "苔石", "color": Color("6f8f4c"), "impact": 10.5},
	LAMP: {"name": "灯", "color": Color("fff0b0"), "render": Render.GLOW},
	HULL_DARK: {"name": "飞船舱体", "color": Color("3d4659")},
	LOOSE: {"name": "松土", "color": Color("9a6a48"), "drill": true, "soft": true, "impact": 8.0},
	CLIFF_B: {"name": "悬崖岩（深层）", "color": Color("96735a")},
	CLIFF_C: {"name": "悬崖岩（灰层）", "color": Color("7f6f64")},
	PINE: {"name": "松针", "color": Color("2f6e45"), "impact": 1.5, "drill": true, "burn": 1.2},
	BLOSSOM: {"name": "花冠", "color": Color("f0a7bd"), "impact": 1.5, "drill": true, "burn": 1.2},
	FIRE: {"name": "燃烧中", "color": Color("ff8a3d"), "render": Render.GLOW, "impact": 2.0, "drill": true},
	EMBER: {"name": "炭火", "color": Color("ff5a2a"), "render": Render.GLOW, "ignites": true},
	COPPER: {"name": "铜导线", "color": Color("c9814a"), "drill": true, "conductive": true},
	BARREL: {"name": "燃料桶", "color": Color("d9463b"), "impact": 3.0, "drill": true, "burn": 1.4, "explodes": true},
	REINFORCED: {"name": "加固墙", "color": Color("6c7385"), "impact": 16.0},
	SCAFFOLD: {"name": "木脚手架", "color": Color("c89a5b"), "impact": 5.0, "drill": true, "burn": 2.5},
	VENT: {"name": "熔炉口", "color": Color("ffb347"), "render": Render.GLOW, "ignites": true},
	BRAMBLE: {"name": "枯荆棘", "color": Color("6e5646"), "burn": 1.4},
	PLANK: {"name": "木板", "color": Color("d9a066"), "drill": true, "burn": 3.0, "catch": 0.3, "impact": 9.0},
	RUST: {"name": "锈铁", "color": Color("b5653e"), "drill": true, "impact": 12.5},
	CRUMBLE: {"name": "碎裂石板", "color": Color("cdb89c"), "impact": 3.0, "drill": true},
	GEM_CHAIN: {"name": "共鸣晶簇", "color": Color("c08cff"), "render": Render.GLOW, "impact": 3.0, "drill": true, "chain": true, "coins": 1},
	LENS: {"name": "受光晶", "color": Color("7fb8d0")},
	DARKROCK: {"name": "深渊岩", "color": Color("5b5470")},
	DARKROCK_B: {"name": "深渊岩（深层）", "color": Color("4a4560")},
	GLOWSHROOM: {"name": "荧光菇", "color": Color("7dffd8"), "render": Render.GLOW, "impact": 1.5, "drill": true, "energy": 1},
	SUPPORT: {"name": "支撑木架", "color": Color("c8904f"), "impact": 2.0, "drill": true, "chain": true, "coins": 1, "burn": 2.5},
}

static var colors := PackedColorArray()
static var render := PackedByteArray()
static var impact := PackedFloat32Array()
static var drill := PackedByteArray()
static var conductive := PackedByteArray()
static var falls := PackedByteArray()
static var soft := PackedByteArray()     ## 钻头能往下钻的方块（避免把自己困在坑里）
static var chain := PackedByteArray()    ## 连锁崩塌：一块被破坏，相连的同类方块依次崩塌
static var burn := PackedFloat32Array()  ## 可燃：烧多久（秒），0 = 不可燃
static var burn_to := PackedByteArray()  ## 烧完变成什么（默认空气）
static var ignites := PackedByteArray()  ## 会点燃旁边的可燃物（炭火、熔炉口）
static var explodes := PackedByteArray() ## 烧完会爆炸（燃料桶）
static var catch_fire := PackedFloat32Array()  ## 被旁边的火引燃的难易（草地很低，免得一烧一大片）

static func _static_init() -> void:
	colors.resize(COUNT)
	render.resize(COUNT)
	impact.resize(COUNT)
	drill.resize(COUNT)
	conductive.resize(COUNT)
	falls.resize(COUNT)
	soft.resize(COUNT)
	chain.resize(COUNT)
	burn.resize(COUNT)
	burn_to.resize(COUNT)
	ignites.resize(COUNT)
	explodes.resize(COUNT)
	catch_fire.resize(COUNT)
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
		burn[t] = float(d.get("burn", 0.0))
		burn_to[t] = int(d.get("burn_to", AIR))
		ignites[t] = 1 if d.get("ignites", false) else 0
		explodes[t] = 1 if d.get("explodes", false) else 0
		catch_fire[t] = float(d.get("catch", 1.0))

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
