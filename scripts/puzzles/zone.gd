class_name Zone
extends Area3D
## 通用触发区域基类：自动生成盒形碰撞，只检测玩家（层 2）和物件（层 4）

signal player_entered

@export var box_size := Vector3(2, 2, 2)

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 | 4
	monitoring = true
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = box_size
	cs.shape = b
	add_child(cs)
	body_entered.connect(func(body: Node3D) -> void:
		if body == GameState.player:
			player_entered.emit()
			_on_player_entered())
	_build()

func _build() -> void:
	pass

func _on_player_entered() -> void:
	pass

func _glow_mat(c: Color, energy := 2.0, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c, alpha)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
