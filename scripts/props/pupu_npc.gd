class_name PupuNPC
extends Node3D
## 噗噗居民（已经被救出来的噗噗，回到了城里）：蹦蹦跳跳，PIX 靠近时冒出一句话，有自己的拟声。

const MODELS := ["platformer/character-oobi", "platformer/character-oodi", "platformer/character-ooli", "platformer/character-oopi", "platformer/character-oozi"]

var lines: PackedStringArray = []
var model_i := 0
var wander := 1.2
var _model: Node3D
var _bubble: Label3D
var _t := 0.0
var _talk_t := 0.0
var _line := 0
var _home := Vector3.ZERO
var _hop := 0.0

func _ready() -> void:
	_model = Kit.model(MODELS[model_i % MODELS.size()])
	var b := Kit.bounds(_model)
	var s := 0.6 / maxf(b.size.y, 0.01)
	_model.scale = Vector3.ONE * s
	_model.position.y = -b.position.y * s
	add_child(_model)
	_bubble = Label3D.new()
	_bubble.font = UIKit.font(true)
	_bubble.font_size = 40
	_bubble.outline_size = 12
	_bubble.outline_modulate = Color("2a2c6b")
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.no_depth_test = true
	_bubble.pixel_size = 0.005
	_bubble.position.y = 1.2
	_bubble.width = 420
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.visible = false
	add_child(_bubble)
	_t = randf() * 10.0

var _home_set := false

func _process(delta: float) -> void:
	if not _home_set:
		_home_set = true
		_home = position
	_t += delta
	_talk_t -= delta
	# 原地小跳、左右张望
	_hop = maxf(0.0, sin(_t * 3.0))
	_model.rotation.y = sin(_t * 0.7) * 0.8
	position = _home + Vector3(sin(_t * 0.23) * wander, _hop * 0.12, cos(_t * 0.17) * wander)
	var p := GameState.player as Node3D
	if p == null or lines.is_empty():
		return
	var d := p.global_position.distance_to(global_position)
	if d < 2.6 and _talk_t <= 0.0:
		_talk_t = 5.0
		_bubble.text = lines[_line % lines.size()]
		_line += 1
		_bubble.visible = true
		Sfx.play("voice_pupu", global_position, -4.0, 0.2, randf_range(0.9, 1.3))
		look_at(Vector3(p.global_position.x, global_position.y, p.global_position.z), Vector3.UP)
	elif d > 4.0 or _talk_t < 1.5:
		_bubble.visible = false
