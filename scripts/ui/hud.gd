class_name Hud
extends CanvasLayer
## 游戏界面（统一风格见 UIKit）
##   左上：金币 / 能源条 / 护盾 / 记忆碎片
##   右上：当前目标卡片
##   下方中间：NOVA 对话（全息头像 + 名牌 + 打字机 + 语音拟声）
##   左下：形态栏（未解锁显示锁）  右下：只显示当前有用的按键提示
##   中央：区域标题卡；右下角：自动保存提示

var _root: Control
var _coins: Label
var _energy_bar: ProgressBar
var _shields: Array[UIIcon] = []
var _frag_row: HBoxContainer
var _frag: Label
var _obj_card: PanelContainer
var _obj_text: Label
var _nova: PanelContainer
var _nova_text: RichTextLabel
var _nova_name: Label
var _portrait: Control
var _forms_row: HBoxContainer
var _form_badges: Array[PanelContainer] = []
var _form_name: Label
var _prompts: VBoxContainer
var _title_card: VBoxContainer
var _save_toast: HBoxContainer
var _queue: PackedStringArray = []
var _nova_time := 0.0
var _chars := 0.0
var _last_char := 0
var _pause: PauseMenu

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.theme = UIKit.theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_stats()
	_build_objective()
	_build_nova()
	_build_forms()
	_build_prompts()
	_build_title_card()
	_build_save_toast()
	GameState.level_cleared.connect(_show_clear)
	_pause = PauseMenu.new()
	add_child(_pause)
	GameState.coins_changed.connect(func(_v: int) -> void: _refresh_stats(true))
	GameState.energy_changed.connect(func(_v: int) -> void: _refresh_stats())
	GameState.shield_changed.connect(func(_v: int) -> void: _refresh_stats())
	GameState.fragments_changed.connect(func(_v: int) -> void: _refresh_stats())
	GameState.form_changed.connect(func(_i: int) -> void: _refresh_forms())
	GameState.form_unlocked.connect(_on_form_unlocked)
	GameState.device_changed.connect(func(_k: String) -> void: _refresh_prompts())
	GameState.nova_say.connect(func(t: String) -> void: _queue.append(t))
	GameState.objective_changed.connect(_on_objective)
	SaveGame.saved.connect(_on_saved)
	_refresh_stats()
	_refresh_forms()
	_refresh_prompts()
	if GameState.objective_index >= 0:
		_on_objective(GameState.objective_index, GameState.objective_text, GameState.objective_pos)

# ================================================================ 通关结算

func _show_clear() -> void:
	if Flow.mode == "debug" or get_tree().paused:
		return
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.05, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.panel(UIKit.BG_SOLID, UIKit.ACCENT2, 20, 36, 2))
	UIKit.place(p, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-330, -215, 330, 215))
	_root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	var small := UIKit.label("区域 1  ·  翠绿温室", 20, UIKit.ACCENT, true)
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(small)
	var big := UIKit.label("区域完成", 52, UIKit.TEXT, true)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(big)
	SaveGame.write()
	var rows := [
		["coin", UIKit.ACCENT2, "金币", str(GameState.coins)],
		["fragment", Color("c89bff"), "记忆碎片", "%d / 3" % GameState.fragments],
		["save", UIKit.ACCENT, "游戏时间", SaveGame.format_time(float(SaveGame.data.get("play_time", 0.0)))],
	]
	for r in rows:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		h.add_child(UIKit.make_spacer(80))
		h.add_child(UIIcon.make(r[0], r[1], 28))
		var l := UIKit.label(r[2], 24, UIKit.DIM)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(UIKit.label(r[3], 26, UIKit.TEXT, true))
		h.add_child(UIKit.make_spacer(80))
		v.add_child(h)
		h.modulate.a = 0.0
		create_tween().tween_property(h, "modulate:a", 1.0, 0.3).set_delay(0.4 + rows.find(r) * 0.25)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 16)
	v.add_child(btns)
	var stay := Button.new()
	stay.text = "继续探索"
	UIKit.juice(stay)
	stay.pressed.connect(func() -> void:
		dim.queue_free()
		p.queue_free()
		get_tree().paused = false
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	var home := Button.new()
	home.text = "返回标题"
	UIKit.juice(home)
	home.pressed.connect(func() -> void:
		SaveGame.write()
		Flow.goto_title())
	btns.add_child(stay)
	btns.add_child(home)
	home.grab_focus.call_deferred()
	p.pivot_offset = Vector2(330, 215)
	p.scale = Vector2(0.9, 0.9)
	p.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(p, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 1.0, 0.25)

# ================================================================ 构建

func _build_stats() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.panel(UIKit.BG, UIKit.LINE, 16, 14))
	UIKit.place(p, Vector4(0, 0, 0, 0), Vector4(24, 22, 290, 22))
	_root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var coin_row := HBoxContainer.new()
	coin_row.add_theme_constant_override("separation", 10)
	coin_row.add_child(UIIcon.make("coin", UIKit.ACCENT2, 30))
	_coins = UIKit.label("0", 30, Color.WHITE, true)
	coin_row.add_child(_coins)
	v.add_child(coin_row)
	var e_row := HBoxContainer.new()
	e_row.add_theme_constant_override("separation", 10)
	e_row.add_child(UIIcon.make("energy", UIKit.ACCENT, 22))
	_energy_bar = ProgressBar.new()
	_energy_bar.show_percentage = false
	_energy_bar.max_value = GameState.ENERGY_PER_SHIELD
	_energy_bar.custom_minimum_size = Vector2(150, 10)
	_energy_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := UIKit.panel(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 5, 0)
	var fg := UIKit.panel(UIKit.ACCENT, Color(0, 0, 0, 0), 5, 0)
	bg.shadow_size = 0
	fg.shadow_size = 0
	_energy_bar.add_theme_stylebox_override("background", bg)
	_energy_bar.add_theme_stylebox_override("fill", fg)
	e_row.add_child(_energy_bar)
	for i in GameState.max_shield:
		var s := UIIcon.make("shield", UIKit.GOOD, 20)
		_shields.append(s)
		e_row.add_child(s)
	v.add_child(e_row)
	_frag_row = HBoxContainer.new()
	_frag_row.add_theme_constant_override("separation", 10)
	_frag_row.add_child(UIIcon.make("fragment", Color("c9a6ff"), 22))
	_frag = UIKit.label("0 / 3", 20, Color("d9c6ff"), true)
	_frag_row.add_child(_frag)
	v.add_child(_frag_row)

func _build_objective() -> void:
	_obj_card = PanelContainer.new()
	var st := UIKit.panel(UIKit.BG, UIKit.ACCENT2, 16, 16, 0)
	st.border_width_left = 4
	_obj_card.add_theme_stylebox_override("panel", st)
	UIKit.place(_obj_card, Vector4(1, 0, 1, 0), Vector4(-470, 22, -24, 22))
	_obj_card.visible = false
	_root.add_child(_obj_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_obj_card.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(UIIcon.make("objective", UIKit.ACCENT2, 18))
	h.add_child(UIKit.label("目标", 16, UIKit.ACCENT2, true))
	v.add_child(h)
	_obj_text = UIKit.label("", 22, UIKit.TEXT, true)
	_obj_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_obj_text)

func _build_nova() -> void:
	_nova = PanelContainer.new()
	_nova.add_theme_stylebox_override("panel", UIKit.panel(UIKit.BG_SOLID, Color(0.31, 0.82, 1.0, 0.45), 18, 16, 2))
	UIKit.place(_nova, Vector4(0.5, 1, 0.5, 1), Vector4(-480, -250, 480, -250))
	_nova.visible = false
	_root.add_child(_nova)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	_nova.add_child(h)
	_portrait = NovaPortrait.new()
	_portrait.custom_minimum_size = Vector2(76, 76)
	h.add_child(_portrait)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	_nova_name = UIKit.label("NOVA · 站点 AI", 17, UIKit.ACCENT, true)
	v.add_child(_nova_name)
	# 富文本：台词里的按键直接显示成手柄 / 键盘图标
	_nova_text = RichTextLabel.new()
	_nova_text.bbcode_enabled = true
	_nova_text.fit_content = true
	_nova_text.scroll_active = false
	_nova_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_nova_text.add_theme_font_override("normal_font", UIKit.font())
	_nova_text.add_theme_font_size_override("normal_font_size", 24)
	_nova_text.add_theme_color_override("default_color", UIKit.TEXT)
	_nova_text.custom_minimum_size = Vector2(620, 0)
	_nova_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_nova_text)

func _build_forms() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	UIKit.place(v, Vector4(0, 1, 0, 1), Vector4(28, -150, 520, -28))
	v.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(v)
	_form_name = UIKit.outline(UIKit.label("", 22, Color.WHITE, true), 8)
	v.add_child(_form_name)
	_forms_row = HBoxContainer.new()
	_forms_row.add_theme_constant_override("separation", 10)
	v.add_child(_forms_row)
	for i in MorphBall.FORMS.size():
		var pc := PanelContainer.new()
		pc.custom_minimum_size = Vector2(56, 56)
		var c := CenterContainer.new()
		pc.add_child(c)
		_forms_row.add_child(pc)
		_form_badges.append(pc)
	var hint := HBoxContainer.new()
	hint.add_theme_constant_override("separation", 6)
	hint.name = "Hint"
	v.add_child(hint)

func _build_prompts() -> void:
	_prompts = VBoxContainer.new()
	_prompts.alignment = BoxContainer.ALIGNMENT_END
	_prompts.add_theme_constant_override("separation", 8)
	UIKit.place(_prompts, Vector4(1, 1, 1, 1), Vector4(-300, -220, -28, -28))
	_root.add_child(_prompts)

func _build_title_card() -> void:
	_title_card = VBoxContainer.new()
	_title_card.alignment = BoxContainer.ALIGNMENT_CENTER
	UIKit.place(_title_card, Vector4(0.5, 0.35, 0.5, 0.35), Vector4(-500, -90, 500, 90))
	_title_card.modulate.a = 0.0
	_title_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_title_card)

func _build_save_toast() -> void:
	_save_toast = HBoxContainer.new()
	_save_toast.add_theme_constant_override("separation", 8)
	UIKit.place(_save_toast, Vector4(1, 0, 1, 0), Vector4(-220, -60, -30, -30))
	_save_toast.alignment = BoxContainer.ALIGNMENT_END
	_save_toast.add_child(UIIcon.make("save", UIKit.ACCENT, 22))
	_save_toast.add_child(UIKit.outline(UIKit.label("已自动保存", 18, UIKit.TEXT, true), 6))
	_save_toast.modulate.a = 0.0
	_root.add_child(_save_toast)

# ================================================================ 刷新

func _refresh_stats(pop := false) -> void:
	_coins.text = str(GameState.coins)
	if pop:
		_coins.pivot_offset = _coins.size * 0.5
		var tw := create_tween()
		_coins.scale = Vector2(1.25, 1.25)
		tw.tween_property(_coins, "scale", Vector2.ONE, 0.18)
	_energy_bar.value = GameState.energy if GameState.shield < GameState.max_shield else GameState.ENERGY_PER_SHIELD
	for i in _shields.size():
		_shields[i].filled = i < GameState.shield
		_shields[i].queue_redraw()
	_frag_row.visible = GameState.fragments_total > 0
	_frag.text = "%d / %d" % [GameState.fragments, GameState.fragments_total]

func _refresh_forms() -> void:
	var p := GameState.player as MorphBall
	var cur := p.form if p else 0
	var unlocked_count := 0
	for i in _form_badges.size():
		var f: Dictionary = MorphBall.FORMS[i]
		var pc := _form_badges[i]
		var unlocked: bool = GameState.unlocked_forms[i]
		if unlocked:
			unlocked_count += 1
		var active := i == cur
		pc.visible = unlocked or i <= 2
		var st := UIKit.panel(Color(f.color, 0.3) if active else UIKit.BG, f.color if active else UIKit.LINE, 999, 4, 3 if active else 1)
		if active:
			st.shadow_color = Color(f.color, 0.5)
			st.shadow_size = 12
		pc.add_theme_stylebox_override("panel", st)
		pc.custom_minimum_size = Vector2(64, 64) if active else Vector2(50, 50)
		var c := pc.get_child(0)
		for ch in c.get_children():
			ch.queue_free()
		if unlocked:
			c.add_child(UIIcon.make("form_" + f.id, f.color if active else Color(f.color, 0.75), 30 if active else 22))
		else:
			c.add_child(UIIcon.make("lock", Color(1, 1, 1, 0.3), 18))
	_form_name.text = MorphBall.FORMS[cur].name if p else ""
	var hint: HBoxContainer = _forms_row.get_parent().get_node("Hint")
	for ch in hint.get_children():
		ch.queue_free()
	if unlocked_count > 1:
		hint.add_child(UIKit.glyph("form", 16))
		hint.add_child(UIKit.outline(UIKit.label("切换形态", 16, UIKit.DIM), 6))
	_refresh_prompts()

func _refresh_prompts() -> void:
	if _prompts == null:
		return
	for c in _prompts.get_children():
		c.queue_free()
	var p := GameState.player as MorphBall
	if p:
		_prompts.add_child(UIKit.prompt("ability", MorphBall.FORMS[p.form].ability, 24))
	_prompts.add_child(UIKit.prompt("boost", "加速", 24))
	if GameState.allow_jump and p:
		_prompts.add_child(UIKit.prompt("jump", MorphBall.FORMS[p.form].jump_name, 24))
	_prompts.add_child(UIKit.prompt("pause", "菜单", 24))
	if _form_badges.size() > 0:
		pass

func _on_form_unlocked(i: int) -> void:
	_refresh_forms()
	var pc := _form_badges[i]
	pc.pivot_offset = pc.size * 0.5
	var tw := create_tween()
	for k in 3:
		tw.tween_property(pc, "scale", Vector2.ONE * 1.35, 0.12)
		tw.tween_property(pc, "scale", Vector2.ONE, 0.12)
	show_area_title("新形态", MorphBall.FORMS[i].name, MorphBall.FORMS[i].ability)

func _on_objective(_i: int, text: String, _pos: Vector3) -> void:
	_obj_text.text = text
	_obj_card.visible = text != ""
	# 新目标：卡片从右侧滑入并闪一下
	_obj_card.modulate = Color(1.6, 1.4, 0.8, 0.0)
	var tw := create_tween().set_parallel()
	tw.tween_property(_obj_card, "modulate", Color.WHITE, 0.5)
	if _i > 0:
		Sfx.play("checkpoint", Vector3.INF, -10.0, 0.0)

func _on_saved() -> void:
	var tw := create_tween()
	tw.tween_property(_save_toast, "modulate:a", 1.0, 0.25)
	tw.tween_interval(1.6)
	tw.tween_property(_save_toast, "modulate:a", 0.0, 0.5)

## 屏幕中央的大标题（进入区域、解锁形态）
func show_area_title(small: String, big: String, sub := "") -> void:
	for c in _title_card.get_children():
		c.queue_free()
	var a := UIKit.outline(UIKit.label(small, 26, UIKit.ACCENT2, true), 8)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var b := UIKit.outline(UIKit.label(big, 72, Color.WHITE, true), 12, Color(0.03, 0.12, 0.25, 0.8))
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_card.add_child(a)
	_title_card.add_child(b)
	if sub != "":
		var c := UIKit.outline(UIKit.label(_fmt(sub), 24, UIKit.TEXT), 8)
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_title_card.add_child(c)
	var tw := create_tween()
	_title_card.scale = Vector2(0.92, 0.92)
	_title_card.pivot_offset = _title_card.size * 0.5
	tw.tween_property(_title_card, "modulate:a", 1.0, 0.5)
	tw.parallel().tween_property(_title_card, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.2)
	tw.tween_property(_title_card, "modulate:a", 0.0, 0.8)

## 把 {jump} 之类的占位符换成当前设备的按键
func _fmt(t: String) -> String:
	for key in GameState.GLYPHS["kbm"].keys():
		t = t.replace("{%s}" % key, "【%s】" % GameState.glyph(key))
	return t

func _fmt_rich(t: String) -> String:
	for key in GameState.GLYPHS["kbm"].keys():
		t = t.replace("{%s}" % key, " " + UIKit.glyph_bbcode(key, 30) + " ")
	return t

# ================================================================ NOVA 对话

func _process(delta: float) -> void:
	if _nova_time <= 0.0 and not _queue.is_empty():
		var t := _fmt_rich(_queue[0])
		_queue.remove_at(0)
		_nova_text.text = t
		t = _nova_text.get_parsed_text()
		_nova_text.visible_characters = 0
		_chars = 0.0
		_last_char = 0
		_nova_time = 2.8 + t.length() * 0.065
		_nova.visible = true
		_nova.modulate.a = 0.0
		create_tween().tween_property(_nova, "modulate:a", 1.0, 0.2)
	if _nova_time > 0.0:
		_nova_time -= delta
		_chars += delta * 38.0
		var n := int(_chars)
		_nova_text.visible_characters = n
		# 语音拟声：每两个字发一个音节
		var plain := _nova_text.get_parsed_text()
		if n != _last_char and n <= plain.length() and n % 2 == 0:
			var ch := plain.substr(n - 1, 1) if n > 0 else ""
			if ch.strip_edges() != "" and not ch in "，。！？、…—「」【】":
				Sfx.play("voice_nova", Vector3.INF, -12.0, 0.18)
		_last_char = n
		(_portrait as NovaPortrait).talking = n < plain.length()
		if _nova_time <= 0.0:
			var tw := create_tween()
			tw.tween_property(_nova, "modulate:a", 0.0, 0.25)
			tw.tween_callback(func() -> void: _nova.visible = _nova_time > 0.0)
