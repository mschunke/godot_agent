@tool
extends Control

const Agent := preload("res://addons/godot_agent/core/agent.gd")
const Settings := preload("res://addons/godot_agent/core/settings.gd")
const SettingsDialogScript := preload("res://addons/godot_agent/ui/settings_dialog.gd")

var plugin: EditorPlugin  # assigned by plugin.gd

var _agent: Agent
var _messages_container: VBoxContainer
var _messages_scroll: ScrollContainer
var _input: TextEdit
var _send_button: Button
var _status_label: Label
var _provider_menu: OptionButton
var _web_toggle: CheckBox
var _settings_dialog: Window


func _ready() -> void:
	custom_minimum_size = Vector2(400, 300)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_agent = Agent.new(self)
	_agent.message_appended.connect(_on_agent_message)
	_agent.tool_started.connect(_on_tool_started)
	_agent.tool_finished.connect(_on_tool_finished)
	_agent.turn_started.connect(_on_turn_started)
	_agent.turn_finished.connect(_on_turn_finished)
	_agent.error_occurred.connect(_on_error)

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
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	root.add_child(_status_label)

	# --- input row ---
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 6)
	root.add_child(input_row)

	_input = TextEdit.new()
	_input.placeholder_text = "Ask the agent to plan, code, or edit your scene... (Ctrl/Cmd+Enter to send)"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.custom_minimum_size = Vector2(0, 70)
	_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_input.gui_input.connect(_on_input_gui_input)
	input_row.add_child(_input)

	_send_button = Button.new()
	_send_button.text = "Send"
	_send_button.custom_minimum_size = Vector2(80, 0)
	_send_button.tooltip_text = "Ctrl/Cmd + Enter"
	_send_button.pressed.connect(_on_send_pressed)
	input_row.add_child(_send_button)


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


func _on_reset() -> void:
	if _agent.is_busy():
		return
	_agent.reset()
	for child in _messages_container.get_children():
		child.queue_free()
	_append_bubble("system", "New chat started.")


func _on_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# Ctrl+Enter (or Cmd+Enter on macOS) sends. Plain Enter keeps its default
		# newline behaviour inside TextEdit, which is what users expect for a
		# multi-line prompt.
		if event.keycode == KEY_ENTER and (event.ctrl_pressed or event.meta_pressed):
			accept_event()
			_on_send_pressed()


func _on_send_pressed() -> void:
	var text := _input.text.strip_edges()
	if text == "":
		return
	if _agent.is_busy():
		return
	_input.text = ""
	_agent.send_user_message(text)


# ---------- agent signals ----------

func _on_agent_message(role: String, text: String) -> void:
	_append_bubble(role, text)


func _on_tool_started(tool_name: String, input: Dictionary) -> void:
	_status_label.text = "→ tool: %s(%s)" % [tool_name, JSON.stringify(input).left(160)]


func _on_tool_finished(tool_name: String, result: Dictionary) -> void:
	var ok := bool(result.get("ok", true))
	var glyph := "✓" if ok else "✗"
	_append_bubble("tool", "%s %s → %s" % [glyph, tool_name, JSON.stringify(result).left(400)])
	_status_label.text = ""


func _on_turn_started() -> void:
	_status_label.text = "thinking..."
	_send_button.disabled = true


func _on_turn_finished(reason: String) -> void:
	_status_label.text = "done (%s)" % reason
	_send_button.disabled = false


func _on_error(msg: String) -> void:
	_append_bubble("error", msg)


# ---------- bubble rendering ----------

func _append_bubble(role: String, text: String) -> void:
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

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	panel.add_child(vb)

	var role_label := Label.new()
	role_label.text = role.to_upper()
	role_label.add_theme_font_size_override("font_size", 10)
	role_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	vb.add_child(role_label)

	var body := RichTextLabel.new()
	body.bbcode_enabled = false
	body.fit_content = true
	body.selection_enabled = true
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.text = text
	vb.add_child(body)

	_messages_container.add_child(panel)
	# Scroll to bottom on next frame after the new bubble is laid out.
	call_deferred("_scroll_to_bottom")


func _scroll_to_bottom() -> void:
	if not is_instance_valid(_messages_scroll):
		return
	var sb := _messages_scroll.get_v_scroll_bar()
	if sb:
		_messages_scroll.scroll_vertical = int(sb.max_value)
