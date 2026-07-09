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
		# functionCall first: a functionCall part may itself carry a
		# `thoughtSignature`, and we must still dispatch it as a tool call.
		if p.has("functionCall"):
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
				# Store the whole part so `thoughtSignature` (a sibling of
				# functionCall on newer thinking models) round-trips too.
				"_gemini_native_part": p,
			})
			continue
		# Pure thought summary parts: either explicitly marked `thought: true`,
		# or a bare `thoughtSignature` with no visible text. Preserve them
		# verbatim so _convert_messages can round-trip them and Gemini's next
		# request passes signature validation.
		var is_pure_thought: bool = bool(p.get("thought", false)) or (p.has("thoughtSignature") and not p.has("text"))
		if is_pure_thought:
			canonical_content.append({
				"type": "thought",
				"_gemini_native": p,
			})
			continue
		if p.has("text"):
			text += String(p.text)
			var text_block := {"type": "text", "text": String(p.text)}
			# The final answer part on thinking models sometimes carries a
			# thoughtSignature too — keep the whole raw part so future turns
			# round-trip the signature back to Gemini.
			if p.has("thoughtSignature"):
				text_block["_gemini_native_part"] = p
			canonical_content.append(text_block)

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
						# If Gemini attached a thoughtSignature to this final
						# answer part, echo the whole raw part so the signature
						# round-trips. Otherwise send a plain text part.
						var text_native: Variant = block.get("_gemini_native_part", null)
						if typeof(text_native) == TYPE_DICTIONARY:
							parts.append(text_native)
						else:
							parts.append({"text": String(block.get("text", ""))})
					elif block.type == "thought":
						# Echo back the raw thought part exactly as received so
						# its `thoughtSignature` remains valid.
						var t_native: Variant = block.get("_gemini_native", null)
						if typeof(t_native) == TYPE_DICTIONARY:
							parts.append(t_native)
					elif block.type == "tool_use":
						name_by_id[block.id] = block.name
						# Prefer the raw response part when we have it — it may
						# include a sibling `thoughtSignature` alongside the
						# functionCall which newer thinking models require to be
						# echoed back verbatim on subsequent turns.
						var native_part: Variant = block.get("_gemini_native_part", null)
						if typeof(native_part) == TYPE_DICTIONARY:
							parts.append(native_part)
							continue
						# Backwards compatibility with older stored conversations
						# that only kept the inner functionCall dict.
						var native: Variant = block.get("_gemini_native", null)
						if typeof(native) == TYPE_DICTIONARY:
							parts.append({"functionCall": native})
						else:
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
					elif block.type == "image":
						parts2.append(_to_gemini_image_part(block))
					elif block.type == "tool_result":
						var name := String(name_by_id.get(block.tool_use_id, ""))
						var content_val: Variant = block.get("content", "")
						if typeof(content_val) == TYPE_ARRAY:
							# Rich tool_result: emit the functionResponse with the
							# text portion, then append any image blocks as
							# additional inline_data parts in the same user turn.
							# Gemini can't embed images inside functionResponse.
							var text_content: String = ""
							var image_parts: Array = []
							for inner in content_val:
								if typeof(inner) != TYPE_DICTIONARY:
									continue
								var t: String = String(inner.get("type", ""))
								if t == "text":
									text_content += String(inner.get("text", ""))
								elif t == "image":
									image_parts.append(_to_gemini_image_part(inner))
							parts2.append({
								"functionResponse": {
									"name": name,
									"response": {"content": text_content},
								},
							})
							for ip in image_parts:
								parts2.append(ip)
						else:
							parts2.append({
								"functionResponse": {
									"name": name,
									"response": {"content": String(content_val)},
								},
							})
			elif typeof(m.content) == TYPE_STRING:
				parts2.append({"text": m.content})
			out.append({"role": "user", "parts": parts2})
	return out


static func _to_gemini_image_part(block: Dictionary) -> Dictionary:
	return {
		"inline_data": {
			"mime_type": String(block.get("media_type", "image/png")),
			"data": String(block.get("data", "")),
		},
	}


func list_models(parent: Node) -> Dictionary:
	var key := Settings.api_key("gemini")
	if key == "":
		return {"ok": false, "error": "Gemini API key not set", "chat": [], "image": []}

	var chat: Array = []
	var images: Array = []
	var page_token := ""
	for _i in 10:
		var url := "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200&key=" + key
		if page_token != "":
			url += "&pageToken=" + page_token
		var resp: Dictionary = await Http.get_json(parent, url, PackedStringArray())
		if not resp.get("ok", false):
			return {"ok": false, "error": "gemini http %s: %s" % [resp.get("code", "?"), resp.get("raw", "")], "chat": [], "image": []}
		var data: Variant = resp.get("body", {})
		if typeof(data) != TYPE_DICTIONARY:
			break
		for m in data.get("models", []):
			var full_name := String(m.get("name", ""))
			# "models/gemini-2.5-pro" -> "gemini-2.5-pro"
			var id_str := full_name.trim_prefix("models/")
			if id_str == "":
				continue
			var display := String(m.get("displayName", id_str))
			var methods: Array = m.get("supportedGenerationMethods", [])
			var lower := id_str.to_lower()
			if "predict" in methods and lower.begins_with("imagen"):
				images.append({"id": id_str, "label": display})
			elif "generateContent" in methods and lower.begins_with("gemini"):
				chat.append({"id": id_str, "label": display})
		page_token = String(data.get("nextPageToken", ""))
		if page_token == "":
			break
	chat.sort_custom(func(a, b): return a.id < b.id)
	images.sort_custom(func(a, b): return a.id < b.id)
	return {"ok": true, "error": "", "chat": chat, "image": images}
