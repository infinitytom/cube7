class_name CoinChallenge
extends Zone
## 限时收集挑战（马里奥的红币）：踩下按钮后，周围出现一圈蓝色金币，限时内全部收集就能打开宝箱。

@export var time_limit := 18.0
var coin_positions: Array[Vector3] = []
var chest_position := Vector3.ZERO
var _button: Node3D
var _active := false
var _done := false
var _left := 0.0
var _coins: Array[Node3D] = []
var _got := 0

func _build() -> void:
	_button = Kit.model("platformer/button-round")
	var b := Kit.bounds(_button)
	var s := 0.9 / maxf(b.size.x, b.size.z)
	_button.scale = Vector3.ONE * s
	_button.position.y = -box_size.y * 0.5 - b.position.y * s
	add_child(_button)

func _on_player_entered() -> void:
	if _active or _done:
		return
	_active = true
	_left = time_limit * 1.4    # 节奏放慢：限时挑战多给 40% 时间
	_got = 0
	Sfx.play("unlock", Vector3.INF, -4.0, 0.0)
	var tw := create_tween()
	tw.tween_property(_button, "scale:y", _button.scale.y * 0.4, 0.1)
	GameState.say("限时挑战！%d 秒内收集全部 %d 枚蓝色金币！" % [int(time_limit * 1.4), coin_positions.size()])
	for p in coin_positions:
		var c := _make_coin()
		get_parent().add_child(c)
		c.global_position = p
		_coins.append(c)
	GameState.challenge_changed.emit(true, _left, _got, coin_positions.size())

func _make_coin() -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var cm := Kit.mesh("platformer/coin-silver")
	mi.mesh = cm
	var ab := cm.get_aabb()
	mi.scale = Vector3.ONE * (0.5 / maxf(ab.size.x, ab.size.y))
	mi.position = -ab.get_center() * mi.scale.x
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("62dcff")
	m.emission_enabled = true
	m.emission = Color("62dcff")
	m.emission_energy_multiplier = 1.2
	mi.material_override = m
	n.add_child(mi)
	return n

func _process(delta: float) -> void:
	if not _active:
		return
	_left -= delta
	var pl := GameState.player as Node3D
	for c in _coins.duplicate():
		if not is_instance_valid(c):
			continue
		c.rotation.y += delta * 4.0
		if pl and pl.global_position.distance_to(c.global_position) < 1.1:
			_coins.erase(c)
			c.queue_free()
			_got += 1
			Sfx.play("coin", Vector3.INF, -4.0, 0.0, 1.0 + _got * 0.08)
			FloatText.spawn(get_parent(), c.global_position, "%d / %d" % [_got, coin_positions.size()], UIKit.ACCENT, 44, 0.8)
	GameState.challenge_changed.emit(true, _left, _got, coin_positions.size())
	if _got >= coin_positions.size():
		_finish(true)
	elif _left <= 0.0:
		_finish(false)

func _finish(ok: bool) -> void:
	_active = false
	GameState.challenge_changed.emit(false, 0.0, _got, coin_positions.size())
	for c in _coins:
		if is_instance_valid(c):
			c.queue_free()
	_coins.clear()
	if ok:
		_done = true
		Sfx.play("success", Vector3.INF, 0.0, 0.0)
		GameState.say("挑战成功！宝箱打开了——里面全是体素能量。")
		_open_chest()
	else:
		Sfx.play("respawn", Vector3.INF, -6.0, 0.0)
		GameState.say("时间到……再踩一次按钮就能重来。")
		var tw := create_tween()
		tw.tween_property(_button, "scale:y", _button.scale.y / 0.4, 0.2)

func _open_chest() -> void:
	var chest := Kit.model("platformer/chest")
	var b := Kit.bounds(chest)
	var s := 1.0 / maxf(b.size.x, b.size.z)
	chest.scale = Vector3.ZERO
	get_parent().add_child(chest)
	chest.global_position = chest_position - Vector3(0, b.position.y * s, 0)
	var tw := chest.create_tween()
	tw.tween_property(chest, "scale", Vector3.ONE * s, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		for i in 25:
			PickupScript.spawn(get_parent(), "coin", chest_position + Vector3.UP * 0.8)
		for i in 5:
			PickupScript.spawn(get_parent(), "energy", chest_position + Vector3.UP * 0.8))

const PickupScript := preload("res://scripts/voxel/pickup.gd")
