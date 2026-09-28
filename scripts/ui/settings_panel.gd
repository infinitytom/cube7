class_name SettingsPanel
extends PanelContainer
## 设置面板（标题画面和暂停菜单共用）。
## 专门为手柄做的：每一行都是一个能拿到焦点的整行，上下选行，左右（十字键 / 摇杆，按住会连续调）改数值，
## ✕/A 切换开关，○/B 返回。当前行有明显的高亮边框。鼠标也能直接拖、点。

signal closed

var _rows: Array[SettingRow] = []

func _ready() -> void:
	theme = UIKit.theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_stylebox_override("panel", UIKit.panel(UIKit.BG_SOLID, UIKit.LINE, 18, 22))
	custom_minimum_size = Vector2(680, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	add_child(v)
	v.add_child(UIKit.label("设置", 30, UIKit.TEXT, true))
	_row(v, "总音量", "master", 0.0, 1.0, 0.05)
	_row(v, "音乐", "music", 0.0, 1.0, 0.05)
	_row(v, "音效", "sfx", 0.0, 1.0, 0.05)
	_row(v, "镜头灵敏度", "cam_sens", 0.4, 2.0, 0.1)
	_row(v, "镜头距离", "cam_dist", 0.8, 1.4, 0.05)
	_row(v, "手柄震动", "rumble", 0.0, 1.0, 0.1)
	_row(v, "镜头上下反转", "invert_y")
	_row(v, "屏幕震动", "shake")
	_row(v, "冲撞辅助瞄准", "aim_assist")
	_row(v, "远景雾", "fog")
	var back := SettingRow.new()
	back.title = "返回"
	back.is_button = true
	back.activated.connect(func() -> void: closed.emit())
	v.add_child(back)
	_rows.append(back)
	var hint := HBoxContainer.new()
	hint.add_theme_constant_override("separation", 18)
	hint.add_child(UIKit.prompt("ui_accept", "切换", 16))
	hint.add_child(UIKit.prompt("ui_cancel", "返回", 16))
	var lr := UIKit.label("十字键 ←→ 调整", 16, UIKit.DIM)
	hint.add_child(lr)
	v.add_child(hint)
	for i in _rows.size():
		var r := _rows[i]
		var up := _rows[(i - 1 + _rows.size()) % _rows.size()]
		var dn := _rows[(i + 1) % _rows.size()]
		r.focus_neighbor_top = r.get_path_to(up)
		r.focus_neighbor_bottom = r.get_path_to(dn)
		r.focus_neighbor_left = r.get_path_to(r)
		r.focus_neighbor_right = r.get_path_to(r)

func open() -> void:
	visible = true
	for r in _rows:
		r.refresh()
	_rows[0].grab_focus.call_deferred()

func _row(parent: Node, title: String, key: String, lo := 0.0, hi := 1.0, step := 0.0) -> void:
	var r := SettingRow.new()
	r.title = title
	r.key = key
	r.lo = lo
	r.hi = hi
	r.step = step
	parent.add_child(r)
	_rows.append(r)

func _unhandled_input(event: InputEvent) -> void:
	# 注意用 is_visible_in_tree：面板挂在隐藏的暂停菜单下时自身 visible 仍为 true，
	# 以前这里会吞掉游戏里所有的“抓取”按键
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Sfx.play("ui_back", Vector3.INF, -8.0, 0.0)
		closed.emit()
