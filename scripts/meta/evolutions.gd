class_name Evolutions
extends RefCounted
## 形态进化：用埋在地层深处的「回声晶核」换来的能力。
## 和金币改装（Upgrades）不同，进化会改变“能去哪里”：钻得进更硬的岩层、听得见更深处的回声、
## 撞得开更厚的墙——找到的晶核越多，世界里能挖开的地方越多。

const LIST := [
	{"id": "echo_range", "name": "深层回声", "form": "通用", "desc": "扫描半径 14 → 22 米，能听见更深处的空腔和晶核", "cost": 2},
	{"id": "spiral_drill", "name": "螺旋钻头", "form": "钻头", "desc": "能钻穿悬崖岩和锈岩（原本打不动的地层），隧道更宽", "cost": 3},
	{"id": "shock_ram", "name": "震荡冲撞", "form": "滚球", "desc": "冲撞会把周围的岩石震裂成大块，满蓄力能撞开岩石", "cost": 3},
	{"id": "resonance", "name": "共鸣气泡", "form": "气泡", "desc": "气浪会震碎晶簇和松动的石板，还能把扫描到的晶核吸过来", "cost": 2},
	{"id": "echo_sight", "name": "回声视界", "form": "通用", "desc": "扫描后，地下的隧道和空腔会透出轮廓 12 秒（原来 6 秒）", "cost": 2},
]

static var _mem := {}

static func _store() -> Dictionary:
	if SaveGame.data.is_empty():
		return _mem
	if not SaveGame.data.has("evolutions"):
		SaveGame.data["evolutions"] = {}
	return SaveGame.data["evolutions"]

static func has(id: String) -> bool:
	return bool(_store().get(id, false))

static func info(id: String) -> Dictionary:
	for e in LIST:
		if e.id == id:
			return e
	return {}

## 手上还没用掉的晶核
static func cores_available() -> int:
	var spent := 0
	for e in LIST:
		if has(e.id):
			spent += int(e.cost)
	return GameState.echo_ids().size() - spent

static func unlock(id: String) -> bool:
	var e := info(id)
	if e.is_empty() or has(id) or cores_available() < int(e.cost):
		return false
	_store()[id] = true
	if not SaveGame.data.is_empty():
		SaveGame.write()
	GameState.upgrades_changed.emit()
	return true

## 测试 / 调试用
static func grant(id: String) -> void:
	_store()[id] = true

static func scan_radius() -> float:
	return 22.0 if has("echo_range") else 14.0

static func reveal_time() -> float:
	return 12.0 if has("echo_sight") else 6.0

## 钻头能不能钻这种方块（螺旋钻头解锁悬崖岩、锈岩、深渊岩）
static func drill_extra(t: int) -> bool:
	return has("spiral_drill") and t in [Blocks.CLIFF, Blocks.CLIFF_B, Blocks.CLIFF_C, Blocks.RUSTROCK, Blocks.DARKROCK, Blocks.DARKROCK_B, Blocks.ROCK]
