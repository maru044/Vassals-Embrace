extends Node
## LLM API 客户端（单 Agent 统一收发）。
## 职责：发送消息、管理对话历史、注入系统事件、异步请求。

signal request_finished(success: bool, response: Dictionary)

const HTTP_TIMEOUT := 120.0

var _http: HTTPRequest
var history: Array[Dictionary] = []


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.timeout = HTTP_TIMEOUT
	_http.request_completed.connect(_on_request_completed)


func reset_history() -> void:
	history.clear()


func add_message(role: String, content: String) -> void:
	history.append({"role": role, "content": content})


func send_request(tools: Array = []) -> void:
	if not ConfigManager.has_valid_config():
		push_warning("LLMClient: API 配置无效")
		request_finished.emit(false, {})
		return
	var payload := {
		"model": ConfigManager.model,
		"messages": history,
	}
	if not tools.is_empty():
		payload["tools"] = tools
		payload["tool_choice"] = "auto"
	var headers := [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % ConfigManager.api_key,
	]
	EventBus.llm_request_started.emit()
	var err := _http.request(ConfigManager.api_url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		push_warning("LLMClient: 请求失败 err=%s" % err)
		request_finished.emit(false, {})


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var success := response_code == 200
	var data := {}
	if success:
		var json: Variant = JSON.parse_string(body.get_string_from_utf8())
		if json is Dictionary:
			data = json
		else:
			success = false
	EventBus.llm_response_received.emit(data)
	request_finished.emit(success, data)
