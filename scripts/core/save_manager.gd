extends Node
## 存档管理（Autoload 单例）：游戏状态保存 / 读取。

const SAVE_PATH := "user://savegame.json"


func save_game(data: Dictionary) -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()


func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var text := file.get_as_text()
		file.close()
		var data: Variant = JSON.parse_string(text)
		if data is Dictionary:
			return data
	return {}
