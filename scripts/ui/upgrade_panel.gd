class_name UpgradePanel
extends PanelContainer
## 改装面板：用金币给 PIX 升级。上下选，✕/A 购买，○/B 返回。

signal closed

var _rows: Array[Control] = []
var _coins: Label
var _list: VBoxContainer

func _ready() -> void:
	theme = UIKit.theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_stylebox_override("panel", UIKit.panel(UIKit.BG_SOLID, UIKit.LINE, 18, 28))
	custom_minimum_size = Vector2(760, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_child(UIKit.label("改装 PIX", 34, UIKit.TEXT, true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UIIcon.make("coin", UIKit.ACCENT2, 28))
	_coins = UIKit.label("0", 28, Color.WHITE, true)
	head.add_child(_coins)
	v.add_child(head)
	v.add_child(UIKit.label("金币可以在这里换成永久的升级，跨章节保留。", 17, UIKit.DIM))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	v.add_child(_list)
	for u in Upgrades.LIST:
		var r := _make_row(u)
		_list.add_child(r)
		_rows.append(r)
	var hint := HBoxContainer.new()
	hint.add_theme_constant_override("separation", 18)
	hint.add_child(UIKit.prompt("ui_accept", "购买", 16))
	hint.add_child(UIKit.prompt("ui_cancel", "返回", 16))
	v.add_child(hint)
	for i in _rows.size():
		var r := _rows[i]
		r.focus_neighbor_top = r.get_path_to(_rows[(i - 1 + _rows.size()) % _rows.size()])
		r.focus_neighbor_bottom = r.get_path_to(_rows[(i + 1) % _rows.size()])

func open() -> void:
	visible = true
	_refresh()
	_rows[0].grab_focus.call_deferred()

func _make_row(u: Dictionary) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.focus_mode = Control.FOCUS_ALL
	pc.custom_minimum_size = Vector2(0, 58)
	var st_n := UIKit.panel(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 12, 10, 0)
	st_n.shadow_size = 0
	var st_f := UIKit.panel(Color(UIKit.ACCENT, 0.18), UIKit.ACCENT, 12, 10, 3)
	pc.add_theme_stylebox_override("panel", st_n)
	pc.focus_entered.connect(func() -> void:
		pc.add_theme_stylebox_override("panel", st_f)
		Sfx.play("ui_move", Vector3.INF, -12.0, 0.0))
	pc.focus_exited.connect(func() -> void: pc.add_theme_stylebox_override("panel", st_n))
	pc.mouse_entered.connect(func() -> void: pc.grab_focus())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(h)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 0)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(tv)
	tv.add_child(UIKit.label(u.name, 22, UIKit.TEXT, true))
	tv.add_child(UIKit.label(u.desc, 15, UIKit.DIM))
	var pips := HBoxContainer.new()
	pips.name = "Pips"
	pips.add_theme_constant_override("separation", 4)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(pips)
	var cost := UIKit.label("", 20, UIKit.ACCENT2, true)
	cost.name = "Cost"
	cost.custom_minimum_size.x = 110
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(cost)
	pc.set_meta("id", u.id)
	pc.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed("ui_accept") or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
			pc.accept_event()
			_buy(pc))
	return pc

func _buy(pc: Control) -> void:
	var id: String = pc.get_meta("id")
	if Upgrades.buy(id):
		Sfx.play("success", Vector3.INF, -4.0, 0.0)
		GameState.rumble(0.5, 0.4, 0.15)
		var tw := pc.create_tween()
		pc.pivot_offset = pc.size * 0.5
		pc.scale = Vector2(1.04, 1.04)
		tw.tween_property(pc, "scale", Vector2.ONE, 0.2)
	else:
		Sfx.play("ui_back", Vector3.INF, -6.0, 0.0)
		var tw := pc.create_tween()
		for k in 3:
			tw.tween_property(pc, "position:x", pc.position.x + 6.0, 0.04)
			tw.tween_property(pc, "position:x", pc.position.x - 6.0, 0.04)
		tw.tween_property(pc, "position:x", pc.position.x, 0.04)
	_refresh()

func _refresh() -> void:
	_coins.text = str(GameState.coins)
	for pc in _rows:
		var id: String = pc.get_meta("id")
		var pips := pc.find_child("Pips", true, false) as HBoxContainer
		for c in pips.get_children():
			c.queue_free()
		for k in Upgrades.max_level(id):
			var d := ColorRect.new()
			d.custom_minimum_size = Vector2(16, 16)
			d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			d.color = UIKit.GOOD if k < Upgrades.level(id) else Color(1, 1, 1, 0.15)
			d.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pips.add_child(d)
		var cost := pc.find_child("Cost", true, false) as Label
		var c := Upgrades.next_cost(id)
		if c < 0:
			cost.text = "已满级"
			cost.add_theme_color_override("font_color", UIKit.GOOD)
		else:
			cost.text = "◉ %d" % c
			cost.add_theme_color_override("font_color", UIKit.ACCENT2 if GameState.coins >= c else Color(1, 0.5, 0.45))

func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Sfx.play("ui_back", Vector3.INF, -8.0, 0.0)
		closed.emit()
