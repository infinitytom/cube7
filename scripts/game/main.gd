extends Node3D
## 主场景：选关卡 → 搭建 → 放主角 → 启动。
## 命令行参数：--level=test 进入机制测试房间；--autotest 自动测试（使用测试房间）；--shots=<目录> 截图

@onready var world: VoxelWorld = $VoxelWorld
@onready var player: MorphBall = $Player
var level: Node3D

func _ready() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var use_test := args.has("--level=test") or args.has("--autotest")
	var gh_test := args.has("--autotest=greenhouse")
	level = (TestRoom.new() if use_test else AreaGreenhouse.new()) as Node3D
	level.name = "Level"
	level.set("world_path", NodePath("../VoxelWorld"))
	add_child(level)
	level.call("build")
	player.world = world
	player.apply_form(MorphBall.BALL, false)
	player.respawn_at(level.call("spawn_position"), -1, false)
	if args.has("--autotest") or gh_test:
		var t := Node.new()
		t.set_script(load("res://scripts/debug/autotest_greenhouse.gd" if gh_test else "res://scripts/debug/autotest.gd"))
		add_child(t)
	elif args.has("--probe"):
		var pr := Node.new()
		pr.set_script(load("res://scripts/debug/probe.gd"))
		add_child(pr)
	elif args.any(func(a: String) -> bool: return a.begins_with("--shots")):
		var s := Node.new()
		s.set_script(load("res://scripts/debug/screenshots.gd"))
		add_child(s)
	elif DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
