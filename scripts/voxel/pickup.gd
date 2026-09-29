extends Node3D
## 金币 / 能源掉落：弹出一下，然后自动飞进球体，无需手动拾取（参考《大金刚 蕉力全开》）

const POP_TIME := 0.18
const COLORS := {"coin": Color("ffd23f"), "energy": Color("4dfcff")}

var kind := "coin"
var _vel := Vector3.ZERO
var _age := 0.0
var _speed := 4.0

static var _script: GDScript
static var _energy_mesh: SphereMesh
static var _alive := 0
const MAX_ALIVE := 60   ## 同时飞着的掉落物上限：超出的直接记账，不再生成节点（大破坏时不卡）

static func spawn(parent: Node, k: String, pos: Vector3) -> void:
	if _alive >= MAX_ALIVE:
		if k == "coin":
			GameState.add_coins(1)
		else:
			GameState.add_energy(1)
		return
	if _script == null:
		_script = load("res://scripts/voxel/pickup.gd")
	var p := Node3D.new()
	p.set_script(_script)
	p.set("kind", k)
	parent.add_child(p)
	p.global_position = pos

func _enter_tree() -> void:
	_alive += 1

func _exit_tree() -> void:
	_alive -= 1

func _ready() -> void:
	var mi := MeshInstance3D.new()
	if kind == "coin":
		# Kenney 金币模型（缩到直径约 0.26 米）
		var cm := Kit.mesh(Kit.COIN)
		mi.mesh = cm
		var ab := cm.get_aabb()
		mi.scale = Vector3.ONE * (0.26 / maxf(ab.size.x, ab.size.y))
		mi.position = -ab.get_center() * mi.scale.x
	else:
		if _energy_mesh == null:
			var mat := StandardMaterial3D.new()
			var c: Color = COLORS["energy"]
			mat.albedo_color = c
			mat.emission_enabled = true
			mat.emission = c
			mat.emission_energy_multiplier = 2.0
			_energy_mesh = SphereMesh.new()
			_energy_mesh.radius = 0.1
			_energy_mesh.height = 0.2
			_energy_mesh.radial_segments = 6
			_energy_mesh.rings = 3
			_energy_mesh.material = mat
		mi.mesh = _energy_mesh
	add_child(mi)
	_vel = Vector3(randf_range(-2, 2), randf_range(3, 5), randf_range(-2, 2))

func _process(delta: float) -> void:
	_age += delta
	rotate_y(delta * 8.0)
	var target: Node3D = GameState.player
	if _age < POP_TIME or target == null:
		_vel.y -= 14.0 * delta
		global_position += _vel * delta
		if target == null and _age > 2.0:
			queue_free()
		return
	_speed += 30.0 * delta
	var to := target.global_position - global_position
	var dist := to.length()
	if dist < 0.45 or _age > 2.5:
		_collect()
		return
	global_position += to / dist * minf(_speed * delta, dist)
	scale = Vector3.ONE * clampf(dist, 0.5, 1.0)

func _collect() -> void:
	if kind == "coin":
		GameState.add_coins(1)
		Sfx.play("coin", Vector3.INF, -8.0, 0.03)
	else:
		GameState.add_energy(1)
		Sfx.play("energy", Vector3.INF, -8.0, 0.05)
	queue_free()
