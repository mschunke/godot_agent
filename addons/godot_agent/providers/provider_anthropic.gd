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
	# Canonical == Anthropic-style already. Pass through, dropping any system messages.
	var out: Array = []
	for m in messages:
		if m.role == "system":
			continue
		out.append({"role": m.role, "content": m.content})
	return out


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
