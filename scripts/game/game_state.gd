extends Node
## 全局状态（自动加载）：收集品、护盾、检查点、NOVA 台词、输入设备与按键图标

signal coins_changed(value: int)
signal energy_changed(value: int)
signal shield_changed(value: int)
signal nova_say(text: String)
@warning_ignore("unused_signal")
signal form_changed(index: int)
signal device_changed(kind: String)
signal level_cleared
signal form_unlocked(index: int)
signal fragments_changed(value: int)
signal seeds_changed(value: int)
@warning_ignore("unused_signal")
signal challenge_changed(active: bool, time_left: float, got: int, total: int)
signal objective_changed(index: int, text: String, pos: Vector3)
@warning_ignore("unused_signal")
signal shake(amount: float)

const ENERGY_PER_SHIELD := 10

var coins := 0
var energy := 0
var shield := 3
var max_shield := 3
var blocks_broken := 0:
	set(v):
		if v > blocks_broken:
			_combo_hit(v - blocks_broken)
		blocks_broken = v
		if v == 80:
			say("你是拆迁队吗？……好吧，拆得还挺专业。")

# ---------------------------------------------------------------- 连拆（连击）
## 1.6 秒内不停地拆东西会累积“连拆”，断掉时按连击数奖励金币——拆得越爽，拿得越多
signal combo_changed(count: int)
signal combo_finished(count: int, bonus: int)
const COMBO_WINDOW := 1.6
var combo := 0
var _combo_t := 0.0

func _combo_hit(n: int) -> void:
	combo += n
	_combo_t = COMBO_WINDOW
	combo_changed.emit(combo)

func add_combo(n: int) -> void:
	_combo_hit(n)

func _process(delta: float) -> void:
	if combo > 0:
		_combo_t -= delta
		if _combo_t <= 0.0:
			var bonus := 0
			if combo >= 8:
				bonus = combo / 4 + (10 if combo >= 30 else 0) + (25 if combo >= 60 else 0)
				add_coins(bonus)
			combo_finished.emit(combo, bonus)
			combo = 0
var player: Node3D
var camera: Node3D
var seeds := 0                      ## 本章救出的噗噗（打开的种子方块）
var seeds_total := 3
var checkpoint := Vector3(4.75, 3.5, 16.0)
var checkpoint_form := -1          ## 复活时强制的形态（-1 = 不改）
var checkpoint_locks_form := false
var device := "kbm"                ## "ps" / "xbox" / "kbm"
var unlocked_forms: Array[bool] = [true, true, true]
var kill_y := -6.0                 ## 掉到这个高度以下就回检查点（由关卡设置）
var allow_jump := true             ## 每种形态跳法不同；个别关卡（如平衡轨道）可以关掉
var enemies_defeated := 0
var fragments := 0
var level_complete := false
var fragments_total := 0
var fragment_logs: PackedStringArray = []
var objective_index := -1
var objective_text := ""
var objective_pos := Vector3.INF

## 推进目标：只会往前推进（重复触发旧目标会被忽略）
func set_objective(index: int, text: String, pos := Vector3.INF) -> void:
	if index <= objective_index:
		return
	objective_index = index
	objective_text = text
	objective_pos = pos
	objective_changed.emit(index, text, pos)

## 关卡开始时调用：重置收集进度
func reset_for_level(forms: Array[bool], jump: bool, kill: float, fragment_count: int) -> void:
	unlocked_forms = forms.duplicate()
	allow_jump = jump
	kill_y = kill
	fragments = 0
	seeds = 0
	objective_index = -1
	objective_text = ""
	objective_pos = Vector3.INF
	level_complete = false
	fragments_total = fragment_count
	fragment_logs = []
	coins = 0
	energy = 0
	shield = max_shield
	blocks_broken = 0
	enemies_defeated = 0

func unlock_form(i: int) -> void:
	if unlocked_forms[i]:
		return
	unlocked_forms[i] = true
	form_unlocked.emit(i)

## 打开种子方块、救出一只噗噗（存档里记下 id）
func add_seed(id: String) -> void:
	seeds += 1
	seeds_changed.emit(seeds)
	if id != "" and not SaveGame.data.is_empty():
		var arr: Array = SaveGame.data.get("seeds", [])
		if not id in arr:
			arr.append(id)
		SaveGame.data["seeds"] = arr
		SaveGame.write()
	if seeds == 1:
		get_tree().create_timer(5.0).timeout.connect(func() -> void:
			say("种子方块里封存的居民……还活着。太好了。每一座浮岛上都有，把他们都找回来吧。"))
	elif seeds == seeds_total:
		get_tree().create_timer(5.0).timeout.connect(func() -> void:
			say("这片浮岛上的噗噗全部救出来了！避难所那边……热闹得有点吵。"))

func add_fragment(log_text: String) -> void:
	fragments += 1
	fragment_logs.append(log_text)
	fragments_changed.emit(fragments)

# ---------------------------------------------------------------- 收集

func add_coins(n: int) -> void:
	coins += n
	coins_changed.emit(coins)

func add_energy(n: int) -> void:
	energy += n
	# 每 10 点能源自动修复 1 格护盾
	while energy >= ENERGY_PER_SHIELD and shield < max_shield:
		energy -= ENERGY_PER_SHIELD
		shield += 1
		shield_changed.emit(shield)
	energy_changed.emit(energy)

func damage(n := 1) -> void:
	shield = maxi(shield - n, 0)
	shield_changed.emit(shield)
	if shield == 0:
		shield = max_shield
		shield_changed.emit(shield)
		respawn()

func respawn() -> void:
	Sfx.play("respawn", Vector3.INF, -4.0)
	Sfx.play("pix_hurt", Vector3.INF, -8.0, 0.1)
	if player and player.has_method("respawn_at"):
		player.respawn_at(checkpoint, checkpoint_form, checkpoint_locks_form)

func set_checkpoint(pos: Vector3, form := -1, locks := false) -> void:
	checkpoint = pos
	checkpoint_form = form
	checkpoint_locks_form = locks

func say(text: String) -> void:
	nova_say.emit(text)

# ---------------------------------------------------------------- 输入设备识别

func _input(event: InputEvent) -> void:
	var kind := device
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.4):
		var joy_name := Input.get_joy_name(event.device).to_lower()
		if "ps" in joy_name or "dualsense" in joy_name or "sony" in joy_name or "wireless controller" in joy_name or "playstation" in joy_name:
			kind = "ps"
		else:
			kind = "xbox"
	elif event is InputEventKey or event is InputEventMouseButton:
		kind = "kbm"
	if kind != device:
		device = kind
		device_changed.emit(device)

const GLYPHS := {
	"ps": {"jump": "✕", "ability": "□", "grab": "○", "view_toggle": "△", "boost": "R2", "form": "L1/R1", "form_direct": "十字键 ←↑→", "respawn": "Create", "pause": "Options", "move": "左摇杆", "camera": "右摇杆", "ui_accept": "✕", "ui_cancel": "○"},
	"xbox": {"jump": "A", "ability": "X", "grab": "B", "view_toggle": "Y", "boost": "RT", "form": "LB/RB", "form_direct": "十字键 ←↑→", "respawn": "View", "pause": "Menu", "move": "左摇杆", "camera": "右摇杆", "ui_accept": "A", "ui_cancel": "B"},
	"kbm": {"jump": "空格", "ability": "左键", "grab": "E", "view_toggle": "V", "boost": "Shift", "form": "滚轮", "form_direct": "1-3", "respawn": "R", "pause": "Esc", "move": "WASD", "camera": "鼠标", "ui_accept": "Enter", "ui_cancel": "Esc"},
}

func glyph(action: String) -> String:
	return GLYPHS[device].get(action, action)
