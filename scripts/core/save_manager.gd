extends Node
## 存档管理（Autoload 单例）：6 槽位 JSON 存储（引擎⑨，参考 Synthetica SaveManager 适配本项目）。
## 路径 user://saves/slot_1.json ~ slot_6.json；每槽一个 JSON（含 metadata：player/year/month/created_at）。
## 保存：调用方把 GameManager.serialize() + LLM 聊天历史 合成 data 后传入 save_game_to_slot。
## 读取：load_game_from_slot 返回 data，调用方执行 GameManager.deserialize() + 恢复聊天历史。

const SAVES_DIR := "user://saves/"
const MAX_SLOTS := 6


func _ready() -> void:
	var dir := DirAccess.open("user://")
	if dir and not dir.dir_exists(SAVES_DIR):
		dir.make_dir_recursive(SAVES_DIR)


func _slot_path(idx: int) -> String:
	return SAVES_DIR + "slot_%d.json" % (idx + 1)


## 6 槽位信息：每项 null（空）或 {id, player, year, month, created_at, ...}（存档 UI 列表用）
func get_slots_info() -> Array:
	var slots := []
	for i in range(MAX_SLOTS):
		var data := _read_json(_slot_path(i))
		if not data.is_empty():
			data["id"] = i
			slots.append(data)
		else:
			slots.append(null)
	return slots


## 保存到槽位：data 需含全运行态 + metadata（调用方组装）；成功返回 true
func save_game_to_slot(idx: int, data: Dictionary) -> bool:
	if idx < 0 or idx >= MAX_SLOTS:
		return false
	var f := FileAccess.open(_slot_path(idx), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
		return true
	return false


## 从槽位读取（空 / 损坏返回 {}）
func load_game_from_slot(idx: int) -> Dictionary:
	if idx < 0 or idx >= MAX_SLOTS:
		return {}
	return _read_json(_slot_path(idx))


## 删除槽位
func delete_slot(idx: int) -> void:
	if idx < 0 or idx >= MAX_SLOTS:
		return
	var path := _slot_path(idx)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## 读 JSON 文件（不存在 / 解析失败返回 {}）
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(text)
	return data if data is Dictionary else {}
