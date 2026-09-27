extends Node3D
## 主场景：搭关卡 → 放主角 → 启动。带 --autotest 参数运行时会挂上自动测试脚本。

@onready var world: VoxelWorld = $VoxelWorld
@onready var level: TestRoom = $TestRoom
@onready var player: MorphBall = $Player

func _ready() -> void:
	level.build()
	player.world = world
	player.respawn_at(level.spawn_position(), -1, false)
	if "--autotest" in OS.get_cmdline_user_args():
		var t := Node.new()
		t.set_script(load("res://scripts/debug/autotest.gd"))
		add_child(t)
	elif Array(OS.get_cmdline_user_args()).any(func(a: String) -> bool: return a.begins_with("--shots")):
		var s := Node.new()
		s.set_script(load("res://scripts/debug/screenshots.gd"))
		add_child(s)
	elif DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
