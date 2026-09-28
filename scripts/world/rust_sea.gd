class_name RustSea
extends Node3D
## 锈海：一直铺到天边的锈泥海面 + 潮汐。
## 潮水会周期性涨落：低潮时露出来的浅滩步道，涨潮时会被淹没——掉进锈泥里就回到检查点。
## 涨潮前会拉响汽笛、海面冒泡，给玩家足够的时间躲到高处。

signal tide_changed(rising: bool)

var low_y := 6.0            ## 低潮海面高度（米）
var high_y := 7.6           ## 高潮海面高度（米）
var tide := true            ## 是否有潮汐（Boss 战时关掉）
## 一个周期：低潮 LOW 秒 → 涨潮 RISE 秒 → 高潮 HIGH 秒 → 退潮 FALL 秒
const LOW := 14.0
const RISE := 3.0
const HIGH := 7.0
const FALL := 3.0
const WARN := 3.0           ## 涨潮前几秒开始预警

var level_y := 6.0
var _t := 0.0
var _plane: MeshInstance3D
var _warned := false
var _rising := false
var _bubbles: CPUParticles3D
var _mat: ShaderMaterial

func _ready() -> void:
	_plane = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3000, 3000)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/rust_sea.gdshader")
	pm.material = mat
	_mat = mat
	_plane.mesh = pm
	_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_plane)
	_bubbles = CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.16
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.85, 0.5, 0.3)
	bm.roughness = 0.3
	sm.material = bm
	_bubbles.mesh = sm
	_bubbles.amount = 60
	_bubbles.lifetime = 0.7
	_bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_bubbles.emission_box_extents = Vector3(30, 0.05, 30)
	_bubbles.direction = Vector3.UP
	_bubbles.spread = 10.0
	_bubbles.initial_velocity_min = 0.6
	_bubbles.initial_velocity_max = 1.4
	_bubbles.gravity = Vector3(0, -3, 0)
	_bubbles.emitting = false
	_bubbles.local_coords = false
	add_child(_bubbles)
	level_y = low_y
	_apply()

func phase() -> String:
	var c := fmod(_t, LOW + RISE + HIGH + FALL)
	if c < LOW:
		return "low"
	if c < LOW + RISE:
		return "rise"
	if c < LOW + RISE + HIGH:
		return "high"
	return "fall"

## 距离下一次涨潮还有几秒（正在涨/高潮时返回 0）
func time_to_rise() -> float:
	var c := fmod(_t, LOW + RISE + HIGH + FALL)
	return maxf(0.0, LOW - c) if c < LOW else 0.0

## 灯塔重建以后：锈海慢慢褪色，变回原来的蓝（重构的奖励画面）
func purify(dur := 8.0, instant := false) -> void:
	var to := {"deep_color": Color(0.05, 0.22, 0.36), "mid_color": Color(0.12, 0.45, 0.62), "foam_color": Color(0.75, 0.93, 1.0)}
	for k in to:
		if instant:
			_mat.set_shader_parameter(k, to[k])
		else:
			var defaults := {"deep_color": Color(0.26, 0.10, 0.07), "mid_color": Color(0.52, 0.22, 0.12), "foam_color": Color(0.86, 0.52, 0.32)}
			var cur = _mat.get_shader_parameter(k)
			var from: Color = defaults[k] if cur == null else (Color(cur.x, cur.y, cur.z) if cur is Vector3 else cur)
			var tw := create_tween()
			tw.tween_method(func(c: Color) -> void: _mat.set_shader_parameter(k, c), from, to[k], dur).set_trans(Tween.TRANS_SINE)

func set_calm(y: float) -> void:
	tide = false
	level_y = y
	_apply()

func _process(delta: float) -> void:
	if tide:
		_t += delta
		var c := fmod(_t, LOW + RISE + HIGH + FALL)
		var want := low_y
		if c < LOW:
			want = low_y
			if c > LOW - WARN and not _warned:
				_warned = true
				Sfx.play("enemy_windup", Vector3.INF, -4.0, 0.0, 0.55)
				tide_changed.emit(true)
		elif c < LOW + RISE:
			want = lerpf(low_y, high_y, smoothstep(0.0, 1.0, (c - LOW) / RISE))
		elif c < LOW + RISE + HIGH:
			want = high_y
			_warned = false
		else:
			want = lerpf(high_y, low_y, smoothstep(0.0, 1.0, (c - LOW - RISE - HIGH) / FALL))
			if not _rising:
				pass
		var rising := c > LOW - WARN and c < LOW + RISE
		if rising != _rising:
			_rising = rising
		_bubbles.emitting = rising
		level_y = want
	_apply()

func _apply() -> void:
	var p := GameState.player as Node3D
	var cx := p.global_position.x if p else 0.0
	var cz := p.global_position.z if p else 0.0
	_plane.global_position = Vector3(cx, level_y, cz)
	_bubbles.global_position = Vector3(cx, level_y, cz)
	GameState.kill_y = level_y - 0.35
