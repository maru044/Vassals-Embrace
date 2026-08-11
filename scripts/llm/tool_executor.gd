extends Node
## 工具执行器（单 Agent）：定义工具 Schema，把 function calling 解析成引擎调用。
## 原则：所有状态改动经工具落地，引擎是唯一事实源。

const TOOLS: Array = [
	{
		"type": "function",
		"function": {
			"name": "modify_favor",
			"description": "调整玩家对某国的好感度",
			"parameters": {
				"type": "object",
				"properties": {
					"target_id": {"type": "string", "description": "目标国家 id（如 England / Wales）"},
					"delta": {"type": "integer", "description": "好感度增减量（简单互动成功+3/失败-3，中等成功+5，困难成功+10）"},
				},
				"required": ["target_id", "delta"],
			},
		},
	},
	{
		"type": "function",
		"function": {
			"name": "modify_service_tendency",
			"description": "调整某角色的奉仕傾向",
			"parameters": {
				"type": "object",
				"properties": {
					"country_id": {"type": "integer", "description": "国家 id"},
					"member_name": {"type": "string", "description": "后宫成员名"},
					"delta": {"type": "integer", "description": "倾向增减量"},
				},
				"required": ["country_id", "member_name", "delta"],
			},
		},
	},
	{
		"type": "function",
		"function": {
			"name": "trigger_event",
			"description": "触发一个私人事件（LLM 演绎用）",
			"parameters": {
				"type": "object",
				"properties": {
					"event_id": {"type": "string", "description": "事件 id"},
				},
				"required": ["event_id"],
			},
		},
	},
]


func execute(tool_name: String, args: Dictionary) -> Dictionary:
	match tool_name:
		"modify_favor":
			return _modify_favor(args)
		"modify_service_tendency":
			return _modify_service_tendency(args)
		"trigger_event":
			return _trigger_event(args)
		_:
			return {"ok": false, "error": "未知工具: %s" % tool_name}


func _modify_favor(args: Dictionary) -> Dictionary:
	var target_id: String = str(args.get("target_id", ""))
	var delta: int = args.get("delta", 0)
	GameManager.change_favor(target_id, float(delta))   # 落库玩家侧好感（即时生效 + 广播刷新）
	EventBus.tool_executed.emit("modify_favor", {"target_id": target_id, "delta": delta})
	return {"ok": true, "target_id": target_id, "delta": delta, "favor": GameManager.player_favor.get(target_id, 0.0)}


func _modify_service_tendency(args: Dictionary) -> Dictionary:
	var country_id: int = args.get("country_id", -1)
	var member_name: String = args.get("member_name", "")
	var delta: int = args.get("delta", 0)
	# TODO: 落库到后宫系统
	EventBus.service_tendency_changed.emit(country_id, delta)
	EventBus.tool_executed.emit("modify_service_tendency", {"country_id": country_id, "member": member_name, "delta": delta})
	return {"ok": true, "country_id": country_id, "delta": delta}


func _trigger_event(args: Dictionary) -> Dictionary:
	var event_id: String = args.get("event_id", "")
	EventBus.event_triggered.emit(event_id)
	EventBus.tool_executed.emit("trigger_event", {"event_id": event_id})
	return {"ok": true, "event_id": event_id}
