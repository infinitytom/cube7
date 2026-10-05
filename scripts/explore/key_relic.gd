class_name KeyRelic
extends Zone
## 本章的关键道具「进化芯片」：埋在地层或塌方堆里，用回声扫描才找得到。
## 拿到它：① PIX 立刻进化出本章的新能力 ② 能和 Boss 身上的锈封印共鸣，打破封印才能开打。

var chapter := ""
var _model: Node3D
var _t := 0.0

func _init() -> void:
	box_size = Vector3(1.2, 1.2, 1.2)

func _build() -> void:
	add_to_group("scan_target")
	add_to_group("key_relic")
	_model = Node3D.new()
	add_child(_model)
	# 金色的八面体芯片 + 两圈交叉的光环
	var gem := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.3
	sp.height = 0.6
	sp.radial_segments = 4
	sp.rings = 2
	gem.mesh = sp
	var mat := _glow_mat(Color("ffd769"), 2.6)
	mat.albedo_color = Color("fff1b8")
	gem.material_override = mat
	_model.add_child(gem)
	for k in 2:
		var ring := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.44
		tor.outer_radius = 0.49
		tor.rings = 28
		ring.mesh = tor
		ring.material_override = _glow_mat(Color("8ff7ff"), 2.2)
		ring.rotation = Vector3(0.6 + k * 1.2, k * 1.1, 0.0)
		ring.name = "Ring%d" % k
		_model.add_child(ring)
	var light := OmniLight3D.new()
	light.light_color = Color("ffd769")
	light.light_energy = 2.0
	light.omni_range = 3.5
	_model.add_child(light)

func scan_kind() -> String:
	return "key"

func scan_label() -> String:
	return "关键道具 · " + ChapterKey.key_name(chapter)

func _process(delta: float) -> void:
	_t += delta
	_model.position.y = sin(_t * 2.2) * 0.1
	_model.rotation.y += delta * 1.6
	for k in 2:
		var r := _model.get_node_or_null("Ring%d" % k) as Node3D
		if r:
			r.rotation.z += delta * (1.5 + k)

func _on_player_entered() -> void:
	set_deferred("monitoring", false)
	ChapterKey.collect(chapter, global_position)
	var tw := create_tween().set_parallel()
	tw.tween_property(_model, "scale", Vector3.ONE * 2.2, 0.35)
	tw.tween_property(_model, "position:y", 1.6, 0.6)
	tw.chain().tween_callback(queue_free)
