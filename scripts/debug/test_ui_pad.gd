extends Node
## 手柄菜单测试：--chapter=1 --debugscript=res://scripts/debug/test_ui_pad.gd

var fails: Array[String] = []

func check(cond: bool, msg: String) -> void:
	print(("  [PASS] " if cond else "  [FAIL] ") + msg)
	if not cond:
		fails.append(msg)

func press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	Input.parse_input_event(r)
	await get_tree().process_frame
	await get_tree().process_frame

func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	print("===== 手柄菜单 / 改装测试 =====")
	check(InputMap.action_has_event("ui_accept", _jb(JOY_BUTTON_A)) and InputMap.action_has_event("ui_cancel", _jb(JOY_BUTTON_B)), "✕/A 确认、○/B 返回已绑定")
	var pm := get_tree().current_scene.find_children("*", "PauseMenu", true, false)
	check(not pm.is_empty(), "有暂停菜单")
	if pm.is_empty():
		get_tree().quit()
		return
	var menu: PauseMenu = pm[0]
	menu.open()
	await get_tree().process_frame
	await get_tree().process_frame
	var f := get_viewport().gui_get_focus_owner()
	check(f is Button and (f as Button).text == "继续游戏", "打开菜单，焦点在「继续游戏」")
	# 下移到「改装 PIX」再确认
	for k in 3:
		await press("ui_down")
	f = get_viewport().gui_get_focus_owner()
	check(f is Button and (f as Button).text == "改装 PIX", "十字键下移三次到「改装 PIX」（%s）" % (f.get("text") if f else "无"))
	await press("ui_accept")
	await get_tree().process_frame
	check(menu._upgrades.visible, "✕/A 打开改装面板")
	GameState.coins = 1000
	var sh0 := GameState.max_shield
	f = get_viewport().gui_get_focus_owner()
	check(f != null and f.has_meta("id") and f.get_meta("id") == "shield", "焦点在第一项「护盾扩容」")
	await press("ui_accept")
	check(Upgrades.level("shield") == 1 and GameState.max_shield == sh0 + 1 and GameState.coins == 800, "✕/A 买下护盾扩容：护盾上限 %d，剩 %d 金币" % [GameState.max_shield, GameState.coins])
	await press("ui_cancel")
	check(not menu._upgrades.visible and menu._panel.visible, "○/B 从改装面板回到暂停菜单")
	# 设置
	await press("ui_down")
	await press("ui_accept")
	check(menu._settings.visible, "打开设置")
	var v0 := float(Settings.get_v("master"))
	await press("ui_left")
	check(float(Settings.get_v("master")) < v0, "←调低总音量（%.2f → %.2f）" % [v0, float(Settings.get_v("master"))])
	await press("ui_right")
	check(absf(float(Settings.get_v("master")) - v0) < 0.001, "→调回来")
	for k in 6:
		await press("ui_down")
	f = get_viewport().gui_get_focus_owner()
	var on0 := bool(Settings.get_v("invert_y"))
	await press("ui_accept")
	check(bool(Settings.get_v("invert_y")) != on0, "下移到「镜头上下反转」，✕/A 切换（%s）" % (f.get("title") if f else "无"))
	await press("ui_accept")
	await press("ui_cancel")
	check(not menu._settings.visible, "○/B 关掉设置")
	menu.close()
	if fails.is_empty():
		print("===== 全部通过 =====")
	else:
		print("===== 失败 %d 项 =====" % fails.size())
	get_tree().quit()

func _jb(i: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = i as JoyButton
	e.device = -1
	return e
