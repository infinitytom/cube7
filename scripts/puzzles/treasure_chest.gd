class_name TreasureChest
extends Zone
## 藏在探索点的宝箱：滚过去碰一下就打开，喷出一堆体素能量（金币）。存档里记住开没开过。

@export var chest_id := ""
@export var coins := 30
@export var energy := 4
@export var line := ""

var _chest: Node3D
var _opened := false
var _t := 0.0
var _glow: OmniLight3D

func _build() -> void:
	_chest = Kit.model("platformer/chest")
	var b := Kit.bounds(_chest)
	var s := 0.95 / maxf(b.size.x, b.size.z)
	_chest.scale = Vector3.ONE * s
	_chest.position.y = -box_size.y * 0.5 - b.position.y * s
	add_child(_chest)
	_glow = OmniLight3D.new()
	_glow.light_color = Color("ffd23f")
	_glow.light_energy = 0.8
	_glow.omni_range = 3.0
	_glow.position.y = -box_size.y * 0.5 + 0.8
	add_child(_glow)
	if chest_id != "" and SaveGame.data.get("chests", []).has(chest_id):
		_opened = true
		_chest.rotation.x = 0.0
		_glow.visible = false

func _process(delta: float) -> void:
	_t += delta
	if not _opened:
		_chest.rotation.y = sin(_t * 1.3) * 0.08
		_glow.light_energy = 0.6 + 0.3 * sin(_t * 3.0)

func _on_player_entered() -> void:
	if _opened:
		return
	_opened = true
	_glow.visible = false
	Sfx.play("success", global_position, -2.0, 0.0)
	Sfx.play("unlock", global_position, -4.0, 0.0)
	var tw := create_tween()
	tw.tween_property(_chest, "scale", _chest.scale * 1.25, 0.12)
	tw.tween_property(_chest, "scale", _chest.scale, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var base := global_position + Vector3.UP * 0.2
	for i in coins:
		PickupScript.spawn(get_parent(), "coin", base)
	for i in energy:
		PickupScript.spawn(get_parent(), "energy", base)
	if line != "":
		GameState.say(line)
	if chest_id != "":
		var list: Array = SaveGame.data.get("chests", [])
		if not list.has(chest_id):
			list.append(chest_id)
		SaveGame.data["chests"] = list

const PickupScript := preload("res://scripts/voxel/pickup.gd")
