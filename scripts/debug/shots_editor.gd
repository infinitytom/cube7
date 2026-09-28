extends Node
## 编辑器截图：--editor --debugscript=res://scripts/debug/shots_editor.gd
func _ready() -> void:
	await get_tree().create_timer(2.5).timeout
	var ed: LevelEditor = get_parent().find_children("*", "LevelEditor", false, false)[0]
	for k in 4:
		ed._place()
		ed._move_cursor(Vector3i(1, 0, 0))
	ed._toggle_cat()
	ed.sel[1] = 9
	ed._move_cursor(Vector3i(0, 0, 3))
	ed._place()
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/shots/editor1.png")
	ed._open_menu()
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/shots/editor2.png")
	get_tree().quit()
