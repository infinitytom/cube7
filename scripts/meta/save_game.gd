extends Node
## 存档（自动加载为 SaveGame）：3 个存档位，JSON 存在 user://save_N.json。
## 在检查点自动保存；“继续游戏”读取最近一次保存的存档位。

const SLOTS := 3
const VERSION := 1

var slot := 0                  ## 当前游玩的存档位
var data := {}                 ## 当前存档内容
var _play_start := 0.0

func path(i: int) -> String:
	return "user://save_%d.json" % i

func exists(i: int) -> bool:
	return FileAccess.file_exists(path(i))

func read(i: int) -> Dictionary:
	if not exists(i):
		return {}
	var f := FileAccess.open(path(i), FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

## 最近保存的存档位（没有则 -1）
func latest_slot() -> int:
	var best := -1
	var best_t := -1.0
	for i in SLOTS:
		var d := read(i)
		if not d.is_empty() and float(d.get("saved_at", 0)) > best_t:
			best_t = float(d.get("saved_at", 0))
			best = i
	return best

func new_game(i: int) -> void:
	slot = i
	data = {
		"version": VERSION, "area": "greenhouse", "saved_at": Time.get_unix_time_from_system(),
		"play_time": 0.0, "checkpoint": null, "checkpoint_form": -1,
		"forms": [], "coins": 0, "fragments": [], "seeds": [], "flags": {}, "intro_seen": false, "chapter": 1,
	}
	_play_start = Time.get_ticks_msec() / 1000.0
	write()

## 进入下一章：保留金币、形态、收集记录，清掉检查点和目标
func start_chapter(ch: int) -> void:
	if data.is_empty():
		return
	data["chapter"] = ch
	data["checkpoint"] = null
	data["checkpoint_form"] = -1
	data["objective"] = -1
	data["objective_text"] = ""
	data["objective_pos"] = null
	data["forms"] = GameState.unlocked_forms.duplicate()
	data["coins"] = GameState.coins
	write()

func load_slot(i: int) -> bool:
	var d := read(i)
	if d.is_empty():
		return false
	slot = i
	data = d
	_play_start = Time.get_ticks_msec() / 1000.0
	return true

func write() -> void:
	if data.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	data["play_time"] = float(data.get("play_time", 0.0)) + (now - _play_start)
	_play_start = now
	data["saved_at"] = Time.get_unix_time_from_system()
	var f := FileAccess.open(path(slot), FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	saved.emit()

signal saved

func set_flag(k: String, v = true) -> void:
	if data.is_empty():
		return
	(data["flags"] as Dictionary)[k] = v

func flag(k: String) -> bool:
	return not data.is_empty() and bool((data.get("flags", {}) as Dictionary).get(k, false))

## 任意一个存档位设置过这个标记（例如 "gh_clear" = 通关过）
func any_flag(k: String) -> bool:
	for i in SLOTS:
		var d := read(i)
		if not d.is_empty() and bool((d.get("flags", {}) as Dictionary).get(k, false)):
			return true
	return false

func has_fragment(id: String) -> bool:
	return not data.is_empty() and id in (data.get("fragments", []) as Array)

## 从当前游戏状态采集并写入（检查点调用）
func save_checkpoint(pos: Vector3, form: int) -> void:
	if data.is_empty():
		return
	data["checkpoint"] = [pos.x, pos.y, pos.z]
	data["checkpoint_form"] = form
	data["forms"] = GameState.unlocked_forms.duplicate()
	data["chapter"] = GameState.chapter
	data["coins"] = GameState.coins
	data["objective"] = GameState.objective_index
	data["objective_text"] = GameState.objective_text
	var op := GameState.objective_pos
	data["objective_pos"] = null if op == Vector3.INF else [op.x, op.y, op.z]
	write()

func delete(i: int) -> void:
	if exists(i):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path(i)))

static func format_time(sec: float) -> String:
	var s := int(sec)
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
