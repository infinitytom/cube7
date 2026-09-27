class_name Checkpoint
extends Zone
## 检查点信标：经过即记录复活位置

@export var lock_form := -1          ## 复活时切换到的形态（-1 不变）
@export var locks := false           ## 复活后是否锁定形态（平衡轨道用）
var _active := false
var _beacon: MeshInstance3D

func _build() -> void:
	# 地面上的发光圆盘，激活后变绿
	_beacon = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.55
	cm.bottom_radius = 0.55
	cm.height = 0.04
	cm.radial_segments = 24
	cm.material = _glow_mat(Color("6b7a99"), 0.2)
	_beacon.mesh = cm
	_beacon.position = Vector3(0, -box_size.y * 0.5 + 0.03, 0)
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beacon)

func _on_player_entered() -> void:
	GameState.set_checkpoint(global_position + Vector3.UP * 0.2, lock_form, locks)
	if not _active:
		_active = true
		(_beacon.mesh as CylinderMesh).material = _glow_mat(Color("5dffb0"), 0.7)
