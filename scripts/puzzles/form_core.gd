class_name FormCore
extends Zone
## 形态核心：拾取后解锁一种新形态。带解锁演出：慢动作、光柱、NOVA 台词、自动变身。

@export var form := 1
@export_multiline var unlock_text := ""

var _model: Node3D
var _beam: MeshInstance3D
var _t := 0.0
var _taken := false

func _build() -> void:
	var c: Color = MorphBall.FORMS[form].color
	# 底座光环
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.7
	tm.outer_radius = 0.85
	tm.material = _glow_mat(c, 2.5)
	ring.mesh = tm
	ring.position.y = -box_size.y * 0.5 + 0.05
	add_child(ring)
	# 光柱
	_beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.7
	cm.height = 6.0
	cm.cap_top = false
	cm.cap_bottom = false
	cm.material = _glow_mat(c, 1.2, 0.18)
	_beam.mesh = cm
	_beam.position.y = 2.0
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	# 漂浮的形态缩影
	_model = Node3D.new()
	add_child(_model)
	var core := MeshInstance3D.new()
	var mesh: Mesh
	match form:
		MorphBall.CUBE:
			var b := BoxMesh.new()
			b.size = Vector3.ONE * 0.5
			mesh = b
		MorphBall.DRILL:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.3
			cone.height = 0.7
			mesh = cone
		_:
			var sm := SphereMesh.new()
			sm.radius = 0.3
			sm.height = 0.6
			mesh = sm
	core.mesh = mesh
	core.material_override = _glow_mat(c, 3.0)
	_model.add_child(core)
	var halo := MeshInstance3D.new()
	var hm := TorusMesh.new()
	hm.inner_radius = 0.5
	hm.outer_radius = 0.56
	hm.material = _glow_mat(Color.WHITE, 2.0)
	halo.mesh = hm
	halo.rotation_degrees.x = 70.0
	_model.add_child(halo)
	var light := OmniLight3D.new()
	light.light_color = c
	light.light_energy = 2.0
	light.omni_range = 5.0
	_model.add_child(light)

func _process(delta: float) -> void:
	_t += delta
	if _model:
		_model.position.y = 0.3 + sin(_t * 2.0) * 0.15
		_model.rotation.y += delta * 1.5

func _on_player_entered() -> void:
	if _taken:
		return
	_taken = true
	var p := GameState.player as MorphBall
	GameState.unlock_form(form)
	Sfx.play("unlock", Vector3.INF, 0.0, 0.0)
	Music.duck(2.5, 0.2)
	Music.set_default("bright")
	# 慢动作 0.8 秒（真实时间）
	Engine.time_scale = 0.25
	get_tree().create_timer(0.2, true, false, true).timeout.connect(func() -> void: Engine.time_scale = 1.0)
	GameState.shake.emit(0.4)
	p.form_locked = false
	p.apply_form(form, true)
	if unlock_text != "":
		GameState.say(unlock_text)
	var tw := create_tween()
	tw.tween_property(_model, "scale", Vector3.ONE * 2.5, 0.25)
	tw.parallel().tween_property(_beam, "scale", Vector3(0.1, 1.5, 0.1), 0.4)
	tw.tween_callback(queue_free)
