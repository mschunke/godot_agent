@tool
extends RefCounted
class_name GodotAgentProviderBase

# Provider interface. Implementations must translate canonical tool schemas
# (see GodotAgentToolSchemas) and canonical messages (see GodotAgentConversation)
# into their native API and back.
#
# send_conversation() takes the full state and returns:
#   {
#     ok: bool,
#     error: String,
#     stop_reason: "end_turn" | "tool_use" | "max_tokens" | "other",
#     text: String,           # any assistant text produced this turn
#     tool_calls: [           # requested tool invocations (may be empty)
#       { id: String, name: String, input: Dictionary }
#     ],
#     assistant_content: Array,  # provider-native assistant blocks to append verbatim
#     usage: Dictionary,
#   }

func send_conversation(_parent: Node, _system: String, _messages: Array, _tools: Array, _web_enabled: bool) -> Dictionary:
	push_error("send_conversation not implemented")
	return {"ok": false, "error": "not implemented"}


func format_tool_results(_results: Array) -> Dictionary:
	# Returns a message to append to `messages` describing the tool_results
	# in provider-native form. Default: canonical tool_result blocks (Anthropic-style).
	var parts: Array = []
	for r in _results:
		parts.append({
			"type": "tool_result",
			"tool_use_id": r.tool_use_id,
			"content": r.content,
			"is_error": r.get("is_error", false),
		})
	return {"role": "user", "content": parts}


static func stringify(v: Variant) -> String:
	if typeof(v) == TYPE_STRING:
		return v
	return JSON.stringify(v)
