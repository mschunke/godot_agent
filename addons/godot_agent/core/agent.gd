@tool
extends RefCounted
class_name GodotAgentAgent

const Settings := preload("res://addons/godot_agent/core/settings.gd")
const Conversation := preload("res://addons/godot_agent/core/conversation.gd")
const AgentLogger := preload("res://addons/godot_agent/core/logger.gd")
const ToolSchemas := preload("res://addons/godot_agent/tools/tool_schemas.gd")
const ToolRegistry := preload("res://addons/godot_agent/tools/tool_registry.gd")
const ProviderFactory := preload("res://addons/godot_agent/providers/provider_factory.gd")

signal message_appended(role: String, text: String)
signal tool_started(name: String, input: Dictionary)
signal tool_finished(name: String, result: Dictionary)
signal turn_started
signal turn_finished(reason: String)
signal error_occurred(message: String)

var conversation: Conversation
var logger: AgentLogger
var parent_node: Node  # required for HTTPRequest child nodes

var _busy: bool = false


func _init(parent: Node) -> void:
	parent_node = parent
	conversation = Conversation.new()
	conversation.set_system_prompt(Settings.system_prompt())
	logger = AgentLogger.new()


func is_busy() -> bool:
	return _busy


func send_user_message(text: String) -> void:
	if _busy:
		logger.warn("agent busy, ignoring message")
		return
	if text.strip_edges() == "":
		return

	conversation.add_user_text(text)
	message_appended.emit("user", text)
	await _run_loop()


func _run_loop() -> void:
	_busy = true
	turn_started.emit()

	# Pick up any system-prompt edits the user made since the last turn.
	conversation.set_system_prompt(Settings.system_prompt())

	var provider_name := Settings.provider()
	var provider = ProviderFactory.create(provider_name)
	if provider == null:
		_finish("error", "no provider available")
		return
	if Settings.api_key(provider_name) == "":
		_finish("error", "no API key set for provider '%s'. Open Settings and paste one." % provider_name)
		return

	var tools := ToolSchemas.all()
	var web := Settings.web_enabled()
	var max_turns := Settings.max_tool_turns()

	for turn_i in max_turns:
		var resp: Dictionary = await provider.send_conversation(
			parent_node,
			conversation.system_prompt(),
			conversation.messages(),
			tools,
			web,
		)
		if not resp.get("ok", false):
			_finish("error", str(resp.get("error", "unknown error")))
			return

		var assistant_content: Array = resp.assistant_content
		conversation.add_assistant(assistant_content)
		if resp.text != "":
			message_appended.emit("assistant", resp.text)

		var tool_calls: Array = resp.tool_calls
		if tool_calls.is_empty():
			_finish(resp.stop_reason, "")
			return

		var results: Array = []
		for call in tool_calls:
			tool_started.emit(call.name, call.input)
			logger.info("tool %s(%s)" % [call.name, JSON.stringify(call.input)])
			var tool_result: Dictionary = await ToolRegistry.dispatch(parent_node, call.name, call.input)
			tool_finished.emit(call.name, tool_result)

			var content_str: String = JSON.stringify(tool_result)
			var is_err := not bool(tool_result.get("ok", true))
			results.append({
				"tool_use_id": call.id,
				"content": content_str,
				"is_error": is_err,
			})

		# Feed tool results back as a canonical user message; each provider converts.
		conversation.add_tool_results(results)

	_finish("max_turns", "hit the tool-turn cap (%d). Ask the assistant to continue if needed." % max_turns)


func _finish(reason: String, extra: String) -> void:
	_busy = false
	if reason == "error":
		error_occurred.emit(extra)
		logger.error(extra)
	turn_finished.emit(reason)


func reset() -> void:
	if _busy:
		return
	conversation.clear()
	conversation.set_system_prompt(Settings.system_prompt())
