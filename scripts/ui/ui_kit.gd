class_name UIKit
extends RefCounted
## 统一的界面风格：配色、字体、面板、按钮、手柄按键图标。所有界面都从这里取样式。

const BG := Color(0.05, 0.07, 0.12, 0.82)
const BG_SOLID := Color(0.06, 0.08, 0.13, 0.96)
const LINE := Color(1, 1, 1, 0.10)
const ACCENT := Color("4fd1ff")
const ACCENT2 := Color("ffd166")
const TEXT := Color("eef3ff")
const DIM := Color("9aa7c2")
const DANGER := Color("ff6b8a")
const GOOD := Color("7dffb0")

const FONT_NAMES := ["Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", "Source Han Sans SC", "sans-serif"]

static var _font: SystemFont
static var _font_bold: SystemFont
static var _theme: Theme

static func font(bold := false) -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(FONT_NAMES)
		_font.font_weight = 400
		_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_font_bold = SystemFont.new()
		_font_bold.font_names = PackedStringArray(FONT_NAMES)
		_font_bold.font_weight = 700
	return _font_bold if bold else _font

static func panel(bg := BG, border := LINE, radius := 14, pad := 18, border_w := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 10
	s.anti_aliasing = true
	return s

## 全局主题：按钮、滑条、复选框统一风格（手柄焦点清晰可见）
static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 22
	t.set_color("font_color", "Label", TEXT)
	# 按钮
	var normal := panel(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.08), 12, 14)
	normal.content_margin_left = 24
	normal.content_margin_right = 24
	var hover := panel(Color(0.31, 0.82, 1.0, 0.16), ACCENT, 12, 14, 2)
	hover.content_margin_left = 24
	hover.content_margin_right = 24
	hover.shadow_color = Color(0.31, 0.82, 1.0, 0.35)
	hover.shadow_size = 14
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.31, 0.82, 1.0, 0.3)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(1, 1, 1, 0.02)
	for st in [["normal", normal], ["hover", hover], ["focus", hover], ["pressed", pressed], ["disabled", disabled], ["hover_pressed", pressed]]:
		t.set_stylebox(st[0], "Button", st[1])
	t.set_font("font", "Button", font(true))
	t.set_font_size("font_size", "Button", 24)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.3))
	t.set_constant("h_separation", "Button", 12)
	# 滑条
	var track := panel(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 4, 0)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := panel(ACCENT, Color(0, 0, 0, 0), 4, 0)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var knob := Image.create(22, 22, false, Image.FORMAT_RGBA8)
	knob.fill(Color(0, 0, 0, 0))
	for y in 22:
		for x in 22:
			var d := Vector2(x - 10.5, y - 10.5).length()
			if d < 10.5:
				knob.set_pixel(x, y, Color(1, 1, 1, clampf(10.5 - d, 0, 1)))
	var ktex := ImageTexture.create_from_image(knob)
	t.set_icon("grabber", "HSlider", ktex)
	t.set_icon("grabber_highlight", "HSlider", ktex)
	t.set_stylebox("focus", "HSlider", panel(Color(0, 0, 0, 0), ACCENT, 8, 0, 2))
	# 复选
	t.set_font("font", "CheckButton", font(true))
	t.set_stylebox("focus", "CheckButton", panel(Color(0.31, 0.82, 1.0, 0.12), ACCENT, 10, 8, 2))
	t.set_color("font_color", "CheckButton", TEXT)
	_theme = t
	return t

static func label(text: String, size := 22, color := TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func outline(l: Label, size := 8, color := Color(0, 0, 0, 0.55)) -> Label:
	l.add_theme_constant_override("outline_size", size)
	l.add_theme_color_override("font_outline_color", color)
	return l

## 锚点 + 偏移一次设好（anchors / offsets 都是 左, 上, 右, 下）
static func place(c: Control, anchors: Vector4, offsets: Vector4) -> void:
	c.anchor_left = anchors.x
	c.anchor_top = anchors.y
	c.anchor_right = anchors.z
	c.anchor_bottom = anchors.w
	c.offset_left = offsets.x
	c.offset_top = offsets.y
	c.offset_right = offsets.z
	c.offset_bottom = offsets.w

## 手柄 / 键盘按键图标：PS 的四个符号各有颜色，Xbox 字母各有颜色，键盘显示为键帽
static func glyph(action: String, size := 20) -> PanelContainer:
	var text := GameState.glyph(action)
	var col := Color(1, 1, 1, 0.9)
	var dev := GameState.device
	if dev == "ps":
		col = {"✕": Color("7fb4ff"), "○": Color("ff7b8a"), "□": Color("e89cff"), "△": Color("5ff0b8")}.get(text, col)
	elif dev == "xbox":
		col = {"A": Color("7ddc6b"), "B": Color("ff6b6b"), "X": Color("5fa8ff"), "Y": Color("ffd24d")}.get(text, col)
	var pc := PanelContainer.new()
	var round := text.length() <= 1
	var st := panel(Color(0, 0, 0, 0.45), col, 999 if round else 7, 0, 2)
	st.content_margin_left = 6 if round else 9
	st.content_margin_right = 6 if round else 9
	st.content_margin_top = 1
	st.content_margin_bottom = 2
	st.shadow_size = 0
	pc.add_theme_stylebox_override("panel", st)
	var l := label(text, size - 4, col, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = size - 6 if round else 0
	pc.add_child(l)
	return pc

static func make_spacer(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.x = w
	return c

## “按钮 + 说明”的一行提示
static func prompt(action: String, desc: String, size := 20) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(glyph(action, size))
	var l := label(desc, size - 2, TEXT)
	outline(l, 6)
	h.add_child(l)
	return h

## 给按钮加上焦点动效与音效
static func juice(b: Button) -> void:
	b.focus_entered.connect(func() -> void:
		b.pivot_offset = b.size * 0.5
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(1.04, 1.04), 0.08)
		Sfx.play("ui_move", Vector3.INF, -12.0, 0.03))
	b.focus_exited.connect(func() -> void:
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2.ONE, 0.08))
	b.mouse_entered.connect(func() -> void: b.grab_focus())
	b.pressed.connect(func() -> void: Sfx.play("ui_confirm", Vector3.INF, -8.0, 0.0))
