extends SceneTree
## 检查 Godot 导入 map.gltf 后的节点结构（写文件，供上色代码匹配节点名）。
## 运行：godot --headless --path . --script res://tests/inspect_map_nodes.gd

const RESULT_PATH := "user://map_nodes.txt"


func _initialize() -> void:
	var out: Array[String] = []
	var paths := [
		"res://assets/map/map.gltf",
		"res://.godot/imported/map.gltf-c5a219dfde5bb46f4ca8ea490766e202.scn",
	]
	var packed: PackedScene = null
	for p in paths:
		packed = load(p)
		if packed != null:
			out.append("OK load: " + p)
			break
	if packed == null:
		out.append("FAIL load map.gltf (both paths)")
	else:
		var inst: Node = packed.instantiate()
		root.add_child(inst)
		await process_frame
		_collect(inst, 0, out)
		root.remove_child(inst)
		inst.free()
	out.append("DONE")
	var f := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out))
		f.close()
	quit()


func _collect(node: Node, depth: int, out: Array[String]) -> void:
	var kind := node.get_class()
	var extra := ""
	if node is MeshInstance3D:
		extra = "  (MeshInstance3D, mesh=" + str(node.mesh) + ")"
	out.append("  ".repeat(depth) + "- " + node.name + " [" + kind + "]" + extra)
	for c in node.get_children():
		_collect(c, depth + 1, out)
