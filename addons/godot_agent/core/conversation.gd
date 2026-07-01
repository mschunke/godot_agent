@tool
extends RefCounted
class_name GodotAgentConversation

# Canonical, provider-neutral conversation store.
#
# Message shape:
#   { role: "user" | "assistant" | "system",
#     content: [
#       { type: "text", text: "..." },
#       { type: "tool_use", id: "call_1", name: "read_file", input: {...} },
#       { type: "tool_result", tool_use_id: "call_1", content: "...", is_error: false }
#     ] }
#
# Each provider adapter converts to/from its native format.

signal changed

var _messages: Array = []
var _system_prompt: String = ""


func set_system_prompt(prompt: String) -> void:
	_system_prompt = prompt
	changed.emit()


func system_prompt() -> String:
	return _system_prompt


func messages() -> Array:
	return _messages


func clear() -> void:
	_messages.clear()
	changed.emit()


func add_user_text(text: String) -> void:
	_messages.append({
		"role": "user",
		"content": [{"type": "text", "text": text}],
	})
	changed.emit()


func add_assistant(content: Array) -> void:
	_messages.append({
		"role": "assistant",
		"content": content,
	})
	changed.emit()


func add_tool_results(results: Array) -> void:
	# results = [{tool_use_id, content, is_error}]
	var parts: Array = []
	for r in results:
		parts.append({
			"type": "tool_result",
			"tool_use_id": r.get("tool_use_id", ""),
			"content": r.get("content", ""),
			"is_error": r.get("is_error", false),
		})
	_messages.append({
		"role": "user",
		"content": parts,
	})
	changed.emit()
