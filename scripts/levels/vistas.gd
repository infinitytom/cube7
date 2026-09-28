class_name Vistas
extends RefCounted
## 每一章的远景布置：云海、远处的浮岛群、从云海拔起的石柱、方舟星核塔、其余的重构塔。
## 坐标单位：米。玩法浮岛大致在 x 0..64、z 0..50、地面高 10 米。
## 世界地理（所有章节一致）：方舟星核塔在东北方远处；五座重构塔围着它；第一章在西南，第二章在第一章的东边。

const ARK_POS := Vector3(430, -40, -560)

static func _sky(level: Node3D, center: Vector3, sea_y: float) -> Vista:
	var sky := SkyWorld.new()
	sky.center = center
	sky.sea_height = sea_y
	level.add_child(sky)
	var v := Vista.new()
	v.name = "Vista"
	v.sea_y = sea_y
	if Array(OS.get_cmdline_user_args()).any(func(a: String) -> bool: return a.begins_with("--shots") or a.begins_with("--autotest") or a == "--sync-vista"):
		v.sync_build = true
	level.add_child(v)
	return v

## 第一章 · 翠绿温室群岛
static func greenhouse(level: Node3D, world: VoxelWorld, island_falls: Array = []) -> Vista:
	var t0 := Time.get_ticks_msec()
	var sea := -30.0
	var v := _sky(level, Vector3(32, 0, 25), sea)
	v.add_underside(world, 46, 11)
	for f in island_falls:
		v.add_waterfall(f[0], f[1], (f[0] as Vector3).y - sea, 2.0)
	# 北面：高耸的“云脊”母岛——带山峰和三道瀑布，是温室背后的大背景
	v.add("island", {"r": 46.0, "top": 8, "under": 40, "hill": 5.0, "peak": 62.0, "peak_r": 0.55, "peak_off": Vector2(0.15, -0.2),
		"trees": 0.035, "kinds": ["pine", "pine", "round"], "seed": 101, "falls": 4, "crystals": true}, Vector3(30, 4, -95), 0.3, {"falls_to": sea, "fall_width": 4.0})
	# 西边：开满粉花的樱花岛（标题画面的背景）+ 废墟
	v.add("island", {"r": 26.0, "top": 6, "under": 30, "hill": 4.0, "trees": 0.06, "kinds": ["blossom", "blossom", "round"], "seed": 102, "falls": 2, "ruins": true}, Vector3(-95, 16, 10), 1.2, {"falls_to": sea})
	# 东边远处：宽阔的平顶岛，上面有殖民地的废墟
	v.add("island", {"r": 30.0, "top": 6, "under": 30, "hill": 3.0, "trees": 0.03, "seed": 103, "falls": 2, "ruins": true, "crystals": true}, Vector3(210, 2, -20), 0.4, {"falls_to": sea, "fall_width": 5.0})
	# 南边：一串小岛
	v.add("island", {"r": 14.0, "top": 4, "under": 18, "hill": 2.0, "trees": 0.08, "seed": 104, "falls": 1}, Vector3(10, -4, 110), 0.0, {"falls_to": sea, "bob": 0.6})
	v.add("island", {"r": 9.0, "top": 3, "under": 12, "hill": 1.0, "trees": 0.1, "seed": 105}, Vector3(60, 22, 95), 0.0, {"bob": 0.9})
	v.add("island", {"r": 7.0, "top": 3, "under": 10, "hill": 1.0, "trees": 0.12, "seed": 106}, Vector3(-40, 30, 70), 0.0, {"bob": 1.1})
	v.add("island", {"r": 11.0, "top": 4, "under": 16, "hill": 2.0, "trees": 0.05, "seed": 107, "crystals": true, "falls": 1}, Vector3(115, 26, 70), 0.0, {"falls_to": sea, "bob": 0.7})
	# 中景的石柱：从云海里直直拔起，给画面纵深
	v.add("pillar", {"r": 5.0, "h": 70, "seed": 111}, Vector3(-30, sea - 8, -20), 0.0)
	v.add("pillar", {"r": 4.0, "h": 58, "seed": 112}, Vector3(95, sea - 8, -15), 0.0)
	v.add("pillar", {"r": 6.0, "h": 50, "seed": 113}, Vector3(85, sea - 8, 125), 0.0)
	v.add("pillar", {"r": 3.5, "h": 64, "seed": 114, "tree": false}, Vector3(-60, sea - 8, 115), 0.0)
	# 远处：更多浮岛（大体素）
	for k in 7:
		var a := k * TAU / 7.0 + 0.4
		var d := 330.0 + (k % 3) * 70.0
		v.add("island", {"r": 24.0 + (k % 3) * 8.0, "top": 5, "under": 22, "hill": 4.0, "peak": 20.0 if k % 2 == 0 else 0.0, "trees": 0.03, "seed": 120 + k, "voxel": 2.0, "falls": 1},
			Vector3(32 + cos(a) * d, -10 + (k % 4) * 14.0, 25 + sin(a) * d), a, {"falls_to": sea, "fall_width": 7.0})
	_ark_and_towers(v, 1, sea)
	if v.sync_build:
		print("[Vista] 同步生成耗时 %d ms" % (Time.get_ticks_msec() - t0))
	return v

## 方舟星核塔 + 其余重构塔（lit_upto：前几座已经点亮）
static func _ark_and_towers(v: Vista, lit_upto: int, sea: float) -> void:
	v.add("ark_spire", {"r": 15.0, "h": 150, "voxel": 2.0}, ARK_POS, 0.3, {"name": "ArkSpire"})
	v.add("island", {"r": 60.0, "top": 8, "under": 40, "hill": 6.0, "trees": 0.02, "seed": 199, "voxel": 2.0, "falls": 5, "crystals": true}, ARK_POS + Vector3(0, 30, 0), 0.0, {"falls_to": sea, "fall_width": 10.0})
	var spots := [Vector3(-40, 0, 40), Vector3(330, 10, -280), Vector3(620, 20, -420), Vector3(700, 30, -760), Vector3(180, 25, -820)]
	for i in spots.size():
		if i == 0:
			continue      # 第一座塔就在第一章的浮岛上
		var lit := i < lit_upto
		v.add("recon_tower", {"r": 18.0, "seed": 300 + i, "voxel": 2.0, "lit": lit, "falls": 1}, spots[i], i * 1.3,
			{"falls_to": sea, "beam": lit, "fall_width": 6.0})

## 第二章 · 齿轮工坊（黄昏）：四周是冒烟的工厂浮岛、慢慢转动的巨型齿轮、锈红色的钢桁架；
## 西边远处是第一章的温室群岛（第一座塔已经点亮，光柱冲天），东北方是方舟星核塔
static func gearworks(level: Node3D, world: VoxelWorld, island_falls: Array = []) -> Vista:
	var t0 := Time.get_ticks_msec()
	var sea := -32.0
	var v := _sky(level, Vector3(34, 0, 26), sea)
	v.add_underside(world, 48, 21)
	for f in island_falls:
		v.add_waterfall(f[0], f[1], (f[0] as Vector3).y - sea, 2.0)
	# 北面：大工厂岛（三根大烟囱）
	v.add("factory_island", {"r": 34.0, "seed": 201, "halls": 4, "chimneys": 3, "under": 34}, Vector3(30, 6, -80), 0.2, {"smoke_scale": 1.6})
	# 东北：熔炉岛
	v.add("factory_island", {"r": 24.0, "seed": 202, "halls": 2, "chimneys": 2}, Vector3(150, 14, -40), 1.1, {"smoke_scale": 1.3})
	# 南面：仓库岛
	v.add("factory_island", {"r": 20.0, "seed": 203, "halls": 3, "chimneys": 1}, Vector3(40, -2, 115), 2.0, {})
	# 东南：矿石岛（带瀑布）
	v.add("island", {"r": 22.0, "top": 5, "under": 28, "hill": 6.0, "peak": 24.0, "trees": 0.02, "kinds": ["pine"], "seed": 204, "falls": 2, "crystals": true}, Vector3(140, 4, 95), 0.5, {"falls_to": sea})
	# 巨型齿轮：立在北岛和东北岛上慢慢转
	v.add("gear", {"r": 16.0, "teeth": 18, "voxel": 1.0}, Vector3(10, 36, -70), 0.3, {"spin": 0.12, "shadow": false})
	v.add("gear", {"r": 10.0, "teeth": 12, "voxel": 1.0}, Vector3(34, 30, -66), 0.3, {"spin": -0.2})
	v.add("gear", {"r": 12.0, "teeth": 14, "voxel": 1.0}, Vector3(150, 40, -45), 1.1, {"spin": 0.16})
	# 钢桁架：把工厂岛连起来（有一座断了）
	v.add("truss", {"len": 90}, Vector3(60, 12, -60), -0.35, {})
	v.add("truss", {"len": 70, "broken": true}, Vector3(78, 6, 105), -0.2, {})
	# 石柱
	v.add("pillar", {"r": 5.0, "h": 64, "seed": 211}, Vector3(-35, sea - 8, 60), 0.0)
	v.add("pillar", {"r": 4.0, "h": 70, "seed": 212, "tree": false}, Vector3(95, sea - 8, -10), 0.0)
	# 远处：更多工厂岛和浮岛
	for k in 6:
		var a := k * TAU / 6.0 + 0.2
		var d := 320.0 + (k % 2) * 90.0
		if k % 2 == 0:
			v.add("factory_island", {"r": 26.0, "seed": 220 + k, "voxel": 2.0, "halls": 3, "chimneys": 2}, Vector3(34 + cos(a) * d, -6 + (k % 3) * 12.0, 26 + sin(a) * d), a, {"smoke_scale": 4.0})
		else:
			v.add("island", {"r": 26.0, "top": 5, "under": 22, "hill": 4.0, "peak": 18.0, "trees": 0.03, "seed": 230 + k, "voxel": 2.0, "falls": 1}, Vector3(34 + cos(a) * d, -10 + (k % 3) * 12.0, 26 + sin(a) * d), a, {"falls_to": sea, "fall_width": 7.0})
	# 西边远处：第一章的温室群岛（第一座塔亮着）
	v.add("recon_tower", {"r": 24.0, "seed": 300, "voxel": 2.0, "lit": true, "falls": 2}, Vector3(-300, 0, 60), 0.6, {"falls_to": sea, "beam": true, "fall_width": 6.0})
	_ark_and_towers(v, 1, sea)
	if v.sync_build:
		print("[Vista] 同步生成耗时 %d ms" % (Time.get_ticks_msec() - t0))
	return v

## 第三章 · 晶簇深渊：四周漂着长满水晶的浮岛和巨大的晶体，远处是星核塔；天坑里有瀑布落下
static func abyss(level: Node3D, world: VoxelWorld, falls: Array = []) -> Vista:
	var t0 := Time.get_ticks_msec()
	var sea := -30.0
	var v := _sky(level, Vector3(32, 0, 32), sea)
	v.add_underside(world, 44, 31)
	for f in falls:
		var top: Vector3 = f[0]
		var to_y: float = f[2] if f.size() > 2 else sea
		v.add_waterfall(top, f[1], top.y - to_y, 2.5)
	for k in 6:
		var a := k * TAU / 6.0 + 0.5
		var d := 120.0 + (k % 3) * 45.0
		v.add("island", {"r": 18.0 + (k % 3) * 6.0, "top": 5, "under": 26, "hill": 4.0, "peak": 14.0 if k % 2 else 0.0, "trees": 0.02, "kinds": ["pine", "round"], "seed": 400 + k, "falls": 1, "crystals": true}, Vector3(32 + cos(a) * d, -8 + (k % 4) * 12.0, 32 + sin(a) * d), a, {"falls_to": sea})
		v.add("shard", {"len": 34 + (k % 3) * 12, "r": 4.0 + (k % 2) * 2.0, "seed": 410 + k, "block": Blocks.CRYSTAL if k % 2 else Blocks.GEM_CHAIN}, Vector3(32 + cos(a + 0.5) * (d * 0.8), -12 + (k % 3) * 10.0, 32 + sin(a + 0.5) * (d * 0.8)), a, {"bob": 1.2})
	for k in 5:
		var a := k * TAU / 5.0 + 0.2
		v.add("shard", {"len": 60, "r": 8.0, "seed": 430 + k, "voxel": 2.0}, Vector3(32 + cos(a) * 380.0, -40.0, 32 + sin(a) * 380.0), a, {})
	v.add("pillar", {"r": 5.0, "h": 70, "seed": 441}, Vector3(-40, sea - 8, 0), 0.0)
	v.add("pillar", {"r": 4.0, "h": 62, "seed": 442, "tree": false}, Vector3(100, sea - 8, 90), 0.0)
	_ark_and_towers(v, 2, sea)
	if v.sync_build:
		print("[Vista] 同步生成耗时 %d ms" % (Time.get_ticks_msec() - t0))
	return v

## 第四章 · 云顶之城：四周是别的城区浮岛（白楼、玻璃穹顶），远处的飞艇，星核塔
static func city(level: Node3D, world: VoxelWorld) -> Vista:
	var t0 := Time.get_ticks_msec()
	var sea := -24.0
	var v := _sky(level, Vector3(36, 20, 40), sea)
	v.add_underside(world, 40, 41)
	for k in 7:
		var a := k * TAU / 7.0 + 0.3
		var d := 110.0 + (k % 3) * 40.0
		v.add("city_island", {"r": 18.0 + (k % 3) * 5.0, "seed": 500 + k, "buildings": 4 + k % 3, "falls": 1 if k % 2 else 0}, Vector3(36 + cos(a) * d, 14 + (k % 4) * 10.0, 40 + sin(a) * d), a, {"falls_to": sea, "bob": 0.4})
	for k in 5:
		var a := k * TAU / 5.0
		v.add("city_island", {"r": 28.0, "seed": 520 + k, "voxel": 2.0, "buildings": 7}, Vector3(36 + cos(a) * 360.0, 0.0 + k * 8.0, 40 + sin(a) * 360.0), a, {})
	# 城区之间的桁架轨道
	v.add("truss", {"len": 80}, Vector3(-40, 22, 20), 0.6, {})
	v.add("truss", {"len": 60, "broken": true}, Vector3(120, 30, 90), 2.2, {})
	_ark_and_towers(v, 3, sea)
	if v.sync_build:
		print("[Vista] 同步生成耗时 %d ms" % (Time.get_ticks_msec() - t0))
	return v

## 第五章 · 锈海：一直铺到天边的锈色海面；四周是半沉的巨船残骸、锈岩柱；远处的方舟和四座已经亮起的塔
static func rust(level: Node3D, world: VoxelWorld) -> Vista:
	var t0 := Time.get_ticks_msec()
	var sea := 6.0
	var sky := SkyWorld.new()
	sky.center = Vector3(40, 0, 45)
	sky.sea_height = sea
	sky.show_sea = false
	sky.bird_flocks = 2
	level.add_child(sky)
	var v := Vista.new()
	v.name = "Vista"
	v.sea_y = sea
	if Array(OS.get_cmdline_user_args()).any(func(a: String) -> bool: return a.begins_with("--shots") or a.begins_with("--autotest") or a == "--sync-vista"):
		v.sync_build = true
	level.add_child(v)
	# 巨船残骸：一圈半沉在海里
	var wrecks := [
		[Vector3(-60, sea, 40), 0.4, {"len": 90, "w": 18, "h": 16, "seed": 601, "bow_up": 0.25, "sink": 7}],
		[Vector3(40, sea, -70), 1.9, {"len": 120, "w": 22, "h": 18, "seed": 602, "bow_up": 0.1, "sink": 8}],
		[Vector3(150, sea, 130), -0.8, {"len": 70, "w": 14, "h": 12, "seed": 603, "bow_up": 0.4, "sink": 5}],
		[Vector3(-30, sea, 150), 2.8, {"len": 60, "w": 12, "h": 11, "seed": 604, "sink": 6}],
		[Vector3(170, sea, -30), 1.2, {"len": 100, "w": 20, "h": 16, "seed": 605, "bow_up": 0.15, "sink": 9}],
	]
	for w in wrecks:
		v.add("wreck", w[2], w[0], w[1], {})
	for k in 6:
		var a := k * TAU / 6.0 + 0.5
		var d := 260.0 + (k % 3) * 90.0
		v.add("wreck", {"len": 120, "w": 24, "h": 20, "seed": 620 + k, "voxel": 2.0, "bow_up": 0.1 * (k % 3), "sink": 10}, Vector3(40 + cos(a) * d, sea, 45 + sin(a) * d), a, {})
	# 锈岩柱
	v.add("pillar", {"r": 6.0, "h": 50, "seed": 611, "rust": true, "tree": false}, Vector3(-25, sea - 6, -20), 0.0)
	v.add("pillar", {"r": 4.0, "h": 38, "seed": 612, "rust": true, "tree": false}, Vector3(110, sea - 6, -40), 0.0)
	v.add("pillar", {"r": 5.0, "h": 44, "seed": 613, "rust": true, "tree": false}, Vector3(120, sea - 6, 110), 0.0)
	v.add("pillar", {"r": 3.5, "h": 30, "seed": 614, "rust": true, "tree": false}, Vector3(-40, sea - 6, 100), 0.0)
	_ark_and_towers(v, 4, sea - 30.0)
	if v.sync_build:
		print("[Vista] 同步生成耗时 %d ms" % (Time.get_ticks_msec() - t0))
	return v

