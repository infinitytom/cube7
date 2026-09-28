extends Node3D
## 游戏主场景：搭关卡 → 按进入方式（新游戏 / 继续 / 测试）放主角 → 开始。
## 命令行：--level=test 测试房间；--autotest / --autotest=greenhouse 自动测试；--shots=<目录> 截图；--probe 调试

@onready var world: VoxelWorld = $VoxelWorld
@onready var player: MorphBall = $Player
@onready var hud: Hud = $Hud
var level: Node3D

func _ready() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var use_test := args.has("--level=test") or args.has("--autotest")
	var gh_test := args.has("--autotest=greenhouse")
	var gw_test := args.has("--autotest=gearworks")
	var ch := int(args.filter(func(a: String) -> bool: return a.begins_with("--chapter=")).map(func(a: String) -> String: return a.substr(10)).front()) if args.any(func(a: String) -> bool: return a.begins_with("--chapter=")) else 0
	if ch == 0:
		ch = Flow.chapter if Flow.chapter > 0 else int(SaveGame.data.get("chapter", 1)) if not SaveGame.data.is_empty() else 1
	if gh_test:
		ch = 1
	if args.has("--autotest=gearworks"):
		ch = 2
	# 其他章节：--autotest=<章节 id> → scripts/debug/autotest_<id>.gd
	var ch_test := ""
	for a in args:
		if a.begins_with("--autotest=") and not gh_test and not gw_test:
			ch_test = a.substr(11)
			for i in Chapters.count():
				if Chapters.LIST[i].id == ch_test:
					ch = i + 1
	Flow.chapter = 0
	GameState.chapter = ch
	var editor_mode := Flow.mode == "editor" or args.has("--editor")
	if editor_mode:
		level = EditorLevel.new()
	else:
		level = (TestRoom.new() if use_test else Chapters.make_level(ch)) as Node3D
	level.name = "Level"
	level.set("world_path", NodePath("../VoxelWorld"))
	add_child(level)
	level.call("build")
	world.track_damage = true
	player.world = world
	player.apply_form(MorphBall.BALL, false)
	player.respawn_at(level.call("spawn_position"), -1, false)

	if editor_mode:
		var ed := LevelEditor.new()
		add_child(ed)
		for a in args:
			if a.begins_with("--debugscript="):
				_attach(a.substr(14))
		return
	if ch_test != "":
		_attach("res://scripts/debug/autotest_%s.gd" % ch_test)
		return
	if args.has("--autotest") or gh_test or gw_test:
		_attach("res://scripts/debug/autotest_greenhouse.gd" if gh_test else ("res://scripts/debug/autotest_gearworks.gd" if gw_test else "res://scripts/debug/autotest.gd"))
		return
	if args.any(func(a: String) -> bool: return a.begins_with("--shots")):
		_attach("res://scripts/debug/screenshots.gd")
		return
	for a in args:
		if a.begins_with("--debugscript="):
			_attach(a.substr(14))
			return
	if args.has("--probe"):
		_attach("res://scripts/debug/probe.gd")
		return

	match Flow.mode:
		"continue":
			_continue()
		"new":
			_new_game()
		"next":
			_next_chapter()
		_:
			_start_play()

func _attach(path: String) -> void:
	var n := Node.new()
	n.set_script(load(path))
	add_child(n)

func _continue() -> void:
	var d := SaveGame.data
	if level.has_method("apply_save"):
		level.call("apply_save", d)
	var cp = d.get("checkpoint", null)
	if cp is Array and cp.size() == 3:
		var pos := Vector3(cp[0], cp[1], cp[2])
		GameState.set_checkpoint(pos, int(d.get("checkpoint_form", -1)))
		player.respawn_at(pos, -1, false)
	_start_play(true)

func _new_game() -> void:
	if level.has_method("intro_shots") and not bool(SaveGame.data.get("intro_seen", false)):
		hud.visible = false
		player.freeze = true
		player.teleport(level.call("spawn_position"))
		var marker := level.get_node_or_null("ObjectiveMarker") as Node3D
		if marker:
			marker.visible = false
		Music.play_cue("intro_cg")
		var cs := Cutscene.new()
		cs.shots = level.call("intro_shots")
		cs.event.connect(func(n: String) -> void:
			if level.has_method("cutscene_event"):
				level.call("cutscene_event", n))
		add_child(cs)
		cs.play()
		await cs.finished
		Music.stop_cue(1.5)
		Music.play_area(Chapters.info(GameState.chapter).music)
		if level.has_method("cutscene_event"):
			level.call("cutscene_event", "end")
		SaveGame.data["intro_seen"] = true
		SaveGame.write()
		player.freeze = false
		hud.visible = true
		if marker:
			marker.visible = true
		Music.set_override("")
	_start_play()

## 从上一章结算画面进入新的一章：带上金币和形态，播一小段抵达演出
func _next_chapter() -> void:
	var d := SaveGame.data
	GameState.coins = int(d.get("coins", 0))
	GameState.coins_changed.emit(GameState.coins)
	if level.has_method("apply_save"):
		level.call("apply_save", d)
	if level.has_method("arrival_shots"):
		hud.visible = false
		player.freeze = true
		player.teleport(level.call("spawn_position"))
		var cs := Cutscene.new()
		cs.shots = level.call("arrival_shots")
		add_child(cs)
		cs.play()
		await cs.finished
		player.freeze = false
		hud.visible = true
	_start_play()

func _start_play(resumed := false) -> void:
	if not resumed and level.has_method("spawn_yaw") and GameState.camera:
		GameState.camera.yaw = level.call("spawn_yaw")
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var info := Chapters.info(GameState.chapter)
	hud.show_area_title(info.num, info.title, "继续旅程" if resumed else "")
