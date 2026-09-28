class_name Goal
extends Zone
## 终点：到达后显示本次测试统计

var _done := false
var line := "引擎节点……接通了。PIX，你比我想象的靠谱一点。还有四座塔。"

func _on_player_entered() -> void:
	if _done:
		return
	_done = true
	GameState.level_complete = true
	GameState.set_objective(99, "%s 完成！" % Chapters.info(GameState.chapter).num, Vector3.INF)
	SaveGame.set_flag("gh_clear" if GameState.chapter == 1 else "ch%d_clear" % GameState.chapter)
	SaveGame.write()
	Sfx.play("level_clear", Vector3.INF, 0.0, 0.0)
	Music.duck(4.0, 0.1)
	GameState.say(line)
	await get_tree().create_timer(4.5).timeout
	GameState.level_cleared.emit()
