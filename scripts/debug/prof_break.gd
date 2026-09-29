extends Node
## 性能剖析：大量破坏 / 打怪之后每帧耗时。
## godot --headless --path . res://scenes/main.tscn -- --chapter=N --debugscript=res://scripts/debug/prof_break.gd

var P: MorphBall
var W: VoxelWorld
var _times: Array[float] = []
var _last := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var main := get_parent()
	P = main.player
	W = main.world
	P.debug_override = true
	_run()

func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	if _last > 0:
		_times.append((now - _last) / 1000.0)
	_last = now

func wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout

func _report(tag: String) -> void:
	var a := _times.duplicate()
	_times.clear()
	if a.is_empty():
		return
	a.sort()
	var s := 0.0
	for x in a:
		s += x
	print("%-18s frames=%4d avg=%6.2fms p95=%6.2fms max=%7.2fms nodes=%d chunks=%d ts=%.2f" % [tag, a.size(), s / a.size(), a[int(a.size() * 0.95)], a[-1], get_tree().get_node_count(), _count_chunks(), Engine.time_scale])

func _count_chunks() -> int:
	var n := 0
	for c in W.get_children():
		if c is VoxelChunk:
			n += 1
	return n

func _run() -> void:
	await wait(2.0)
	_times.clear()
	await wait(3.0)
	_report("baseline")
	# 大量破坏：以玩家为中心一圈一圈砸
	var c := P.global_position
	var t0 := Time.get_ticks_usec()
	for i in 24:
		var a := i * 0.7
		var p := c + Vector3(cos(a), 0, sin(a)) * (2.0 + i * 0.35) + Vector3.DOWN * 0.6
		W.break_sphere(p, 1.7, "impact", 16.0, Vector3.DOWN)
		GameState.hitstop(0.05)
		await get_tree().process_frame
	print("break loop took %.1fms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	_report("during breaks")
	await wait(1.0)
	_report("0-1s after")
	await wait(2.0)
	_report("1-3s after")
	# 打怪
	var es := get_tree().get_nodes_in_group("enemy")
	var k := 0
	for e in es:
		if e.has_method("defeat") and k < 10:
			e.defeat(true)
			k += 1
			await get_tree().process_frame
	print("defeated ", k)
	await wait(1.0)
	_report("kills 0-1s")
	await wait(3.0)
	_report("kills 1-4s")
	await wait(5.0)
	_report("later 4-9s")
	get_tree().quit()
