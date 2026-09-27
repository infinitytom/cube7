extends CanvasLayer
## 场景流程（自动加载为 Flow）：淡入淡出切换场景，并在场景之间传递“怎么进入游戏”。
##   mode = "new"      新游戏（播放开场演出）
##   mode = "continue" 继续游戏（回到存档的检查点）
##   mode = "debug"    命令行测试

var mode := "debug"
var _fade: ColorRect
var busy := false

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.03, 0.06, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

func fade_to(alpha: float, secs := 0.5) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, secs)
	await tw.finished

func goto(scene: String, how := "") -> void:
	if busy:
		return
	busy = true
	if how != "":
		mode = how
	await fade_to(1.0, 0.45)
	get_tree().paused = false
	get_tree().change_scene_to_file(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	busy = false
	fade_to(0.0, 0.6)

func goto_game(how: String) -> void:
	goto("res://scenes/main.tscn", how)

func goto_title() -> void:
	goto("res://scenes/title.tscn", "")
