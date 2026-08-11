extends SceneTree
## 引擎②-B3-2 行军引擎冒烟测试：
## 邻接可达（2格/月）、命令下发、超范围拦截、月末推进（BFS 最短路径）
## 运行：godot --headless --path . --script res://tests/test_march.gd

const RESULT_PATH := "user://test_march_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	var gm: Node = load("res://scripts/core/game_manager.gd").new()
	root.add_child(gm)
	await process_frame
	gm.set("player_country_id", "England")   # 玩家 = 英格兰
	gm.call("init_army_positions", {"England": "London", "Scotland": "Lothian", "Wales": "Wales"})

	# 可达范围：London 2 格陆地（不含自身）
	var reach: Array = gm.call("get_reachable_provinces", "England")
	out.append("England reachable(%d)=%s" % [reach.size(), ", ".join(reach)])
	var expect := ["East Anglia", "Home Counties", "Wessex", "Lincolnshire", "Midlands", "Severn Valley", "Southwest"]
	var miss: Array[String] = []
	for e in expect:
		if not reach.has(e):
			miss.append(str(e))
	out.append("missing from reachable: %s" % ("none" if miss.is_empty() else ", ".join(miss)))

	# B3-2c：可达树（{子省: 父省}）——键集应与可达集合一致，且每条边父省是子省的陆地邻接
	var tree: Dictionary = gm.call("get_reachable_tree", "England")
	var keys: Array = tree.keys()
	keys.sort()
	var reach_sorted: Array = reach.duplicate()
	reach_sorted.sort()
	out.append("tree keys == reachable: %s (tree=%d reach=%d)" % [str(keys) == str(reach_sorted), keys.size(), reach_sorted.size()])
	var adj: Dictionary = gm.get("_adjacency")
	if adj.is_empty():
		adj = {}
	# 直接验证：每个父省 ∈ 邻接图且为 land 边
	var bad_edges: Array[String] = []
	for child in tree:
		var parent: String = tree[child]
		if not adj.has(parent) or adj[parent].get(child, "") != "land":
			bad_edges.append(str(child) + "<-" + parent)
	out.append("tree invalid land edges: %s" % ("none" if bad_edges.is_empty() else ", ".join(bad_edges)))

	# B3-2c：公开路径查询 get_army_path（London -> Midlands）
	var path: Array = gm.call("get_army_path", "England", "Midlands")
	out.append("path London->Midlands: %s" % ", ".join(path))
	out.append("path head/tail ok: %s" % (path.size() >= 2 and path[0] == "London" and path[path.size() - 1] == "Midlands"))

	# 超范围拦截：Wales 距 London 3 步 > 2
	var r_far: Dictionary = gm.call("issue_order", "England", "Wales")
	out.append("order Wales (3 steps) -> ok=%s error=%s" % [r_far.get("ok"), r_far.get("error", "")])

	# 合法命令：Midlands 2 步
	var r_ok: Dictionary = gm.call("issue_order", "England", "Midlands")
	out.append("order Midlands (2 steps) -> ok=%s" % r_ok.get("ok"))

	# 月末推进：England London -> Midlands（2 步到达，命令清空）
	gm.call("_advance_army")
	var pos: Dictionary = gm.get("army_position")
	var order: Dictionary = gm.get("army_order")
	out.append("after month: England pos=%s order=%s" % [pos.get("England", ""), order.get("England", "")])

	# 下一月：Midlands -> Wales（1 步）
	gm.call("issue_order", "England", "Wales")
	gm.call("_advance_army")
	out.append("after 2nd month: England pos=%s order=%s" % [pos.get("England", ""), order.get("England", "")])

	# 非玩家无法下命令（玩家是 England，命令 Scotland 应拦截）
	var r_other: Dictionary = gm.call("issue_order", "Scotland", "Lothian")
	out.append("order Scotland by England player -> ok=%s error=%s" % [r_other.get("ok"), r_other.get("error", "")])

	root.remove_child(gm)
	gm.free()
	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
