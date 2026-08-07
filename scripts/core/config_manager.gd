extends Node
## 配置管理（Autoload 单例）：API 地址 / 密钥 / 模型等全局配置。
## 持久化到 user://config.cfg

const CONFIG_PATH := "user://config.cfg"

var api_url: String = ""
var api_key: String = ""
var model: String = ""


func _ready() -> void:
	load_config()


func load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		api_url = cfg.get_value("llm", "api_url", api_url)
		api_key = cfg.get_value("llm", "api_key", api_key)
		model = cfg.get_value("llm", "model", model)


func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("llm", "api_url", api_url)
	cfg.set_value("llm", "api_key", api_key)
	cfg.set_value("llm", "model", model)
	cfg.save(CONFIG_PATH)


func has_valid_config() -> bool:
	return not api_url.is_empty() and not api_key.is_empty() and not model.is_empty()
