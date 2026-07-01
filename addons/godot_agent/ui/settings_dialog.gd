@tool
extends Window

const Settings := preload("res://addons/godot_agent/core/settings.gd")

signal closed

var _keys: Dictionary = {}       # provider -> LineEdit
var _models: Dictionary = {}     # provider -> LineEdit
var _image_provider_menu: OptionButton
var _max_turns_edit: SpinBox
var _confirm_toggle: CheckBox
var _system_prompt_edit: TextEdit


func _init() -> void:
	title = "Godot Agent — Settings"
	size = Vector2i(560, 500)
	unresizable = false
	transient = true
	exclusive = false
	close_requested.connect(_on_close)


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	# Outer layout: scrollable content on top, fixed button row on the bottom.
	var outer := VBoxContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 8)
	outer.offset_left = 12
	outer.offset_top = 12
	outer.offset_right = -12
	outer.offset_bottom = -12
	add_child(outer)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)

	var intro := Label.new()
	intro.text = "API keys are stored in your EditorSettings (user-scoped, never written to the project)."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(intro)

	# ---- providers ----
	for provider in Settings.PROVIDERS:
		content.add_child(_build_provider_section(provider))

	content.add_child(HSeparator.new())

	# ---- image provider ----
	var img_row := HBoxContainer.new()
	img_row.add_theme_constant_override("separation", 8)
	var img_label := Label.new()
	img_label.text = "Image provider:"
	img_label.custom_minimum_size = Vector2(140, 0)
	img_row.add_child(img_label)

	_image_provider_menu = OptionButton.new()
	_image_provider_menu.add_item("Auto (match chat provider, fall back)", 0)
	_image_provider_menu.add_item("OpenAI (gpt-image-1)", 1)
	_image_provider_menu.add_item("Gemini (Imagen 4)", 2)
	var current_img := Settings.image_provider()
	var idx := 0
	if current_img == "openai": idx = 1
	elif current_img == "gemini": idx = 2
	_image_provider_menu.select(idx)
	_image_provider_menu.item_selected.connect(func(i: int) -> void:
		var value := "auto"
		if i == 1: value = "openai"
		elif i == 2: value = "gemini"
		Settings.set_image_provider(value))
	img_row.add_child(_image_provider_menu)
	content.add_child(img_row)

	# ---- max turns ----
	var turns_row := HBoxContainer.new()
	turns_row.add_theme_constant_override("separation", 8)
	var turns_label := Label.new()
	turns_label.text = "Max tool turns:"
	turns_label.custom_minimum_size = Vector2(140, 0)
	turns_row.add_child(turns_label)

	_max_turns_edit = SpinBox.new()
	_max_turns_edit.min_value = 1
	_max_turns_edit.max_value = 200
	_max_turns_edit.value = Settings.max_tool_turns()
	_max_turns_edit.value_changed.connect(func(v: float) -> void: Settings.set_max_tool_turns(int(v)))
	turns_row.add_child(_max_turns_edit)
	content.add_child(turns_row)

	# ---- confirm destructive ----
	_confirm_toggle = CheckBox.new()
	_confirm_toggle.text = "Warn on destructive tool calls (write_file, delete_node, ...)"
	_confirm_toggle.button_pressed = Settings.confirm_destructive()
	_confirm_toggle.toggled.connect(func(v: bool) -> void: Settings.set_confirm_destructive(v))
	content.add_child(_confirm_toggle)

	content.add_child(HSeparator.new())

	# ---- system prompt ----
	var sp_header_row := HBoxContainer.new()
	sp_header_row.add_theme_constant_override("separation", 8)
	var sp_label := Label.new()
	sp_label.text = "System prompt"
	sp_label.add_theme_font_size_override("font_size", 14)
	sp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp_header_row.add_child(sp_label)

	var sp_reset_btn := Button.new()
	sp_reset_btn.text = "Reset to default"
	sp_reset_btn.pressed.connect(_on_reset_system_prompt)
	sp_header_row.add_child(sp_reset_btn)
	content.add_child(sp_header_row)

	var sp_hint := Label.new()
	sp_hint.text = "Sent to the model at the start of a chat. Edits apply to new chats only — existing chats keep the prompt they were created with."
	sp_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sp_hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	content.add_child(sp_hint)

	_system_prompt_edit = TextEdit.new()
	_system_prompt_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_system_prompt_edit.custom_minimum_size = Vector2(0, 160)
	_system_prompt_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_system_prompt_edit.text = Settings.system_prompt()
	_system_prompt_edit.text_changed.connect(func() -> void: Settings.set_system_prompt(_system_prompt_edit.text))
	content.add_child(_system_prompt_edit)

	# ---- close row (stays visible outside the scroll area) ----
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	outer.add_child(btn_row)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(_on_close)
	btn_row.add_child(close_btn)


func _build_provider_section(provider: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var header := Label.new()
	header.text = provider.capitalize()
	header.add_theme_font_size_override("font_size", 14)
	box.add_child(header)

	# key row
	var key_row := HBoxContainer.new()
	key_row.add_theme_constant_override("separation", 6)
	var key_label := Label.new()
	key_label.text = "API key:"
	key_label.custom_minimum_size = Vector2(80, 0)
	key_row.add_child(key_label)

	var key_edit := LineEdit.new()
	key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_edit.secret = true
	key_edit.placeholder_text = "sk-... / AIza... / etc."
	key_edit.text = Settings.api_key(provider)
	key_edit.text_changed.connect(func(t: String) -> void: Settings.set_api_key(provider, t))
	key_row.add_child(key_edit)
	_keys[provider] = key_edit

	var reveal := CheckBox.new()
	reveal.text = "Show"
	reveal.toggled.connect(func(v: bool) -> void: key_edit.secret = not v)
	key_row.add_child(reveal)

	box.add_child(key_row)

	# model row
	var model_row := HBoxContainer.new()
	model_row.add_theme_constant_override("separation", 6)
	var model_label := Label.new()
	model_label.text = "Model:"
	model_label.custom_minimum_size = Vector2(80, 0)
	model_row.add_child(model_label)

	var model_edit := LineEdit.new()
	model_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	model_edit.text = Settings.model_for(provider)
	model_edit.placeholder_text = _default_model_placeholder(provider)
	model_edit.text_changed.connect(func(t: String) -> void: Settings.set_model_for(provider, t))
	model_row.add_child(model_edit)
	_models[provider] = model_edit

	box.add_child(model_row)

	return box


func _default_model_placeholder(provider: String) -> String:
	match provider:
		"anthropic": return Settings.DEFAULT_MODEL_ANTHROPIC
		"openai": return Settings.DEFAULT_MODEL_OPENAI
		"gemini": return Settings.DEFAULT_MODEL_GEMINI
	return ""


func _on_close() -> void:
	closed.emit()
	hide()


func _on_reset_system_prompt() -> void:
	Settings.set_system_prompt(Settings.DEFAULT_SYSTEM_PROMPT)
	if is_instance_valid(_system_prompt_edit):
		_system_prompt_edit.text = Settings.DEFAULT_SYSTEM_PROMPT
