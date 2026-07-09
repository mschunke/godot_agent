@tool
extends "res://addons/godot_agent/providers/provider_base.gd"
class_name GodotAgentProviderOpenAI

const Settings := preload("res://addons/godot_agent/core/settings.gd")
const Http := preload("res://addons/godot_agent/core/http_client.gd")

const API_URL := "https://api.openai.com/v1/chat/completions"


func send_conversation(parent: Node, system: String, messages: Array, tools: Array, web_enabled: bool) -> Dictionary:
	var key := Settings.api_key("openai")
	if key == "":
		return {"ok": false, "error": "OpenAI API key not set"}

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + key,
	])

	var native_tools := _convert_tools(tools)
	# Note: OpenAI's Chat Completions endpoint has no first-party web-search tool.
	# Users who want live web access with OpenAI should switch to a *-search-preview
	# model variant; we surface the toggle intent to the model via the system prompt
	# rather than registering a fake tool the agent can't fulfil.
	var effective_system := system
	if web_enabled:
		effective_system += "\n\n[Web search is enabled by the user. If your currently selected OpenAI model supports built-in web browsing, feel free to consult the web; otherwise mention that OpenAI Chat Completions does not expose a first-party search tool.]"

	var body := {
		"model": Settings.model_for("openai"),
		"messages": _convert_messages(effective_system, messages),
		"tools": native_tools,
	}

	var resp: Dictionary = await Http.post_json(parent, API_URL, headers, body)
	if not resp.get("ok", false):
		return {"ok": false, "error": "openai http error %s: %s" % [resp.get("code", "?"), resp.get("raw", "")]}

	var data: Dictionary = resp.body
	var choices: Array = data.get("choices", [])
	if choices.is_empty():
		return {"ok": false, "error": "openai returned no choices"}

	var choice: Dictionary = choices[0]
	var msg: Dictionary = choice.get("message", {})
	var finish: String = choice.get("finish_reason", "stop")
	var text := String(msg.get("content", "")) if msg.get("content") != null else ""

	var tool_calls_raw: Array = msg.get("tool_calls", []) if msg.get("tool_calls") != null else []
	var tool_calls: Array = []
	var canonical_content: Array = []
	if text != "":
		canonical_content.append({"type": "text", "text": text})
	for tc in tool_calls_raw:
		var fn: Dictionary = tc.get("function", {})
		var args_str: String = fn.get("arguments", "{}")
		var parsed: Variant = JSON.parse_string(args_str)
		var input_dict: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
		var call := {
			"id": tc.get("id", ""),
			"name": fn.get("name", ""),
			"input": input_dict,
		}
		tool_calls.append(call)
		canonical_content.append({
			"type": "tool_use",
			"id": call.id,
			"name": call.name,
			"input": call.input,
		})

	return {
		"ok": true,
		"stop_reason": _normalize_stop(finish, tool_calls),
		"text": text,
		"tool_calls": tool_calls,
		"assistant_content": canonical_content,
		"usage": data.get("usage", {}),
	}


func _convert_tools(tools: Array) -> Array:
	var out: Array = []
	for t in tools:
		out.append({
			"type": "function",
			"function": {
				"name": t.name,
				"description": t.description,
				"parameters": t.parameters,
			},
		})
	return out


func _convert_messages(system: String, messages: Array) -> Array:
	var out: Array = []
	if system != "":
		out.append({"role": "system", "content": system})

	for m in messages:
		if m.role == "system":
			continue
		if m.role == "assistant":
			out.append(_convert_assistant(m.content))
		elif m.role == "user":
			# Split each canonical user message: text + image blocks become a
			# user message with a content-parts array; tool_results become
			# individual role=tool messages.
			var user_parts: Array = []  # [{type:"text"|"image_url", ...}]
			var tool_msgs: Array = []
			if typeof(m.content) == TYPE_ARRAY:
				for block in m.content:
					if block.type == "text":
						user_parts.append({"type": "text", "text": String(block.get("text", ""))})
					elif block.type == "image":
						user_parts.append(_to_openai_image_part(block))
					elif block.type == "tool_result":
						tool_msgs.append(_convert_tool_result(block))
			elif typeof(m.content) == TYPE_STRING:
				user_parts.append({"type": "text", "text": String(m.content)})
			if not user_parts.is_empty():
				# OpenAI accepts a plain string when there's only text; otherwise
				# a parts array. Collapse the single-text case for compatibility.
				if user_parts.size() == 1 and user_parts[0].get("type", "") == "text":
					out.append({"role": "user", "content": String(user_parts[0].get("text", ""))})
				else:
					out.append({"role": "user", "content": user_parts})
			for tm in tool_msgs:
				out.append(tm)
	return out


static func _to_openai_image_part(block: Dictionary) -> Dictionary:
	var media: String = String(block.get("media_type", "image/png"))
	var data: String = String(block.get("data", ""))
	return {
		"type": "image_url",
		"image_url": {"url": "data:%s;base64,%s" % [media, data]},
	}


static func _convert_tool_result(block: Dictionary) -> Dictionary:
	# OpenAI tool messages: {role:"tool", tool_call_id, content}. Content may
	# be a string OR (on gpt-4o and newer vision-capable models) a parts array
	# with text + image_url entries.
	var content_val: Variant = block.get("content", "")
	if typeof(content_val) == TYPE_ARRAY:
		var parts: Array = []
		for inner in content_val:
			if typeof(inner) != TYPE_DICTIONARY:
				continue
			var t: String = String(inner.get("type", ""))
			if t == "text":
				parts.append({"type": "text", "text": String(inner.get("text", ""))})
			elif t == "image":
				parts.append(_to_openai_image_part(inner))
		return {
			"role": "tool",
			"tool_call_id": block.tool_use_id,
			"content": parts,
		}
	return {
		"role": "tool",
		"tool_call_id": block.tool_use_id,
		"content": String(content_val),
	}


func _convert_assistant(content: Variant) -> Dictionary:
	var text := ""
	var tool_calls: Array = []
	if typeof(content) == TYPE_ARRAY:
		for block in content:
			if block.type == "text":
				text += String(block.get("text", ""))
			elif block.type == "tool_use":
				tool_calls.append({
					"id": block.id,
					"type": "function",
					"function": {
						"name": block.name,
						"arguments": JSON.stringify(block.input),
					},
				})
	elif typeof(content) == TYPE_STRING:
		text = content
	var msg := {"role": "assistant", "content": text}
	if not tool_calls.is_empty():
		msg["tool_calls"] = tool_calls
	return msg


func _normalize_stop(finish: String, tool_calls: Array) -> String:
	if not tool_calls.is_empty():
		return "tool_use"
	match finish:
		"stop": return "end_turn"
		"length": return "max_tokens"
		"tool_calls": return "tool_use"
	return "other"


func list_models(parent: Node) -> Dictionary:
	var key := Settings.api_key("openai")
	if key == "":
		return {"ok": false, "error": "OpenAI API key not set", "chat": [], "image": []}
	var headers := PackedStringArray([
		"Authorization: Bearer " + key,
	])
	var resp: Dictionary = await Http.get_json(parent, "https://api.openai.com/v1/models", headers)
	if not resp.get("ok", false):
		return {"ok": false, "error": "openai http %s: %s" % [resp.get("code", "?"), resp.get("raw", "")], "chat": [], "image": []}
	var data: Variant = resp.get("body", {})
	if typeof(data) != TYPE_DICTIONARY:
		return {"ok": false, "error": "unexpected response shape", "chat": [], "image": []}

	var chat: Array = []
	var images: Array = []
	for m in data.get("data", []):
		var id_str := String(m.get("id", ""))
		if id_str == "":
			continue
		var lower := id_str.to_lower()
		# Image models: dall-e-*, gpt-image-*.
		if lower.begins_with("dall-e") or lower.begins_with("gpt-image"):
			images.append({"id": id_str, "label": id_str})
			continue
		# Chat/reasoning models: keep prefixes we know, drop everything else
		# (embeddings, tts, whisper, moderations, ...).
		if lower.begins_with("gpt-") or lower.begins_with("o1") or lower.begins_with("o3") or lower.begins_with("o4") or lower.begins_with("chatgpt-"):
			chat.append({"id": id_str, "label": id_str})
	chat.sort_custom(func(a, b): return a.id < b.id)
	images.sort_custom(func(a, b): return a.id < b.id)
	return {"ok": true, "error": "", "chat": chat, "image": images}
