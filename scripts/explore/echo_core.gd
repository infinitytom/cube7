class_name EchoCore
extends Zone
## 回声晶核：埋在地层深处的晶洞里，是这颗星球被拆成方块之前的“记忆”。
## 用回声扫描能隔着地层看到它；挖过去、碰到就收下。收集到的晶核是形态进化的材料。

var core_id := ""
var memory := ""          ## 拾取时 NOVA 读出来的一段回声
var locked_hint := ""     ## 需要进化才挖得到时，扫描标记上的提示
var _model: Node3D
var _t := 0.0

func _init() -> void:
	box_size = Vector3(1.0, 1.0, 1.0)

func _build() -> void:
	add_to_group("scan_target")
	_model = Node3D.new()
	add_child(_model)
	# 六棱柱晶体 + 外面一圈慢慢转的光环
	var gem := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.radial_segments = 6
	cyl.rings = 1
	cyl.top_radius = 0.0
	cyl.bottom_radius = 0.16
	cyl.height = 0.26
	var top := MeshInstance3D.new()
	top.mesh = cyl
	top.position.y = 0.2
	var mid := CylinderMesh.new()
	mid.radial_segments = 6
	mid.rings = 1
	mid.top_radius = 0.16
	mid.bottom_radius = 0.16
	mid.height = 0.14
	gem.mesh = mid
	var cyl2 := cyl.duplicate() as CylinderMesh
	cyl2.top_radius = 0.16
	cyl2.bottom_radius = 0.0
	var bot := MeshInstance3D.new()
	bot.mesh = cyl2
	bot.position.y = -0.2
	var mat := _glow_mat(Color("8ff7ff"), 2.4)
	mat.albedo_color = Color("c9fbff")
	for m in [gem, top, bot]:
		(m as MeshInstance3D).material_override = mat
		_model.add_child(m)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.3
	tor.outer_radius = 0.34
	tor.rings = 24
	ring.mesh = tor
	ring.material_override = _glow_mat(Color("ffe08a"), 2.0)
	ring.rotation.x = 0.5
	ring.name = "Ring"
	_model.add_child(ring)
	var light := OmniLight3D.new()
	light.light_color = Color("8ff7ff")
	light.light_energy = 1.4
	light.omni_range = 2.6
	_model.add_child(light)

func scan_kind() -> String:
	return "core"

func scan_label() -> String:
	return locked_hint if locked_hint != "" else "回声晶核"

func _process(delta: float) -> void:
	_t += delta
	_model.position.y = sin(_t * 2.0) * 0.08
	_model.rotation.y += delta * 1.2
	var ring := _model.get_node_or_null("Ring") as Node3D
	if ring:
		ring.rotation.z += delta * 2.0

func _on_player_entered() -> void:
	GameState.add_echo(core_id)
	Sfx.play("echo_core", Vector3.INF, -2.0, 0.0)
	Sfx.play("pix_happy", Vector3.INF, -8.0, 0.05)
	GameState.rumble(0.4, 0.6, 0.25)
	GameState.shake.emit(0.12)
	var avail := Evolutions.cores_available()
	GameState.say("「%s」\n—— 回声晶核 %d / %d（可用于进化：%d 颗）" % [memory, GameState.echo_found, GameState.echo_total, avail])
	var tw := create_tween().set_parallel()
	tw.tween_property(_model, "scale", Vector3.ONE * 1.8, 0.25)
	tw.tween_property(_model, "position:y", 1.2, 0.4)
	tw.chain().tween_callback(queue_free)
	set_deferred("monitoring", false)
