class_name EchoCaches
extends RefCounted
## 在每一章的地层深处埋下回声晶核（晶洞）。
## 规则：
##   · 只埋在厚实的自然地层里（四周至少 2 格都是平滑材质），离地表 4～9 格——从外面看不出来，得靠扫描
##   · 晶洞之间、和关卡里的重要地点（重构点、种子方块、检查点……）保持距离，不破坏原有的谜题
##   · 一部分晶洞埋在钻头钻不动的悬崖岩里：要先进化出「螺旋钻头」才挖得到（扫描会提示）
## 位置由章节 id 决定（固定种子），每次进同一章都一样；拿过的晶核不会再出现，但晶洞还在。

const PER_CHAPTER := 5

## 每章五段“星球的回声”：方块化之前，这片土地上发生过的小事。越往后的章节，越接近那一天。
const MEMORIES := {
	"greenhouse": [
		"每天早上六点，温室的喷淋头准时打开。噗噗们会排成一队，等着淋第一场“雨”。",
		"有个孩子在这块石头底下埋了一封信，写给“一百年以后挖到它的人”。",
		"艾拉博士喜欢在午休时躺在这片草坡上，数天上那颗行星的光环。",
		"这里原来是一片萝卜田。噗噗们第一次见到萝卜的时候，以为它是一种不会唱歌的噗噗。",
		"“如果有一天要把这里拆开——请记得把温室的味道也存下来。” —— 一位园丁的留言",
	],
	"gearworks": [
		"工坊的汽笛每到下班会响三声。最后一声总是有点走调，大家都说那是机器在打哈欠。",
		"维修机器人们在这面墙后面偷偷攒了一堆漂亮的螺丝，像在攒宝石。",
		"艾拉在这里第一次测试了方舟引擎的原型：一块方糖，被拆开又拼回来，甜味一点没少。",
		"夜班的工程师说，齿轮转动的声音和噗噗的歌是同一个调。",
		"“万一拼回来的时候少了一颗螺丝怎么办？” “那就再造一颗，这里是工坊。”",
	],
	"abyss": [
		"矿工们会对着晶簇唱歌。晶簇会把歌声存起来，过很多年再慢慢放出来。",
		"这条矿道的尽头，刻着十二个名字。那是第一批下到深渊里的人。",
		"深渊最深处很安静。艾拉说，在这里能听见星球的心跳。",
		"有只噗噗在矿洞里迷路了三天，出来的时候学会了一首谁也没听过的歌。",
		"“晶体会记住一切。”艾拉在日志里写，“也许我们也能。”",
	],
	"city": [
		"空中轨道的第一班车总是空的。司机说，他是在载着清晨兜风。",
		"市政厅的钟慢了七分钟，整座城市都按这个慢钟生活，谁也没去修。",
		"日冕潮预警发出的那天，城里的咖啡馆免费营业了一整夜。",
		"玻璃穹顶下的花园里，有一张长椅是艾拉和她妹妹的“秘密基地”。",
		"撤离广播循环了一百遍。第一百零一遍的时候，广播员换成了一首歌。",
	],
	"rust": [
		"这片海原来是蓝色的，涨潮的时候会把贝壳送到灯塔的台阶上。",
		"灯塔看守人每天晚上都会对着海说一句“晚安”。海从来没有回答过。",
		"锈蚀刚出现的时候，像一小片秋天的落叶。没人想到它会蔓延。",
		"艾拉在灯塔顶上算了一整夜：十年以后，日冕潮还会再来。",
		"“如果我把它拼回去，然后又要再拆一次呢？”—— 没有寄出的一封信",
	],
	"core": [
		"方舟引擎启动前的最后一分钟，控制室里很安静。有人在小声地数数。",
		"艾拉把最后一个座位让给了一只受伤的噗噗。",
		"引擎的核心里存着一句话，是在最后一秒写进去的：“等我。”",
		"星核记得每一块方块原来的位置，也记得每一个人回家的路。",
		"NOVA 第一次开口说话时，说的是：“……好吧，我来看着。”",
	],
}

## 在关卡里埋晶洞（关卡 build() 之后、开始游戏之前调用）
static func place(level: Node3D, world: VoxelWorld, chapter_id: String) -> int:
	if not MEMORIES.has(chapter_id):
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("echo:" + chapter_id)
	var avoid: Array[Vector3] = []
	for grp in ["rebuild_site", "seed_cube", "checkpoint", "scan_target", "usable_item"]:
		for n in level.get_tree().get_nodes_in_group(grp):
			if n is Node3D:
				avoid.append((n as Node3D).global_position)
	for n in level.find_children("*", "Checkpoint", true, false):
		avoid.append((n as Node3D).global_position)
	for n in level.find_children("*", "Goal", true, false):
		avoid.append((n as Node3D).global_position)
	var spawn: Vector3 = level.call("spawn_position") if level.has_method("spawn_position") else Vector3.ZERO
	avoid.append(spawn)
	var cs := world.csize
	var placed: Array[Vector3i] = []
	var locked_n := 0
	var found := 0
	for tries in 12000:
		if placed.size() >= PER_CHAPTER:
			break
		var x := rng.randi_range(4, cs.x - 5)
		var z := rng.randi_range(4, cs.z - 5)
		var top := _surface(world, x, z)
		if top < 6:
			continue
		var depth := rng.randi_range(3, 7)
		var c := Vector3i(x, top - depth, z)
		if c.y < 3:
			continue
		var info := _solid_shell(world, c)
		if info.is_empty():
			continue
		var locked: bool = info.locked
		# 最多一半需要进化才挖得到
		if locked and locked_n >= (PER_CHAPTER / 2 if tries < 8000 else PER_CHAPTER):
			continue
		var wp := world.voxel_center(c)
		var ok := true
		for a in avoid:
			if a.distance_to(wp) < 7.0:
				ok = false
				break
		for p in placed:
			if Vector3(p).distance_to(Vector3(c)) < 12.0:
				ok = false
				break
		if not ok:
			continue
		placed.append(c)
		if locked:
			locked_n += 1
		var idx := placed.size() - 1
		var id := "%s_echo_%d" % [chapter_id, idx]
		_carve(world, c, rng)
		if GameState.has_echo(id):
			found += 1
			continue
		var core := EchoCore.new()
		core.name = "EchoCore%d" % idx
		core.core_id = id
		core.memory = (MEMORIES[chapter_id] as Array)[idx % 5]
		core.locked_hint = "回声晶核（需要进化：螺旋钻头）" if locked else ""
		level.add_child(core)
		core.global_position = wp
	world.flush_dirty()
	GameState.set_echo_total(found, placed.size())
	print("[Echo] %s：埋下 %d 颗回声晶核（%d 颗需要螺旋钻头）" % [chapter_id, placed.size(), locked_n])
	return placed.size()

static func _surface(world: VoxelWorld, x: int, z: int) -> int:
	for y in range(world.csize.y - 1, -1, -1):
		var t := world.get_block(Vector3i(x, y, z))
		if t != Blocks.AIR:
			return y if Blocks.smooth[t] == 1 else -1
	return -1

## 晶洞四周 ±2 格全是平滑材质的实心地层，洞顶至少 1 米厚。
## locked：从洞顶到地表这一列里有钻头钻不动的岩层（要先进化「螺旋钻头」）。不合格返回 {}
static func _solid_shell(world: VoxelWorld, c: Vector3i) -> Dictionary:
	for dz in range(-2, 3):
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var t := world.get_block(c + Vector3i(dx, dy, dz))
				if t == Blocks.AIR or not t in LevelSpice.PLAIN:
					return {}
	# 再外面一圈（±4 格）不能有关卡里的特殊东西（晶洞谜题、矿脉、建筑……）
	for dz in range(-4, 5, 2):
		for dy in range(-4, 5, 2):
			for dx in range(-4, 5, 2):
				var t3 := world.get_block(c + Vector3i(dx, dy, dz))
				if t3 != Blocks.AIR and not t3 in LevelSpice.PLAIN:
					return {}
	var cv := c * VoxelWorld.CELL + Vector3i.ONE
	for k in range(5, 9):
		for o in [Vector3i.ZERO, Vector3i(2, 0, 0), Vector3i(-2, 0, 0), Vector3i(0, 0, 2), Vector3i(0, 0, -2)]:
			var t := world.vget(cv + o + Vector3i(0, k, 0))
			if t == Blocks.AIR or Blocks.smooth[t] == 0:
				return {}
	var locked := false
	var k2 := 5
	while k2 < 80:
		var t2 := world.vget(cv + Vector3i(0, k2, 0))
		if t2 == Blocks.AIR:
			break
		if Blocks.drill[t2] == 0:
			locked = true
		k2 += 1
	return {"locked": locked}

## 挖出一个椭球形的晶洞，洞壁零星长着共鸣晶簇（撞碎会连锁崩落、掉金币）
static func _carve(world: VoxelWorld, c: Vector3i, rng: RandomNumberGenerator) -> void:
	var center := Vector3(c * VoxelWorld.CELL) + Vector3.ONE * float(VoxelWorld.CELL) * 0.5
	var r := 4.2   # 体素
	for z in range(-6, 7):
		for y in range(-5, 6):
			for x in range(-6, 7):
				var p := Vector3(center) + Vector3(x, y, z)
				var q := Vector3(x, y * 1.3, z)
				var d := q.length()
				var v := Vector3i(p.floor())
				if d <= r:
					world.vset(v, Blocks.AIR)
				elif d <= r + 1.2 and rng.randf() < 0.18 and world.vget(v) != Blocks.AIR:
					world.vset(v, Blocks.GEM_CHAIN)
