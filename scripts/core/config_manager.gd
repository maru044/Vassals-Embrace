extends Node
## 配置管理（Autoload 单例）：API 配置 + 游戏设置（音量 / 分辨率 / 自动保存）。
## 持久化到 user://config.cfg

const CONFIG_PATH := "user://config.cfg"

var api_url: String = ""
var api_key: String = ""
var model: String = ""

# ---------- 游戏设置 ----------
var volume: float = 0.8                    # 0.0 ~ 1.0
var resolution: Vector2i = Vector2i(1920, 1080)
var autosave_interval: String = "monthly"  # monthly / quarterly / yearly


func _ready() -> void:
	load_config()


func load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		api_url = cfg.get_value("llm", "api_url", api_url)
		api_key = cfg.get_value("llm", "api_key", api_key)
		model = cfg.get_value("llm", "model", model)
		volume = cfg.get_value("settings", "volume", volume)
		resolution = cfg.get_value("settings", "resolution", resolution)
		autosave_interval = cfg.get_value("settings", "autosave_interval", autosave_interval)


func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("llm", "api_url", api_url)
	cfg.set_value("llm", "api_key", api_key)
	cfg.set_value("llm", "model", model)
	cfg.set_value("settings", "volume", volume)
	cfg.set_value("settings", "resolution", resolution)
	cfg.set_value("settings", "autosave_interval", autosave_interval)
	cfg.save(CONFIG_PATH)


func has_valid_config() -> bool:
	return not api_url.is_empty() and not api_key.is_empty() and not model.is_empty()
