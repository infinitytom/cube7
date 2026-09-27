class_name Checkpoint
extends Zone
## 检查点信标：经过即记录复活位置

@export var lock_form := -1          ## 复活时切换到的形态（-1 不变）
@export var locks := false           ## 复活后是否锁定形态（平衡轨道用）
var _active := false
var _beacon: MeshInstance3D
var _flag: Node3D

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
	# Kenney 小旗：没激活时旗子半降，激活后“唰”地升起
	_flag = Kit.model(Kit.FLAG)
	var b := Kit.bounds(_flag)
	var s := 1.4 / maxf(b.size.y, 0.01)
	_flag.scale = Vector3.ONE * s
	_flag.position = Vector3(box_size.x * 0.35, -box_size.y * 0.5 - b.position.y * s, 0)
	add_child(_flag)
	_flag.scale.y = s * 0.55

func _on_player_entered() -> void:
	GameState.set_checkpoint(global_position + Vector3.UP * 0.2, lock_form, locks)
	SaveGame.save_checkpoint(global_position + Vector3.UP * 0.2, lock_form)
	if not _active:
		_active = true
		Sfx.play("checkpoint", global_position, -6.0, 0.0)
		Sfx.play("pix_happy", Vector3.INF, -12.0, 0.1)
		(_beacon.mesh as CylinderMesh).material = _glow_mat(Color("66daa3"), 0.7)
		var tw := create_tween()
		tw.tween_property(_flag, "scale:y", _flag.scale.x, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
