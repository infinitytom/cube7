extends "res://scripts/debug/screenshots.gd"
## 菜单截图：--level=test --debugscript=res://scripts/debug/shots_menus.gd --out=<目录>

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = get_parent()
	_go()

func _go() -> void:
	await get_tree().create_timer(2.0).timeout
	var menu: PauseMenu = get_tree().current_scene.find_children("*", "PauseMenu", true, false)[0]
	GameState.coins = 420
	menu.open()
	await get_tree().create_timer(0.3, true, false, true).timeout
	await _save("m1_pause")
	menu._panel.visible = false
	menu._upgrades.open()
	await get_tree().create_timer(0.3, true, false, true).timeout
	await _save("m2_upgrades")
	menu._upgrades.visible = false
	menu._settings.open()
	await get_tree().create_timer(0.3, true, false, true).timeout
	await _save("m3_settings")
	get_tree().quit()
