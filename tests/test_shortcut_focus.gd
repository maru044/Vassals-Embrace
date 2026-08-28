extends SceneTree


const RESULT_PATH := "user://test_shortcut_focus_result.txt"
const InputFocusGuard := preload("res://scripts/ui/input_focus_guard.gd")

var _out: Array[String] = []
var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var map_scene: PackedScene = load("res://scenes/map/map_view.tscn")
	var map_view: Node3D = map_scene.instantiate()
	root.add_child(map_view)
	await process_frame

	var input := LineEdit.new()
	root.add_child(input)
	input.grab_focus()
	await process_frame
	_check(root.gui_get_focus_owner() == input, "测试输入框已获得焦点")
	_check(InputFocusGuard.should_block_game_shortcuts(root), "LineEdit 聚焦时启用游戏快捷键拦截")

	var target_before: Vector3 = map_view.get("_target")
	map_view.call("_apply_wasd_movement", 1.0, Vector3(0.0, 0.0, -1.0))
	var target_after: Vector3 = map_view.get("_target")
	_check(target_before.is_equal_approx(target_after), "输入框有焦点时 WASD 不移动地图")

	var spines_before: bool = map_view.get("_show_spines")
	map_view.call("_unhandled_input", _key_event(KEY_F9, true))
	var spines_after: bool = map_view.get("_show_spines")
	_check(spines_before == spines_after, "输入框有焦点时 F9 不触发地图快捷键")

	input.release_focus()
	await process_frame
	_check(not InputFocusGuard.should_block_game_shortcuts(root), "输入框失焦时关闭游戏快捷键拦截")

	target_before = map_view.get("_target")
	map_view.call("_apply_wasd_movement", 1.0, Vector3(0.0, 0.0, -1.0))
	target_after = map_view.get("_target")
	_check(not target_before.is_equal_approx(target_after), "输入框无焦点时 WASD 仍可移动地图")

	spines_before = map_view.get("_show_spines")
	map_view.call("_unhandled_input", _key_event(KEY_F9, true))
	spines_after = map_view.get("_show_spines")
	_check(spines_before != spines_after, "输入框无焦点时 F9 仍可触发地图快捷键")

	var text_edit := TextEdit.new()
	root.add_child(text_edit)
	text_edit.grab_focus()
	await process_frame
	_check(InputFocusGuard.should_block_game_shortcuts(root), "TextEdit 聚焦时同样拦截游戏快捷键")
	text_edit.release_focus()
	text_edit.queue_free()

	var game_scene: PackedScene = load("res://scenes/game/game.tscn")
	var game: Node3D = game_scene.instantiate()
	root.add_child(game)
	await process_frame
	input.grab_focus()
	await process_frame
	var debug_before: bool = game.get("_debug_mode")
	game.call("_input", _key_event(KEY_QUOTELEFT, true))
	var debug_after: bool = game.get("_debug_mode")
	_check(debug_before == debug_after, "输入框有焦点时全局调试快捷键不触发")

	input.release_focus()
	await process_frame
	debug_before = game.get("_debug_mode")
	game.call("_input", _key_event(KEY_QUOTELEFT, true))
	debug_after = game.get("_debug_mode")
	_check(debug_before != debug_after, "输入框无焦点时全局调试快捷键仍可用")

	var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if file:
		file.store_string("\n".join(_out))
		file.close()
	print("\n".join(_out))
	quit(1 if _failed else 0)


func _key_event(keycode: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	return event


func _check(condition: bool, label: String) -> void:
	if condition:
		_out.append("PASS: " + label)
	else:
		_out.append("FAIL: " + label)
		_failed = true
