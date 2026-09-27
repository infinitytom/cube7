extends Node
## 音效（自动加载为 Sfx）：Sfx.play("coin") 或 Sfx.play("break_hard", 位置)

const MIN_GAP := 0.045            ## 同一个音效的最短间隔（防止一次破坏几十块时叠爆）
var _cache := {}
var _last := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # 暂停菜单里也要有音效

func _stream(n: String) -> AudioStream:
	if not _cache.has(n):
		_cache[n] = load("res://audio/sfx/%s.ogg" % n)
	return _cache[n]

func play(n: String, pos := Vector3.INF, volume_db := 0.0, pitch_var := 0.08, pitch := 1.0) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(n, -10.0)) < MIN_GAP:
		return
	_last[n] = now
	var s := _stream(n)
	if s == null:
		return
	var p: Node
	if pos == Vector3.INF:
		var p2 := AudioStreamPlayer.new()
		p2.stream = s
		p2.volume_db = volume_db
		p2.pitch_scale = pitch + randf_range(-pitch_var, pitch_var)
		p2.bus = "SFX"
		p = p2
		add_child(p2)
		p2.play()
		p2.finished.connect(p2.queue_free)
	else:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = s
		p3.volume_db = volume_db
		p3.unit_size = 8.0
		p3.max_distance = 60.0
		p3.pitch_scale = pitch + randf_range(-pitch_var, pitch_var)
		p3.bus = "SFX"
		p = p3
		add_child(p3)
		p3.global_position = pos
		p3.play()
		p3.finished.connect(p3.queue_free)

## 方块破坏音效按材质分类
func break_sound(t: int, pos: Vector3) -> void:
	var n := "break_soft"
	match t:
		Blocks.GLASS:
			n = "break_glass"
		Blocks.CRATE, Blocks.CRATE_ITEM, Blocks.SUPPORT, Blocks.WOOD, Blocks.LEAVES:
			n = "break_wood"
		Blocks.ROCK, Blocks.ORE, Blocks.GEODE, Blocks.METAL:
			n = "break_hard"
	play(n, pos, -2.0, 0.15)
