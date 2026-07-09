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
var _totals: Dictionary = {"input": 0, "output": 0, "total": 0}


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


func add_user_message(text: String, attachments: Array) -> void:
	# Like add_user_text but supports attachments produced by the UI.
	# Attachment shapes:
	#   {kind: "image", media_type: "image/png", data: "<base64>", name?: "..."}
	#     → canonical image block
	#   {kind: "text_file", path: "res://...", content: "..."}
	#     → prepended to the text as a fenced code block with a header
	var body_text: String = text
	var image_blocks: Array = []
	for att_variant in attachments:
		if typeof(att_variant) != TYPE_DICTIONARY:
			continue
		var att: Dictionary = att_variant
		var kind: String = String(att.get("kind", ""))
		if kind == "image":
			var block: Dictionary = {
				"type": "image",
				"media_type": String(att.get("media_type", "image/png")),
				"data": String(att.get("data", "")),
			}
			var att_name: String = String(att.get("name", ""))
			if att_name != "":
				block["name"] = att_name
			image_blocks.append(block)
		elif kind == "text_file":
			var header: String = "[Attached file: %s]" % String(att.get("path", ""))
			var content_str: String = String(att.get("content", ""))
			var chunk: String = "\n\n%s\n```\n%s\n```" % [header, content_str]
			if body_text == "":
				body_text = header + "\n```\n" + content_str + "\n```"
			else:
				body_text += chunk

	var content: Array = []
	if body_text != "":
		content.append({"type": "text", "text": body_text})
	for b in image_blocks:
		content.append(b)
	if content.is_empty():
		return

	_messages.append({"role": "user", "content": content})
	_touch()
	if title == "New chat":
		var seed_text: String = body_text if body_text != "" else "(attachment)"
		title = _derive_title(seed_text)
	changed.emit()


func add_assistant(content: Array, provider: String = "", model: String = "") -> void:
	var msg: Dictionary = {
		"role": "assistant",
		"content": content,
	}
	if provider != "":
		msg["provider"] = provider
	if model != "":
		msg["model"] = model
	_messages.append(msg)
	_touch()
	changed.emit()


func add_tool_results(results: Array) -> void:
	var parts: Array = []
	for r in results:
		# Support two content shapes:
		#   1) plain string (existing) — {content: "..."}
		#   2) rich content — {content: "...", image_content: {media_type, data}}
		#      For rich results we emit an array of blocks: [{text}, {image}].
		#      Providers convert as appropriate; Anthropic accepts this shape
		#      natively, OpenAI/Gemini get a follow-up image part.
		var block: Dictionary = {
			"type": "tool_result",
			"tool_use_id": r.get("tool_use_id", ""),
			"is_error": r.get("is_error", false),
		}
		var image: Variant = r.get("image_content", null)
		if typeof(image) == TYPE_DICTIONARY and String(image.get("data", "")) != "":
			var text_str: String = String(r.get("content", ""))
			var content_arr: Array = []
			if text_str != "":
				content_arr.append({"type": "text", "text": text_str})
			content_arr.append({
				"type": "image",
				"media_type": String(image.get("media_type", "image/png")),
				"data": String(image.get("data", "")),
			})
			block["content"] = content_arr
		else:
			block["content"] = r.get("content", "")
		parts.append(block)
	_messages.append({
		"role": "user",
		"content": parts,
	})
	_touch()
	changed.emit()


func is_empty() -> bool:
	return _messages.is_empty()


func totals() -> Dictionary:
	return _totals.duplicate()


func add_usage(provider: String, usage: Dictionary) -> void:
	# Normalize the provider's native usage shape to {input, output, total}.
	if usage == null or usage.is_empty():
		return
	var delta_in := 0
	var delta_out := 0
	match provider:
		"anthropic":
			delta_in = int(usage.get("input_tokens", 0)) \
				+ int(usage.get("cache_creation_input_tokens", 0)) \
				+ int(usage.get("cache_read_input_tokens", 0))
			delta_out = int(usage.get("output_tokens", 0))
		"openai":
			delta_in = int(usage.get("prompt_tokens", 0))
			delta_out = int(usage.get("completion_tokens", 0))
		"gemini":
			# Gemini reports thinking tokens separately; they're billed as output.
			delta_in = int(usage.get("promptTokenCount", 0))
			delta_out = int(usage.get("candidatesTokenCount", 0)) \
				+ int(usage.get("thoughtsTokenCount", 0))
	if delta_in == 0 and delta_out == 0:
		return
	_totals["input"] = int(_totals.get("input", 0)) + delta_in
	_totals["output"] = int(_totals.get("output", 0)) + delta_out
	_totals["total"] = int(_totals.get("input", 0)) + int(_totals.get("output", 0))
	_touch()
	changed.emit()


func to_dict() -> Dictionary:
	return {
		"version": FORMAT_VERSION,
		"id": id,
		"title": title,
		"created_at": created_at,
		"updated_at": updated_at,
		"system_prompt": _system_prompt,
		"messages": _messages,
		"totals": _totals,
	}


func load_from_dict(data: Dictionary) -> void:
	id = String(data.get("id", _generate_id()))
	title = String(data.get("title", "Loaded chat"))
	created_at = int(data.get("created_at", _now()))
	updated_at = int(data.get("updated_at", created_at))
	_system_prompt = String(data.get("system_prompt", ""))
	var raw_msgs: Variant = data.get("messages", [])
	_messages = raw_msgs if typeof(raw_msgs) == TYPE_ARRAY else []
	var raw_totals: Variant = data.get("totals", null)
	if typeof(raw_totals) == TYPE_DICTIONARY:
		_totals = {
			"input": int(raw_totals.get("input", 0)),
			"output": int(raw_totals.get("output", 0)),
			"total": int(raw_totals.get("total", 0)),
		}
	else:
		_totals = {"input": 0, "output": 0, "total": 0}
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
