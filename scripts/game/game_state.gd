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
		blocks_broken = v
		if v == 80:
			say("你是拆迁队吗？……好吧，拆得还挺专业。")
var player: Node3D
var camera: Node3D
var checkpoint := Vector3(4.75, 3.5, 16.0)
var checkpoint_form := -1          ## 复活时强制的形态（-1 = 不改）
var checkpoint_locks_form := false
var device := "kbm"                ## "ps" / "xbox" / "kbm"
var unlocked_forms: Array[bool] = [true, true, true, true, true]
var kill_y := -6.0                 ## 掉到这个高度以下就回检查点（由关卡设置）
var allow_jump := false            ## 默认不能跳（致敬平衡球，高低差靠坡道和形态解决）
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

func unlock_form(i: int) -> void:
	if unlocked_forms[i]:
		return
	unlocked_forms[i] = true
	form_unlocked.emit(i)

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
	"ps": {"jump": "✕", "ability": "□", "grab": "○", "view_toggle": "△", "boost": "R2", "form": "L1/R1", "form_direct": "十字键", "respawn": "Create", "pause": "Options", "move": "左摇杆", "camera": "右摇杆", "ui_accept": "✕", "ui_cancel": "○"},
	"xbox": {"jump": "A", "ability": "X", "grab": "B", "view_toggle": "Y", "boost": "RT", "form": "LB/RB", "form_direct": "十字键", "respawn": "View", "pause": "Menu", "move": "左摇杆", "camera": "右摇杆", "ui_accept": "A", "ui_cancel": "B"},
	"kbm": {"jump": "空格", "ability": "左键", "grab": "E", "view_toggle": "V", "boost": "Shift", "form": "滚轮", "form_direct": "1-5", "respawn": "R", "pause": "Esc", "move": "WASD", "camera": "鼠标", "ui_accept": "Enter", "ui_cancel": "Esc"},
}

func glyph(action: String) -> String:
	return GLYPHS[device].get(action, action)
