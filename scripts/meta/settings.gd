extends Node
## 设置（自动加载为 Settings）：音量、镜头、震屏，存在 user://settings.cfg

signal changed

var values := {
	"master": 0.9, "music": 0.8, "sfx": 0.9,
	"cam_sens": 1.0, "invert_y": false, "shake": true, "subtitles_speed": 1.0,
}

func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") == OK:
		for k in values.keys():
			values[k] = cf.get_value("settings", k, values[k])
	apply.call_deferred()

func get_v(k: String):
	return values.get(k)

func set_v(k: String, v) -> void:
	values[k] = v
	apply()
	var cf := ConfigFile.new()
	for key in values.keys():
		cf.set_value("settings", key, values[key])
	cf.save("user://settings.cfg")
	changed.emit()

func apply() -> void:
	for pair in [["Master", "master"], ["Music", "music"], ["SFX", "sfx"]]:
		var i := AudioServer.get_bus_index(pair[0])
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(float(values[pair[1]]), 0.0001)) + (-4.0 if pair[0] == "Music" else 0.0))
