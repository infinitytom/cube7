class_name ItemDispenser
extends Node3D
## 物件补给点（比如炭火盆）：场上没有这个物件时，隔几秒在这里生成一个新的。
## 火种、晶块这类“用掉就没了”的东西，靠它保证谜题不会卡死。

var item_id := "ember"
var color := Color("ff7a2a")
var delay := 2.0
var item: UsableItem
var _t := 0.0

func _ready() -> void:
	_spawn()

func _spawn() -> void:
	item = UsableItem.new()
	item.item_id = item_id
	item.color = color
	get_parent().add_child.call_deferred(item)
	await get_tree().process_frame
	if is_instance_valid(item):
		item.global_position = global_position
		item.home = global_position

func _physics_process(delta: float) -> void:
	if is_instance_valid(item):
		_t = 0.0
		return
	_t += delta
	if _t >= delay:
		_t = 0.0
		_spawn()
