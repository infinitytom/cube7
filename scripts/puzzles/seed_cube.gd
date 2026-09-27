class_name SeedCube
extends Node3D
## 种子方块：方舟引擎把居民封存在里面。发光的半透明方块，里面蜷着一只噗噗。
## 用任何攻击（冲撞 / 钻 / 下砸 / 气浪）打开它：噗噗跳出来、说句话（有自己的拟声）、挥挥手，然后被传送回避难所。

const PUPU_MODELS := ["platformer/character-oobi", "platformer/character-oodi", "platformer/character-ooli", "platformer/character-oopi", "platformer/character-oozi"]
const LINES := [
	["噗！……外面好亮！", "是你把我拼回来的吗？谢谢你，圆圆的小家伙！"],
	["噗噗噗！我还以为要睡一辈子了！", "我要去避难所找妈妈了——你也要加油哦！"],
	["哇，我的脚……是方块形状的！", "嘿嘿，其实也挺可爱的。谢谢你，PIX！"],
]

@export var seed_id := ""
@export var line_index := 0

var _shell: MeshInstance3D
var _pupu: Node3D
var _area: Area3D
var _opened := false
var _t := 0.0
var _bubble: Label3D

func _ready() -> void:
	add_to_group("seed_cube")
	# 噗噗（缩在方块里）
	_pupu = Kit.model(PUPU_MODELS[absi(hash(seed_id)) % PUPU_MODELS.size()])
	var b := Kit.bounds(_pupu)
	var s := 0.55 / maxf(b.size.y, 0.01)
	_pupu.scale = Vector3.ONE * s
	_pupu.position = Vector3(0, 0.25 - b.position.y * s, 0)
	add_child(_pupu)
	# 半透明的发光方块外壳
	_shell = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.95
	_shell.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 1.0, 0.86, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color("7dffc8")
	m.emission_energy_multiplier = 0.8
	m.rim_enabled = true
	m.rim = 1.0
	m.roughness = 0.1
	_shell.material_override = m
	_shell.position.y = 0.55
	add_child(_shell)
	var light := OmniLight3D.new()
	light.light_color = Color("7dffc8")
	light.light_energy = 1.0
	light.omni_range = 3.0
	light.position.y = 0.6
	add_child(light)
	# 碰撞：先挡住球，打开后移除
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * 0.95
	cs.shape = box
	cs.position.y = 0.55
	body.add_child(cs)
	add_child(body)
	body.name = "Body"
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	var as_ := CollisionShape3D.new()
	var ab := BoxShape3D.new()
	ab.size = Vector3.ONE * 1.6
	as_.shape = ab
	as_.position.y = 0.55
	_area.add_child(as_)
	add_child(_area)
	_bubble = Label3D.new()
	_bubble.font = UIKit.font(true)
	_bubble.font_size = 44
	_bubble.outline_size = 14
	_bubble.modulate = Color.WHITE
	_bubble.outline_modulate = Color("2a2c6b")
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.no_depth_test = true
	_bubble.pixel_size = 0.005
	_bubble.position.y = 1.7
	_bubble.width = 420
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.visible = false
	add_child(_bubble)
	_t = randf() * TAU

func _process(delta: float) -> void:
	_t += delta
	if not _opened:
		_shell.rotation.y = sin(_t * 0.8) * 0.15
		_shell.position.y = 0.55 + sin(_t * 2.0) * 0.04
		_pupu.rotation.y = sin(_t * 0.5) * 0.6
		_check_hit()

func _check_hit() -> void:
	var p := GameState.player as MorphBall
	if p == null or not _area.overlaps_body(p):
		return
	if p.attack != "":
		open()

## 气泡的气浪也能打开（MorphBall 里遍历 seed_cube 组调用）
func on_wave(_from: Vector3) -> void:
	open()

func open() -> void:
	if _opened:
		return
	_opened = true
	($Body as StaticBody3D).queue_free()
	Sfx.play("break_glass", global_position, 0.0, 0.05)
	Sfx.play("unlock", Vector3.INF, -6.0, 0.0)
	GameState.shake.emit(0.2)
	var tw := create_tween()
	tw.tween_property(_shell, "scale", Vector3.ONE * 1.3, 0.1)
	tw.tween_property(_shell, "scale", Vector3.ZERO, 0.15)
	# 噗噗跳出来
	var jump := create_tween()
	jump.tween_property(_pupu, "position:y", _pupu.position.y + 0.9, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	jump.tween_property(_pupu, "position:y", _pupu.position.y - 0.2, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	# 转向 PIX
	var p := GameState.player as Node3D
	if p:
		var d := p.global_position - global_position
		d.y = 0.0
		if d.length() > 0.1:
			_pupu.look_at(_pupu.global_position - d, Vector3.UP)
	GameState.add_seed(seed_id)
	_talk()

func _talk() -> void:
	var lines: Array = LINES[line_index % LINES.size()]
	await get_tree().create_timer(0.5).timeout
	for l in lines:
		await _say(l)
		await get_tree().create_timer(1.1).timeout
	# 挥手告别，然后被传送走
	var wave := create_tween().set_loops(3)
	wave.tween_property(_pupu, "rotation:z", 0.25, 0.12)
	wave.tween_property(_pupu, "rotation:z", -0.25, 0.12)
	await wave.finished
	_bubble.visible = false
	_beam_out()

func _say(text: String) -> void:
	_bubble.visible = true
	_bubble.text = ""
	for i in text.length():
		_bubble.text = text.substr(0, i + 1)
		if i % 2 == 0 and not text[i] in "，。！？…—":
			Sfx.play("voice_pupu", global_position, -4.0, 0.2)
		await get_tree().create_timer(0.045).timeout

func _beam_out() -> void:
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35
	cm.bottom_radius = 0.35
	cm.height = 8.0
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.albedo_color = Color(0.5, 1.0, 0.8, 0.0)
	cm.material = bm
	beam.mesh = cm
	beam.position.y = 4.0
	add_child(beam)
	Sfx.play("checkpoint", global_position, -2.0, 0.0)
	var tw := create_tween()
	tw.tween_property(bm, "albedo_color:a", 0.7, 0.25)
	tw.parallel().tween_property(_pupu, "scale", Vector3(_pupu.scale.x * 0.2, _pupu.scale.y * 2.5, _pupu.scale.z * 0.2), 0.35).set_delay(0.15)
	tw.parallel().tween_property(_pupu, "position:y", _pupu.position.y + 3.0, 0.35).set_delay(0.15)
	tw.tween_property(bm, "albedo_color:a", 0.0, 0.4)
	tw.tween_callback(queue_free)
