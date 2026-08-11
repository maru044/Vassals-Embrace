extends SceneTree
## 省份风景图资源冒烟测试：确认资源可加载 + 尺寸
## 运行：godot --headless --path . --script res://tests/test_landscape.gd

func _initialize() -> void:
	var path := "res://assets/province_landscape/ireland_01.png"
	print("exists=", ResourceLoader.exists(path))
	var t: Texture2D = load(path)
	if t:
		print("tex size=", t.get_size())
	else:
		print("tex load FAILED")
	quit()
