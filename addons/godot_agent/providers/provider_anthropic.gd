@tool
extends "res://addons/godot_agent/providers/provider_base.gd"
class_name GodotAgentProviderAnthropic

const Settings := preload("res://addons/godot_agent/core/settings.gd")
const Http := preload("res://addons/godot_agent/core/http_client.gd")

const API_URL := "https://api.anthropic.com/v1/messages"
const API_VERSION := "2023-06-01"
const MAX_TOKENS := 8192


func send_conversation(parent: Node, system: String, messages: Array, tools: Array, web_enabled: bool) -> Dictionary:
	var key := Settings.api_key("anthropic")
	if key == "":
		return {"ok": false, "error": "Anthropic API key not set"}

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"x-api-key: " + key,
		"anthropic-version: " + API_VERSION,
	])

	var body := {
		"model": Settings.model_for("anthropic"),
		"max_tokens": MAX_TOKENS,
		"system": system,
		"messages": _convert_messages(messages),
		"tools": _convert_tools(tools),
	}
	if web_enabled:
		body["tools"].append({
			"type": "web_search_20250305",
			"name": "web_search",
			"max_uses": 5,
		})

	var resp: Dictionary = await Http.post_json(parent, API_URL, headers, body)
	if not resp.get("ok", false):
		return {"ok": false, "error": "anthropic http error %s: %s" % [resp.get("code", "?"), resp.get("raw", "")]}

	var data: Dictionary = resp.body
	var stop_reason: String = data.get("stop_reason", "other")
	var content: Array = data.get("content", [])
	var text := ""
	var tool_calls: Array = []
	for block in content:
		if block.type == "text":
			text += String(block.get("text", ""))
		elif block.type == "tool_use":
			tool_calls.append({
				"id": block.get("id", ""),
				"name": block.get("name", ""),
				"input": block.get("input", {}),
			})

	return {
		"ok": true,
		"stop_reason": _normalize_stop(stop_reason),
		"text": text,
		"tool_calls": tool_calls,
		"assistant_content": content,
		"usage": data.get("usage", {}),
	}


func format_tool_results(results: Array) -> Dictionary:
	# Anthropic accepts canonical tool_result blocks as-is.
	var parts: Array = []
	for r in results:
		parts.append({
			"type": "tool_result",
			"tool_use_id": r.tool_use_id,
			"content": String(r.content),
			"is_error": r.get("is_error", false),
		})
	return {"role": "user", "content": parts}


func _convert_tools(tools: Array) -> Array:
	var out: Array = []
	for t in tools:
		out.append({
			"name": t.name,
			"description": t.description,
			"input_schema": t.parameters,
		})
	return out


func _convert_messages(messages: Array) -> Array:
	# Canonical is Anthropic-shaped for text/tool_use/tool_result already, but
	# canonical image blocks are stored flat as {type:"image", media_type, data}
	# while Anthropic expects {type:"image", source:{type:"base64", media_type, data}}.
	# Rewrite images in user message content and inside tool_result content arrays.
	var out: Array = []
	for m in messages:
		if m.role == "system":
			continue
		var content_variant: Variant = m.content
		if typeof(content_variant) != TYPE_ARRAY:
			out.append({"role": m.role, "content": content_variant})
			continue
		var converted: Array = []
		for block_variant in content_variant:
			if typeof(block_variant) != TYPE_DICTIONARY:
				converted.append(block_variant)
				continue
			var block: Dictionary = block_variant
			converted.append(_convert_block(block))
		out.append({"role": m.role, "content": converted})
	return out


func _convert_block(block: Dictionary) -> Variant:
	var t: String = String(block.get("type", ""))
	if t == "image":
		return _to_anthropic_image(block)
	if t == "tool_result":
		var content_val: Variant = block.get("content", "")
		if typeof(content_val) == TYPE_ARRAY:
			var arr: Array = []
			for inner in content_val:
				if typeof(inner) == TYPE_DICTIONARY:
					arr.append(_convert_block(inner))
				else:
					arr.append(inner)
			var out_block: Dictionary = block.duplicate(true)
			out_block["content"] = arr
			return out_block
	return block


static func _to_anthropic_image(block: Dictionary) -> Dictionary:
	# Already Anthropic-shaped? Pass through.
	if block.has("source"):
		return block
	return {
		"type": "image",
		"source": {
			"type": "base64",
			"media_type": String(block.get("media_type", "image/png")),
			"data": String(block.get("data", "")),
		},
	}


func _normalize_stop(reason: String) -> String:
	match reason:
		"end_turn": return "end_turn"
		"tool_use": return "tool_use"
		"max_tokens": return "max_tokens"
	return "other"


func list_models(parent: Node) -> Dictionary:
	var key := Settings.api_key("anthropic")
	if key == "":
		return {"ok": false, "error": "Anthropic API key not set", "chat": [], "image": []}
	var headers := PackedStringArray([
		"x-api-key: " + key,
		"anthropic-version: " + API_VERSION,
	])
	var chat: Array = []
	var next_page := ""
	# Anthropic paginates via `after_id`. Loop a few pages defensively.
	for _i in 5:
		var url := "https://api.anthropic.com/v1/models?limit=100"
		if next_page != "":
			url += "&after_id=" + next_page
		var resp: Dictionary = await Http.get_json(parent, url, headers)
		if not resp.get("ok", false):
			return {"ok": false, "error": "anthropic http %s: %s" % [resp.get("code", "?"), resp.get("raw", "")], "chat": [], "image": []}
		var data: Variant = resp.get("body", {})
		if typeof(data) != TYPE_DICTIONARY:
			break
		var items: Array = data.get("data", [])
		for m in items:
			chat.append({
				"id": String(m.get("id", "")),
				"label": String(m.get("display_name", m.get("id", ""))),
			})
		if not bool(data.get("has_more", false)):
			break
		next_page = String(data.get("last_id", ""))
		if next_page == "":
			break
	# Anthropic offers no image-gen models.
	return {"ok": true, "error": "", "chat": chat, "image": []}
