class_name VoxelFire
extends Node3D
## 体素燃烧：可燃的体素（木头、树叶、木箱、脚手架、草……）被点着后会变成“燃烧中”的发光体素，
## 一边烧一边随机引燃相邻的可燃体素（往上烧得更快），烧完变成空气（草烧成泥土）。
## 燃料桶烧完会爆炸。烧断的支撑会让上面的结构整块塌下来（交给 VoxelWorld.detach_floating）。
## 炭火、熔炉口是常驻火源；气泡的气浪能吹灭一片火。
## 为了不卡：每 0.1 秒结算一次，同时燃烧的体素有上限。

const TICK := 0.1
const MAX_BURNING := 700
const SPREAD := 2.4          ## 每秒引燃一个相邻可燃体素的概率（向上 ×2，向下 ×0.4）
const HURT_RANGE := 0.55

var world: VoxelWorld
var burning := {}            ## 体素 -> [剩余时间, 原来的类型]
var sources := {}            ## 常驻火源体素（炭火 / 熔炉口）
var _t := 0.0
var _fx_t := 0.0
var _rng := RandomNumberGenerator.new()
var _particles: CPUParticles3D
var _smoke: CPUParticles3D
var _light: OmniLight3D
var _crackle_t := 0.0

signal exploded(pos: Vector3)

func _ready() -> void:
	_particles = _make_particles(Color(1.0, 0.72, 0.3, 1.0), Color(0.9, 0.2, 0.05, 0.0), 0.28, 0.6, 2.0)
	_smoke = _make_particles(Color(0.3, 0.28, 0.27, 0.35), Color(0.5, 0.5, 0.5, 0.0), 0.5, 1.8, 1.2)
	_light = OmniLight3D.new()
	_light.light_color = Color("ff8a3d")
	_light.light_energy = 0.0
	_light.omni_range = 6.0
	add_child(_light)

static var _dot: GradientTexture2D

## 圆形柔边的粒子贴图（火苗、烟）
static func _soft_dot() -> GradientTexture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.6))
		_dot = GradientTexture2D.new()
		_dot.gradient = g
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1.0, 0.5)
		_dot.width = 64
		_dot.height = 64
	return _dot

func _make_particles(c0: Color, c1: Color, size: float, life: float, speed: float) -> CPUParticles3D:
	var ps := CPUParticles3D.new()
	ps.emitting = false
	ps.amount = 90
	ps.lifetime = life
	ps.local_coords = false
	ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	ps.direction = Vector3.UP
	ps.spread = 18.0
	ps.gravity = Vector3(0, 1.5, 0)
	ps.initial_velocity_min = speed * 0.5
	ps.initial_velocity_max = speed
	var m := QuadMesh.new()
	m.size = Vector2.ONE * size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = _soft_dot()
	if c0.a > 0.9:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.material = mat
	ps.mesh = m
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	ps.color_ramp = g
	var cv := Curve.new()
	cv.add_point(Vector2(0, 0.6))
	cv.add_point(Vector2(0.3, 1.0))
	cv.add_point(Vector2(1, 0.1))
	ps.scale_amount_curve = cv
	add_child(ps)
	return ps

## 登记常驻火源：扫描一块区域（格坐标）里的炭火 / 熔炉口
func scan_sources(lo_cell: Vector3i, hi_cell: Vector3i) -> void:
	var lo := lo_cell * VoxelWorld.CELL
	var hi := hi_cell * VoxelWorld.CELL + Vector3i.ONE * (VoxelWorld.CELL - 1)
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var p := Vector3i(x, y, z)
				if Blocks.ignites[world.vget(p)] == 1:
					sources[p] = true

func ignite(p: Vector3i) -> bool:
	if burning.size() >= MAX_BURNING or burning.has(p):
		return false
	var t := world.vget(p)
	if Blocks.burn[t] <= 0.0:
		return false
	burning[p] = [Blocks.burn[t] * _rng.randf_range(0.8, 1.3), t]
	world.vset(p, Blocks.FIRE)
	return true

## 点燃球形范围内的可燃体素（火种、爆炸）
func ignite_sphere(center: Vector3, radius: float) -> int:
	var c := world.to_v(center)
	var r := int(ceil(radius / VoxelWorld.VOXEL))
	var n := 0
	for z in range(c.z - r, c.z + r + 1):
		for y in range(c.y - r, c.y + r + 1):
			for x in range(c.x - r, c.x + r + 1):
				var p := Vector3i(x, y, z)
				if world.vcenter(p).distance_to(center) <= radius and ignite(p):
					n += 1
	return n

## 吹灭 / 浇灭：燃烧中的体素恢复成原来的类型（已经烧了一半的就当烧焦了，变成空气）
func extinguish_sphere(center: Vector3, radius: float) -> int:
	var n := 0
	for p in burning.keys():
		if world.vcenter(p).distance_to(center) <= radius:
			var info: Array = burning[p]
			burning.erase(p)
			var orig: int = info[1]
			world.vset(p, orig if info[0] > Blocks.burn[orig] * 0.4 else Blocks.burn_to[orig])
			n += 1
	if n > 0:
		Sfx.play("wave", center, -6.0, 0.1, 0.7)
	return n

func is_burning_near(pos: Vector3, r: float) -> bool:
	var c := world.to_v(pos)
	var k := int(ceil(r / VoxelWorld.VOXEL))
	for z in range(c.z - k, c.z + k + 1):
		for y in range(c.y - k, c.y + k + 1):
			for x in range(c.x - k, c.x + k + 1):
				var p := Vector3i(x, y, z)
				if (burning.has(p) or sources.has(p)) and world.vcenter(p).distance_to(pos) <= r + VoxelWorld.VOXEL * 0.5:
					return true
	return false

func _physics_process(delta: float) -> void:
	if world == null:
		return
	_t += delta
	if _t < TICK:
		return
	var dt := _t
	_t = 0.0
	# 常驻火源：只点离主角不远的（远处的熔炉不用一直算）
	var pl := GameState.player as Node3D
	for s in sources.keys():
		if world.vget(s) == Blocks.AIR:
			sources.erase(s)
			continue
		if pl and world.vcenter(s).distance_squared_to(pl.global_position) > 900.0:
			continue
		for d in VoxelWorld.DIRS:
			if _rng.randf() < SPREAD * dt * 0.8:
				ignite(s + d)
	if burning.is_empty():
		_particles.emitting = false
		_smoke.emitting = false
		_light.light_energy = move_toward(_light.light_energy, 0.0, dt * 3.0)
		return
	var done: Array[Vector3i] = []
	var spread: Array[Vector3i] = []
	for p in burning.keys():
		if world.vget(p) != Blocks.FIRE:
			burning.erase(p)    # 燃烧中的方块被撞掉/钻掉了
			continue
		var info: Array = burning[p]
		info[0] -= dt
		# 往四周蔓延：向上快、向下慢
		for d in VoxelWorld.DIRS:
			var w := 2.0 if d.y > 0 else (0.4 if d.y < 0 else 1.0)
			if _rng.randf() < SPREAD * dt * w:
				spread.append(p + d)
		if info[0] <= 0.0:
			done.append(p)
	for p in spread:
		if _rng.randf() < Blocks.catch_fire[world.vget(p)]:
			ignite(p)
	var burned: Array[Vector3i] = []
	for p in done:
		var info: Array = burning[p]
		burning.erase(p)
		var orig: int = info[1]
		world.vset(p, Blocks.burn_to[orig])
		if Blocks.burn_to[orig] == Blocks.AIR:
			burned.append(p)
		if world._first_hit(p):
			world._drops(p, orig)
		if Blocks.explodes[orig] == 1:
			explode_at(world.vcenter(p))
	if not burned.is_empty():
		world.detach_floating(burned)
	_hurt_player()
	_update_fx(dt)

## 一个燃料桶只炸一次：0.3 秒内附近已经炸过就不再炸
var _recent: Array = []

func explode_at(pos: Vector3) -> void:
	var now := Time.get_ticks_msec()
	for e in _recent:
		if now - int(e[1]) < 300 and (e[0] as Vector3).distance_to(pos) < 1.2:
			return
	_recent.append([pos, now])
	if _recent.size() > 8:
		_recent.pop_front()
	_explode(pos)

func _explode(pos: Vector3) -> void:
	# 燃料桶：一整桶只炸一次——把同一个桶里剩下的体素也清掉
	world.break_sphere(pos, 1.6, "impact", 20.0)
	ignite_sphere(pos, 2.2)
	GameState.shake.emit(0.5)
	Sfx.play("impact_big", pos, 2.0, 0.1, 1.3)
	var pl := GameState.player as RigidBody3D
	if pl and pl.global_position.distance_to(pos) < 3.2:
		var away := (pl.global_position - pos).normalized()
		pl.linear_velocity += away * 8.0 + Vector3.UP * 4.0
		if pl.has_method("hurt"):
			pl.call("hurt", pos, 1)
	exploded.emit(pos)
	_flash(pos)

func _flash(pos: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color("ffb04a")
	l.light_energy = 6.0
	l.omni_range = 9.0
	add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.5)
	tw.tween_callback(l.queue_free)

func _hurt_player() -> void:
	var pl := GameState.player as MorphBall
	if pl == null or pl.is_invulnerable():
		return
	if is_burning_near(pl.global_position, HURT_RANGE):
		pl.hurt(pl.global_position + Vector3(_rng.randf_range(-0.3, 0.3), -0.3, _rng.randf_range(-0.3, 0.3)), 1)
		GameState.say("好烫！火会伤到你——用气泡的气浪可以把火吹灭。")

func _update_fx(dt: float) -> void:
	_fx_t -= dt
	if _fx_t > 0.0:
		return
	_fx_t = 0.3
	var pts := PackedVector3Array()
	var keys := burning.keys()
	var step := maxi(1, keys.size() / 60)
	var sum := Vector3.ZERO
	var pl := GameState.player as Node3D
	for i in range(0, keys.size(), step):
		var wp := world.vcenter(keys[i])
		pts.append(_particles.to_local(wp + Vector3.UP * 0.1))
		sum += wp
	_particles.emission_points = pts
	_smoke.emission_points = pts
	_particles.amount = clampi(pts.size() * 3, 12, 180)
	_particles.emitting = true
	_smoke.emitting = true
	var mid := sum / maxf(pts.size(), 1.0)
	_light.global_position = mid + Vector3.UP * 0.5
	_light.light_energy = clampf(0.6 + keys.size() * 0.02, 0.6, 3.0)
	_light.omni_range = clampf(4.0 + keys.size() * 0.05, 4.0, 12.0)
	_crackle_t -= 0.3
	if _crackle_t <= 0.0 and pl and mid.distance_to(pl.global_position) < 25.0:
		_crackle_t = 0.6
		Sfx.play("break_wood", mid, -16.0, 0.3, 0.6)
