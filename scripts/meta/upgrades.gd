class_name Upgrades
extends RefCounted
## PIX 的改装（成长系统）：用金币给 PIX 升级，存在存档里，跨章节保留。
## 暂停菜单 →「改装」，或者章节结算画面里都能打开。

const LIST := [
	{"id": "shield", "name": "护盾扩容", "desc": "护盾上限 +1 格", "cost": [200, 450]},
	{"id": "charge", "name": "快速蓄力", "desc": "原地蓄力冲刺更快充满", "cost": [150, 350]},
	{"id": "ram", "name": "强化冲角", "desc": "撞击力 +12%：普通冲刺也能撞开更硬的东西", "cost": [250, 500]},
	{"id": "speed", "name": "轴承润滑", "desc": "滚动和加速的最高速度 +8%", "cost": [120, 300]},
	{"id": "matter", "name": "物质回收", "desc": "拆东西得到的重构物质 +25%", "cost": [150, 350]},
	{"id": "energy", "name": "能源回路", "desc": "修复一格护盾需要的能源 10 → 7", "cost": [220]},
	{"id": "bubble", "name": "气泡喷口", "desc": "气泡形态空中多跳一次", "cost": [300]},
	{"id": "drill", "name": "合金钻头", "desc": "钻掘更快、隧道更宽", "cost": [180]},
]

static var _mem := {}          ## 没有存档时（测试）用内存

static func _store() -> Dictionary:
	if SaveGame.data.is_empty():
		return _mem
	if not SaveGame.data.has("upgrades"):
		SaveGame.data["upgrades"] = {}
	return SaveGame.data["upgrades"]

static func level(id: String) -> int:
	return int(_store().get(id, 0))

static func info(id: String) -> Dictionary:
	for u in LIST:
		if u.id == id:
			return u
	return {}

static func max_level(id: String) -> int:
	return (info(id).cost as Array).size()

static func next_cost(id: String) -> int:
	var lv := level(id)
	var c: Array = info(id).cost
	return int(c[lv]) if lv < c.size() else -1

static func buy(id: String) -> bool:
	var c := next_cost(id)
	if c < 0 or GameState.coins < c:
		return false
	GameState.coins -= c
	GameState.coins_changed.emit(GameState.coins)
	_store()[id] = level(id) + 1
	apply()
	if not SaveGame.data.is_empty():
		SaveGame.data["coins"] = GameState.coins
		SaveGame.write()
	return true

## 把改装效果套到当前的游戏状态上（关卡开始、买完以后调用）
static func apply() -> void:
	var old := GameState.max_shield
	GameState.max_shield = 3 + level("shield")
	if GameState.max_shield > old:
		GameState.shield += GameState.max_shield - old
	GameState.shield = mini(GameState.shield, GameState.max_shield)
	GameState.energy_per_shield = 7 if level("energy") > 0 else 10
	GameState.shield_changed.emit(GameState.shield)
	GameState.upgrades_changed.emit()

static func charge_time() -> float:
	return [0.9, 0.65, 0.45][level("charge")]

static func ram_mult() -> float:
	return 1.0 + 0.12 * level("ram")

static func speed_mult() -> float:
	return 1.0 + 0.08 * level("speed")

static func matter_mult() -> float:
	return 1.0 + 0.25 * level("matter")
