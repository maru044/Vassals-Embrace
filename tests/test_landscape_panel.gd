extends SceneTree
## 省份风景图面板测试：实例化 game 场景，模拟构建 Ulster 省份面板，检查 TextureRect 是否加入容器
## 运行：godot --headless --path . --script res://tests/test_landscape_panel.gd

func _initialize() -> void:
	var packed := load("res://scenes/game/game.tscn") as PackedScene
	var game: Node = packed.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var body: Control = game.get("_left_body")
	if body == null:
		print("NO _left_body")
		quit()
		return
	# 模拟点击爱尔兰省份 Ulster（owner=Ulster）
	game.call("_build_province_content", "Ulster", "Ulster")
	await process_frame
	var found := 0
	for c in body.get_children():
		if c is TextureRect:
			found += 1
			var tr: TextureRect = c
			print("FOUND TextureRect #", found, " tex=", (tr.texture if tr.texture else "null"), " min=", tr.custom_minimum_size, " expand=", tr.expand_mode)
	print("texture_rect_count=", found)
	print("body_child_count=", body.get_child_count())
	root.remove_child(game)
	game.free()
	quit()
