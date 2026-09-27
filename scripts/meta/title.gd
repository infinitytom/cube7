extends Node3D
## 开始界面：浮岛全景做背景，镜头缓慢环绕。
## 流程：按任意键 → 主菜单（继续游戏 / 新游戏 / 读取存档 / 设置 / 退出）

@onready var world: VoxelWorld = $VoxelWorld

var _cam: Camera3D
var _angle := 0.0
var _ui: Control
var _press: Label
var _logo: Control
var _menu: VBoxContainer
var _slots: PanelContainer
var _settings: SettingsPanel
var _confirm: PanelContainer
var _state := "press"
var _t := 0.0
var _slot_mode := "new"
var _hero: Node3D
var _hero_ring: Node3D
var _logo_y := 120.0

const CENTER := Vector3(32, 10, 25)

func _ready() -> void:
	# 命令行测试直接进游戏
	var args := Array(OS.get_cmdline_user_args())
	if args.any(func(a: String) -> bool: return a.begins_with("--autotest") or a.begins_with("--level") or a.begins_with("--shots") or a == "--probe"):
		Flow.mode = "debug"
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
		return
	if args.any(func(a: String) -> bool: return a.begins_with("--uishots")):
		var shots := Node.new()
		shots.set_script(load("res://scripts/debug/ui_shots.gd"))
		get_tree().root.add_child.call_deferred(shots)
	var level := AreaGreenhouse.new()
	level.backdrop = true
	level.world_path = NodePath("../VoxelWorld")
	add_child(level)
	level.build()
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.current = true
	add_child(_cam)
	_build_hero()
	_build_ui()
	Music.set_override("title")
	Music.play_area("title")

func _process(delta: float) -> void:
	_t += delta
	_angle += delta * 0.035
	var p := CENTER + Vector3(cos(_angle) * 62.0, 26.0 + sin(_angle * 0.7) * 3.0, sin(_angle) * 62.0)
	_cam.global_position = p
	_cam.look_at(CENTER + Vector3(0, -1, 0))
	if _press:
		_press.modulate.a = 0.45 + 0.55 * absf(sin(_t * 2.2))
	if _logo:
		_logo.position.y = _logo_y + sin(_t * 1.1) * 4.0
	if _hero:
		# PIX 在镜头右前方悬浮、缓慢自转，偶尔“看”一眼镜头
		_hero.position = Vector3(1.55, -0.35 + sin(_t * 1.6) * 0.07, -4.2)
		_hero.rotation = Vector3(sin(_t * 0.9) * 0.12, _t * 0.6, sin(_t * 0.7) * 0.1)
		_hero_ring.rotation.z = _t * 1.8

## 主角特写：和经典作品的标题画面一样，主角就在镜头前
func _build_hero() -> void:
	_hero = Node3D.new()
	_cam.add_child(_hero)
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color("2b3450")
	shell.roughness = 0.3
	shell.metallic = 0.4
	shell.rim_enabled = true
	shell.rim = 0.5
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("46c3ff")
	glow.emission_enabled = true
	glow.emission = Color("46c3ff")
	glow.emission_energy_multiplier = 3.0
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.48
	sm.height = 0.96
	ball.mesh = sm
	ball.material_override = shell
	_hero.add_child(ball)
	_hero_ring = Node3D.new()
	_hero.add_child(_hero_ring)
	for rx in [0.0, 90.0]:
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.455
		t.outer_radius = 0.525
		ring.mesh = t
		ring.material_override = glow
		ring.rotation_degrees.x = rx
		_hero_ring.add_child(ring)
	var light := OmniLight3D.new()
	light.light_color = Color("46c3ff")
	light.light_energy = 0.6
	light.omni_range = 2.5
	_hero.add_child(light)

# ================================================================ 界面

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.theme = UIKit.theme()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_ui)
	# 左侧渐变遮罩，让文字更清楚
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.04, 0.09, 0.78))
	grad.set_color(1, Color(0.02, 0.04, 0.09, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	UIKit.place(shade, Vector4(0, 0, 0.62, 1), Vector4.ZERO)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)
	# 标志
	_logo = VBoxContainer.new()
	UIKit.place(_logo, Vector4(0, 0, 0, 0), Vector4(110, 120, 900, 420))
	_ui.add_child(_logo)
	var title := UIKit.outline(UIKit.label("立方-7", 128, Color.WHITE, true), 14, Color(0.05, 0.2, 0.35, 0.8))
	title.add_theme_constant_override("line_spacing", -20)
	_logo.add_child(title)
	var sub := UIKit.label("C  U  B  E  -  7", 30, UIKit.ACCENT, true)
	UIKit.outline(sub, 6)
	_logo.add_child(sub)
	var tag := UIKit.outline(UIKit.label("变形 · 滚动 · 把整个世界拆开来看看", 24, UIKit.TEXT), 6)
	tag.modulate.a = 0.85
	_logo.add_child(tag)
	# 按任意键
	_press = UIKit.outline(UIKit.label("按任意键开始", 28, Color.WHITE, true), 8)
	UIKit.place(_press, Vector4(0, 1, 0, 1), Vector4(116, -190, 700, -140))
	_ui.add_child(_press)
	# 主菜单
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 12)
	UIKit.place(_menu, Vector4(0, 1, 0, 1), Vector4(110, -430, 560, -80))
	_menu.visible = false
	_ui.add_child(_menu)
	# 版本号
	var ver := UIKit.label("原型 v0.3 · 区域 1", 16, UIKit.DIM)
	UIKit.place(ver, Vector4(1, 1, 1, 1), Vector4(-260, -44, -30, -16))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ui.add_child(ver)
	# 设置
	_settings = SettingsPanel.new()
	UIKit.place(_settings, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-310, -290, 310, 290))
	_settings.visible = false
	_settings.closed.connect(func() -> void:
		_settings.visible = false
		_show_menu())
	_ui.add_child(_settings)

func _unhandled_input(event: InputEvent) -> void:
	if _state == "press":
		var pressed: bool = (event is InputEventKey and event.pressed) or (event is InputEventJoypadButton and event.pressed) or (event is InputEventMouseButton and event.pressed)
		if pressed:
			get_viewport().set_input_as_handled()
			Sfx.play("unlock", Vector3.INF, -8.0, 0.0)
			_press.visible = false
			_show_menu()
	elif _state == "slots" and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_slots.queue_free()
		_show_menu()
	elif _state == "confirm" and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_confirm.queue_free()
		_open_slots(_slot_mode)

func _clear_menu() -> void:
	for c in _menu.get_children():
		c.queue_free()

func _button(text: String, cb: Callable, sub := "") -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(430, 64 if sub == "" else 78)
	if sub != "":
		b.text = text + "\n" + sub
		b.add_theme_font_size_override("font_size", 22)
	UIKit.juice(b)
	b.pressed.connect(cb)
	_menu.add_child(b)
	return b

func _show_menu() -> void:
	_state = "menu"
	_logo_show(true)
	_clear_menu()
	_menu.visible = true
	var latest := SaveGame.latest_slot()
	var first: Button
	if latest >= 0:
		var d := SaveGame.read(latest)
		first = _button("继续游戏", func() -> void: _continue(latest),
			"存档 %d · 区域 1 翠绿温室 · %s" % [latest + 1, SaveGame.format_time(float(d.get("play_time", 0)))])
	var ng := _button("新游戏", func() -> void: _open_slots("new"))
	if first == null:
		first = ng
	if latest >= 0:
		_button("读取存档", func() -> void: _open_slots("load"))
	_button("设置", func() -> void:
		_menu.visible = false
		_state = "settings"
		_settings.open())
	_button("退出游戏", func() -> void: get_tree().quit())
	first.grab_focus.call_deferred()
	# 菜单滑入
	_menu.modulate.a = 0.0
	_menu.position.x -= 30
	var tw := create_tween().set_parallel()
	tw.tween_property(_menu, "modulate:a", 1.0, 0.25)
	tw.tween_property(_menu, "position:x", _menu.position.x + 30, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _logo_show(on: bool) -> void:
	create_tween().tween_property(_logo, "modulate:a", 1.0 if on else 0.0, 0.2)

func _continue(i: int) -> void:
	if SaveGame.load_slot(i):
		Music.stop()
		Flow.goto_game("continue")

## 存档位选择：新游戏 / 读取
func _open_slots(mode: String) -> void:
	_slot_mode = mode
	_state = "slots"
	_logo_show(false)
	_menu.visible = false
	_slots = PanelContainer.new()
	_slots.theme = UIKit.theme()
	_slots.add_theme_stylebox_override("panel", UIKit.panel(UIKit.BG_SOLID, UIKit.LINE, 18, 28))
	UIKit.place(_slots, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-380, -270, 380, 270))
	_ui.add_child(_slots)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_slots.add_child(v)
	v.add_child(UIKit.label("选择存档位" if mode == "new" else "读取存档", 32, UIKit.TEXT, true))
	var first: Button
	for i in SaveGame.SLOTS:
		var d := SaveGame.read(i)
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(700, 104)
		b.add_theme_font_size_override("font_size", 22)
		if d.is_empty():
			b.text = "存档 %d\n空" % (i + 1)
			b.disabled = mode == "load"
		else:
			var when := Time.get_datetime_string_from_unix_time(int(float(d.get("saved_at", 0))) + 8 * 3600, true)
			b.text = "存档 %d   ·   区域 1 翠绿温室\n游戏时间 %s   ·   记忆碎片 %d/3   ·   金币 %d   ·   %s" % [
				i + 1, SaveGame.format_time(float(d.get("play_time", 0))), (d.get("fragments", []) as Array).size(), int(d.get("coins", 0)), when.substr(5, 11)]
		UIKit.juice(b)
		b.pressed.connect(func() -> void: _pick_slot(i, d.is_empty()))
		v.add_child(b)
		if first == null and not b.disabled:
			first = b
	var hint := HBoxContainer.new()
	hint.add_child(UIKit.label("返回：", 18, UIKit.DIM))
	hint.add_child(UIKit.glyph("pause" if GameState.device == "kbm" else "grab", 18))
	v.add_child(hint)
	if first:
		first.grab_focus.call_deferred()

func _pick_slot(i: int, empty: bool) -> void:
	if _slot_mode == "load":
		_slots.queue_free()
		_continue(i)
		return
	if empty:
		_start_new(i)
		return
	# 覆盖确认
	_slots.queue_free()
	_state = "confirm"
	_confirm = PanelContainer.new()
	_confirm.theme = UIKit.theme()
	_confirm.add_theme_stylebox_override("panel", UIKit.panel(UIKit.BG_SOLID, UIKit.DANGER, 18, 30, 2))
	UIKit.place(_confirm, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-300, -130, 300, 130))
	_ui.add_child(_confirm)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	_confirm.add_child(v)
	v.add_child(UIKit.label("覆盖存档 %d？" % (i + 1), 30, UIKit.TEXT, true))
	v.add_child(UIKit.label("原来的进度会被清除，无法恢复。", 20, UIKit.DIM))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	v.add_child(h)
	var no := Button.new()
	no.text = "取消"
	UIKit.juice(no)
	no.pressed.connect(func() -> void:
		_confirm.queue_free()
		_open_slots("new"))
	var yes := Button.new()
	yes.text = "覆盖并开始"
	UIKit.juice(yes)
	yes.pressed.connect(func() -> void: _start_new(i))
	h.add_child(no)
	h.add_child(yes)
	no.grab_focus.call_deferred()

func _start_new(i: int) -> void:
	SaveGame.new_game(i)
	Music.stop()
	Flow.goto_game("new")
