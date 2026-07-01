@tool
extends "res://addons/godot_agent/providers/provider_base.gd"
class_name GodotAgentProviderGemini

const Settings := preload("res://addons/godot_agent/core/settings.gd")
const Http := preload("res://addons/godot_agent/core/http_client.gd")


func send_conversation(parent: Node, system: String, messages: Array, tools: Array, web_enabled: bool) -> Dictionary:
	var key := Settings.api_key("gemini")
	if key == "":
		return {"ok": false, "error": "Gemini API key not set"}

	var model := Settings.model_for("gemini")
	var url := "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s" % [model, key]

	var headers := PackedStringArray(["Content-Type: application/json"])

	var effective_system := system
	var native_tools := _convert_tools(tools)

	# Gemini rejects google_search grounding when it's combined with functionDeclarations
	# ("Built-in tools and Function Calling cannot be combined"). Since our tool set is
	# essential for the agent to actually do anything, we drop google_search and tell
	# the model about the limitation via the system prompt.
	if web_enabled and native_tools.is_empty():
		# Very rare path — no functions at all — safe to attach grounding.
		effective_system = _append_web_note(effective_system, false)
		var body := {
			"contents": _convert_messages(messages),
			"tools": [{"google_search": {}}],
		}
		if effective_system != "":
			body["systemInstruction"] = {"parts": [{"text": effective_system}]}
		return await _send(parent, url, headers, body)

	if web_enabled:
		effective_system = _append_web_note(effective_system, true)

	var body := {
		"contents": _convert_messages(messages),
		"tools": [{"functionDeclarations": native_tools}],
	}
	if effective_system != "":
		body["systemInstruction"] = {"parts": [{"text": effective_system}]}

	return await _send(parent, url, headers, body)


func _append_web_note(system: String, tools_present: bool) -> String:
	if tools_present:
		var note := "\n\n[Web search: The user enabled internet access, but the Gemini API disallows combining Google Search grounding with function calling. Live search is unavailable this turn; rely on your own knowledge or ask the user to switch to Anthropic/OpenAI for web-heavy tasks.]"
		return system + note
	return system


func _send(parent: Node, url: String, headers: PackedStringArray, body: Dictionary) -> Dictionary:
	var resp: Dictionary = await Http.post_json(parent, url, headers, body)
	if not resp.get("ok", false):
		return {"ok": false, "error": "gemini http error %s: %s" % [resp.get("code", "?"), resp.get("raw", "")]}

	var data: Dictionary = resp.body
	var candidates: Array = data.get("candidates", [])
	if candidates.is_empty():
		return {"ok": false, "error": "gemini returned no candidates"}
	var cand: Dictionary = candidates[0]
	var finish_reason: String = String(cand.get("finishReason", "STOP"))
	var content: Dictionary = cand.get("content", {})
	var parts: Array = content.get("parts", [])

	var text := ""
	var tool_calls: Array = []
	var canonical_content: Array = []
	var call_counter := 0
	for p in parts:
		if p.has("text"):
			text += String(p.text)
			canonical_content.append({"type": "text", "text": String(p.text)})
		elif p.has("functionCall"):
			var fc: Dictionary = p.functionCall
			# Gemini doesn't emit call IDs; synthesize one so tool_result matching works.
			call_counter += 1
			var id_str := "gem_%d" % call_counter
			var input_dict: Dictionary = fc.get("args", {})
			var call := {"id": id_str, "name": fc.name, "input": input_dict}
			tool_calls.append(call)
			canonical_content.append({
				"type": "tool_use",
				"id": id_str,
				"name": fc.name,
				"input": input_dict,
				"_gemini_native": fc,  # kept so _convert_messages can round-trip it
			})

	var stop := "end_turn"
	if not tool_calls.is_empty():
		stop = "tool_use"
	elif finish_reason == "MAX_TOKENS":
		stop = "max_tokens"

	return {
		"ok": true,
		"stop_reason": stop,
		"text": text,
		"tool_calls": tool_calls,
		"assistant_content": canonical_content,
		"usage": data.get("usageMetadata", {}),
	}


func _convert_tools(tools: Array) -> Array:
	var out: Array = []
	for t in tools:
		out.append({
			"name": t.name,
			"description": t.description,
			"parameters": _sanitize_schema(t.parameters),
		})
	return out


static func _sanitize_schema(schema: Variant) -> Variant:
	# Gemini's function-declaration schema doesn't accept `default` or `additionalProperties`.
	if typeof(schema) != TYPE_DICTIONARY:
		return schema
	var out: Dictionary = {}
	for k in schema.keys():
		if k == "default" or k == "additionalProperties":
			continue
		out[k] = _sanitize_schema(schema[k])
	return out


func _convert_messages(messages: Array) -> Array:
	# Gemini's `contents` array uses role: "user" | "model" and parts with either
	# text or functionCall / functionResponse.
	var out: Array = []
	# Track the most recent assistant tool_use names by id so we can attach names
	# to functionResponse blocks (Gemini requires the name, not an id).
	var name_by_id: Dictionary = {}
	for m in messages:
		if m.role == "system":
			continue
		if m.role == "assistant":
			var parts: Array = []
			if typeof(m.content) == TYPE_ARRAY:
				for block in m.content:
					if block.type == "text":
						parts.append({"text": String(block.get("text", ""))})
					elif block.type == "tool_use":
						name_by_id[block.id] = block.name
						parts.append({"functionCall": {"name": block.name, "args": block.input}})
			elif typeof(m.content) == TYPE_STRING:
				parts.append({"text": m.content})
			out.append({"role": "model", "parts": parts})
		elif m.role == "user":
			var parts2: Array = []
			if typeof(m.content) == TYPE_ARRAY:
				for block in m.content:
					if block.type == "text":
						parts2.append({"text": String(block.get("text", ""))})
					elif block.type == "tool_result":
						var name := String(name_by_id.get(block.tool_use_id, ""))
						parts2.append({
							"functionResponse": {
								"name": name,
								"response": {"content": String(block.content)},
							},
						})
			elif typeof(m.content) == TYPE_STRING:
				parts2.append({"text": m.content})
			out.append({"role": "user", "parts": parts2})
	return out
