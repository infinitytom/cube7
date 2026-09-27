class_name PauseMenu
extends CanvasLayer
## 暂停菜单：继续 / 回到检查点 / 操作说明 / 设置 / 返回标题（自动保存）

var _root: Control
var _panel: PanelContainer
var _list: VBoxContainer
var _controls: PanelContainer
var _settings: SettingsPanel
var _open := false

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.theme = UIKit.theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.07, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UIKit.panel(UIKit.BG_SOLID, UIKit.LINE, 20, 32))
	UIKit.place(_panel, Vector4(0, 0.5, 0, 0.5), Vector4(90, -300, 560, 300))
	_root.add_child(_panel)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 12)
	_panel.add_child(_list)
	_list.add_child(UIKit.label("暂停", 40, UIKit.TEXT, true))
	var obj := UIKit.label("", 20, UIKit.ACCENT2)
	obj.name = "Obj"
	obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(obj)
	_btn("继续游戏", close)
	_btn("回到检查点", func() -> void:
		close()
		GameState.respawn())
	_btn("操作说明", func() -> void: _show_controls())
	_btn("设置", func() -> void:
		_panel.visible = false
		_settings.open())
	_btn("保存并返回标题", func() -> void:
		SaveGame.write()
		close()
		Music.stop()
		Flow.goto_title())
	_settings = SettingsPanel.new()
	UIKit.place(_settings, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-310, -290, 310, 290))
	_settings.visible = false
	_settings.closed.connect(func() -> void:
		_settings.visible = false
		_panel.visible = true
		(_list.get_child(2) as Button).grab_focus())
	_root.add_child(_settings)

func _btn(t: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = t
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(400, 60)
	UIKit.juice(b)
	b.pressed.connect(cb)
	_list.add_child(b)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if _open:
			close()
		else:
			open()
	elif _open and event.is_action_pressed("ui_cancel") and _panel.visible and (_controls == null or not _controls.visible):
		get_viewport().set_input_as_handled()
		close()
	elif _open and _controls and _controls.visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept")):
		get_viewport().set_input_as_handled()
		_controls.visible = false
		_panel.visible = true
		(_list.get_child(4) as Button).grab_focus()

func open() -> void:
	if Flow.busy:
		return
	_open = true
	get_tree().paused = true
	Sfx.play("ui_confirm", Vector3.INF, -10.0, 0.0)
	_root.visible = true
	_panel.visible = true
	(_list.get_node("Obj") as Label).text = "当前目标：" + GameState.objective_text if GameState.objective_text != "" else ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	(_list.get_child(2) as Button).grab_focus.call_deferred()
	Music.duck(9999.0, 0.4)

func close() -> void:
	_open = false
	Sfx.play("ui_back", Vector3.INF, -10.0, 0.0)
	get_tree().paused = false
	_root.visible = false
	_settings.visible = false
	if _controls:
		_controls.visible = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Music.duck(0.0, 1.0)

func _show_controls() -> void:
	_panel.visible = false
	if _controls:
		_controls.queue_free()
	_controls = PanelContainer.new()
	_controls.add_theme_stylebox_override("panel", UIKit.panel(UIKit.BG_SOLID, UIKit.LINE, 20, 30))
	UIKit.place(_controls, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-330, -300, 330, 300))
	_root.add_child(_controls)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_controls.add_child(v)
	v.add_child(UIKit.label("操作说明", 34, UIKit.TEXT, true))
	var dev: String = {"ps": "PS5 手柄", "xbox": "Xbox 手柄", "kbm": "键盘鼠标"}[GameState.device]
	v.add_child(UIKit.label("当前设备：" + dev + "（会随你使用的设备自动切换）", 18, UIKit.DIM))
	for pair in [["move", "移动"], ["camera", "转动镜头"], ["ability", "形态能力"], ["boost", "加速"], ["grab", "抓取 / 投掷"],
			["form", "切换形态"], ["form_direct", "直接选择形态"], ["view_toggle", "俯视全景"], ["respawn", "回到检查点"]]:
		v.add_child(UIKit.prompt(pair[0], pair[1], 22))
	v.add_child(UIKit.label("按确认或返回键关闭", 16, UIKit.DIM))
