extends Node
## 编辑器截图：--editor --debugscript=res://scripts/debug/shots_editor.gd --out=<目录>
func _ready() -> void:
	var out := "/tmp/shots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(2.5).timeout
	var ed: LevelEditor = get_parent().find_children("*", "LevelEditor", false, false)[0]
	for k in 4:
		ed._place()
		ed._move_cursor(Vector3i(1, 0, 0))
	ed._select_slot(9)
	ed._move_cursor(Vector3i(0, 0, 3))
	ed._place()
	ed._select_slot(3)
	ed._anchor = ed.cursor + Vector3i(-4, 0, -3)
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("editor1.png"))
	ed._anchor = Vector3i(-999, 0, 0)
	ed._open_picker()
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("editor2.png"))
	get_tree().quit()
