extends PanelContainer
## LLM 聊天对话框（复用已有案例的简化占位）。

@onready var _history: RichTextLabel = $Margin/VBox/History
@onready var _input: LineEdit = $Margin/VBox/Input
@onready var _send: Button = $Margin/VBox/Send


func _ready() -> void:
	_send.pressed.connect(_on_send_pressed)
	_input.text_submitted.connect(func(_text: String) -> void: _on_send_pressed())


func _on_send_pressed() -> void:
	var text := _input.text.strip_edges()
	if text.is_empty():
		return
	_history.append_text("[b]你：[/b] %s\n" % text)
	_input.clear()
	# TODO: 接入 LLMClient（聊天 + 工具调用 + 回复展示）
	EventBus.llm_request_started.emit()
	_history.append_text("[color=gray]（LLM 回复接入中…）[/color]\n")


func append_reply(text: String) -> void:
	_history.append_text("[b]Miku：[/b] %s\n" % text)
