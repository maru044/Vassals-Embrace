extends SceneTree
## 引擎②-B3-1 邻接图冒烟测试：
## 1) 41 省全在 adjacency 内（与 map_data.province_owner 一致）
## 2) 对称性：A 邻接 B ⇒ B 邻接 A 且类型一致
## 3) 边类型合法（land/sea）
## 运行：godot --headless --path . --script res://tests/test_adjacency.gd

const RESULT_PATH := "user://test_adjacency_result.txt"


func _initialize() -> void:
	var out: Array[String] = []
	var adj_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/province_adjacency.json"))
	var adj: Dictionary = adj_data["adjacency"]
	var map_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/map_data.json"))
	var owners: Dictionary = map_data["province_owner"]

	out.append("adjacency provinces=%d (map_data=%d)" % [adj.size(), owners.size()])

	# 1) 省完整性：map_data 的省都应在 adjacency 中（双向）
	var missing: Array[String] = []
	for p in owners:
		if not adj.has(p):
			missing.append(str(p))
	out.append("missing in adjacency: %s" % ("none" if missing.is_empty() else ", ".join(missing)))

	# 2) 对称性 + 类型合法
	var asym: Array[String] = []
	var badtype: Array[String] = []
	var edge_count := 0
	for a in adj:
		for b in adj[a]:
			var t: String = adj[a][b]
			edge_count += 1
			if t != "land" and t != "sea":
				badtype.append("%s-%s=%s" % [a, b, t])
			if not adj.has(b) or not adj[b].has(a) or adj[b][a] != t:
				asym.append("%s-%s" % [a, b])
	out.append("edges=%d" % edge_count)
	out.append("asymmetric: %s" % ("none" if asym.is_empty() else ", ".join(asym)))
	out.append("bad types: %s" % ("none" if badtype.is_empty() else ", ".join(badtype)))

	out.append("TEST_DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	print("\n".join(out))
	quit()
