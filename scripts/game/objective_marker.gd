class_name ObjectiveMarker
extends Node3D
## 目标标记：远处可见的光柱 + 漂浮的菱形，靠近后淡出。马里奥式的“目标始终看得见”。

var _beam: MeshInstance3D
var _gem: MeshInstance3D
var _mat_beam: StandardMaterial3D
var _mat_gem: StandardMaterial3D
var _t := 0.0

func _ready() -> void:
	_mat_beam = StandardMaterial3D.new()
	_mat_beam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_beam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_beam.albedo_color = Color(1.0, 0.85, 0.4, 0.22)
	_mat_beam.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_beam.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.35
	cm.height = 22.0
	cm.cap_top = false
	cm.cap_bottom = false
	cm.material = _mat_beam
	_beam.mesh = cm
	_beam.position.y = 11.0
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	_mat_gem = StandardMaterial3D.new()
	_mat_gem.albedo_color = Color("ffd166")
	_mat_gem.emission_enabled = true
	_mat_gem.emission = Color("ffb400")
	_mat_gem.emission_energy_multiplier = 2.5
	_mat_gem.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_gem = MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.5, 0.6, 0.5)
	pm.material = _mat_gem
	_gem.mesh = pm
	_gem.rotation_degrees.z = 180.0
	add_child(_gem)
	GameState.objective_changed.connect(_on_objective)
	_on_objective(GameState.objective_index, GameState.objective_text, GameState.objective_pos)

func _on_objective(_i: int, _t2: String, pos: Vector3) -> void:
	visible = pos != Vector3.INF
	if visible:
		global_position = pos

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_gem.position.y = 2.2 + sin(_t * 2.5) * 0.25
	_gem.rotation.y += delta * 1.8
	var pl: Node3D = GameState.player
	var a := 1.0
	if pl:
		var d := pl.global_position.distance_to(global_position)
		a = clampf((d - 3.0) / 8.0, 0.0, 1.0)
	_mat_beam.albedo_color.a = 0.22 * a
	_mat_gem.albedo_color.a = maxf(a, 0.15)
