class_name LevelEditor
extends Node
## 关卡编辑器（游戏内）：摆方块、摆物件（出生点、终点、敌人、机关、金币……）、一键试玩、存到本地、用分享码分享。
##
## 手柄：
##   左摇杆 移动光标（光标自动贴在这一列的最上面）   右摇杆 转镜头
##   ✕ 放置（按住拖动连续放）   ○ 删除（按住拖动连续删）
##   L1 / R1 换方块（或物件）   □ 切换「方块 / 物件」
##   十字键 ↑↓ 光标抬高 / 降低   十字键 ←→ 转动物件朝向
##   △ 试玩（试玩中按 Options 回来）   Options 菜单（保存、读取、分享码、新建、返回标题）
## 键盘鼠标：
##   鼠标指到哪里光标就在哪里；左键放、右键删、滚轮换方块、中键拖动转镜头
##   WASD 移动光标   R / F 光标抬高 / 降低   X 转朝向   Tab 方块 / 物件   T 或 V 试玩   Esc 菜单   Ctrl+滚轮 缩放

var level: EditorLevel
var world: VoxelWorld
var player: MorphBall
var hud: CanvasLayer

var cursor := Vector3i(36, LevelData.BASE_Y, 36)
var lift := 0                    ## 光标在“贴地高度”上额外抬高几格
var cat := 0                     ## 0 方块 1 物件
var sel := [0, 0]
var testing := false
var yaw := -PI * 0.75
var pitch := -0.75
var dist := 16.0

var _cam: Camera3D
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _frame: MeshInstance3D
var _grid: MeshInstance3D
var _grid_mat: ShaderMaterial
var _markers := Node3D.new()
var _move_t := 0.0
var _paint_last := Vector3i(-999, -999, -999)
var _dirty_rebuild := false
var _ui: CanvasLayer
var _bar_name: Label
var _bar_swatch: ColorRect
var _palette: HBoxContainer
var _coords: Label
var _toast: Label
var _help: VBoxContainer
var _menu: PanelContainer
var _menu_list: VBoxContainer
var _test_bar: HBoxContainer
var _test_t := 0.0
var _mouse_cell := Vector3i(-1, -1, -1)
var _mouse_face := Vector3i.ZERO
var hub: LevelHub
var _hub_busy := false

func _ready() -> void:
	var main := get_parent()
	level = main.level
	world = main.world
	player = main.player
	hud = main.hud
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.far = 2000.0
	main.add_child(_cam)
	_build_cursor()
	main.add_child(_markers)
	_build_ui()
	hub = LevelHub.new()
	add_child(hub)
	level.goal_reached.connect(_on_goal)
	var sp := level.data.find_object("spawn")
	if sp >= 0:
		cursor = level.data.objects[sp].cell
	_enter_edit()

# ================================================================ 编辑 / 试玩切换

func _enter_edit() -> void:
	testing = false
	_cam.current = true
	player.freeze = true
	player.set_visual_hidden(true)
	player.teleport(level.spawn_position() + Vector3.UP * 40.0)
	hud.visible = false
	hud.process_mode = Node.PROCESS_MODE_DISABLED
	_ui.visible = true
	_test_bar.visible = false
	_ghost.visible = true
	_frame.visible = true
	_grid.visible = true
	_markers.visible = true
	_refresh_markers()
	_refresh_bar()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Music.set_override("")

func _start_test() -> void:
	if level.data.find_object("spawn") < 0:
		_say("先放一个出生点（物件 → 出生点）")
		return
	testing = true
	_test_t = 0.0
	await Flow.fade_to(1.0, 0.25)
	_ui.visible = true
	_test_bar.visible = true
	_menu.visible = false
	_ghost.visible = false
	_frame.visible = false
	_grid.visible = false
	_markers.visible = false
	level.start_play()
	hud.process_mode = Node.PROCESS_MODE_INHERIT
	hud.visible = true
	player.set_visual_hidden(false)
	player.freeze = false
	player.apply_form(MorphBall.BALL, false)
	player.respawn_at(level.spawn_position(), -1, false)
	if GameState.camera:
		(GameState.camera as CameraRig).yaw = yaw
		(GameState.camera as CameraRig)._cam.current = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Flow.fade_to(0.0, 0.3)

func _stop_test(msg := "") -> void:
	if not testing:
		return
	await Flow.fade_to(1.0, 0.25)
	level.stop_play()
	_enter_edit()
	if msg != "":
		_say(msg)
	Flow.fade_to(0.0, 0.3)

func _on_goal() -> void:
	if testing:
		Sfx.play("level_clear", Vector3.INF, -4.0, 0.0)
		_stop_test("到达终点！用时 %.1f 秒" % _test_t)

# ================================================================ 输入

func _input(event: InputEvent) -> void:
	if testing:
		if event.is_action_pressed("pause"):
			get_viewport().set_input_as_handled()
			_stop_test()
		return
	if _menu.visible:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_open_menu()
		return
	# 十字键（直接读手柄按键：ui_up/down 也绑了左摇杆，不能用）
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_DPAD_UP:
				_lift(1)
			JOY_BUTTON_DPAD_DOWN:
				_lift(-1)
			JOY_BUTTON_DPAD_LEFT:
				_rotate_obj(-1)
			JOY_BUTTON_DPAD_RIGHT:
				_rotate_obj(1)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				_lift(1)
			KEY_F:
				_lift(-1)
			KEY_TAB:
				_toggle_cat()
			KEY_T:
				_start_test()
			KEY_X:
				_rotate_obj(1)
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if Input.is_key_pressed(KEY_CTRL):
					dist = maxf(5.0, dist - 1.0)
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				if Input.is_key_pressed(KEY_CTRL):
					dist = minf(40.0, dist + 1.0)
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_LEFT:
				if _mouse_cell.x >= 0:
					cursor = _mouse_cell
					_place()
			MOUSE_BUTTON_RIGHT:
				if _mouse_cell.x >= 0:
					cursor = _mouse_cell
					_erase(true)
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			yaw -= event.relative.x * 0.006
			pitch = clampf(pitch - event.relative.y * 0.006, -1.45, -0.1)
		else:
			_mouse_pick(event.position)

func _process(delta: float) -> void:
	if testing:
		_test_t += delta
		return
	if _menu.visible:
		return
	# 镜头
	var look := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
	if Input.is_action_pressed("boost"):
		dist = clampf(dist + look.y * delta * 18.0, 5.0, 40.0)
	else:
		yaw -= look.x * delta * 2.4
		pitch = clampf(pitch - look.y * delta * 1.6, -1.45, -0.1)
	# 光标
	var mv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if mv.length() > 0.4:
		_move_t -= delta
		if _move_t <= 0.0:
			_move_t = 0.11 if _move_t > -1.0 else 0.11
			var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
			var right := Vector3(cos(yaw), 0, -sin(yaw))
			var d := right * mv.x - fwd * mv.y
			var step := Vector3i(roundi(d.x), 0, roundi(d.z)) if absf(d.x) > 0.38 and absf(d.z) > 0.38 else (Vector3i(signi(roundi(d.x * 2.0)), 0, 0) if absf(d.x) >= absf(d.z) else Vector3i(0, 0, signi(roundi(d.z * 2.0))))
			_move_cursor(step)
	else:
		_move_t = 0.0
	# 按住放置 / 删除：光标移到新格子就继续放
	if Input.is_action_just_pressed("jump"):
		_paint_last = Vector3i(-999, -999, -999)
		_place()
	elif Input.is_action_pressed("jump") and _col(cursor) != _col(_paint_last):
		_place()
	var mouse_r := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if Input.is_action_just_pressed("grab") and not mouse_r:
		_paint_last = Vector3i(-999, -999, -999)
		_erase(false)
	elif Input.is_action_pressed("grab") and not mouse_r and _col(cursor) != _col(_paint_last):
		_erase(false)
	if Input.is_action_just_pressed("form_next"):
		_cycle(1)
	if Input.is_action_just_pressed("form_prev"):
		_cycle(-1)
	if Input.is_action_just_pressed("ability") and GameState.device != "kbm":
		_toggle_cat()
	if Input.is_action_just_pressed("view_toggle"):
		_start_test()
	if _dirty_rebuild:
		_dirty_rebuild = false
		world.flush_dirty()
	_update_cursor_visual(delta)
	_update_camera(delta)

## 按住拖动时只看水平位置：原地按住不会一直往上垒
func _col(c: Vector3i) -> Vector2i:
	return Vector2i(c.x, c.z)

func _update_camera(delta: float) -> void:
	var target := world.voxel_center(cursor)
	var dir := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))
	var want := target + dir * dist
	_cam.global_position = _cam.global_position.lerp(want, 1.0 - exp(-10.0 * delta)) if _cam.global_position.distance_to(want) < 30.0 else want
	_cam.look_at(target, Vector3.UP)

# ================================================================ 光标

## 这一列最上面的实心方块上方那一格
func _surface(x: int, z: int) -> int:
	for y in range(LevelData.SIZE.y - 1, -1, -1):
		if world.get_block(Vector3i(x, y, z)) != Blocks.AIR:
			return y + 1
	return LevelData.BASE_Y

func _move_cursor(step: Vector3i) -> void:
	var c := cursor + step
	c.x = clampi(c.x, 0, LevelData.SIZE.x - 1)
	c.z = clampi(c.z, 0, LevelData.SIZE.z - 1)
	c.y = clampi(_surface(c.x, c.z) + lift, 0, LevelData.SIZE.y - 2)
	if c != cursor:
		cursor = c
		Sfx.play("ui_move", Vector3.INF, -16.0, 0.0, 1.4)

func _lift(n: int) -> void:
	lift = clampi(lift + n, -6, 20)
	cursor.y = clampi(_surface(cursor.x, cursor.z) + lift, 0, LevelData.SIZE.y - 2)
	_refresh_bar()

func _mouse_pick(pos: Vector2) -> void:
	var from := _cam.project_ray_origin(pos)
	var dir := _cam.project_ray_normal(pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 200.0, 1)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_mouse_cell = Vector3i(-1, -1, -1)
		return
	var p: Vector3 = hit.position
	var n: Vector3 = hit.normal
	var c := world.world_to_voxel(p + n * 0.1)
	if c.x < 0 or c.z < 0 or c.x >= LevelData.SIZE.x or c.z >= LevelData.SIZE.z or c.y >= LevelData.SIZE.y - 1:
		return
	_mouse_cell = c
	cursor = c
	lift = 0

func _build_cursor() -> void:
	_ghost = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * VoxelWorld.CELL_M * 0.98
	_ghost.mesh = bm
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.albedo_color = Color(1, 1, 1, 0.5)
	_ghost.material_override = _ghost_mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child.call_deferred(_ghost)
	# 光标外框
	_frame = MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var h := VoxelWorld.CELL_M * 0.52
	var corners := [Vector3(-h, -h, -h), Vector3(h, -h, -h), Vector3(h, -h, h), Vector3(-h, -h, h), Vector3(-h, h, -h), Vector3(h, h, -h), Vector3(h, h, h), Vector3(-h, h, h)]
	var edges := [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for e in edges:
		im.surface_add_vertex(corners[e[0]])
		im.surface_add_vertex(corners[e[1]])
	# 往下的竖线：看得出光标离地多高
	im.surface_add_vertex(Vector3(0, -h, 0))
	im.surface_add_vertex(Vector3(0, -h - 20.0, 0))
	im.surface_end()
	_frame.mesh = im
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1, 1, 1)
	fm.no_depth_test = true
	_frame.material_override = fm
	get_parent().add_child.call_deferred(_frame)
	# 光标所在高度的网格
	_grid = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(LevelData.SIZE.x, LevelData.SIZE.z) * VoxelWorld.CELL_M
	_grid.mesh = pm
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec3 center;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 g = abs(fract(wp.xz * 2.0 + 0.5) - 0.5);
	float line = 1.0 - smoothstep(0.0, 0.04, min(g.x, g.y));
	float fade = 1.0 - smoothstep(2.0, 7.0, distance(wp.xz, center.xz));
	ALBEDO = vec3(0.7, 0.95, 1.0);
	ALPHA = line * fade * 0.55;
}"""
	_grid_mat = ShaderMaterial.new()
	_grid_mat.shader = sh
	_grid.material_override = _grid_mat
	_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child.call_deferred(_grid)

func _update_cursor_visual(_delta: float) -> void:
	var p := world.voxel_center(cursor)
	_ghost.global_position = p
	_frame.global_position = p
	_grid.global_position = Vector3(LevelData.SIZE.x * VoxelWorld.CELL_M * 0.5, p.y - VoxelWorld.CELL_M * 0.5 + 0.01, LevelData.SIZE.z * VoxelWorld.CELL_M * 0.5)
	_grid_mat.set_shader_parameter("center", p)
	var col: Color = Blocks.colors[LevelData.BLOCKS[sel[0]][0]] if cat == 0 else LevelData.OBJECTS[sel[1]][2]
	_ghost_mat.albedo_color = Color(col, 0.55 + 0.2 * sin(Time.get_ticks_msec() / 150.0))
	_coords.text = "光标 (%d, %d, %d)   抬高 %+d" % [cursor.x, cursor.y, cursor.z, lift]

# ================================================================ 编辑操作

func _place() -> void:
	_paint_last = cursor
	var d := level.data
	if cat == 0:
		var t: int = LevelData.BLOCKS[sel[0]][0]
		if world.get_block(cursor) == t:
			return
		d.blocks[cursor] = t
		world.set_block(cursor, t)
		_dirty_rebuild = true
		Sfx.play("rebuild", world.voxel_center(cursor), -6.0, 0.05, 1.2)
		GameState.rumble(0.2, 0.0, 0.05)
		# 放完方块，光标跟着“贴地”上去一格（连续按 ✕ 就是往上垒）
		if lift == 0:
			cursor.y = clampi(_surface(cursor.x, cursor.z), 0, LevelData.SIZE.y - 2)
	else:
		var id: String = LevelData.OBJECTS[sel[1]][0]
		var i := d.object_at(cursor)
		if i >= 0:
			d.objects.remove_at(i)
		# 出生点、终点只能有一个：挪过去
		if id == "spawn" or id == "goal":
			var j := d.find_object(id)
			if j >= 0:
				d.objects.remove_at(j)
		d.objects.append({"id": id, "cell": cursor, "yaw": yaw})
		Sfx.play("grab", world.voxel_center(cursor), -6.0, 0.05)
		GameState.rumble(0.3, 0.1, 0.08)
		_refresh_markers()

func _erase(exact: bool) -> void:
	_paint_last = cursor
	var d := level.data
	var i := d.object_at(cursor)
	if i >= 0:
		d.objects.remove_at(i)
		Sfx.play("ui_back", Vector3.INF, -8.0, 0.0)
		_refresh_markers()
		return
	if cat == 1:
		return
	var c := cursor
	if not exact and world.get_block(c) == Blocks.AIR:
		c = cursor + Vector3i.DOWN
	if world.get_block(c) == Blocks.AIR:
		return
	var t := world.get_block(c)
	d.blocks.erase(c)
	world.break_fx_at(world.voxel_center(c), t, false)
	world.set_block(c, Blocks.AIR)
	_dirty_rebuild = true
	GameState.rumble(0.25, 0.1, 0.05)
	if lift == 0:
		cursor.y = clampi(_surface(cursor.x, cursor.z), 0, LevelData.SIZE.y - 2)

func _cycle(n: int) -> void:
	var size := LevelData.BLOCKS.size() if cat == 0 else LevelData.OBJECTS.size()
	sel[cat] = posmod(sel[cat] + n, size)
	Sfx.play("ui_move", Vector3.INF, -10.0, 0.0)
	_refresh_bar()

func _toggle_cat() -> void:
	cat = 1 - cat
	Sfx.play("ui_confirm", Vector3.INF, -8.0, 0.0)
	_refresh_bar()

func _rotate_obj(n: int) -> void:
	var i := level.data.object_at(cursor)
	if i >= 0:
		level.data.objects[i].yaw = float(level.data.objects[i].get("yaw", 0.0)) + n * PI / 4.0
		_refresh_markers()

func _refresh_markers() -> void:
	for c in _markers.get_children():
		c.queue_free()
	for o in level.data.objects:
		var info: Array = []
		for od in LevelData.OBJECTS:
			if od[0] == o.id:
				info = od
		if info.is_empty():
			continue
		var n := Node3D.new()
		_markers.add_child(n)
		n.global_position = world.voxel_top(o.cell + Vector3i.DOWN)
		var mi := MeshInstance3D.new()
		var big: bool = o.id == "spawn" or o.id == "goal"
		if o.id == "goal":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.1
			cm.bottom_radius = 0.5
			cm.height = 1.6
			mi.mesh = cm
		else:
			var sm := SphereMesh.new()
			sm.radius = 0.28 if not big else 0.4
			sm.height = sm.radius * 2.0
			mi.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = info[2]
		m.emission_enabled = true
		m.emission = info[2]
		m.emission_energy_multiplier = 0.6
		mi.material_override = m
		mi.position.y = 0.4 if not big else 0.8
		n.add_child(mi)
		var l := Label3D.new()
		l.text = info[1]
		l.font = UIKit.font(true)
		l.font_size = 48
		l.outline_size = 14
		l.outline_modulate = Color(0.05, 0.08, 0.2)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.pixel_size = 0.01
		l.position.y = 1.2 if not big else 2.0
		l.no_depth_test = true
		n.add_child(l)

# ================================================================ 界面

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 30
	add_child(_ui)
	var root := Control.new()
	root.theme = UIKit.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
	# 顶部：当前选择 + 调色板
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", UIKit.panel(UIKit.BG, UIKit.LINE, 16, 12))
	UIKit.place(top, Vector4(0.5, 0, 0.5, 0), Vector4(-520, 16, 520, 16))
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 6)
	top.add_child(tv)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	tv.add_child(row)
	_bar_swatch = ColorRect.new()
	_bar_swatch.custom_minimum_size = Vector2(28, 28)
	row.add_child(_bar_swatch)
	_bar_name = UIKit.label("", 24, UIKit.TEXT, true)
	_bar_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_bar_name)
	row.add_child(UIKit.prompt("form", "换", 16))
	row.add_child(UIKit.prompt("ability", "方块/物件", 16))
	_palette = HBoxContainer.new()
	_palette.add_theme_constant_override("separation", 4)
	tv.add_child(_palette)
	# 左下：坐标和提示
	_coords = UIKit.outline(UIKit.label("", 18, UIKit.TEXT), 6)
	UIKit.place(_coords, Vector4(0, 1, 0, 1), Vector4(24, -40, 500, -12))
	root.add_child(_coords)
	_help = VBoxContainer.new()
	_help.add_theme_constant_override("separation", 6)
	UIKit.place(_help, Vector4(1, 1, 1, 1), Vector4(-300, -280, -24, -24))
	_help.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(_help)
	for p in [["jump", "放置（按住拖动）"], ["grab", "删除"], ["view_toggle", "试玩"], ["pause", "菜单"]]:
		_help.add_child(UIKit.prompt(p[0], p[1], 18))
	var dh := UIKit.label("十字键 ↑↓ 抬高/降低   ←→ 转朝向", 15, UIKit.DIM)
	_help.add_child(dh)
	_toast = UIKit.outline(UIKit.label("", 26, UIKit.ACCENT2, true), 8)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.place(_toast, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-400, 120, 400, 170))
	_toast.modulate.a = 0.0
	root.add_child(_toast)
	# 试玩时的提示条
	_test_bar = HBoxContainer.new()
	_test_bar.add_theme_constant_override("separation", 10)
	UIKit.place(_test_bar, Vector4(0.5, 0, 0.5, 0), Vector4(-200, 14, 200, 50))
	_test_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_test_bar.add_child(UIKit.outline(UIKit.label("试玩中", 20, UIKit.ACCENT2, true), 6))
	_test_bar.add_child(UIKit.prompt("pause", "回到编辑", 18))
	root.add_child(_test_bar)
	# 菜单
	_menu = PanelContainer.new()
	_menu.add_theme_stylebox_override("panel", UIKit.panel(UIKit.BG_SOLID, UIKit.LINE, 20, 26))
	UIKit.place(_menu, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-300, -300, 300, 300))
	_menu.visible = false
	root.add_child(_menu)
	# 菜单项多（关卡库列表）时可以滚动；手柄移动焦点会自动滚到可见处
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(540, 548)
	_menu.add_child(scroll)
	_menu_list = VBoxContainer.new()
	_menu_list.add_theme_constant_override("separation", 8)
	_menu_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_menu_list)

func _refresh_bar() -> void:
	var list: Array = LevelData.BLOCKS if cat == 0 else LevelData.OBJECTS
	var cur: Array = list[sel[cat]]
	_bar_name.text = ("方块 · " if cat == 0 else "物件 · ") + str(cur[1])
	_bar_swatch.color = Blocks.colors[cur[0]] if cat == 0 else cur[2]
	for c in _palette.get_children():
		c.queue_free()
	for k in range(-5, 6):
		var i := posmod(sel[cat] + k, list.size())
		var it: Array = list[i]
		var sw := ColorRect.new()
		var s := 34 if k == 0 else 24
		sw.custom_minimum_size = Vector2(s, s)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sw.color = Blocks.colors[it[0]] if cat == 0 else it[2]
		sw.modulate.a = 1.0 if k == 0 else 0.55
		_palette.add_child(sw)

func _say(t: String) -> void:
	_toast.text = t
	var tw := _toast.create_tween()
	tw.tween_property(_toast, "modulate:a", 1.0, 0.2)
	tw.tween_interval(2.2)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)

# ---------------------------------------------------------------- 菜单

func _open_menu(page := "main") -> void:
	_menu.visible = true
	for c in _menu_list.get_children():
		c.queue_free()
	var first: Button
	match page:
		"main":
			_menu_list.add_child(UIKit.label("关卡编辑器 · " + level.data.name, 28, UIKit.TEXT, true))
			first = _mbtn("继续编辑", func() -> void: _menu.visible = false)
			_mbtn("试玩", func() -> void:
				_menu.visible = false
				_start_test())
			_mbtn("保存到……", func() -> void: _open_menu("save"))
			_mbtn("读取……", func() -> void: _open_menu("load"))
			_mbtn("GitHub 关卡库……", func() -> void: _open_menu("hub"))
			_mbtn("复制分享码", func() -> void:
				DisplayServer.clipboard_set(level.data.share_code())
				_menu.visible = false
				_say("分享码已复制到剪贴板——发给朋友，他们在「粘贴分享码」里就能玩到"))
			_mbtn("粘贴分享码", func() -> void:
				var d := LevelData.from_share_code(DisplayServer.clipboard_get())
				_menu.visible = false
				if d == null:
					_say("剪贴板里没有有效的分享码（应该以 CUBE7: 开头）")
				else:
					_load(d)
					_say("已导入：" + d.name))
			_mbtn("新建（清空）", func() -> void:
				_menu.visible = false
				_load(LevelData.new_default())
				_say("新关卡"))
			_mbtn("返回标题", func() -> void:
				_menu.visible = false
				Music.stop()
				Flow.goto_title())
		"save", "load":
			_menu_list.add_child(UIKit.label("保存到哪个位置？" if page == "save" else "读取哪个关卡？", 26, UIKit.TEXT, true))
			for i in 5:
				var nm := LevelData.slot_name(i)
				var b := _mbtn("位置 %d   %s" % [i + 1, nm if nm != "" else "（空）"], func() -> void:
					if page == "save":
						# 防止重复：别的位置已经存着一模一样的关卡就不再存一份
						var dup := level.data.duplicate_slot(i)
						if dup >= 0:
							_menu.visible = false
							_say("位置 %d 已经存着一模一样的关卡，没有重复保存" % (dup + 1))
							return
						level.data.name = "我的关卡 %d" % (i + 1) if level.data.name.begins_with("我的关卡") or level.data.name == "" else level.data.name
						level.data.save_slot(i)
						_menu.visible = false
						_say("已保存到位置 %d" % (i + 1))
					else:
						var d := LevelData.load_slot(i)
						_menu.visible = false
						if d:
							_load(d)
							_say("已读取：" + d.name))
				if page == "load" and nm == "":
					b.disabled = true
				if first == null and not b.disabled:
					first = b
			_mbtn("返回", func() -> void: _open_menu("main"))
		"hub":
			_menu_list.add_child(UIKit.label("GitHub 关卡库", 28, UIKit.TEXT, true))
			var info := UIKit.label("仓库：%s\n令牌：%s\n同样内容的关卡（改名也算）只会存一份。" % [hub.repo, "已设置" if hub.token != "" else "未设置（只能浏览；上传会打开浏览器提交）"], 17, UIKit.DIM)
			info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info.custom_minimum_size.x = 520
			_menu_list.add_child(info)
			first = _mbtn("上传当前关卡", _hub_upload)
			_mbtn("浏览关卡库", func() -> void: _open_menu("hub_list"))
			_mbtn("粘贴仓库地址（剪贴板）", func() -> void:
				var r := LevelHub.parse_repo(DisplayServer.clipboard_get())
				if r == "":
					_say("剪贴板里不是 GitHub 仓库地址（owner/仓库名）")
				else:
					hub.repo = r
					hub.save_cfg()
					_say("关卡库改成了 " + r)
				_open_menu("hub"))
			_mbtn("粘贴 GitHub 令牌（剪贴板）", func() -> void:
				var t := DisplayServer.clipboard_get().strip_edges()
				if t.length() < 20 or t.contains(" ") or t.contains("\n"):
					_say("剪贴板里不像是 GitHub 令牌")
				else:
					hub.token = t
					hub.save_cfg()
					DisplayServer.clipboard_set("")
					_say("令牌已保存（只存在这台电脑上）")
				_open_menu("hub"))
			if hub.token != "":
				_mbtn("清除令牌", func() -> void:
					hub.token = ""
					hub.save_cfg()
					_open_menu("hub"))
			_mbtn("返回", func() -> void: _open_menu("main"))
		"hub_list":
			_menu_list.add_child(UIKit.label("GitHub 关卡库", 28, UIKit.TEXT, true))
			var wait := UIKit.label("正在读取 %s ……" % hub.repo, 18, UIKit.DIM)
			_menu_list.add_child(wait)
			_hub_list(wait)
	if first:
		first.grab_focus.call_deferred()

func _hub_upload() -> void:
	if _hub_busy:
		return
	_hub_busy = true
	_say("正在检查关卡库……")
	var res: Dictionary = await hub.upload(level.data)
	_hub_busy = false
	match str(res.status):
		"need_token":
			# 没有令牌：用浏览器在 GitHub 网页上提交（文件名就是指纹，重复的已经在上面拦下了）
			OS.shell_open(hub.browser_submit_url(level.data))
			_menu.visible = false
			_say("已在浏览器打开提交页面，点“Commit / Propose changes”即可")
		_:
			_menu.visible = false
			_say(str(res.msg))

func _hub_list(wait: Label) -> void:
	if _hub_busy:
		return
	_hub_busy = true
	var res: Dictionary = await hub.list_levels()
	_hub_busy = false
	if not _menu.visible or not is_instance_valid(wait):
		return
	wait.text = str(res.msg)
	wait.visible = str(res.msg) != ""
	var first: Button
	var mine := {}
	for i in LevelData.SLOTS:
		var d := LevelData.load_slot(i)
		if d:
			mine[d.content_hash()] = i
	for it in res.levels:
		var d: LevelData = it.data
		var h := d.content_hash()
		var tag := "   （本地位置 %d 已有）" % (int(mine[h]) + 1) if mine.has(h) else ""
		var b := _mbtn("%s%s" % [it.name, tag], func() -> void:
			_menu.visible = false
			_load(d)
			_say("已读取：" + d.name))
		if first == null:
			first = b
	var back := _mbtn("返回", func() -> void: _open_menu("hub"))
	(first if first else back).grab_focus.call_deferred()

func _mbtn(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(520, 46)
	UIKit.juice(b)
	b.pressed.connect(cb)
	_menu_list.add_child(b)
	return b

func _unhandled_input(event: InputEvent) -> void:
	if _menu.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_menu.visible = false

func _load(d: LevelData) -> void:
	level.load_data(d)
	var sp := d.find_object("spawn")
	if sp >= 0:
		cursor = d.objects[sp].cell
	_refresh_markers()
	_refresh_bar()
