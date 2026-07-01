@tool
extends Control

const Agent := preload("res://addons/godot_agent/core/agent.gd")
const Settings := preload("res://addons/godot_agent/core/settings.gd")
const SettingsDialogScript := preload("res://addons/godot_agent/ui/settings_dialog.gd")
const HistoryDialogScript := preload("res://addons/godot_agent/ui/history_dialog.gd")

var plugin: EditorPlugin  # assigned by plugin.gd

var _agent: Agent
var _messages_container: VBoxContainer
var _messages_scroll: ScrollContainer
var _input: TextEdit
var _send_button: Button
var _retry_button: Button
var _status_label: Label
var _status_dot: Panel
var _status_dot_style: StyleBoxFlat
var _token_label: Label
var _provider_menu: OptionButton
var _web_toggle: CheckBox
var _settings_dialog: Window
var _history_dialog: Window
var _turn_produced_output: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(400, 300)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Editor's main-screen container is a VBoxContainer; without expand flags
	# our root sits at its minimum size and leaves empty space below.
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_agent = Agent.new(self)
	_agent.message_appended.connect(_on_agent_message)
	_agent.tool_started.connect(_on_tool_started)
	_agent.tool_finished.connect(_on_tool_finished)
	_agent.turn_started.connect(_on_turn_started)
	_agent.turn_finished.connect(_on_turn_finished)
	_agent.error_occurred.connect(_on_error)
	_agent.conversation_loaded.connect(_on_conversation_loaded)
	_agent.history_changed.connect(_on_history_changed)

	_build_ui()
	_refresh_provider_menu()
	_web_toggle.button_pressed = Settings.web_enabled()

	_append_bubble("system", "Godot Agent ready. Configure your API key in Settings, then ask me anything about your project.")


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# --- top bar ---
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)

	var title := Label.new()
	title.text = "AI Agent"
	title.add_theme_font_size_override("font_size", 16)
	top.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)

	var provider_label := Label.new()
	provider_label.text = "Provider:"
	top.add_child(provider_label)

	_provider_menu = OptionButton.new()
	_provider_menu.item_selected.connect(_on_provider_changed)
	top.add_child(_provider_menu)

	_web_toggle = CheckBox.new()
	_web_toggle.text = "Web"
	_web_toggle.tooltip_text = "Allow the agent to search the internet (uses provider-native web tools)"
	_web_toggle.toggled.connect(func(v: bool) -> void: Settings.set_web_enabled(v))
	top.add_child(_web_toggle)

	var settings_btn := Button.new()
	settings_btn.text = "Settings"
	settings_btn.pressed.connect(_open_settings)
	top.add_child(settings_btn)

	var history_btn := Button.new()
	history_btn.text = "History"
	history_btn.tooltip_text = "Browse previous conversations"
	history_btn.pressed.connect(_open_history)
	top.add_child(history_btn)

	var reset_btn := Button.new()
	reset_btn.text = "New chat"
	reset_btn.pressed.connect(_on_reset)
	top.add_child(reset_btn)

	# --- messages area ---
	_messages_scroll = ScrollContainer.new()
	_messages_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_messages_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_messages_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_messages_scroll)

	_messages_container = VBoxContainer.new()
	_messages_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_messages_container.add_theme_constant_override("separation", 10)
	_messages_scroll.add_child(_messages_container)

	# --- status ---
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 6)
	root.add_child(status_row)

	_status_dot = Panel.new()
	_status_dot.custom_minimum_size = Vector2(10, 10)
	_status_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_dot_style = StyleBoxFlat.new()
	_status_dot_style.corner_radius_top_left = 5
	_status_dot_style.corner_radius_top_right = 5
	_status_dot_style.corner_radius_bottom_left = 5
	_status_dot_style.corner_radius_bottom_right = 5
	_status_dot.add_theme_stylebox_override("panel", _status_dot_style)
	status_row.add_child(_status_dot)

	_status_label = Label.new()
	_status_label.text = ""
	status_row.add_child(_status_label)

	_set_status("idle", "Ready")

	# --- input row ---
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 6)
	root.add_child(input_row)

	_input = TextEdit.new()
	_input.placeholder_text = "Ask the agent to plan, code, or edit your scene... (Ctrl/Cmd+Enter to send)"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.custom_minimum_size = Vector2(0, 70)
	_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	# Inline lambda instead of a named callback: named-method lookups on
	# gui_input have been observed to intermittently fire "Method not found"
	# after @tool hot-reloads (the signal fires against the previous script
	# revision briefly). A lambda captures the current script state directly.
	_input.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed:
			# Ctrl+Enter (or Cmd+Enter on macOS) sends. Plain Enter keeps its
			# default newline behaviour, which is what users expect in a
			# multi-line prompt.
			if event.keycode == KEY_ENTER and (event.ctrl_pressed or event.meta_pressed):
				accept_event()
				_on_send_pressed())
	input_row.add_child(_input)

	_send_button = Button.new()
	_send_button.text = "Send"
	_send_button.custom_minimum_size = Vector2(80, 0)
	_send_button.tooltip_text = "Ctrl/Cmd + Enter"
	_send_button.pressed.connect(_on_send_pressed)
	input_row.add_child(_send_button)

	_retry_button = Button.new()
	_retry_button.text = "Retry"
	_retry_button.custom_minimum_size = Vector2(70, 0)
	_retry_button.tooltip_text = "Re-run the model against the current conversation (available when the last turn produced nothing or after an error)."
	_retry_button.disabled = true
	_retry_button.pressed.connect(_on_retry_pressed)
	input_row.add_child(_retry_button)

	_token_label = Label.new()
	_token_label.text = ""
	_token_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_token_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.72))
	_token_label.tooltip_text = "Cumulative tokens used by this conversation (input / output)."
	input_row.add_child(_token_label)
	_refresh_token_label()


func _refresh_provider_menu() -> void:
	_provider_menu.clear()
	var current := Settings.provider()
	for i in Settings.PROVIDERS.size():
		var p: String = Settings.PROVIDERS[i]
		_provider_menu.add_item(p.capitalize(), i)
		if p == current:
			_provider_menu.select(i)


func _on_provider_changed(index: int) -> void:
	var p: String = Settings.PROVIDERS[index]
	Settings.set_provider(p)
	if Settings.api_key(p) == "":
		_append_bubble("system", "No API key set for %s. Open Settings to add one." % p)


func _open_settings() -> void:
	if _settings_dialog and is_instance_valid(_settings_dialog):
		_settings_dialog.popup_centered()
		return
	_settings_dialog = SettingsDialogScript.new()
	add_child(_settings_dialog)
	_settings_dialog.closed.connect(_refresh_provider_menu)
	_settings_dialog.popup_centered()


func _open_history() -> void:
	if _history_dialog == null or not is_instance_valid(_history_dialog):
		_history_dialog = HistoryDialogScript.new()
		add_child(_history_dialog)
		_history_dialog.load_requested.connect(_on_history_load)
		_history_dialog.delete_requested.connect(_on_history_delete)
	_history_dialog.refresh(_agent.list_conversations())
	_history_dialog.popup_centered()


func _on_history_load(id: String) -> void:
	if _agent.is_busy():
		_append_bubble("error", "Wait for the current turn to finish before loading another chat.")
		return
	var r: Dictionary = _agent.load_conversation(id)
	if not r.get("ok", false):
		_append_bubble("error", "Failed to load chat: %s" % r.get("error", ""))


func _on_history_delete(id: String) -> void:
	_agent.delete_conversation(id)
	if _history_dialog and is_instance_valid(_history_dialog):
		_history_dialog.refresh(_agent.list_conversations())


func _on_history_changed() -> void:
	if _history_dialog and is_instance_valid(_history_dialog) and _history_dialog.visible:
		_history_dialog.refresh(_agent.list_conversations())


func _on_conversation_loaded() -> void:
	_clear_messages_ui()
	if _agent.conversation.is_empty():
		_append_bubble("system", "New chat started.")
	else:
		_replay_conversation(_agent.conversation)
		_append_bubble("system", "Loaded chat: %s" % _agent.conversation.title)
	_refresh_token_label()
	_update_retry_button()


func _clear_messages_ui() -> void:
	for child in _messages_container.get_children():
		child.queue_free()


func _replay_conversation(convo) -> void:
	# Build a lookup of tool_use_id → tool name from assistant messages so
	# tool_result bubbles during replay can show which tool they belong to.
	var name_by_id: Dictionary = {}
	for m in convo.messages():
		var content: Variant = m.get("content", [])
		if typeof(content) != TYPE_ARRAY or m.get("role", "") != "assistant":
			continue
		for block in content:
			if block.get("type", "") == "tool_use":
				name_by_id[block.get("id", "")] = block.get("name", "")

	for m in convo.messages():
		var role: String = m.get("role", "")
		var content: Variant = m.get("content", [])
		if typeof(content) != TYPE_ARRAY:
			continue
		for block in content:
			match block.get("type", ""):
				"text":
					if role == "user":
						_append_bubble("user", String(block.get("text", "")))
					elif role == "assistant":
						_append_bubble("assistant", String(block.get("text", "")))
				"tool_result":
					var raw := String(block.get("content", ""))
					var is_err := bool(block.get("is_error", false))
					var tool_use_id := String(block.get("tool_use_id", ""))
					var tool_name := String(name_by_id.get(tool_use_id, "tool"))
					_append_tool_bubble(tool_name, not is_err, raw)
				# tool_use blocks are elided from the replay since their tool_result
				# already conveys what happened.


func _on_reset() -> void:
	if _agent.is_busy():
		return
	_agent.reset()


func _on_send_pressed() -> void:
	var text := _input.text.strip_edges()
	if text == "":
		return
	if _agent.is_busy():
		return
	_input.text = ""
	_retry_button.disabled = true
	_agent.send_user_message(text)


# ---------- agent signals ----------

func _on_agent_message(role: String, text: String) -> void:
	if role == "assistant" or role == "user":
		_turn_produced_output = true
	_append_bubble(role, text)


func _on_tool_started(tool_name: String, input: Dictionary) -> void:
	_turn_produced_output = true
	_set_status("processing", "→ tool: %s(%s)" % [tool_name, JSON.stringify(input).left(160)])


func _on_tool_finished(tool_name: String, result: Dictionary) -> void:
	var ok := bool(result.get("ok", true))
	_append_tool_bubble(tool_name, ok, JSON.stringify(result))
	_set_status("processing", "thinking...")
	_refresh_token_label()


func _on_turn_started() -> void:
	_turn_produced_output = false
	_set_status("processing", "thinking...")
	_send_button.disabled = true
	_retry_button.disabled = true


func _on_turn_finished(reason: String) -> void:
	if reason == "error":
		# _on_error already set the error status; leave it.
		pass
	elif reason == "max_turns":
		_set_status("idle", "paused (max_turns) — type 'Continue' to keep going")
	else:
		_set_status("idle", "done (%s)" % reason)
	_send_button.disabled = false
	# Max-turn stop always gets its own notice so the user knows what happened
	# and how to resume, even if the last turn already produced visible output.
	if reason == "max_turns":
		_append_max_turns_notice()
	elif reason != "error" and not _turn_produced_output:
		# Empty final turn — the model didn't say or do anything visible.
		_append_empty_turn_notice(reason)
	_refresh_token_label()
	_update_retry_button()


func _on_error(msg: String) -> void:
	var first_line := msg.get_slice("\n", 0)
	if first_line.length() > 100:
		first_line = first_line.substr(0, 97) + "..."
	_set_status("error", "error: " + first_line)
	_append_error_bubble(msg)
	_update_retry_button()


func _update_retry_button() -> void:
	if _agent.is_busy():
		_retry_button.disabled = true
		return
	# Retry is possible when the last recorded message is a user message (either
	# the original prompt or a batch of tool_results waiting for a reply).
	var msgs: Array = _agent.conversation.messages()
	var can := not msgs.is_empty() and String(msgs[msgs.size() - 1].get("role", "")) == "user"
	_retry_button.disabled = not can


func _refresh_token_label() -> void:
	if not is_instance_valid(_token_label):
		return
	var t: Dictionary = _agent.conversation.totals()
	var total: int = int(t.get("total", 0))
	if total <= 0:
		_token_label.text = "tokens: —"
		return
	var inp: int = int(t.get("input", 0))
	var outp: int = int(t.get("output", 0))
	_token_label.text = "tokens: %s in / %s out (%s)" % [
		_format_tokens(inp), _format_tokens(outp), _format_tokens(total)
	]


static func _format_tokens(n: int) -> String:
	if n < 1000:
		return str(n)
	if n < 1_000_000:
		return "%.1fk" % (float(n) / 1000.0)
	return "%.2fM" % (float(n) / 1_000_000.0)


func _on_retry_pressed() -> void:
	if _agent.is_busy():
		return
	_retry_button.disabled = true
	var r: Dictionary = await _agent.retry_last()
	if not r.get("ok", false):
		_append_error_bubble("Retry failed: %s" % r.get("error", ""))
	_update_retry_button()


# ---------- bubble rendering ----------

func _append_bubble(role: String, text: String) -> void:
	var panel := _make_bubble_panel(role)
	var vb := _bubble_vbox(panel)
	vb.add_child(_role_label(role))

	var use_markdown := role == "assistant"
	vb.add_child(_make_body_label(text, use_markdown))

	_messages_container.add_child(panel)
	call_deferred("_scroll_to_bottom")


func _append_tool_bubble(tool_name: String, ok: bool, result_text: String) -> void:
	var panel := _make_bubble_panel("tool")
	var vb := _bubble_vbox(panel)

	var glyph := "✓" if ok else "✗"
	var summary := "%s  %s  (%d chars — click to expand)" % [glyph, tool_name, result_text.length()]

	var header := Button.new()
	header.text = "▶  " + summary
	header.flat = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.focus_mode = Control.FOCUS_NONE
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(header)

	var body := _make_body_label(result_text, false)
	body.visible = false
	vb.add_child(body)

	header.pressed.connect(func() -> void:
		body.visible = not body.visible
		header.text = ("▼  " if body.visible else "▶  ") + summary)

	_messages_container.add_child(panel)
	call_deferred("_scroll_to_bottom")


func _append_error_bubble(msg: String) -> void:
	var panel := _make_bubble_panel("error")
	var vb := _bubble_vbox(panel)

	var first_line := msg.get_slice("\n", 0)
	if first_line.length() > 120:
		first_line = first_line.substr(0, 117) + "..."

	var header := Button.new()
	header.text = "▼  ERROR — " + first_line
	header.flat = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.focus_mode = Control.FOCUS_NONE
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(header)

	var body := _make_body_label(msg, false)
	body.visible = true
	vb.add_child(body)

	header.pressed.connect(func() -> void:
		body.visible = not body.visible
		header.text = ("▼  " if body.visible else "▶  ") + "ERROR — " + first_line)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 6)
	vb.add_child(actions)

	var retry_btn := Button.new()
	retry_btn.text = "Retry"
	retry_btn.tooltip_text = "Re-send the last user message to the model"
	retry_btn.pressed.connect(func() -> void:
		retry_btn.disabled = true
		var r: Dictionary = await _agent.retry_last()
		if not r.get("ok", false):
			_append_error_bubble("Retry failed: %s" % r.get("error", "")))
	actions.add_child(retry_btn)

	_messages_container.add_child(panel)
	call_deferred("_scroll_to_bottom")


func _append_empty_turn_notice(reason: String) -> void:
	var panel := _make_bubble_panel("system")
	var vb := _bubble_vbox(panel)
	vb.add_child(_role_label("notice"))

	var msg := "The model finished the turn (%s) without producing any visible text or tool call. This can happen with thinking models that emit only a thought summary. Click Retry to re-run the model against the current conversation." % reason
	vb.add_child(_make_body_label(msg, false))

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 6)
	vb.add_child(actions)

	var retry_btn := Button.new()
	retry_btn.text = "Retry"
	retry_btn.tooltip_text = "Re-run the model against the current conversation state"
	retry_btn.pressed.connect(func() -> void:
		retry_btn.disabled = true
		var r: Dictionary = await _agent.retry_last()
		if not r.get("ok", false):
			_append_error_bubble("Retry failed: %s" % r.get("error", ""))
		_update_retry_button())
	actions.add_child(retry_btn)

	_messages_container.add_child(panel)
	call_deferred("_scroll_to_bottom")


func _append_max_turns_notice() -> void:
	var panel := _make_bubble_panel("system")
	var vb := _bubble_vbox(panel)
	vb.add_child(_role_label("notice"))

	var cap := Settings.max_tool_turns()
	var msg := "Reached the tool-turn cap (%d) for this run. The task is paused, not failed — type [b]Continue[/b] (or any follow-up) to let the model keep working. You can raise the cap in Settings if this happens often." % cap
	vb.add_child(_make_body_label(msg, true))

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 6)
	vb.add_child(actions)

	var continue_btn := Button.new()
	continue_btn.text = "Continue"
	continue_btn.tooltip_text = "Send 'Continue' as the next user message"
	continue_btn.pressed.connect(func() -> void:
		if _agent.is_busy():
			return
		continue_btn.disabled = true
		_agent.send_user_message("Continue"))
	actions.add_child(continue_btn)

	_messages_container.add_child(panel)
	call_deferred("_scroll_to_bottom")


func _make_bubble_panel(role: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	match role:
		"user":
			style.bg_color = Color(0.16, 0.24, 0.36)
		"assistant":
			style.bg_color = Color(0.14, 0.14, 0.18)
		"tool":
			style.bg_color = Color(0.10, 0.15, 0.10)
		"error":
			style.bg_color = Color(0.35, 0.10, 0.10)
		_:
			style.bg_color = Color(0.20, 0.20, 0.22)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _bubble_vbox(panel: PanelContainer) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	panel.add_child(vb)
	return vb


func _role_label(role: String) -> Label:
	var role_label := Label.new()
	role_label.text = role.to_upper()
	role_label.add_theme_font_size_override("font_size", 10)
	role_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	return role_label


func _make_body_label(text: String, use_markdown: bool) -> RichTextLabel:
	var body := RichTextLabel.new()
	body.bbcode_enabled = use_markdown
	body.fit_content = true
	body.selection_enabled = true
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# fit_content + autowrap only computes height once the label knows its width,
	# which in a fresh ScrollContainer layout isn't set for a frame or two. A
	# small min height keeps the bubble visible while the layout settles.
	body.custom_minimum_size = Vector2(0, 24)
	if use_markdown:
		body.text = _markdown_to_bbcode(text)
	else:
		body.text = text
	return body


static func _markdown_to_bbcode(text: String) -> String:
	# Escape existing BBCode brackets so they render literally.
	var s := text.replace("[", "[lb]")

	var re_code := RegEx.new()
	re_code.compile("`([^`\\n]+)`")
	s = re_code.sub(s, "[code]$1[/code]", true)

	var re_h3 := RegEx.new()
	re_h3.compile("(?m)^###\\s+(.+)$")
	s = re_h3.sub(s, "[b]$1[/b]", true)

	var re_h2 := RegEx.new()
	re_h2.compile("(?m)^##\\s+(.+)$")
	s = re_h2.sub(s, "[b][font_size=16]$1[/font_size][/b]", true)

	var re_h1 := RegEx.new()
	re_h1.compile("(?m)^#\\s+(.+)$")
	s = re_h1.sub(s, "[b][font_size=18]$1[/font_size][/b]", true)

	var re_bold := RegEx.new()
	re_bold.compile("\\*\\*([^*\\n]+)\\*\\*")
	s = re_bold.sub(s, "[b]$1[/b]", true)

	var re_italic := RegEx.new()
	re_italic.compile("(?<![\\w*])\\*([^*\\n]+)\\*(?![\\w*])")
	s = re_italic.sub(s, "[i]$1[/i]", true)

	return s


func _scroll_to_bottom() -> void:
	# RichTextLabel with fit_content needs several layout passes before its
	# final height is reported to the ScrollContainer. Snap to max across a few
	# frames so the last frame catches the finalized size.
	if not is_instance_valid(_messages_scroll):
		return
	var sb := _messages_scroll.get_v_scroll_bar()
	if sb == null:
		return
	for i in 6:
		await get_tree().process_frame
		if not is_instance_valid(_messages_scroll):
			return
		_messages_scroll.scroll_vertical = int(sb.max_value)


func _set_status(state: String, text: String) -> void:
	var dot_color: Color
	var text_color: Color
	match state:
		"processing":
			dot_color = Color(0.36, 0.66, 0.98)   # blue
			text_color = Color(0.75, 0.85, 0.98)
		"error":
			dot_color = Color(0.90, 0.30, 0.30)   # red
			text_color = Color(0.98, 0.70, 0.70)
		_:  # "idle" / anything else
			dot_color = Color(0.40, 0.75, 0.45)   # green
			text_color = Color(0.65, 0.65, 0.70)
	if _status_dot_style:
		_status_dot_style.bg_color = dot_color
	if _status_label:
		_status_label.text = text
		_status_label.add_theme_color_override("font_color", text_color)
