class_name SettingsPanel
extends PanelContainer
## 设置面板（标题画面和暂停菜单共用）

signal closed

var _first: Control

func _ready() -> void:
	theme = UIKit.theme()
	add_theme_stylebox_override("panel", UIKit.panel(UIKit.BG_SOLID, UIKit.LINE, 18, 30))
	custom_minimum_size = Vector2(620, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	add_child(v)
	v.add_child(UIKit.label("设置", 34, UIKit.TEXT, true))
	_first = _slider(v, "总音量", "master", 0.0, 1.0)
	_slider(v, "音乐", "music", 0.0, 1.0)
	_slider(v, "音效", "sfx", 0.0, 1.0)
	_slider(v, "镜头灵敏度", "cam_sens", 0.4, 2.0)
	_check(v, "镜头上下反转", "invert_y")
	_check(v, "屏幕震动", "shake")
	var back := Button.new()
	back.text = "返回"
	UIKit.juice(back)
	back.pressed.connect(func() -> void: closed.emit())
	v.add_child(back)

func open() -> void:
	visible = true
	_first.grab_focus.call_deferred()

func _slider(parent: Node, title: String, key: String, lo: float, hi: float) -> Control:
	var h := HBoxContainer.new()
	var l := UIKit.label(title, 22)
	l.custom_minimum_size.x = 170
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = float(Settings.get_v(key))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size.y = 32
	var fmt := func(x: float) -> String:
		return ("%.1f×" % x) if hi > 1.0 else ("%d%%" % roundi(x * 100))
	var val := UIKit.label(fmt.call(s.value), 20, UIKit.DIM)
	val.custom_minimum_size.x = 70
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(x: float) -> void:
		Settings.set_v(key, x)
		val.text = fmt.call(x))
	h.add_child(s)
	h.add_child(val)
	parent.add_child(h)
	return s

func _check(parent: Node, title: String, key: String) -> void:
	var c := CheckButton.new()
	c.text = title
	c.button_pressed = bool(Settings.get_v(key))
	c.add_theme_font_size_override("font_size", 22)
	c.toggled.connect(func(on: bool) -> void: Settings.set_v(key, on))
	parent.add_child(c)

func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("grab")):
		get_viewport().set_input_as_handled()
		closed.emit()
