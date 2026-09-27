class_name Hud
extends CanvasLayer
## 界面：左上收集品与护盾，顶部 NOVA 对话，底部形态栏与按键提示（随设备切换 PS5 / Xbox / 键鼠图标）

const FONT_NAMES := ["Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", "Source Han Sans SC", "sans-serif"]

var _coins: Label
var _energy: Label
var _shield: Label
var _frag: Label
var _nova_panel: PanelContainer
var _nova_label: Label
var _form_slots: Array[Label] = []
var _hint: Label
var _form_hint: Label
var _pause: PanelContainer
var _pause_label: Label
var _queue: PackedStringArray = []
var _nova_time := 0.0
var _chars := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var font := SystemFont.new()
	font.font_names = PackedStringArray(FONT_NAMES)
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 22
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme
	add_child(root)

	# 左上：收集品
	var stats := VBoxContainer.new()
	stats.position = Vector2(28, 22)
	root.add_child(stats)
	_coins = _label(stats, 26, Color("ffd23f"))
	_energy = _label(stats, 22, Color("4dfcff"))
	_shield = _label(stats, 22, Color("9cff9c"))
	_frag = _label(stats, 22, Color("c9a6ff"))

	# 顶部：NOVA 对话
	_nova_panel = PanelContainer.new()
	_nova_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.06, 0.08, 0.14, 0.82), Color("46c3ff")))
	_place(_nova_panel, Vector4(0.5, 0, 0.5, 0), Vector4(-410, 24, 410, 24))
	_nova_panel.visible = false
	root.add_child(_nova_panel)
	_nova_label = Label.new()
	_nova_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_nova_label.add_theme_font_size_override("font_size", 22)
	_nova_panel.add_child(_nova_label)

	# 底部：形态栏
	var bottom := VBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	_place(bottom, Vector4(0.5, 1, 0.5, 1), Vector4(-330, -118, 330, -20))
	root.add_child(bottom)
	_form_hint = _label(bottom, 17, Color(1, 1, 1, 0.7))
	_form_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 10)
	bottom.add_child(bar)
	for i in MorphBall.FORMS.size():
		var pc := PanelContainer.new()
		pc.custom_minimum_size = Vector2(118, 46)
		bar.add_child(pc)
		var l := Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pc.add_child(l)
		_form_slots.append(l)

	# 右下：按键提示
	_hint = Label.new()
	_place(_hint, Vector4(1, 1, 1, 1), Vector4(-330, -220, -24, -20))
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	root.add_child(_hint)

	# 暂停
	_pause = PanelContainer.new()
	_pause.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.05, 0.1, 0.92), Color("ffd23f")))
	_place(_pause, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-320, -230, 320, 230))
	_pause.visible = false
	root.add_child(_pause)
	_pause_label = Label.new()
	_pause.add_child(_pause_label)

	GameState.coins_changed.connect(func(_v: int) -> void: _refresh_stats())
	GameState.energy_changed.connect(func(_v: int) -> void: _refresh_stats())
	GameState.shield_changed.connect(func(_v: int) -> void: _refresh_stats())
	GameState.fragments_changed.connect(func(_v: int) -> void: _refresh_stats())
	GameState.form_unlocked.connect(_on_form_unlocked)
	GameState.form_changed.connect(func(_i: int) -> void: _refresh_forms())
	GameState.device_changed.connect(func(_k: String) -> void: _refresh_hints())
	GameState.nova_say.connect(func(t: String) -> void: _queue.append(t))
	_refresh_stats()
	_refresh_forms()
	_refresh_hints()

## anchors = (左, 上, 右, 下) 锚点比例；offsets = 相对锚点的像素偏移
func _place(c: Control, anchors: Vector4, offsets: Vector4) -> void:
	c.anchor_left = anchors.x
	c.anchor_top = anchors.y
	c.anchor_right = anchors.z
	c.anchor_bottom = anchors.w
	c.offset_left = offsets.x
	c.offset_top = offsets.y
	c.offset_right = offsets.z
	c.offset_bottom = offsets.w

func _label(parent: Node, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)
	return l

func _panel_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(10)
	s.set_content_margin_all(16)
	return s

## 把 {jump} 之类的占位符换成当前设备的按键
func _fmt(t: String) -> String:
	for key in GameState.GLYPHS["kbm"].keys():
		t = t.replace("{%s}" % key, "【%s】" % GameState.glyph(key))
	return t

func _on_form_unlocked(i: int) -> void:
	_refresh_forms()
	var pc := _form_slots[i].get_parent() as Control
	pc.pivot_offset = pc.size * 0.5
	var tw := create_tween()
	for k in 3:
		tw.tween_property(pc, "scale", Vector2.ONE * 1.25, 0.12)
		tw.tween_property(pc, "scale", Vector2.ONE, 0.12)

func _refresh_stats() -> void:
	_coins.text = "◆ 金币  %d" % GameState.coins
	if GameState.shield < GameState.max_shield:
		_energy.text = "⚡ 能源  %d / %d（集满修复护盾）" % [GameState.energy, GameState.ENERGY_PER_SHIELD]
	else:
		_energy.text = "⚡ 能源  %d" % GameState.energy
	_shield.text = "护盾  " + "■".repeat(GameState.shield) + "□".repeat(GameState.max_shield - GameState.shield)
	_frag.visible = GameState.fragments_total > 0
	_frag.text = "◈ 记忆碎片  %d / %d" % [GameState.fragments, GameState.fragments_total]

func _refresh_forms() -> void:
	var p := GameState.player as MorphBall
	var current := p.form if p else 0
	for i in _form_slots.size():
		var f: Dictionary = MorphBall.FORMS[i]
		var l := _form_slots[i]
		var unlocked: bool = GameState.unlocked_forms[i]
		l.text = f.name if unlocked else "？"
		var pc := l.get_parent() as PanelContainer
		var active := i == current
		pc.add_theme_stylebox_override("panel", _panel_style(
			Color(f.color, 0.35) if active else Color(0.05, 0.06, 0.1, 0.7),
			f.color if active else Color(1, 1, 1, 0.15)))
		l.add_theme_color_override("font_color", Color.WHITE if active else Color(1, 1, 1, 0.55))
	_refresh_hints()

func _refresh_hints() -> void:
	var p := GameState.player as MorphBall
	var ability: String = MorphBall.FORMS[p.form].ability if p else "冲刺"
	_form_hint.text = "切换形态 %s · 直选 %s" % [GameState.glyph("form"), GameState.glyph("form_direct")]
	_hint.text = "\n".join([
		"移动  %s" % GameState.glyph("move"),
		"镜头  %s" % GameState.glyph("camera"),
		("跳跃  %s" % GameState.glyph("jump")) if GameState.allow_jump else "",
		"%s  %s" % [ability, GameState.glyph("ability")],
		"加速  %s" % GameState.glyph("boost"),
		"抓取/投掷  %s" % GameState.glyph("grab"),
		"俯视  %s   复位  %s" % [GameState.glyph("view_toggle"), GameState.glyph("respawn")],
	])
	_pause_label.text = "\n".join([
		"暂停", "",
		"当前设备：%s" % {"ps": "PS5 手柄", "xbox": "Xbox 手柄", "kbm": "键盘鼠标"}[GameState.device],
		"", _hint.text, "",
		"%s 继续" % GameState.glyph("pause"),
	])

func _process(delta: float) -> void:
	# NOVA 打字机效果
	if _nova_time <= 0.0 and not _queue.is_empty():
		var t := _fmt(_queue[0])
		_queue.remove_at(0)
		_nova_label.text = "NOVA：" + t
		_nova_label.visible_characters = 0
		_chars = 0.0
		_nova_time = 2.6 + t.length() * 0.06
		_nova_panel.visible = true
	if _nova_time > 0.0:
		_nova_time -= delta
		_chars += delta * 40.0
		_nova_label.visible_characters = int(_chars)
		if _nova_time <= 0.0:
			_nova_panel.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		var paused := not get_tree().paused
		get_tree().paused = paused
		_pause.visible = paused
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif get_tree().paused and event.is_action_pressed("jump"):
		get_tree().paused = false
		_pause.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
