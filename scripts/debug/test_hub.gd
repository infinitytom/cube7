extends Node
## GitHub 关卡库测试（配合本地假服务器）：godot --headless --path . res://scenes/main.tscn -- --editor --debugscript=res://scripts/debug/test_hub.gd

var fails: Array[String] = []

func check(cond: bool, msg: String) -> void:
	print(("  [PASS] " if cond else "  [FAIL] ") + msg)
	if not cond:
		fails.append(msg)

func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	print("===== GitHub 关卡库 / 防重复 =====")
	var main := get_parent()
	var ed: LevelEditor = main.find_children("*", "LevelEditor", false, false)[0]
	var hub: LevelHub = ed.hub
	hub.api = "http://127.0.0.1:8765"
	hub.repo = "test/levels"
	hub.token = ""
	var d := LevelData.new_default()
	d.name = "测试关 A"
	# 指纹：和名字无关、和方块有关
	var h1 := d.content_hash()
	var d2 := LevelData.from_share_code(d.share_code())
	d2.name = "改了个名字"
	check(d2.content_hash() == h1, "改名不改内容 → 指纹相同（%s）" % h1.left(16))
	var d3 := LevelData.from_share_code(d.share_code())
	d3.blocks[Vector3i(30, LevelData.BASE_Y, 30)] = Blocks.CRATE
	check(d3.content_hash() != h1, "多放一个方块 → 指纹不同")
	check(LevelHub.parse_repo("https://github.com/degnrui/cube7-levels.git") == "degnrui/cube7-levels" and LevelHub.parse_repo("a b") == "", "识别仓库地址")
	# 没令牌：先查重，再提示用浏览器
	var r0: Dictionary = await hub.upload(d)
	check(r0.status == "need_token", "没有令牌 → 提示用浏览器提交（%s）" % r0.status)
	check(hub.browser_submit_url(d).begins_with("https://github.com/test/levels/new/main/levels?filename=" + h1.left(16)), "浏览器提交地址带好了文件名和内容")
	hub.token = "ghp_" + "x".repeat(36)
	var r1: Dictionary = await hub.upload(d)
	check(r1.status == "ok", "上传 A：%s" % r1.msg)
	var r2: Dictionary = await hub.upload(d2)
	check(r2.status == "duplicate", "改名后再传 → 判定重复：%s" % r2.msg)
	var r3: Dictionary = await hub.upload(d3)
	check(r3.status == "ok", "改了内容的 → 可以上传")
	var lst: Dictionary = await hub.list_levels()
	check(lst.ok and lst.levels.size() == 2, "浏览关卡库：%d 关（%s）" % [lst.levels.size(), ", ".join(lst.levels.map(func(x: Dictionary) -> String: return x.name))])
	var got: LevelData = lst.levels[0].data if lst.levels.size() > 0 else null
	check(got != null and (got.content_hash() == h1 or got.content_hash() == d3.content_hash()), "下载下来的关卡内容和上传的一致")
	# 本地存档防重复
	d.save_slot(3)
	check(d2.duplicate_slot(4) == 3 and d3.duplicate_slot(4) == -1, "本地保存：同内容会被认出（位置 4）")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelData.slot_path(3)))
	# 仓库不存在
	hub.repo = "nobody/none"
	var r4: Dictionary = await hub.upload(d3)
	check(r4.status == "error", "仓库不存在 → 报错不上传：%s" % r4.msg)
	print("===== 全部通过 =====" if fails.is_empty() else "===== 失败 %d 项 =====" % fails.size())
	get_tree().quit()
