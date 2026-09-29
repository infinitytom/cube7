extends Node3D
## 开始界面。
## 画面：黄昏光线下的浮岛全景，镜头缓慢环绕；主角 PIX 悬浮在镜头前；旋转的立方体徽记 + 流光标题。
## 流程：黑场淡入 → 标志依次浮现 → 按任意键 → 主菜单（继续 / 新游戏 / 读取 / 设置 / 赞赏作者 / 退出）

@onready var world: VoxelWorld = $VoxelWorld

var _cam: Camera3D
var _angle := 0.0
var _ui: Control
var _black: ColorRect
var _dim: ColorRect
var _logo: Control
var _emblem: CubeEmblem
var _title_label: Label
var _shimmer: ShaderMaterial
var _rule: ColorRect
var _press: HBoxContainer
var _menu: VBoxContainer
var _hints: HBoxContainer
var _slots: PanelContainer
var _settings: SettingsPanel
var _confirm: PanelContainer
var _donate: PanelContainer
var _state := "intro"
var _t := 0.0
var _slot_mode := "new"
var _hero: Node3D
var _hero_ring: Node3D
var _hero_eyes: Array[MeshInstance3D] = []
var _logo_y := 96.0

const CENTER := Vector3(32, 10, 25)
const MENU_W := 520.0
const ANGLE0 := 0.15     ## 镜头构图的基准角度：只在附近缓慢摆动，不整圈环绕

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
	if args.any(func(a: String) -> bool: return a.begins_with("--titletest")):
		var tt := Node.new()
		tt.set_script(load("res://scripts/debug/test_title.gd"))
		get_tree().root.add_child.call_deferred(tt)
	var level := AreaGreenhouse.new()
	level.backdrop = true
	level.world_path = NodePath("../VoxelWorld")
	add_child(level)
	_golden_hour()
	level.build()
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.current = true
	add_child(_cam)
	_build_hero()
	_build_ui()
	GameState.device_changed.connect(func(_k: String) -> void: _refresh_glyphs())
	Music.set_override("title")
	Music.play_area("title")
	_intro()

# ================================================================ 画面

## 黄昏配色：深蓝天顶、暖橙地平线、低角度暖光。只影响标题画面。
func _golden_hour() -> void:
	Atmosphere.apply(self, "title")
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		# 光从镜头一侧斜照过来（侧逆光太暗），偏暖
		sun.rotation_degrees = Vector3(-32, 90.0 - rad_to_deg(ANGLE0) + 35.0, 0)

func _process(delta: float) -> void:
	_t += delta
	_angle = ANGLE0 + sin(_t * 0.045) * 0.22
	var p := CENTER + Vector3(cos(_angle) * 60.0, 19.0 + sin(_angle * 0.7) * 2.5, sin(_angle) * 60.0)
	_cam.global_position = p
	_cam.look_at(CENTER + Vector3(0, 6.5, 0))
	if _press and _state == "press":
		_press.modulate.a = 0.4 + 0.6 * (0.5 + 0.5 * sin(_t * 2.4))
	if _logo:
		_logo.position.y = _logo_y + sin(_t * 1.1) * 3.0
	if _shimmer:
		# 每 5 秒扫过一次流光
		var cyc := fmod(_t, 5.0) / 1.4
		_shimmer.set_shader_parameter("sweep", lerpf(-200.0, 1300.0, clampf(cyc, 0.0, 1.0)))
	if _hero:
		_hero.position = Vector3(2.7, -1.05 + sin(_t * 1.6) * 0.07, -6.4)
		_hero.rotation = Vector3(sin(_t * 0.9) * 0.1, sin(_t * 0.5) * 0.35, sin(_t * 0.7) * 0.08)
		_hero_ring.rotation.x = _t * 1.6
		var blink := 0.12 if fmod(_t, 3.7) < 0.12 else 1.0
		for e in _hero_eyes:
			e.scale.y = blink

## 主角特写：和经典作品的标题画面一样，主角就在镜头前
func _build_hero() -> void:
	_hero = Node3D.new()
	_cam.add_child(_hero)
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color("f3f5ff")
	shell.roughness = 0.25
	shell.metallic = 0.5
	shell.rim_enabled = true
	shell.rim = 0.6
	shell.rim_tint = 0.4
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
	# 屏幕脸：深色面罩 + 两只发光的眼睛（朝着镜头）
	var face := Node3D.new()
	_hero.add_child(face)
	face.rotation_degrees.y = 157.0
	var visor := MeshInstance3D.new()
	var vm := SphereMesh.new()
	vm.radius = 0.2
	vm.height = 0.24
	visor.mesh = vm
	var vmat := StandardMaterial3D.new()
	vmat.albedo_color = Color("1b1f3b")
	vmat.roughness = 0.15
	visor.material_override = vmat
	visor.scale = Vector3(1.35, 0.95, 0.35)
	visor.position = Vector3(0, 0.1, -0.43)
	visor.rotation_degrees.x = -12.0
	face.add_child(visor)
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = Color("9ff0ff")
	for x in [-0.085, 0.085]:
		var e := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.034
		cm.height = 0.13
		e.mesh = cm
		e.material_override = em
		e.position = Vector3(x, 0.115, -0.505)
		e.rotation_degrees.x = -12.0
		face.add_child(e)
		_hero_eyes.append(e)
	var light := OmniLight3D.new()
	light.light_color = Color("46c3ff")
	light.light_energy = 0.7
	light.omni_range = 2.5
	_hero.add_child(light)
	# 暖色轮廓光，让主角从黄昏背景里跳出来
	var rim := OmniLight3D.new()
	rim.light_color = Color(1.0, 0.75, 0.5)
	rim.light_energy = 2.0
	rim.omni_range = 3.0
	rim.position = Vector3(1.2, 0.8, -1.0)
	_hero.add_child(rim)

# ================================================================ 界面搭建

func _soft_dot() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 32
	gt.height = 32
	return gt

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.theme = UIKit.theme()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 根节点不拦鼠标：否则“按任意键开始”时鼠标点击被它吃掉，传不到 _unhandled_input
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui)
	# 暗角
	var vg := Gradient.new()
	vg.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	vg.colors = PackedColorArray([Color(0.02, 0.03, 0.08, 0.0), Color(0.02, 0.03, 0.08, 0.05), Color(0.05, 0.05, 0.2, 0.4)])
	var vt := GradientTexture2D.new()
	vt.gradient = vg
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.55, 0.45)
	vt.fill_to = Vector2(1.25, 1.05)
	var vign := TextureRect.new()
	vign.texture = vt
	vign.stretch_mode = TextureRect.STRETCH_SCALE
	vign.set_anchors_preset(Control.PRESET_FULL_RECT)
	vign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(vign)
	# 左侧柔和遮罩，给文字留出“呼吸”的底
	var sg := Gradient.new()
	sg.set_color(0, Color(0.03, 0.05, 0.12, 0.7))
	sg.set_color(1, Color(0.03, 0.05, 0.12, 0.0))
	var st := GradientTexture2D.new()
	st.gradient = sg
	st.fill_from = Vector2(0, 0)
	st.fill_to = Vector2(1, 0)
	var shade := TextureRect.new()
	shade.texture = st
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	UIKit.place(shade, Vector4(0, 0, 0.55, 1), Vector4.ZERO)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)
	# 空气中漂浮的光尘
	var motes := CPUParticles2D.new()
	motes.amount = 22
	motes.lifetime = 12.0
	motes.preprocess = 12.0
	motes.texture = _soft_dot()
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(1100, 620)
	motes.position = Vector2(960, 600)
	motes.direction = Vector2(0.3, -1)
	motes.spread = 25.0
	motes.gravity = Vector2.ZERO
	motes.initial_velocity_min = 6.0
	motes.initial_velocity_max = 18.0
	motes.scale_amount_min = 0.08
	motes.scale_amount_max = 0.32
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color(1, 0.9, 0.75, 0), Color(1, 0.9, 0.75, 0.55), Color(1, 0.9, 0.75, 0.55), Color(1, 0.9, 0.75, 0)])
	motes.color_ramp = ramp
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	motes.material = add
	_ui.add_child(motes)

	_build_logo()

	# 按任意键
	_press = HBoxContainer.new()
	_press.add_theme_constant_override("separation", 10)
	UIKit.place(_press, Vector4(0, 1, 0, 1), Vector4(128, -200, 800, -150))
	_press.modulate.a = 0.0
	_press.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_press)
	# 主菜单
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 2)
	# 菜单占标题下方到底部提示之间的区域；打开菜单时标题会缩小上移，给菜单让位
	UIKit.place(_menu, Vector4(0, 0, 0, 1), Vector4(96, 300, 96 + MENU_W, -104))
	_menu.alignment = BoxContainer.ALIGNMENT_END
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.visible = false
	_ui.add_child(_menu)
	# 底部按键提示
	_hints = HBoxContainer.new()
	_hints.add_theme_constant_override("separation", 26)
	UIKit.place(_hints, Vector4(0, 1, 0, 1), Vector4(128, -70, 800, -34))
	_hints.modulate.a = 0.0
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_hints)
	_refresh_glyphs()
	# 版本号
	var ver := UIKit.label("v1.1  ·  全六章 + 关卡编辑器", 15, Color(1, 1, 1, 0.45))
	UIKit.place(ver, Vector4(1, 1, 1, 1), Vector4(-280, -52, -40, -26))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ui.add_child(ver)
	# 弹出面板时的压暗层
	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.02, 0.05, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.modulate.a = 0.0
	_ui.add_child(_dim)
	# 设置
	_settings = SettingsPanel.new()
	UIKit.place(_settings, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-350, -340, 350, 340))
	_settings.visible = false
	_settings.closed.connect(func() -> void:
		_settings.visible = false
		Sfx.play("ui_back", Vector3.INF, -8.0, 0.0)
		_show_menu())
	_ui.add_child(_settings)
	# 开场黑场
	_black = ColorRect.new()
	_black.color = Color(0.0, 0.0, 0.02, 1.0)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_black)

func _build_logo() -> void:
	_logo = Control.new()
	UIKit.place(_logo, Vector4(0, 0, 0, 0), Vector4(96, _logo_y, 1000, _logo_y + 360))
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_logo)
	_emblem = CubeEmblem.new()
	_emblem.position = Vector2(0, 14)
	_emblem.size = Vector2(150, 150)
	_emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.add_child(_emblem)
	_title_label = UIKit.label("方舟星球", 124, Color.WHITE, true)
	UIKit.outline(_title_label, 10, Color(0.04, 0.1, 0.22, 0.75))
	_title_label.position = Vector2(160, 0)
	_title_label.add_theme_constant_override("shadow_offset_x", 0)
	_title_label.add_theme_constant_override("shadow_offset_y", 8)
	_title_label.add_theme_constant_override("shadow_outline_size", 24)
	_title_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.05, 0.15, 0.35))
	_shimmer = ShaderMaterial.new()
	_shimmer.shader = load("res://shaders/ui_shimmer.gdshader")
	_title_label.material = _shimmer
	_logo.add_child(_title_label)
	_rule = ColorRect.new()
	_rule.color = UIKit.ACCENT
	_rule.position = Vector2(166, 182)
	_rule.size = Vector2(430, 2)
	_logo.add_child(_rule)
	var dot := ColorRect.new()
	dot.color = UIKit.ACCENT2
	dot.size = Vector2(8, 8)
	dot.position = Vector2(-4, -3)
	dot.rotation = PI / 4.0
	_rule.add_child(dot)
	var sub := UIKit.label("V O X E L   A R K", 24, UIKit.ACCENT, true)
	sub.add_theme_constant_override("outline_size", 0)
	sub.position = Vector2(168, 196)
	_logo.add_child(sub)
	for c in _logo.get_children():
		(c as CanvasItem).modulate.a = 0.0

## 开场：黑场淡开 → 徽记、标题、细线、副标题依次浮现
func _intro() -> void:
	var tw := create_tween()
	tw.tween_property(_black, "color:a", 0.0, 2.2).set_trans(Tween.TRANS_SINE)
	var kids := _logo.get_children()
	var delays := [0.8, 1.2, 1.7, 2.0, 2.3]
	for i in kids.size():
		var c := kids[i] as Control
		var d: float = delays[mini(i, delays.size() - 1)]
		var target := c.position
		c.position = target + Vector2(0, 16)
		var t2 := create_tween().set_parallel()
		t2.tween_property(c, "modulate:a", 1.0, 0.9).set_delay(d)
		t2.tween_property(c, "position", target, 1.1).set_delay(d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# 细线从左往右画出来
	var full := _rule.size.x
	_rule.size.x = 0.0
	create_tween().tween_property(_rule, "size:x", full, 1.2).set_delay(1.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(2.8).timeout
	if _state == "intro":
		_state = "press"

func _skip_intro() -> void:
	for tw in get_tree().get_processed_tweens():
		tw.custom_step(10.0)
	_black.color.a = 0.0
	for c in _logo.get_children():
		(c as CanvasItem).modulate.a = 1.0

func _refresh_glyphs() -> void:
	for c in _press.get_children():
		c.queue_free()
	if GameState.device == "kbm":
		_press.add_child(UIKit.outline(UIKit.label("按任意键开始", 26, Color.WHITE, true), 6, Color(0, 0, 0, 0.4)))
	else:
		_press.add_child(UIKit.outline(UIKit.label("按", 26, Color.WHITE, true), 6, Color(0, 0, 0, 0.4)))
		_press.add_child(UIKit.glyph("ui_accept", 28))
		_press.add_child(UIKit.outline(UIKit.label("开始", 26, Color.WHITE, true), 6, Color(0, 0, 0, 0.4)))
	for c in _hints.get_children():
		c.queue_free()
	_hints.add_child(UIKit.prompt("ui_accept", "确认", 18))
	_hints.add_child(UIKit.prompt("ui_cancel", "返回", 18))

# ================================================================ 输入

func _unhandled_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventJoypadButton and event.pressed) or (event is InputEventMouseButton and event.pressed)
	if _state == "intro" and pressed:
		get_viewport().set_input_as_handled()
		_skip_intro()
		_state = "press"
		return
	if _state == "press":
		if pressed:
			get_viewport().set_input_as_handled()
			Sfx.play("ui_confirm", Vector3.INF, -4.0, 0.0)
			Sfx.play("pix_happy", Vector3.INF, -10.0, 0.05)
			var tw := create_tween()
			tw.tween_property(_press, "modulate:a", 0.0, 0.2)
			tw.tween_callback(func() -> void: _press.visible = false)
			_show_menu()
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	match _state:
		"slots":
			get_viewport().set_input_as_handled()
			Sfx.play("ui_back", Vector3.INF, -8.0, 0.0)
			_close_panel(_slots)
			_show_menu()
		"confirm":
			get_viewport().set_input_as_handled()
			Sfx.play("ui_back", Vector3.INF, -8.0, 0.0)
			_close_panel(_confirm)
			_open_slots(_slot_mode)
		"donate":
			get_viewport().set_input_as_handled()
			Sfx.play("ui_back", Vector3.INF, -8.0, 0.0)
			_close_panel(_donate)
			_show_menu()
		"settings":
			get_viewport().set_input_as_handled()
			_settings.closed.emit()

# ================================================================ 主菜单

func _clear_menu() -> void:
	for c in _menu.get_children():
		c.queue_free()

## 简洁的文字菜单项：选中时左侧亮起一根强调色竖条，背后淡淡的光带，文字右移
func _item(text: String, cb: Callable, sub := "", accent := UIKit.ACCENT) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(MENU_W, 64 if sub != "" else 46)
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 30
	empty.content_margin_bottom = 22 if sub != "" else 0
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(st, empty)
	b.add_theme_font_size_override("font_size", 27)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.62))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	b.add_theme_constant_override("outline_size", 6)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.3))
	# 背后的光带
	var hg := Gradient.new()
	hg.set_color(0, Color(accent, 0.18))
	hg.set_color(1, Color(accent, 0.0))
	var ht := GradientTexture2D.new()
	ht.gradient = hg
	ht.fill_to = Vector2(1, 0)
	var hl := TextureRect.new()
	hl.texture = ht
	hl.stretch_mode = TextureRect.STRETCH_SCALE
	hl.set_anchors_preset(Control.PRESET_FULL_RECT)
	hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hl.show_behind_parent = true
	hl.modulate.a = 0.0
	b.add_child(hl)
	# 左侧竖条
	var bar := ColorRect.new()
	bar.color = accent
	UIKit.place(bar, Vector4(0, 0, 0, 1), Vector4(0, 10, 4, -10))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.scale.y = 0.0
	b.add_child(bar)
	if sub != "":
		var sl := UIKit.label(sub, 16, Color(1, 1, 1, 0.55))
		UIKit.place(sl, Vector4(0, 1, 1, 1), Vector4(32, -30, 0, -6))
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(sl)
	b.focus_entered.connect(func() -> void:
		bar.pivot_offset = Vector2(2, bar.size.y * 0.5)
		var tw := b.create_tween().set_parallel()
		tw.tween_property(bar, "scale:y", 1.0, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(hl, "modulate:a", 1.0, 0.16)
		tw.tween_method(func(v: float) -> void: _margin(b, v), _margin_of(b), 44.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		Sfx.play("ui_move", Vector3.INF, -12.0, 0.03))
	b.focus_exited.connect(func() -> void:
		var tw := b.create_tween().set_parallel()
		tw.tween_property(bar, "scale:y", 0.0, 0.14)
		tw.tween_property(hl, "modulate:a", 0.0, 0.14)
		tw.tween_method(func(v: float) -> void: _margin(b, v), _margin_of(b), 30.0, 0.14))
	b.mouse_entered.connect(func() -> void: b.grab_focus())
	b.pressed.connect(func() -> void: Sfx.play("ui_confirm", Vector3.INF, -8.0, 0.0))
	b.pressed.connect(cb)
	_menu.add_child(b)
	return b

func _margin_of(b: Button) -> float:
	return (b.get_theme_stylebox("focus") as StyleBoxEmpty).content_margin_left

## 所有状态共用同一个 StyleBoxEmpty，改一次即可让文字整体右移
func _margin(b: Button, v: float) -> void:
	(b.get_theme_stylebox("focus") as StyleBoxEmpty).content_margin_left = v
	b.queue_redraw()
	for c in b.get_children():
		if c is Label:
			(c as Label).offset_left = v + 2

func _show_menu() -> void:
	_state = "menu"
	_logo_show(true)
	_dim_show(false)
	_clear_menu()
	_menu.visible = true
	var latest := SaveGame.latest_slot()
	var first: Button
	if latest >= 0:
		var d := SaveGame.read(latest)
		first = _item("继续游戏", func() -> void: _continue(latest),
			"存档 %d  ·  %s %s  ·  %s" % [latest + 1, Chapters.info(int(d.get("chapter", 1))).num, Chapters.info(int(d.get("chapter", 1))).title, SaveGame.format_time(float(d.get("play_time", 0)))])
	var ng := _item("新游戏", func() -> void: _open_slots("new"))
	if first == null:
		first = ng
	if latest >= 0:
		_item("读取存档", func() -> void: _open_slots("load"))
	# 章节选择：任何一个存档到过的章节都能回去重玩（重玩不改存档，改装等级照带）
	var reached := 0
	var best_up := {}
	for i in SaveGame.SLOTS:
		var sd := SaveGame.read(i)
		if sd.is_empty():
			continue
		var ch := int(sd.get("chapter", 1))
		if bool((sd.get("flags", {}) as Dictionary).get("game_clear", false)):
			ch = Chapters.count()
		if ch > reached:
			reached = ch
			best_up = sd.get("upgrades", {})
	if reached >= 2:
		_item("章节选择", func() -> void: _open_chapters(reached, best_up), "重玩到过的任意一章")
	_item("关卡编辑器", func() -> void:
		Music.stop()
		Flow.goto_game("editor"), "自己搭关卡、试玩、用分享码分享给朋友")
	_item("设置", func() -> void:
		_state = "settings"
		_menu.visible = false
		_logo_show(false)
		_dim_show(true)
		_settings.open())
	_item("赞赏作者", _open_donate, "", UIKit.ACCENT2)
	_item("退出游戏", func() -> void: get_tree().quit())
	first.grab_focus.call_deferred()
	# 菜单项依次滑入
	var i := 0
	for c in _menu.get_children():
		var ci := c as Control
		ci.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(ci, "modulate:a", 1.0, 0.25).set_delay(0.04 * i)
		i += 1
	create_tween().tween_property(_hints, "modulate:a", 1.0, 0.4)

func _open_chapters(reached: int, ups: Dictionary) -> void:
	_state = "slots"
	_menu.visible = false
	_logo_show(false)
	_dim_show(true)
	_slots = _panel(700, 600)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_slots.add_child(v)
	v.add_child(UIKit.label("章节选择", 32, UIKit.TEXT, true))
	var first: Button
	for i in reached:
		var info := Chapters.info(i + 1)
		var b := Button.new()
		b.text = "%s   %s" % [info.num, info.title]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(620, 60)
		UIKit.juice(b)
		var n := i + 1
		b.pressed.connect(func() -> void:
			SaveGame.data = {}
			Upgrades._mem = ups.duplicate()
			Flow.chapter = n
			Music.stop()
			Flow.goto_game("replay"))
		v.add_child(b)
		if first == null:
			first = b
	var hint := HBoxContainer.new()
	hint.add_theme_constant_override("separation", 26)
	hint.add_child(UIKit.prompt("ui_accept", "选择", 18))
	hint.add_child(UIKit.prompt("ui_cancel", "返回", 18))
	v.add_child(hint)
	if first:
		first.grab_focus.call_deferred()

func _logo_show(on: bool) -> void:
	var tw := create_tween().set_parallel()
	tw.tween_property(_logo, "modulate:a", 1.0 if on else 0.0, 0.25)
	# 主菜单出现后标题缩小、上移，免得和菜单项叠在一起
	if on and _state == "menu":
		tw.tween_property(self, "_logo_y", 34.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_logo, "scale", Vector2(0.62, 0.62), 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _dim_show(on: bool) -> void:
	create_tween().tween_property(_dim, "modulate:a", 1.0 if on else 0.0, 0.25)

func _panel(w: float, h: float, border := UIKit.LINE) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme = UIKit.theme()
	p.add_theme_stylebox_override("panel", UIKit.panel(UIKit.BG_SOLID, border, 18, 30, 1 if border == UIKit.LINE else 2))
	UIKit.place(p, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-w * 0.5, -h * 0.5, w * 0.5, h * 0.5))
	_ui.add_child(p)
	# 弹出动画
	p.modulate.a = 0.0
	p.scale = Vector2(0.96, 0.96)
	p.pivot_offset = Vector2(w, h) * 0.5
	var tw := create_tween().set_parallel()
	tw.tween_property(p, "modulate:a", 1.0, 0.18)
	tw.tween_property(p, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return p

func _close_panel(p: Control) -> void:
	if is_instance_valid(p):
		p.queue_free()

func _continue(i: int) -> void:
	if SaveGame.load_slot(i):
		Music.stop()
		Flow.goto_game("continue")

# ================================================================ 存档位

func _open_slots(mode: String) -> void:
	_slot_mode = mode
	_state = "slots"
	_menu.visible = false
	_logo_show(false)
	_dim_show(true)
	_slots = _panel(780, 560)
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
			var chi := Chapters.info(int(d.get("chapter", 1)))
			var cleared := bool((d.get("flags", {}) as Dictionary).get("gh_clear" if int(d.get("chapter", 1)) == 1 else "ch%d_clear" % int(d.get("chapter", 1)), false))
			var tot := Chapters.count() * 3
			b.text = "存档 %d   ·   %s %s%s\n游戏时间 %s   ·   救出噗噗 %d/%d   ·   记忆碎片 %d/%d   ·   %s" % [
				i + 1, chi.num, chi.title, "   ·   已通关" if cleared else "", SaveGame.format_time(float(d.get("play_time", 0))),
				(d.get("seeds", []) as Array).size(), tot, (d.get("fragments", []) as Array).size(), tot, when.substr(5, 11)]
		UIKit.juice(b)
		b.pressed.connect(func() -> void: _pick_slot(i, d.is_empty()))
		v.add_child(b)
		if first == null and not b.disabled:
			first = b
	var hint := HBoxContainer.new()
	hint.add_theme_constant_override("separation", 26)
	hint.add_child(UIKit.prompt("ui_accept", "选择", 18))
	hint.add_child(UIKit.prompt("ui_cancel", "返回", 18))
	v.add_child(hint)
	if first:
		first.grab_focus.call_deferred()

func _pick_slot(i: int, empty: bool) -> void:
	if _slot_mode == "load":
		_close_panel(_slots)
		_continue(i)
		return
	if empty:
		_start_new(i)
		return
	# 覆盖确认
	_close_panel(_slots)
	_state = "confirm"
	_confirm = _panel(600, 260, UIKit.DANGER)
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
		_close_panel(_confirm)
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

# ================================================================ 赞赏（通关后出现）

func _open_donate() -> void:
	_state = "donate"
	_menu.visible = false
	_logo_show(false)
	_dim_show(true)
	_donate = _panel(540, 760, UIKit.ACCENT2)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_donate.add_child(v)
	var t := UIKit.label("喜欢《方舟星球》吗？", 32, UIKit.TEXT, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var body := UIKit.label("游戏完全免费。如果它让你开心，\n可以请作者喝一杯咖啡，支持继续开发～", 19, UIKit.DIM)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(body)
	var qr := TextureRect.new()
	qr.texture = load("res://ui/donate_qr.png")
	qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	qr.custom_minimum_size = Vector2(0, 480)
	v.add_child(qr)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(220, 0)
	UIKit.juice(back)
	back.pressed.connect(func() -> void:
		_close_panel(_donate)
		_show_menu())
	h.add_child(back)
	back.grab_focus.call_deferred()
	Sfx.play("pix_happy", Vector3.INF, -8.0, 0.05)
