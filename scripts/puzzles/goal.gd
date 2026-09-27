class_name Goal
extends Zone
## 终点：到达后显示本次测试统计

var _done := false

func _on_player_entered() -> void:
	if _done:
		return
	_done = true
	GameState.level_complete = true
	GameState.set_objective(99, "区域 1 完成！", Vector3.INF)
	SaveGame.set_flag("gh_clear")
	SaveGame.write()
	Sfx.play("level_clear", Vector3.INF, 0.0, 0.0)
	Music.duck(4.0, 0.1)
	GameState.say("测试区全部通过！金币 %d，拆掉方块 %d 个。PIX，你比我想象的靠谱一点。" % [GameState.coins, GameState.blocks_broken])
