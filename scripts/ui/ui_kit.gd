class_name UIKit
extends RefCounted
## 统一的界面风格：配色、字体、面板、按钮、手柄按键图标。所有界面都从这里取样式。

## 可爱科幻配色：深靛蓝底 + 天空蓝 / 阳光黄点缀（和 Kenney 粉彩素材一致）
const BG := Color(0.14, 0.15, 0.36, 0.86)
const BG_SOLID := Color(0.16, 0.17, 0.39, 0.97)
const LINE := Color(1, 1, 1, 0.16)
const ACCENT := Color("62dcff")
const ACCENT2 := Color("ffd769")
const TEXT := Color("fdfaff")
const DIM := Color("bcc0ea")
const DANGER := Color("ff7a9c")
const GOOD := Color("66daa3")

## 字体：英文数字用圆润的 Fredoka，中文用站酷快乐体（都是 OFL 开源字体）
const FONT_LATIN := "res://assets/fonts/Fredoka.ttf"
const FONT_CJK := "res://assets/fonts/ZCOOLKuaiLe.ttf"

static var _font: Font
static var _font_bold: Font
static var _theme: Theme

static func font(bold := false) -> Font:
	if _font == null:
		var cjk := load(FONT_CJK) as FontFile
		var latin := load(FONT_LATIN) as FontFile
		var cjk_bold := FontVariation.new()
		cjk_bold.base_font = cjk
		cjk_bold.variation_embolden = 0.55
		var reg := FontVariation.new()
		reg.base_font = latin
		reg.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 500}
		reg.fallbacks = [cjk]
		var bold_v := FontVariation.new()
		bold_v.base_font = latin
		bold_v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 650}
		bold_v.fallbacks = [cjk_bold]
		_font = reg
		_font_bold = bold_v
	return _font_bold if bold else _font

static func panel(bg := BG, border := LINE, radius := 20, pad := 18, border_w := 2) -> StyleBoxFlat:
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

## 手柄 / 键盘按键图标：用 Kenney Input Prompts 的真实按键图（PS5 / Xbox / 键鼠自动切换）
const PROMPTS := {
	"ps": {"jump": ["color_cross"], "ability": ["color_square"], "grab": ["color_circle"], "view_toggle": ["color_triangle"],
		"boost": ["r2"], "form": ["l1", "r1"], "form_direct": ["dpad"], "respawn": ["create"], "pause": ["options"],
		"move": ["stick_l"], "camera": ["stick_r"], "ui_accept": ["color_cross"], "ui_cancel": ["color_circle"]},
	"xbox": {"jump": ["color_a"], "ability": ["color_x"], "grab": ["color_b"], "view_toggle": ["color_y"],
		"boost": ["rt"], "form": ["lb", "rb"], "form_direct": ["dpad_all"], "respawn": ["view"], "pause": ["menu"],
		"move": ["stick_l"], "camera": ["stick_r"], "ui_accept": ["color_a"], "ui_cancel": ["color_b"]},
	"kbm": {"jump": ["keyboard_space"], "ability": ["mouse_left"], "grab": ["keyboard_e"], "view_toggle": ["keyboard_v"],
		"boost": ["keyboard_shift"], "form": ["mouse_scroll"], "form_direct": ["keyboard_1", "keyboard_2", "keyboard_3"],
		"respawn": ["keyboard_r"], "pause": ["keyboard_escape"], "move": ["keyboard_w", "keyboard_a", "keyboard_s", "keyboard_d"],
		"camera": ["mouse_move"], "ui_accept": ["keyboard_enter"], "ui_cancel": ["keyboard_escape"]},
}

## 某个动作在当前设备上的图标路径（可能有多个，比如 L1 + R1）
static func prompt_paths(action: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dev := GameState.device
	for n in (PROMPTS[dev] as Dictionary).get(action, []):
		out.append("res://assets/prompts/%s/%s.png" % [dev, n])
	return out

static func glyph(action: String, size := 20) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	var paths := prompt_paths(action)
	if paths.is_empty():
		var l := label(GameState.glyph(action), size - 2, TEXT, true)
		h.add_child(l)
		return h
	for p in paths:
		var t := TextureRect.new()
		t.texture = load(p)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# 键盘图标的按键本体只占画布中间一小块，放大一些才和手柄图标一样醒目
		var k := 1.9 if p.contains("/kbm/") else 1.35
		t.custom_minimum_size = Vector2(size, size) * k
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(t)
	return h

## 富文本里内嵌的按键图标（NOVA 对话用）
static func glyph_bbcode(action: String, size := 30) -> String:
	var paths := prompt_paths(action)
	if paths.is_empty():
		return "【%s】" % GameState.glyph(action)
	var s := ""
	for p in paths:
		s += "[img=%d]%s[/img]" % [int(size * (1.6 if p.contains("/kbm/") else 1.0)), p]
	return s

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
