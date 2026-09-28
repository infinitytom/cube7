class_name Chapters
extends RefCounted
## 章节表：标题、音乐、对应的关卡脚本。

const LIST := [
	{"id": "greenhouse", "num": "第一章", "title": "翠绿温室群岛", "music": "gh", "tower": 1},
	{"id": "gearworks", "num": "第二章", "title": "齿轮工坊", "music": "gw", "tower": 2},
	{"id": "abyss", "num": "第三章", "title": "晶簇深渊", "music": "ab", "tower": 3},
	{"id": "city", "num": "第四章", "title": "云顶之城", "music": "cc", "tower": 4},
]

static func count() -> int:
	return LIST.size()

static func info(ch: int) -> Dictionary:
	return LIST[clampi(ch, 1, LIST.size()) - 1]

static func make_level(ch: int) -> Node3D:
	if ch == 2:
		return AreaGearworks.new()
	if ch == 3:
		return AreaAbyss.new()
	if ch == 4:
		return AreaCity.new()
	return AreaGreenhouse.new()
