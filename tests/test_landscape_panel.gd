extends SceneTree
## 省份风景图面板测试：实例化 game 场景，抽查多个省份，验证「省→图片」查表正确加载对应纹理
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
	# 抽查：每类至少一个省
	var checks := {
		"Ulster": "ireland_02.png",          # 爱尔兰沿海
		"Westmeath": "ireland_01.png",       # 爱尔兰内陆
		"Wales": "wales.png",                # 威尔士
		"Highlands": "scotland_highland_01.png",   # 高地尼斯湖
		"The Isles": "isles_02.png",         # 群岛赫布里底
		"East Anglia": "england_lowland_02.png",   # 低地东安格利亚
		"Midlands": "england_hills_02.png",  # 丘陵米德兰
		"Lothian": "scotland.png",           # 苏格兰低地
	}
	for province in checks:
		for c in body.get_children():
			c.queue_free()
		await process_frame
		game.call("_build_province_content", province, province)
		await process_frame
		var got := ""
		for c in body.get_children():
			if c is TextureRect and c.texture != null:
				got = c.texture.resource_path.get_file()
		var expect: String = checks[province]
		print("province=%s expect=%s got=%s -> %s" % [province, expect, got, "OK" if got == expect else "FAIL"])
	root.remove_child(game)
	game.free()
	quit()
