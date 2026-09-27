class_name PressurePlate
extends Zone
## 压力板：区域内刚体总质量超过阈值时触发，打开闸门（触发后保持打开）

signal pressed

@export var mass_threshold := 2.8
var world: VoxelWorld
var gate_blocks: Array[Vector3i] = []
var done := false
var _hint_t := 0.0

func _physics_process(delta: float) -> void:
	if done:
		return
	var total := 0.0
	var player_on := false
	for b in get_overlapping_bodies():
		if b is RigidBody3D and not (b is UsableItem and b.held):
			total += b.mass
			if b == GameState.player:
				player_on = true
	if total >= mass_threshold:
		done = true
		for p in gate_blocks:
			world.try_break_any(p)
		GameState.shake.emit(0.3)
		GameState.say("咔哒——闸门开了。重量才是正义。")
		pressed.emit()
	elif player_on:
		_hint_t -= delta
		if _hint_t <= 0.0:
			_hint_t = 6.0
			GameState.say("压力板纹丝不动……这个形态太轻了，换个重一点的？")
