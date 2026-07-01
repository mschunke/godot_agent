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

const FORMAT_VERSION := 1

signal changed

var id: String = ""
var title: String = "New chat"
var created_at: int = 0
var updated_at: int = 0

var _messages: Array = []
var _system_prompt: String = ""


func _init() -> void:
	id = _generate_id()
	created_at = _now()
	updated_at = created_at


func set_system_prompt(prompt: String) -> void:
	_system_prompt = prompt
	changed.emit()


func system_prompt() -> String:
	return _system_prompt


func messages() -> Array:
	return _messages


func clear() -> void:
	_messages.clear()
	title = "New chat"
	updated_at = _now()
	changed.emit()


func add_user_text(text: String) -> void:
	_messages.append({
		"role": "user",
		"content": [{"type": "text", "text": text}],
	})
	_touch()
	if title == "New chat":
		title = _derive_title(text)
	changed.emit()


func add_assistant(content: Array) -> void:
	_messages.append({
		"role": "assistant",
		"content": content,
	})
	_touch()
	changed.emit()


func add_tool_results(results: Array) -> void:
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
	_touch()
	changed.emit()


func is_empty() -> bool:
	return _messages.is_empty()


func to_dict() -> Dictionary:
	return {
		"version": FORMAT_VERSION,
		"id": id,
		"title": title,
		"created_at": created_at,
		"updated_at": updated_at,
		"system_prompt": _system_prompt,
		"messages": _messages,
	}


func load_from_dict(data: Dictionary) -> void:
	id = String(data.get("id", _generate_id()))
	title = String(data.get("title", "Loaded chat"))
	created_at = int(data.get("created_at", _now()))
	updated_at = int(data.get("updated_at", created_at))
	_system_prompt = String(data.get("system_prompt", ""))
	var raw_msgs: Variant = data.get("messages", [])
	_messages = raw_msgs if typeof(raw_msgs) == TYPE_ARRAY else []
	changed.emit()


# ---------- helpers ----------

func _touch() -> void:
	updated_at = _now()


static func _now() -> int:
	return int(Time.get_unix_time_from_system())


static func _generate_id() -> String:
	# 12-char hex from time + random. Enough uniqueness for local storage.
	var t := int(Time.get_ticks_usec())
	var r := randi()
	return "%08x%04x" % [t & 0xFFFFFFFF, r & 0xFFFF]


static func _derive_title(text: String) -> String:
	var t := text.strip_edges().replace("\n", " ")
	if t.length() > 60:
		t = t.substr(0, 57) + "..."
	return t
