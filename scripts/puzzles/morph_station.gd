class_name MorphStation
extends Zone
## 变形站（致敬《平衡球》的材质变换器）：进入后切换到指定形态，并锁定/解锁自由变形

@export var set_form := 0
@export var lock := true

func _build() -> void:
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.9
	t.outer_radius = 1.05
	var c: Color = MorphBall.FORMS[set_form].color
	t.material = _glow_mat(c, 2.5)
	ring.mesh = t
	ring.rotation_degrees.z = 90.0
	add_child(ring)

func _on_player_entered() -> void:
	var p := GameState.player as MorphBall
	p.form_locked = false
	if p.form != set_form:
		p.apply_form(set_form, true)
	p.form_locked = lock
	if lock:
		GameState.say("变形站：已切换为%s，这段轨道内禁止自由变形。" % MorphBall.FORMS[set_form].name)
