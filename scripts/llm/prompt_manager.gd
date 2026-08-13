extends Node
## 提示词管理器（复刻旧项目 PromptManager，适配《欧陆百合风云》）
## 职责：
## 1. 加载 res://data/Prompts/*.md（SillyTavern 世界书式：JSON 头 + 正文，--- 分隔）
## 2. 解析 JSON 头 {role, depth, enabled}，enabled=false 跳过
## 3. 组装 System Prompt：按 depth 降序（999 → 0）拼接，支持 {占位符} 替换（String.format）
## 4. 支持按文件名 include / exclude 筛选（聊天与 AI 外交需要的提示词集合不同）
## 用法：PromptManager.build_system_context(extra_dict, include, exclude)


const PROMPT_DIR := "res://data/Prompts/"

## 缓存：[{role, depth, fname, content}]
var _prompts: Array = []


func _ready() -> void:
	_load_all_prompts()


## 扫描提示词目录，解析并缓存所有启用状态的 md 文件
func _load_all_prompts() -> void:
	_prompts.clear()
	var dir := DirAccess.open(PROMPT_DIR)
	if dir == null:
		push_warning("[PromptManager] 无法打开提示词目录: " + PROMPT_DIR)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".md"):
			_parse_and_cache(fname)
		fname = dir.get_next()
	print("[PromptManager] 加载提示词文件: %d 个" % _prompts.size())


## 解析单个 md 文件：按首个 "---" 切分 JSON 头与正文
func _parse_and_cache(fname: String) -> void:
	var content := FileAccess.get_file_as_string(PROMPT_DIR + fname)
	if content.is_empty():
		return
	var parts := content.split("---", true, 1)
	var header: Dictionary = {}
	var body := content
	if parts.size() > 1:
		var header_str := parts[0].strip_edges()
		if header_str.begins_with("{") and header_str.ends_with("}"):
			var parsed: Variant = JSON.parse_string(header_str)
			if typeof(parsed) == TYPE_DICTIONARY:
				header = parsed
				body = parts[1].strip_edges()
	if not header.get("enabled", true):
		return
	_prompts.append({
		"role": str(header.get("role", "system")),
		"depth": int(header.get("depth", 500)),
		"fname": fname,
		"content": body,
	})


## [核心] 组装 System Prompt 文本
## extra:   {占位符: 值} 用于 String.format 替换（缺失键保留原样）
## include: 非空则只包含这些文件名；exclude: 排除这些文件名
func build_system_context(extra: Dictionary = {}, include: Array = [], exclude: Array = []) -> String:
	var list := _ordered_system_prompts()
	var parts: Array[String] = []
	for p in list:
		var fname: String = str(p["fname"])
		if not include.is_empty() and not include.has(fname):
			continue
		if exclude.has(fname):
			continue
		parts.append(String(p["content"]).format(extra))
	return "\n\n".join(parts).strip_edges()


## 按 depth 降序返回所有 role=system 的提示词（深拷贝防篡改）
func get_system_prompts() -> Array:
	var list := _ordered_system_prompts()
	var out: Array = []
	for p in list:
		out.append(p.duplicate())
	return out


## 返回某文件的正文（不含 JSON 头）；未加载则 ""
func get_prompt_content(fname: String) -> String:
	for p in _prompts:
		if str(p["fname"]) == fname:
			return str(p["content"])
	return ""


func _ordered_system_prompts() -> Array:
	var list: Array = []
	for p in _prompts:
		if str(p["role"]) == "system":
			list.append(p)
	list.sort_custom(func(a, b): return int(a["depth"]) > int(b["depth"]))
	return list
