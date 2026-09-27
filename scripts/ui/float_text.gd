class_name FloatText
extends Label3D
## 世界里飘起来的小字（撞不开时的提示、连击数、奖励……），升起后淡出。

static func spawn(parent: Node, pos: Vector3, text: String, color := Color.WHITE, size := 52, life := 1.1) -> FloatText:
	var f := FloatText.new()
	f.text = text
	f.font = UIKit.font(true)
	f.font_size = size
	f.outline_size = 16
	f.modulate = color
	f.outline_modulate = Color("2a2c6b")
	f.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	f.no_depth_test = true
	f.pixel_size = 0.005
	parent.add_child(f)
	f.global_position = pos
	f.scale = Vector3.ONE * 0.6
	var tw := f.create_tween()
	tw.tween_property(f, "scale", Vector3.ONE * 1.1, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(f, "scale", Vector3.ONE, 0.08)
	tw.parallel().tween_property(f, "position:y", f.position.y + 0.9, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(f, "modulate:a", 0.0, 0.35).set_delay(life - 0.35)
	tw.tween_callback(f.queue_free)
	return f
