class_name MemoryFragment
extends Zone
## 记忆碎片：隐藏收集品，拾取后在对话框显示一段科学家日志

@export_multiline var log_text := ""
var _model: Node3D
var _t := 0.0

func _build() -> void:
	_model = Node3D.new()
	add_child(_model)
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.36, 0.36, 0.08)
	mi.mesh = b
	mi.material_override = _glow_mat(Color("b28dff"), 2.2)
	_model.add_child(mi)
	var inner := MeshInstance3D.new()
	var b2 := BoxMesh.new()
	b2.size = Vector3(0.2, 0.12, 0.1)
	inner.mesh = b2
	inner.material_override = _glow_mat(Color.WHITE, 3.0)
	_model.add_child(inner)
	var light := OmniLight3D.new()
	light.light_color = Color("b28dff")
	light.light_energy = 1.2
	light.omni_range = 3.0
	_model.add_child(light)

func _process(delta: float) -> void:
	_t += delta
	_model.position.y = sin(_t * 2.5) * 0.12
	_model.rotation.y += delta * 2.0

func _on_player_entered() -> void:
	GameState.add_fragment(log_text)
	Sfx.play("fragment", Vector3.INF, -2.0, 0.0)
	GameState.say("找到记忆碎片（%d/%d）——「%s」" % [GameState.fragments, GameState.fragments_total, log_text])
	GameState.shake.emit(0.15)
	queue_free()
