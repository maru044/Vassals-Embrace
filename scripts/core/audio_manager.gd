extends Node
## BGM 管理器（Autoload 单例）：
## - 标题界面 / 国家选择：播放主旋律 Main Theme（循环）
## - 进入游戏后：从其余 4 首随机循环（避免刚播过的立即重播）
## - 音量联动 ConfigManager.volume（设置里的音量滑块），实时生效

const MAIN_THEME_PATH := "res://assets/music/main_theme.mp3"
const GAME_TRACKS: Array[String] = [
	"res://assets/music/battle_highlands.mp3",
	"res://assets/music/among_the_poor.mp3",
	"res://assets/music/alba.mp3",
	"res://assets/music/birthplace_renaissance.mp3",
	"res://assets/music/eire.mp3",
]

enum Mode { NONE, MENU, GAME }

var _player: AudioStreamPlayer = null
var _mode: int = Mode.NONE
var _last_game_track: String = ""


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)
	_player.finished.connect(_on_finished)
	apply_volume()


## 标题 / 选国：主旋律循环
func play_menu_music() -> void:
	if _mode == Mode.MENU and _player.playing:
		return
	_mode = Mode.MENU
	_play_track(MAIN_THEME_PATH)


## 进入游戏：随机一首游戏曲目（排除刚播过的那首）
func play_game_music() -> void:
	if _mode == Mode.GAME and _player.playing:
		return
	_mode = Mode.GAME
	_play_random_game_track()


## 音量联动：读取 ConfigManager.volume（0~1）换算 dB
func apply_volume() -> void:
	if _player == null:
		return
	var v := clampf(ConfigManager.volume, 0.0, 1.0)
	_player.volume_db = linear_to_db(maxf(v, 0.001))


func _play_random_game_track() -> void:
	var pool := GAME_TRACKS
	if pool.size() > 1 and _last_game_track != "":
		pool = pool.duplicate()
		pool.erase(_last_game_track)
	var path := pool[randi() % pool.size()]
	_last_game_track = path
	_play_track(path)


func _play_track(path: String) -> void:
	var stream: AudioStream = load(path)
	if stream == null:
		push_warning("AudioManager: 找不到音频 " + path)
		return
	_player.stream = stream
	_player.play()


func _on_finished() -> void:
	match _mode:
		Mode.MENU:
			_play_track(MAIN_THEME_PATH)
		Mode.GAME:
			_play_random_game_track()
