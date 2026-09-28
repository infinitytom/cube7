class_name SettingRow
extends PanelContainer
## 设置面板里的一行：标题 + 数值条（或开关），整行可聚焦。
##   滑条：←/→ 调整，按住会越调越快；鼠标可以点、拖
##   开关：✕/A 或 ←/→ 切换；鼠标点击切换
##   按钮（返回）：✕/A 触发

signal activated

var title := ""
var key := ""
var lo := 0.0
var hi := 1.0
var step := 0.0              ## 0 = 开关
var is_button := false

var _label: Label
var _bar_bg: Panel
var _bar_fill: Panel
var _value: Label
var _st_normal: StyleBoxFlat
var _st_focus: StyleBoxFlat
var _hold := 0.0
var _hold_dir := 0
var _repeat := 0.0

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = Vector2(0, 42)
	_st_normal = UIKit.panel(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.0), 12, 10, 0)
	_st_focus = UIKit.panel(Color(UIKit.ACCENT, 0.18), UIKit.ACCENT, 12, 10, 3)
	_st_normal.shadow_size = 0
	add_theme_stylebox_override("panel", _st_normal)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	_label = UIKit.label(title, 22, UIKit.TEXT, true)
	_label.custom_minimum_size.x = 190
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_label)
	if is_button:
		_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		_bar_bg = Panel.new()
		_bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_bar_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_bar_bg.custom_minimum_size = Vector2(0, 14)
		_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bgs := UIKit.panel(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 7, 0)
		bgs.shadow_size = 0
		_bar_bg.add_theme_stylebox_override("panel", bgs)
		h.add_child(_bar_bg)
		_bar_fill = Panel.new()
		_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fs := UIKit.panel(UIKit.ACCENT, Color(0, 0, 0, 0), 7, 0)
		fs.shadow_size = 0
		_bar_fill.add_theme_stylebox_override("panel", fs)
		_bar_bg.add_child(_bar_fill)
		_value = UIKit.label("", 20, UIKit.DIM, true)
		_value.custom_minimum_size.x = 78
		_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(_value)
		if step == 0.0:
			_bar_bg.custom_minimum_size = Vector2(0, 0)
			_bar_bg.visible = false
			var sp := Control.new()
			sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(sp)
			h.move_child(sp, 1)
	focus_entered.connect(func() -> void:
		add_theme_stylebox_override("panel", _st_focus)
		Sfx.play("ui_move", Vector3.INF, -12.0, 0.0))
	focus_exited.connect(func() -> void: add_theme_stylebox_override("panel", _st_normal))
	mouse_entered.connect(func() -> void: grab_focus())
	resized.connect(refresh)
	if _bar_bg:
		_bar_bg.resized.connect(refresh)
	refresh()

func _val():
	return Settings.get_v(key)

func refresh() -> void:
	if is_button or _value == null:
		return
	if step == 0.0:
		var on := bool(_val())
		_value.text = "开" if on else "关"
		_value.add_theme_color_override("font_color", UIKit.GOOD if on else UIKit.DIM)
		return
	var v := float(_val())
	var k := clampf((v - lo) / (hi - lo), 0.0, 1.0)
	if _bar_bg.size.x > 0.0:
		_bar_fill.position = Vector2.ZERO
		_bar_fill.size = Vector2(maxf(14.0, _bar_bg.size.x * k), _bar_bg.size.y)
	_value.text = ("%.2f×" % v) if hi > 1.0 else ("%d%%" % roundi(v * 100))

func _nudge(dir: int) -> void:
	if is_button:
		return
	if step == 0.0:
		_toggle()
		return
	var v := clampf(snappedf(float(_val()) + dir * step, step), lo, hi)
	if v != float(_val()):
		Settings.set_v(key, v)
		Sfx.play("ui_move", Vector3.INF, -10.0, 0.0, 0.9 + (v - lo) / (hi - lo) * 0.4)
		if key == "rumble":
			GameState.rumble(0.6, 0.6, 0.15)
	refresh()

func _toggle() -> void:
	Settings.set_v(key, not bool(_val()))
	Sfx.play("ui_confirm", Vector3.INF, -8.0, 0.0)
	refresh()

func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		accept_event()
		if is_button:
			Sfx.play("ui_confirm", Vector3.INF, -6.0, 0.0)
			activated.emit()
		elif step == 0.0:
			_toggle()
		return
	for d in [["ui_left", -1], ["ui_right", 1]]:
		if event.is_action_pressed(d[0], true):
			accept_event()
			if not event.is_echo():
				_hold_dir = d[1]
				_hold = 0.0
				_repeat = 0.0
				_nudge(d[1])
			return
		if event.is_action_released(d[0]):
			if _hold_dir == d[1]:
				_hold_dir = 0
			accept_event()
			return
	# 鼠标：点开关 / 在数值条上点、拖
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_button:
			activated.emit()
		elif step == 0.0:
			_toggle()
		else:
			_mouse_set(event.position)
		accept_event()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) and step > 0.0:
		_mouse_set(event.position)

func _mouse_set(local: Vector2) -> void:
	var bx := _bar_bg.get_global_rect()
	var gx := get_global_rect().position.x + local.x
	var k := clampf((gx - bx.position.x) / maxf(bx.size.x, 1.0), 0.0, 1.0)
	Settings.set_v(key, clampf(snappedf(lo + k * (hi - lo), step), lo, hi))
	refresh()

func _process(delta: float) -> void:
	# 按住 ←/→：0.35 秒后开始连续调，越按越快
	if _hold_dir == 0 or not has_focus():
		_hold_dir = 0
		return
	var action := "ui_left" if _hold_dir < 0 else "ui_right"
	if not Input.is_action_pressed(action):
		_hold_dir = 0
		return
	_hold += delta
	if _hold < 0.35:
		return
	_repeat -= delta
	if _repeat <= 0.0:
		_repeat = maxf(0.04, 0.12 - (_hold - 0.35) * 0.05)
		_nudge(_hold_dir)
