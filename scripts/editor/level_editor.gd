class_name LevelEditor
extends Node
## 关卡编辑器（游戏内）：摆方块、摆物件（出生点、终点、敌人、机关、金币……）、一键试玩、存到本地、导出成文件分享。
##
## 参考《马力欧创作家》的快速编辑：
##   · 顶部快捷栏 10 格：常用的方块 / 物件放在这里，L1 / R1（数字键 1～0）秒切
##   · 全部物块面板：□（Tab）打开，按类别排好、带图标和说明，选中的会放进当前快捷格
##   · 按住拖动连续画；框选填充：L3（Shift + 鼠标拖）拉一个矩形，一次铺满
##   · 吸管：R3（Q）把光标处的方块 / 物件吸到当前快捷格
##   · 撤销 / 重做：Create/View（Ctrl+Z / Ctrl+Y）；按住 R2 再按就是重做
##   · 试玩：△（T）从出生点开始；按住 R2 再按 △（Shift+T）从光标处直接开始
##
## 手柄：
##   左摇杆 移动光标（光标自动贴在这一列的最上面）   右摇杆 转镜头（按住 R2 推拉远近）
##   ✕ 放置（按住拖动连续放）   ○ 删除（按住拖动连续删）
##   十字键 ↑↓ 光标抬高 / 降低   十字键 ←→ 转动物件朝向   Options 菜单
## 键盘鼠标：
##   鼠标指到哪里光标就在哪里；左键放、右键删、滚轮换快捷格、中键拖动转镜头
##   WASD 移动光标   R / F 光标抬高 / 降低   X 转朝向   Esc 菜单   Ctrl+滚轮 缩放

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

## 快捷栏：10 格 [类别, 序号]
var hotbar: Array = [[0, 0], [0, 1], [0, 3], [0, 17], [0, 10], [0, 22], [1, 3], [1, 2], [1, 7], [1, 9]]
var slot := 0
var _hotbar_box: HBoxContainer
var _desc: Label
var _bar_icon: BlockIcon
var _picker: PanelContainer
var _picker_grid: GridContainer
## 撤销 / 重做：每一笔（按下到松开）是一条记录 {"blocks": [[cell, old, new], ...], "objects": 之前的物件列表 or null}
var _undo: Array = []
var _redo: Array = []
var _stroke: Dictionary = {}
## 框选：起点（未开始时 x = -999）
var _anchor := Vector3i(-999, 0, 0)
var _anchor_box: MeshInstance3D
var _mouse_rect := false
const UNDO_MAX := 60

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
	# 把 .cube7 文件拖进游戏窗口就能导入
	get_window().files_dropped.connect(_on_files_dropped)
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

func _start_test(from_cursor := false) -> void:
	if level.data.find_object("spawn") < 0 and not from_cursor:
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
	var start := level.spawn_position()
	if from_cursor:
		# 马造式：从光标处直接开始试玩（找光标这一列最上面的空位）
		var top := _surface(cursor.x, cursor.z)
		start = world.voxel_top(Vector3i(cursor.x, top - 1, cursor.z)) + Vector3.UP * 0.55
		GameState.set_checkpoint(start)
	player.respawn_at(start, -1, false)
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
	if _picker and _picker.visible:
		if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_TAB) or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_X):
			get_viewport().set_input_as_handled()
			_close_picker()
		return
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_LEFT_STICK:
				_toggle_anchor()
			JOY_BUTTON_RIGHT_STICK:
				_eyedrop()
			JOY_BUTTON_BACK:
				if Input.is_action_pressed("boost"):
					_redo_step()
				else:
					_undo_step()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.physical_keycode == KEY_Z:
			if event.shift_pressed:
				_redo_step()
			else:
				_undo_step()
			get_viewport().set_input_as_handled()
			return
		if event.ctrl_pressed and event.physical_keycode == KEY_Y:
			_redo_step()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode >= KEY_0 and event.physical_keycode <= KEY_9 and not event.ctrl_pressed:
			_select_slot(posmod(int(event.physical_keycode - KEY_1), 10))
			return
		if event.physical_keycode == KEY_Q:
			_eyedrop()
			return
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
				_open_picker()
			KEY_T:
				_start_test(event.shift_pressed)
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
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				if _mouse_cell.x >= 0:
					cursor = _mouse_cell
					if Input.is_key_pressed(KEY_SHIFT):
						# Shift + 拖：框选，松开时一次铺满（右键是一次删掉）
						_anchor = cursor
						_mouse_rect = true
					else:
						_begin_stroke()
						if event.button_index == MOUSE_BUTTON_LEFT:
							_place()
						else:
							_erase(true)
	if event is InputEventMouseButton and not event.pressed and _mouse_rect and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		_mouse_rect = false
		_fill_rect(_anchor, cursor, event.button_index == MOUSE_BUTTON_RIGHT)
		_anchor = Vector3i(-999, 0, 0)
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			yaw -= event.relative.x * 0.006
			pitch = clampf(pitch - event.relative.y * 0.006, -1.45, -0.1)
		else:
			_mouse_pick(event.position)
			if not _mouse_rect and _mouse_cell.x >= 0:
				if event.button_mask & MOUSE_BUTTON_MASK_LEFT and _col(cursor) != _col(_paint_last):
					_place()
				elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT and cursor != _paint_last:
					_erase(true)

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
	if _picker and _picker.visible:
		_update_camera(delta)
		return
	if Input.is_action_just_pressed("jump") and _anchor.x != -999 and not _mouse_rect:
		_fill_rect(_anchor, cursor, false)
		_anchor = Vector3i(-999, 0, 0)
	elif Input.is_action_just_pressed("grab") and _anchor.x != -999 and not _mouse_rect:
		_fill_rect(_anchor, cursor, true)
		_anchor = Vector3i(-999, 0, 0)
	elif Input.is_action_just_pressed("jump"):
		_paint_last = Vector3i(-999, -999, -999)
		_begin_stroke()
		_place()
	elif Input.is_action_pressed("jump") and _col(cursor) != _col(_paint_last):
		_place()
	var mouse_r := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if Input.is_action_just_pressed("grab") and not mouse_r and _anchor.x == -999:
		_paint_last = Vector3i(-999, -999, -999)
		_begin_stroke()
		_erase(false)
	elif Input.is_action_pressed("grab") and not mouse_r and _col(cursor) != _col(_paint_last):
		_erase(false)
	if Input.is_action_just_pressed("form_next") and not Input.is_key_pressed(KEY_CTRL):
		_select_slot(posmod(slot + 1, 10))
	if Input.is_action_just_pressed("form_prev") and not Input.is_key_pressed(KEY_CTRL):
		_select_slot(posmod(slot - 1, 10))
	if Input.is_action_just_pressed("ability") and GameState.device != "kbm":
		_open_picker()
	if Input.is_action_just_pressed("view_toggle"):
		_start_test(Input.is_action_pressed("boost"))
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
	# 框选范围预览
	_anchor_box = MeshInstance3D.new()
	_anchor_box.mesh = BoxMesh.new()
	var am := StandardMaterial3D.new()
	am.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	am.albedo_color = Color(0.45, 0.9, 1.0, 0.25)
	am.no_depth_test = true
	_anchor_box.material_override = am
	_anchor_box.visible = false
	_anchor_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child.call_deferred(_anchor_box)

func _update_cursor_visual(_delta: float) -> void:
	var p := world.voxel_center(cursor)
	_ghost.global_position = p
	_frame.global_position = p
	_grid.global_position = Vector3(LevelData.SIZE.x * VoxelWorld.CELL_M * 0.5, p.y - VoxelWorld.CELL_M * 0.5 + 0.01, LevelData.SIZE.z * VoxelWorld.CELL_M * 0.5)
	_grid_mat.set_shader_parameter("center", p)
	var col: Color = Blocks.colors[LevelData.BLOCKS[sel[0]][0]] if cat == 0 else LevelData.OBJECTS[sel[1]][2]
	_ghost_mat.albedo_color = Color(col, 0.55 + 0.2 * sin(Time.get_ticks_msec() / 150.0))
	_coords.text = "光标 (%d, %d, %d)   抬高 %+d   撤销 %d 步" % [cursor.x, cursor.y, cursor.z, lift, _undo.size()]
	if _anchor.x != -999:
		var lo := Vector3i(mini(_anchor.x, cursor.x), _anchor.y, mini(_anchor.z, cursor.z))
		var hi := Vector3i(maxi(_anchor.x, cursor.x), _anchor.y, maxi(_anchor.z, cursor.z))
		var a := world.voxel_center(lo)
		var b := world.voxel_center(hi)
		_anchor_box.visible = true
		_anchor_box.global_position = (a + b) * 0.5
		_anchor_box.scale = (b - a).abs() + Vector3.ONE * VoxelWorld.CELL_M * 1.02
		_coords.text += "   框选 %d × %d（✕/左键 铺满，○/右键 清空）" % [hi.x - lo.x + 1, hi.z - lo.z + 1]
	else:
		_anchor_box.visible = false

# ================================================================ 编辑操作

func _place() -> void:
	_paint_last = cursor
	var d := level.data
	if cat == 0:
		var t: int = LevelData.BLOCKS[sel[0]][0]
		if world.get_block(cursor) == t:
			return
		_rec_block(cursor, world.get_block(cursor), t)
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
		_rec_objects()
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
		_rec_objects()
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
	_rec_block(c, t, Blocks.AIR)
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
	UIKit.place(top, Vector4(0.5, 0, 0.5, 0), Vector4(-460, 16, 460, 16))
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 6)
	top.add_child(tv)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	tv.add_child(row)
	_bar_swatch = ColorRect.new()
	_bar_swatch.visible = false
	row.add_child(_bar_swatch)
	_bar_icon = BlockIcon.make(0, 0, 46)
	row.add_child(_bar_icon)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 0)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nv)
	_bar_name = UIKit.label("", 24, UIKit.TEXT, true)
	nv.add_child(_bar_name)
	_desc = UIKit.label("", 15, UIKit.DIM)
	nv.add_child(_desc)
	row.add_child(UIKit.prompt("form", "快捷格", 16))
	row.add_child(UIKit.prompt("ability", "全部物块", 16))
	_palette = HBoxContainer.new()
	_palette.visible = false
	tv.add_child(_palette)
	_hotbar_box = HBoxContainer.new()
	_hotbar_box.add_theme_constant_override("separation", 6)
	_hotbar_box.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_child(_hotbar_box)
	# 左下：坐标和提示
	_coords = UIKit.outline(UIKit.label("", 18, UIKit.TEXT), 6)
	UIKit.place(_coords, Vector4(0, 1, 0, 1), Vector4(24, -40, 500, -12))
	root.add_child(_coords)
	_help = VBoxContainer.new()
	_help.add_theme_constant_override("separation", 6)
	UIKit.place(_help, Vector4(1, 1, 1, 1), Vector4(-470, -360, -24, -24))
	_help.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(_help)
	for p in [["jump", "放置（按住拖动）"], ["grab", "删除"], ["view_toggle", "试玩（按住加速键：从光标处）"], ["respawn", "撤销（按住加速键：重做）"], ["pause", "菜单"]]:
		_help.add_child(UIKit.prompt(p[0], p[1], 18))
	var dh := UIKit.label("十字键 ↑↓ 抬高/降低  ←→ 转朝向\nL3 框选铺满   R3 吸管\n键鼠：Shift+拖 框选  Q 吸管  1～0 快捷格  Ctrl+Z/Y", 15, UIKit.DIM)
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
	_build_picker(root)

func _refresh_bar() -> void:
	var list: Array = LevelData.BLOCKS if cat == 0 else LevelData.OBJECTS
	var cur: Array = list[sel[cat]]
	_bar_name.text = ("方块 · " if cat == 0 else "物件 · ") + str(cur[1])
	_desc.text = BlockIcon.describe(cat, sel[cat])
	_bar_icon.cat = cat
	_bar_icon.index = sel[cat]
	_bar_icon.queue_redraw()
	for c in _hotbar_box.get_children():
		c.queue_free()
	for i in hotbar.size():
		var h: Array = hotbar[i]
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		var ic := BlockIcon.make(int(h[0]), int(h[1]), 48 if i == slot else 40)
		ic.selected = i == slot
		ic.modulate.a = 1.0 if i == slot else 0.8
		v.add_child(ic)
		var num := UIKit.label(str((i + 1) % 10), 12, UIKit.ACCENT2 if i == slot else UIKit.DIM, true)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(num)
		_hotbar_box.add_child(v)

## 切换快捷格
func _select_slot(i: int) -> void:
	slot = i
	var h: Array = hotbar[slot]
	cat = int(h[0])
	sel[cat] = int(h[1])
	Sfx.play("ui_move", Vector3.INF, -10.0, 0.0)
	_refresh_bar()

## 把某个物块放进当前快捷格并选中
func _assign(c: int, i: int) -> void:
	hotbar[slot] = [c, i]
	_select_slot(slot)

# ---------------------------------------------------------------- 全部物块面板

const GROUPS := [
	["自然地形", [Blocks.GRASS, Blocks.DIRT, Blocks.SAND, Blocks.LOOSE, Blocks.ROCK, Blocks.CLIFF, Blocks.MOSS, Blocks.RUSTDUNE, Blocks.ORE, Blocks.LEAVES, Blocks.BLOSSOM, Blocks.WOOD]],
	["建筑", [Blocks.TILE, Blocks.PAVING, Blocks.HULL, Blocks.HULL_DARK, Blocks.METAL, Blocks.GLASS, Blocks.PLANK, Blocks.LAMP, Blocks.CRYSTAL]],
	["可破坏 / 机关", [Blocks.CRATE, Blocks.CRUMBLE, Blocks.GEM_CHAIN, Blocks.SCAFFOLD, Blocks.RUST, Blocks.REINFORCED, Blocks.BARREL]],
]

func _build_picker(root: Control) -> void:
	_picker = PanelContainer.new()
	_picker.add_theme_stylebox_override("panel", UIKit.panel(UIKit.BG_SOLID, UIKit.LINE, 22, 22))
	UIKit.place(_picker, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-560, -330, 560, 330))
	_picker.visible = false
	root.add_child(_picker)
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_picker.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var head := HBoxContainer.new()
	head.add_child(UIKit.label("全部物块", 30, UIKit.TEXT, true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UIKit.prompt("ui_accept", "放进快捷格", 16))
	head.add_child(UIKit.prompt("ui_cancel", "关闭", 16))
	v.add_child(head)
	var groups: Array = []
	for g in GROUPS:
		var idx: Array = []
		for t in g[1]:
			for i in LevelData.BLOCKS.size():
				if LevelData.BLOCKS[i][0] == t:
					idx.append([0, i])
		groups.append([g[0], idx])
	var used := {}
	for g in groups:
		for it in g[1]:
			used[it[1]] = true
	var rest: Array = []
	for i in LevelData.BLOCKS.size():
		if not used.has(i):
			rest.append([0, i])
	if not rest.is_empty():
		groups.append(["其他方块", rest])
	var collect: Array = []
	var enemies: Array = []
	for i in LevelData.OBJECTS.size():
		var id: String = LevelData.OBJECTS[i][0]
		if id in ["scrapling", "rustfly", "spikeshell", "sentinel", "mortar", "burrower"]:
			enemies.append([1, i])
		else:
			collect.append([1, i])
	groups.append(["物件 · 机关与收集", collect])
	groups.append(["物件 · 敌人", enemies])
	for g in groups:
		v.add_child(UIKit.label(g[0], 19, UIKit.ACCENT2, true))
		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		v.add_child(grid)
		if _picker_grid == null:
			_picker_grid = grid
		for it in g[1]:
			grid.add_child(_picker_button(int(it[0]), int(it[1])))

func _picker_button(c: int, i: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(172, 64)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = ""
	b.tooltip_text = BlockIcon.describe(c, i)
	b.set_meta("item", [c, i])
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.add_theme_constant_override("separation", 6)
	b.add_child(h)
	h.add_child(UIKit.make_spacer(4))
	h.add_child(BlockIcon.make(c, i, 46))
	var nm := UIKit.label(str((LevelData.BLOCKS if c == 0 else LevelData.OBJECTS)[i][1]), 16, UIKit.TEXT, true)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(nm)
	b.focus_entered.connect(func() -> void:
		_desc.text = BlockIcon.describe(c, i)
		Sfx.play("ui_move", Vector3.INF, -14.0, 0.0))
	b.pressed.connect(func() -> void:
		_assign(c, i)
		_close_picker())
	return b

func _open_picker() -> void:
	_picker.visible = true
	Sfx.play("ui_confirm", Vector3.INF, -8.0, 0.0)
	# 焦点放在当前选中的那一格
	var want := [cat, sel[cat]]
	var target: Button = null
	for b in _picker.find_children("*", "Button", true, false):
		if b.get_meta("item", []) == want:
			target = b
	if target == null:
		var all := _picker.find_children("*", "Button", true, false)
		if not all.is_empty():
			target = all[0]
	if target:
		target.grab_focus.call_deferred()

func _close_picker() -> void:
	_picker.visible = false
	Sfx.play("ui_back", Vector3.INF, -10.0, 0.0)
	_refresh_bar()

# ---------------------------------------------------------------- 吸管 / 框选 / 撤销

## 吸管：光标处有物件就吸物件，否则吸方块（脚下那一格）
func _eyedrop() -> void:
	var c := _mouse_cell if GameState.device == "kbm" and _mouse_cell.x >= 0 else cursor
	var oi := level.data.object_at(c)
	if oi >= 0:
		var id: String = level.data.objects[oi].id
		for i in LevelData.OBJECTS.size():
			if LevelData.OBJECTS[i][0] == id:
				_assign(1, i)
				_say("吸管：" + str(LevelData.OBJECTS[i][1]))
				return
	for q in [c, c + Vector3i.DOWN]:
		var t := world.get_block(q)
		if t != Blocks.AIR:
			for i in LevelData.BLOCKS.size():
				if LevelData.BLOCKS[i][0] == t:
					_assign(0, i)
					_say("吸管：" + str(LevelData.BLOCKS[i][1]))
					return
	_say("这里没有能吸的东西")

func _toggle_anchor() -> void:
	if _anchor.x == -999:
		_anchor = cursor
		_say("框选：移动光标拉出范围，✕ 铺满 / ○ 清空，再按 L3 取消")
	else:
		_anchor = Vector3i(-999, 0, 0)

## 在起点那一层铺满（或清空）一个矩形
func _fill_rect(a: Vector3i, b: Vector3i, erase: bool) -> void:
	if cat == 1 and not erase:
		_say("框选只能铺方块")
		return
	var lo := Vector3i(mini(a.x, b.x), a.y, mini(a.z, b.z))
	var hi := Vector3i(maxi(a.x, b.x), a.y, maxi(a.z, b.z))
	if (hi.x - lo.x + 1) * (hi.z - lo.z + 1) > 1600:
		_say("框选范围太大（最多 40 × 40）")
		return
	_begin_stroke()
	var t: int = Blocks.AIR if erase else LevelData.BLOCKS[sel[0]][0]
	var n := 0
	for z in range(lo.z, hi.z + 1):
		for x in range(lo.x, hi.x + 1):
			var c := Vector3i(x, lo.y, z)
			var old := world.get_block(c)
			if old == t:
				continue
			_rec_block(c, old, t)
			if erase:
				level.data.blocks.erase(c)
			else:
				level.data.blocks[c] = t
			world.set_block(c, t)
			n += 1
	_dirty_rebuild = true
	Sfx.play("rebuild_done" if not erase else "break_soft", world.voxel_center(cursor), -6.0, 0.05)
	GameState.rumble(0.4, 0.3, 0.12)
	_say(("清空了 %d 格" if erase else "铺了 %d 格") % n)

func _begin_stroke() -> void:
	if not _stroke.is_empty() and ((_stroke.blocks as Array).size() > 0 or _stroke.objects != null):
		_undo.append(_stroke)
		if _undo.size() > UNDO_MAX:
			_undo.pop_front()
		_redo.clear()
	_stroke = {"blocks": [], "objects": null}

func _rec_block(c: Vector3i, old: int, new: int) -> void:
	if _stroke.is_empty():
		_begin_stroke()
	(_stroke.blocks as Array).append([c, old, new])

func _rec_objects() -> void:
	if _stroke.is_empty():
		_begin_stroke()
	if _stroke.objects == null:
		_stroke.objects = level.data.objects.duplicate(true)

## 把正在进行的这一笔收进撤销栈
func _flush_stroke() -> void:
	_begin_stroke()
	_stroke = {}

func _undo_step() -> void:
	_flush_stroke()
	if _undo.is_empty():
		_say("没有可以撤销的了")
		return
	var st: Dictionary = _undo.pop_back()
	_redo.append(_apply_record(st, true))
	Sfx.play("ui_back", Vector3.INF, -6.0, 0.0)
	_say("撤销（还能撤销 %d 步）" % _undo.size())

func _redo_step() -> void:
	_flush_stroke()
	if _redo.is_empty():
		_say("没有可以重做的了")
		return
	var st: Dictionary = _redo.pop_back()
	_undo.append(_apply_record(st, false))
	Sfx.play("ui_confirm", Vector3.INF, -6.0, 0.0)
	_say("重做")

## 应用一条记录（backward = 撤销）；返回反向记录
func _apply_record(st: Dictionary, backward: bool) -> Dictionary:
	var inv := {"blocks": [], "objects": null}
	var bl: Array = st.blocks
	var order := range(bl.size() - 1, -1, -1) if backward else range(bl.size())
	for k in order:
		var e: Array = bl[k]
		var c: Vector3i = e[0]
		var t: int = e[1] if backward else e[2]
		if t == Blocks.AIR:
			level.data.blocks.erase(c)
		else:
			level.data.blocks[c] = t
		world.set_block(c, t)
		(inv.blocks as Array).append(e)
	if st.objects != null:
		inv.objects = level.data.objects.duplicate(true)
		level.data.objects = (st.objects as Array).duplicate(true)
		_refresh_markers()
	_dirty_rebuild = true
	return inv

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
			_mbtn("导出（分享给朋友）", func() -> void:
				var r: Dictionary = level.data.export_file()
				_menu.visible = false
				if not r.ok:
					_say("导出失败：写不进 " + str(r.path))
				elif r.dup:
					_say("这一关已经导出过了：" + str(r.path).get_file())
				else:
					_say("已导出：文档/立方7关卡/%s，把这个文件发给朋友就行" % str(r.path).get_file()))
			_mbtn("导入……", func() -> void: _open_menu("import"))
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
		"import":
			_menu_list.add_child(UIKit.label("导入关卡", 28, UIKit.TEXT, true))
			var tip := UIKit.label("把朋友发来的 .cube7 文件放进「文档/立方7关卡」，或者直接拖进游戏窗口。", 17, UIKit.DIM)
			tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			tip.custom_minimum_size.x = 520
			_menu_list.add_child(tip)
			var mine := {}
			for i in LevelData.SLOTS:
				var sd := LevelData.load_slot(i)
				if sd:
					mine[sd.content_hash()] = i
			for it in LevelData.list_exports():
				var d: LevelData = it.data
				var h := d.content_hash()
				var tag := "   （和本地位置 %d 一样）" % (int(mine[h]) + 1) if mine.has(h) else ""
				var b := _mbtn(d.name + tag, func() -> void:
					_menu.visible = false
					_load(d)
					_say("已导入：" + d.name))
				if first == null:
					first = b
			_mbtn("打开关卡文件夹", func() -> void:
				DirAccess.make_dir_recursive_absolute(LevelData.export_dir())
				OS.shell_open(LevelData.export_dir()))
			var back := _mbtn("返回", func() -> void: _open_menu("main"))
			if first == null:
				first = back
	if first:
		first.grab_focus.call_deferred()

func _on_files_dropped(files: PackedStringArray) -> void:
	for f in files:
		var d := LevelData.load_file(f)
		if d:
			if testing:
				_stop_test()
			_menu.visible = false
			_load(d)
			_say("已导入：" + d.name)
			return
	_say("这不是立方7的关卡文件（.cube7）")

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
	_undo.clear()
	_redo.clear()
	_stroke = {}
	level.load_data(d)
	var sp := d.find_object("spawn")
	if sp >= 0:
		cursor = d.objects[sp].cell
	_refresh_markers()
	_refresh_bar()
