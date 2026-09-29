class_name LevelBase
extends Node3D
## 关卡基类：搭建工具函数（区域、对话、金币、树……）

@export var world_path: NodePath

var world: VoxelWorld
var decor: Decor
var rng := RandomNumberGenerator.new()

func build() -> void:
	pass

func spawn_position() -> Vector3:
	return Vector3.ZERO

func spawn_yaw() -> float:
	return -PI / 2.0

## 用体素包围盒（含两端）放置一个区域
func zone(script: GDScript, a: Vector3i, b: Vector3i, props := {}) -> Node:
	var z: Node3D = script.new()
	z.set("box_size", Vector3((b - a).abs() + Vector3i.ONE) * VoxelWorld.CELL_M)
	for k in props:
		z.set(k, props[k])
	add_child(z)
	var lo := Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z))
	var hi := Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))
	z.global_position = world.to_global(Vector3(lo + hi + Vector3i.ONE) * VoxelWorld.CELL_M * 0.5)
	return z

func talk(a: Vector3i, b: Vector3i, lines: Array) -> void:
	zone(TalkTrigger, a, b, {"lines": PackedStringArray(lines)})

func cells(a: Vector3i, b: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for z in range(mini(a.z, b.z), maxi(a.z, b.z) + 1):
		for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
			for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
				out.append(Vector3i(x, y, z))
	return out

## 在体素 cell（空气格）里放一枚金币，悬浮在格子中间偏下
func coin(cell: Vector3i) -> void:
	var c := StaticCoin.new()
	add_child(c)
	c.global_position = world.voxel_center(cell) + Vector3.UP * 0.25

## 两点之间摆一串金币（引路面包屑）
func coin_line(a: Vector3i, b: Vector3i, n: int) -> void:
	for i in n:
		var t := 0.0 if n == 1 else float(i) / (n - 1)
		var p := Vector3(a).lerp(Vector3(b), t)
		coin(Vector3i(roundi(p.x), roundi(p.y), roundi(p.z)))

## 地表高度：列 (x, z) 最高的实心方块上方那一格的 y（没有地面返回 -1）
func surface_y(x: int, z: int) -> int:
	for y in range(world.csize.y - 2, -1, -1):
		if world.get_block(Vector3i(x, y, z)) != Blocks.AIR:
			return y + 1 if world.get_shape(Vector3i(x, y, z)) == 0 else -1
	return -1

## 在 (x, z) 附近找一块 w×w 的平地，返回地面上方那一格；找不到返回 (-1,-1,-1)
func find_flat(x: int, z: int, rad := 5, w := 3) -> Vector3i:
	for r in range(0, rad + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var cx := x + dx
				var cz := z + dz
				var h := surface_y(cx, cz)
				if h < 0:
					continue
				var ok := true
				var half := w / 2
				for oz in range(-half, half + 1):
					for ox in range(-half, half + 1):
						if surface_y(cx + ox, cz + oz) != h:
							ok = false
				if ok:
					return Vector3i(cx, h, cz)
	return Vector3i(-1, -1, -1)

## 一个不会被撞飞的装饰物件（营地的箱子、设备……）
func deco(path: String, x: int, z: int, height_m: float, solid := "box", yaw := INF) -> Prop:
	var c := find_flat(x, z, 4, 3)
	if c.y < 0:
		return null
	var p := prop(path, c, height_m, false, 0, solid)
	if yaw != INF:
		p.rotation.y = yaw
	return p

## 一棵体素树（0.25 米精度，树叶撞得碎、树干要钻）。base = 地面上方那一格；h 为树干高度（格），r 为树冠半径（格）
func tree(base: Vector3i, h: int, r: float, kind := "") -> void:
	if kind == "":
		var roll := rng.randf()
		kind = "pine" if roll < 0.35 else ("blossom" if roll < 0.45 else "round")
	var root := Vector3i(base.x * VoxelWorld.CELL, base.y * VoxelWorld.CELL, base.z * VoxelWorld.CELL)
	# 贴地：往下找到真正的地面体素
	while root.y > 0 and world.vget(root + Vector3i.DOWN) == Blocks.AIR:
		root.y -= 1
	var trunk := int(h * VoxelWorld.CELL * (1.1 if kind == "pine" else 0.85))
	world.put_tree(root, trunk, r * VoxelWorld.CELL_M * (0.85 if kind == "pine" else 0.9), kind, rng)

## 在地面格 base（空气格，下方是地面）上放一个道具
func prop(path: String, base: Vector3i, height_m: float, breakable := true, coins := 1, solid := "trunk", sound := "break_wood") -> Prop:
	var p := Prop.new()
	p.model_path = path
	p.height = height_m
	p.breakable = breakable
	p.coins = coins
	p.solid = solid
	p.pop_sound = sound
	p.ground_cell = base + Vector3i.DOWN
	add_child(p)
	p.global_position = world.voxel_top(base + Vector3i.DOWN)
	return p

## 灯柱
func lamp_post(base: Vector3i, h := 3) -> void:
	world.fill_box(base, base + Vector3i(0, h - 2, 0), Blocks.HULL_DARK)
	world.fill_box(base + Vector3i(0, h - 1, 0), base + Vector3i(0, h - 1, 0), Blocks.LAMP)
	var l := OmniLight3D.new()
	l.light_color = Color("ffe0a0")
	l.light_energy = 0.8
	l.omni_range = 5.0
	add_child(l)
	l.global_position = world.voxel_center(base + Vector3i(0, h - 1, 0))

## 在地面上撒草丛和花
func scatter_decor(region_lo: Vector3i, region_hi: Vector3i, grass_rate: float, flower_rate: float, prop_rate := 0.012) -> void:
	var flowers := ["flower_red", "flower_yellow", "flower_white", "flower_blue"]
	for z in range(region_lo.z, region_hi.z + 1):
		for x in range(region_lo.x, region_hi.x + 1):
			for y in range(region_hi.y, region_lo.y - 1, -1):
				var t := world.get_block(Vector3i(x, y, z))
				if t == Blocks.AIR:
					continue
				if t == Blocks.GRASS and world.get_shape(Vector3i(x, y, z)) == 0 and world.get_block(Vector3i(x, y + 1, z)) == Blocks.AIR:
					var roll := rng.randf()
					if roll < prop_rate:
						# 零星的 Kenney 小道具：花丛、蘑菇、小草、石头（小的可以撞飞）
						var pick := rng.randf()
						if pick < 0.45:
							prop(Kit.FLOWERS[rng.randi() % Kit.FLOWERS.size()], Vector3i(x, y + 1, z), rng.randf_range(0.45, 0.7), true, 0, "none", "break_soft")
						elif pick < 0.8:
							prop(Kit.PLANTS[rng.randi() % Kit.PLANTS.size()], Vector3i(x, y + 1, z), rng.randf_range(0.4, 0.65), true, 1, "none", "break_soft")
						else:
							prop(Kit.ROCKS[rng.randi() % Kit.ROCKS.size()], Vector3i(x, y + 1, z), rng.randf_range(0.3, 0.5), true, 0, "none", "break_hard")
					elif roll < flower_rate:
						decor.add(flowers[rng.randi() % flowers.size()], Vector3i(x, y, z), rng)
					elif roll < flower_rate + grass_rate:
						decor.add("grass", Vector3i(x, y, z), rng)
				break

# ================================================================ 破坏与重构

## 重构波：塔点亮时，一道光环从 center 扩散出去，沿途被砸烂的地形一块块飞回原位
func reconstruct(center: Vector3, radius := 80.0, dur := 7.0) -> int:
	var n := world.restore_wave(center, radius, dur)
	for k in 2:
		var mi := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.985
		t.outer_radius = 1.0
		t.rings = 96
		t.ring_segments = 6
		mi.mesh = t
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(0.45, 1.0, 0.85, 0.9)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = center
		mi.scale = Vector3(1.0, 6.0, 1.0)
		var tw := mi.create_tween().set_parallel()
		tw.tween_interval(k * 0.5)
		tw.chain().tween_property(mi, "scale", Vector3(radius, 30.0, radius), dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(m, "albedo_color:a", 0.0, dur)
		tw.chain().tween_callback(mi.queue_free)
	Sfx.play("rebuild_done", Vector3.INF, -2.0, 0.0, 0.85)
	GameState.shake.emit(0.3)
	if n > 0:
		get_tree().create_timer(2.5).timeout.connect(func() -> void:
			var p := GameState.player as Node3D
			if p:
				FloatText.spawn(self, p.global_position + Vector3.UP * 1.5, "重构波：%d 块地形回到原位" % n, Color("9dffcf"), 44, 2.0))
	return n

## 重构点 · 螺旋瞭望台：在 (x, z) 附近找块平地放蓝图，建好以后顶上出现宝箱
func rebuild_tower(id: String, x: int, z: int, cost: int, h := 12, chest := {}) -> RebuildSite:
	var base := _find_site(x, z, h + 3)
	if base.x < 0:
		push_warning("重构点 %s 找不到平地" % id)
		return null
	return rebuild_tower_at(id, base, cost, h, chest)

## 指定位置放瞭望台（base：塔芯西北角的地面格）
func rebuild_tower_at(id: String, base: Vector3i, cost: int, h := 12, chest := {}) -> RebuildSite:
	var res := RebuildSite.tower(base, h)
	# 地基：塔脚下低一格的地方补平
	var found: Array = []
	for oz in range(-3, 7):
		for ox in range(-6, 7):
			var c := base + Vector3i(ox, -1, oz)
			if world.get_block(c) == Blocks.AIR:
				found.append([c, Blocks.PAVING, 0])
	res[0] = found + res[0]
	var site := RebuildSite.new()
	site.set_meta("base", base)
	site.clear_a = base + Vector3i(-6, 0, -3)
	site.clear_b = base + Vector3i(6, 5, 6)
	site.world = world
	site.site_id = id
	site.title = "瞭望台"
	site.cost = cost
	site.blueprint = res[0]
	site.pad_cell = base + Vector3i(-5, 0, 1)
	var top: Vector3i = res[1]
	site.rebuilt.connect(func() -> void:
		var c := top
		var props := {"chest_id": "rb_" + id, "coins": 20, "energy": 3, "line": "瞭望台顶上的宝箱！从这儿看得好远。"}
		props.merge(chest, true)
		zone(TreasureChest, c, c, props))
	add_child(site)
	return site

## 重构点 · 桥
func rebuild_bridge(id: String, a: Vector3i, b: Vector3i, cost: int, pad: Vector3i, title := "断桥") -> RebuildSite:
	var res := RebuildSite.bridge(a, b)
	var site := RebuildSite.new()
	site.world = world
	site.site_id = id
	site.title = title
	site.cost = cost
	site.blueprint = res[0]
	site.pad_cell = pad
	add_child(site)
	return site

## 找一块平地（塔 10×10 + 西边的光圈）：地面高低差不超过 1 格（矮的地方重建时补地基），
## 零星的小石头、灌木（最多 16 列、不超过 4 格高）重建时会被清掉
func _find_site(x: int, z: int, clear: int) -> Vector3i:
	for r in range(0, 15):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var cx := x + dx
				var cz := z + dz
				var h := surface_y(cx, cz)
				if h < 0:
					continue
				var ok := true
				var bumps := 0
				for oz in range(-3, 7):
					if not ok:
						break
					for ox in range(-6, 7):
						var sy := surface_y(cx + ox, cz + oz)
						if sy == h or sy == h - 1:
							continue
						if sy > h and sy <= h + 4 and world.get_block(Vector3i(cx + ox, h - 1, cz + oz)) != Blocks.AIR:
							bumps += 1
							if bumps <= 16:
								continue
						ok = false
						break
				if ok:
					for oz in range(-3, 7):
						for ox in range(-6, 7):
							for y in range(h + 5, h + clear):
								if world.get_block(Vector3i(cx + ox, y, cz + oz)) != Blocks.AIR:
									ok = false
				if ok:
					return Vector3i(cx, h, cz)
	return Vector3i(-1, -1, -1)

## 关卡搭好以后检查一遍：出生在半空（脚下几格内没有地面）的敌人，挪到附近最近的一块地面上。
## 以前有几只敌人摆在了平台边缘外面，一开局就掉下去摔没了（还白送连击）。
const _NO_GROUND_CHECK := ["rustfly.gd", "rust_worm.gd", "rust_heart.gd", "rust_airship.gd", "rust_bomb.gd"]
func settle_enemies() -> void:
	if world == null:
		return
	for e in get_tree().get_nodes_in_group("enemy"):
		var n := e as Node3D
		if n == null or n.get_script() == null or str(n.get_script().resource_path.get_file()) in _NO_GROUND_CHECK:
			continue
		var c := world.world_to_voxel(n.global_position + Vector3.UP * 0.1)
		# 埋在地里（出生以后地形又被垫高了）：往上找到露天的地方
		if world.get_block(c) != Blocks.AIR or world.get_block(c + Vector3i.UP) != Blocks.AIR:
			for up in range(1, 8):
				var q := c + Vector3i.UP * up
				if world.get_block(q) == Blocks.AIR and world.get_block(q + Vector3i.UP) == Blocks.AIR:
					n.global_position = world.voxel_top(q + Vector3i.DOWN) + Vector3.UP * 0.05
					break
			continue
		if _solid_below(c, 3):
			continue
		var best := Vector3i(-1, -1, -1)
		for r in range(1, 9):
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dz)) != r or best.x >= 0:
						continue
					for dy in [0, -1, 1, -2, 2, -3]:
						var q := c + Vector3i(dx, dy, dz)
						if world.get_block(q) == Blocks.AIR and world.get_block(q + Vector3i.UP) == Blocks.AIR and world.get_block(q + Vector3i.DOWN) != Blocks.AIR:
							best = q
							break
			if best.x >= 0:
				break
		if best.x >= 0:
			n.global_position = world.voxel_top(best + Vector3i.DOWN) + Vector3.UP * 0.05
		else:
			push_warning("敌人出生点附近没有地面：%s %s" % [n.name, c])

func _solid_below(c: Vector3i, depth: int) -> bool:
	for k in range(0, depth + 1):
		if world.get_block(c + Vector3i.DOWN * k) != Blocks.AIR:
			return true
	return false
