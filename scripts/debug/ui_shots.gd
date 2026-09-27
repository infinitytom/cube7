extends Node
## 界面截图：godot --path . --rendering-driver opengl3 -- --uishots=<目录>
## 走一遍 标题 → 主菜单 → 存档位 → 设置 → 新游戏开场 → HUD → 暂停菜单

var out_dir := "/tmp/uishots"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uishots="):
			out_dir = a.substr(10)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true).timeout

func _save(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
	print("saved ", n)

func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var r := e.duplicate() as InputEventKey
	r.pressed = false
	Input.parse_input_event(r)
	await get_tree().process_frame

func _run() -> void:
	for i in SaveGame.SLOTS:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_%d.json" % i))
	await _wait(3.0)
	await _save("u01_title")
	await _key(KEY_SPACE)
	await _wait(0.8)
	await _save("u02_menu")
	var title := get_tree().current_scene
	title.call("_open_slots", "new")
	await _wait(0.6)
	await _save("u03_slots")
	title.get("_slots").queue_free()
	title.set("_state", "settings")
	title.call("_logo_show", false)
	(title.get("_settings") as Control).call("open")
	await _wait(0.5)
	await _save("u04_settings")
	title.call("_start_new", 0)
	await _wait(2.0)
	for t in [1.5, 5.0, 7.0, 5.0, 6.0, 6.0]:
		await _wait(t)
		await _save("u05_cut_%.0f" % Time.get_ticks_msec())
	# 等开场结束
	while get_tree().current_scene.get_node_or_null("Hud") and not get_tree().current_scene.get_node("Hud").visible:
		await _wait(0.5)
	await _wait(1.2)
	await _save("u06_hud_title")
	await _wait(4.0)
	GameState.nova_say.emit("先离开这个坑。温室和中枢塔都在东边……")
	await _wait(2.0)
	await _save("u07_hud_nova")
	var hud := get_tree().current_scene.get_node("Hud")
	(hud.get("_pause") as Node).call("open")
	await _wait(0.6)
	await _save("u08_pause")
	get_tree().quit()
