class_name Credits
extends CanvasLayer
## 通关后的制作人员表：慢慢往上滚，最后停在“谢谢游玩”。按住 ✕/A 或 Enter 加速，结束后按任意键回标题。

signal finished

var _scroll: VBoxContainer
var _end: VBoxContainer
var _t := 0.0
var _done := false
var _can_exit := false

const LINES := [
	["title", "立方-7  Cube-7"],
	["gap", ""],
	["head", "一颗被锈蚀的星球，和一个会变形的小探测球"],
	["gap", ""],
	["role", "游戏设计 · 关卡 · 程序"], ["name", "Infinity Tom"],
	["role", "共同开发"], ["name", "Claude"],
	["gap", ""],
	["role", "主角"], ["name", "PIX（滚球 · 钻头 · 气泡）"],
	["role", "站点 AI"], ["name", "NOVA / 艾拉·林"],
	["role", "被救出来的居民"], ["name", "噗噗们"],
	["gap", ""],
	["role", "章节"],
	["name", "第一章 · 翠绿温室群岛"], ["name", "第二章 · 齿轮工坊"], ["name", "第三章 · 晶簇深渊"],
	["name", "第四章 · 云顶之城"], ["name", "第五章 · 锈海"], ["name", "终章 · 星核"],
	["gap", ""],
	["role", "引擎"], ["name", "Godot Engine 4 · Jolt Physics · Voxel Tools"],
	["role", "模型"], ["name", "Kenney（CC0）"],
	["role", "音乐采样"], ["name", "FluidR3 GM SoundFont"],
	["gap", ""],
	["head", "拆掉的，都能重建。"],
	["head", "忘掉的，总有人记得。"],
	["gap", ""],
	["gap", ""],
]

func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.theme = UIKit.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.08, 0.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	create_tween().tween_property(bg, "color:a", 0.92, 2.0)
	_scroll = VBoxContainer.new()
	_scroll.alignment = BoxContainer.ALIGNMENT_BEGIN
	_scroll.add_theme_constant_override("separation", 10)
	_scroll.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_scroll.position = Vector2(0, 760)
	root.add_child(_scroll)
	for l in LINES:
		var lab: Label
		match l[0]:
			"title":
				lab = UIKit.outline(UIKit.label(l[1], 64, Color.WHITE, true), 12)
			"head":
				lab = UIKit.label(l[1], 30, UIKit.ACCENT, true)
			"role":
				lab = UIKit.label(l[1], 20, UIKit.DIM)
			"name":
				lab = UIKit.label(l[1], 28, UIKit.TEXT, true)
			_:
				lab = UIKit.label(" ", 30)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_scroll.add_child(lab)
	_end = VBoxContainer.new()
	_end.alignment = BoxContainer.ALIGNMENT_CENTER
	_end.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end.modulate.a = 0.0
	root.add_child(_end)
	var thanks := UIKit.outline(UIKit.label("谢谢游玩！", 72, Color.WHITE, true), 12)
	thanks.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end.add_child(thanks)
	var stats := UIKit.label("", 22, UIKit.DIM)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.text = "星球重构完成 · 标题画面里可以继续回到任意一章，关卡编辑器也已开放"
	_end.add_child(stats)
	var hint := HBoxContainer.new()
	hint.alignment = BoxContainer.ALIGNMENT_CENTER
	hint.add_child(UIKit.prompt("ui_accept", "回到标题", 20))
	_end.add_child(hint)

func _process(delta: float) -> void:
	_t += delta
	if _done:
		return
	var fast := Input.is_action_pressed("ui_accept") or Input.is_action_pressed("jump")
	_scroll.position.y -= delta * (60.0 if not fast else 260.0)
	if _scroll.position.y + _scroll.size.y < 200.0:
		_done = true
		create_tween().tween_property(_end, "modulate:a", 1.0, 1.5)
		get_tree().create_timer(1.5).timeout.connect(func() -> void: _can_exit = true)

func _input(event: InputEvent) -> void:
	if _can_exit and (event.is_action_pressed("ui_accept") or event.is_action_pressed("jump") or event.is_action_pressed("pause")):
		_can_exit = false
		finished.emit()
		queue_free()
