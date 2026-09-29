extends Node
## 关卡编辑器测试：godot --headless --path . res://scenes/main.tscn -- --editor --debugscript=res://scripts/debug/test_editor.gd

var fails: Array[String] = []

func check(cond: bool, msg: String) -> void:
	print(("  [PASS] " if cond else "  [FAIL] ") + msg)
	if not cond:
		fails.append(msg)

func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)
	await get_tree().process_frame

func _ready() -> void:
	await wait(1.0)
	print("===== 关卡编辑器 =====")
	var main := get_parent()
	var ed: LevelEditor = main.find_children("*", "LevelEditor", false, false)[0]
	var W: VoxelWorld = main.world
	var L: EditorLevel = main.level
	check(ed != null and L.data != null, "编辑器打开，默认关卡有 %d 个方块、%d 个物件" % [L.data.blocks.size(), L.data.objects.size()])
	check(ed.cursor.y == LevelData.BASE_Y, "光标贴在地面上（y=%d）" % ed.cursor.y)
	# 放方块：原地连按三次 → 垒三层
	var c0 := ed.cursor
	for k in 3:
		await tap("jump")
	check(W.get_block(c0) != Blocks.AIR and W.get_block(c0 + Vector3i.UP * 2) != Blocks.AIR and ed.cursor.y == c0.y + 3, "原地按三次放置：垒起三层（光标升到 y=%d）" % ed.cursor.y)
	await tap("grab")
	check(W.get_block(c0 + Vector3i.UP * 2) == Blocks.AIR and ed.cursor.y == c0.y + 2, "删除：拿掉最上面一块")
	# 换方块
	var s0: int = ed.sel[0]
	await tap("form_next")
	check(ed.sel[0] == s0 + 1, "R1 换下一种方块（%s）" % LevelData.BLOCKS[ed.sel[0]][1])
	# 移动光标
	var cx := ed.cursor
	Input.action_press("move_right")
	await wait(0.3)
	Input.action_release("move_right")
	await get_tree().process_frame
	check(ed.cursor.x != cx.x or ed.cursor.z != cx.z, "左摇杆移动光标（%s → %s）" % [cx, ed.cursor])
	# 物件：切到物件，放一个金币和一只锈块兽
	ed._toggle_cat()
	check(ed.cat == 1, "切换到物件")
	ed.sel[1] = 3   # 金币
	ed.cursor = Vector3i(30, LevelData.BASE_Y, 36)
	await tap("jump")
	ed.sel[1] = 9   # 锈块兽
	ed.cursor = Vector3i(40, LevelData.BASE_Y, 30)
	await tap("jump")
	check(L.data.object_at(Vector3i(30, LevelData.BASE_Y, 36)) >= 0 and L.data.object_at(Vector3i(40, LevelData.BASE_Y, 30)) >= 0, "放下金币和锈块兽（共 %d 个物件）" % L.data.objects.size())
	# 导出 / 导入往返，重复导出会被认出
	var ex: Dictionary = L.data.export_file()
	var back := LevelData.load_file(ex.path)
	check(ex.ok and not ex.dup and back != null and back.content_hash() == L.data.content_hash(), "导出文件再导入一致（%s）" % str(ex.path).get_file())
	var ex2: Dictionary = L.data.export_file()
	check(ex2.dup and ex2.path == ex.path, "同样的关卡再导出一次 → 认出重复，不多生成文件")
	check(LevelData.list_exports().any(func(it: Dictionary) -> bool: return it.path == ex.path), "导入列表里能看到这个文件")
	DirAccess.remove_absolute(ex.path)
	# 本地保存防重复
	L.data.save_slot(3)
	check(L.data.duplicate_slot(4) == 3, "本地保存：同内容会被认出")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelData.slot_path(3)))
	# 存档往返
	L.data.save_slot(4)
	var ld := LevelData.load_slot(4)
	check(ld != null and ld.blocks.size() == L.data.blocks.size(), "保存到本地再读回来一致")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelData.slot_path(4)))
	# 试玩
	var blocks_before := W.data.duplicate()
	ed._start_test()
	await wait(1.5)
	var P: MorphBall = main.player
	check(ed.testing and not P.freeze, "△ 试玩：PIX 出现在出生点")
	var enemies := get_tree().get_nodes_in_group("enemy")
	check(enemies.size() >= 1, "试玩时敌人被生成出来（%d）" % enemies.size())
	# 试玩中拆点东西
	W.break_sphere(P.global_position + Vector3.DOWN * 0.6, 1.5, "impact", 14.0, Vector3.DOWN)
	await wait(0.3)
	# 滚到终点
	var gi := L.data.find_object("goal")
	var gc: Vector3i = L.data.objects[gi].cell
	P.teleport(W.voxel_top(gc + Vector3i.DOWN) + Vector3.UP * 0.6)
	await wait(1.8)
	check(not ed.testing, "到达终点：试玩结束，回到编辑")
	check(get_tree().get_nodes_in_group("enemy").is_empty(), "回到编辑后，试玩生成的敌人都清掉了")
	check(W.data == blocks_before, "试玩里拆掉的方块全部还原")
	ed._open_menu("main")
	await wait(0.1)
	ed._open_menu("import")
	await wait(0.1)
	check(ed._menu.visible and ed._menu_list.get_child_count() >= 4, "菜单：导入页能打开（%d 项）" % ed._menu_list.get_child_count())
	ed._menu.visible = false
	if fails.is_empty():
		print("===== 全部通过 =====")
	else:
		print("===== 失败 %d 项 =====" % fails.size())
	get_tree().quit()
