class_name MemoryFragment
extends Zone
## 记忆碎片：隐藏收集品，拾取后在对话框显示一段科学家日志

@export_multiline var log_text := ""
var frag_id := ""
var _model: Node3D
var _t := 0.0

func _build() -> void:
	_model = Node3D.new()
	add_child(_model)
	var crystal := Kit.model(Kit.CRYSTAL)
	var bb := Kit.bounds(crystal)
	var s := 0.55 / maxf(bb.size.y, 0.01)
	crystal.scale = Vector3.ONE * s
	crystal.position = -bb.get_center() * s
	_model.add_child(crystal)
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
	if frag_id != "" and not SaveGame.data.is_empty():
		(SaveGame.data["fragments"] as Array).append(frag_id)
		SaveGame.write()
	Sfx.play("fragment", Vector3.INF, -2.0, 0.0)
	Sfx.play("pix_curious", Vector3.INF, -8.0, 0.05)
	GameState.say("找到记忆碎片（%d/%d）——「%s」" % [GameState.fragments, GameState.fragments_total, log_text])
	GameState.shake.emit(0.15)
	queue_free()
