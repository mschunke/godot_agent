@tool
extends Window

const Settings := preload("res://addons/godot_agent/core/settings.gd")
const ProviderFactory := preload("res://addons/godot_agent/providers/provider_factory.gd")

signal closed

var _keys: Dictionary = {}           # provider -> LineEdit
var _models: Dictionary = {}         # provider -> LineEdit  (chat model)
var _image_models: Dictionary = {}   # provider -> LineEdit  (image model; openai/gemini)
var _fetch_status: Dictionary = {}   # provider -> Label
var _image_provider_menu: OptionButton
var _max_turns_edit: SpinBox
var _confirm_toggle: CheckBox
var _system_prompt_edit: TextEdit
var _models_cache: Dictionary = {}   # provider -> {"chat": [...], "image": [...]}


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
	key_label.custom_minimum_size = Vector2(90, 0)
	key_row.add_child(key_label)

	var key_edit := LineEdit.new()
	key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_edit.secret = true
	key_edit.placeholder_text = "sk-... / AIza... / etc."
	key_edit.text = Settings.api_key(provider)
	key_edit.text_changed.connect(func(t: String) -> void:
		Settings.set_api_key(provider, t)
		# Invalidate cached model list — new key may unlock/restrict models.
		_models_cache.erase(provider))
	key_row.add_child(key_edit)
	_keys[provider] = key_edit

	var reveal := CheckBox.new()
	reveal.text = "Show"
	reveal.toggled.connect(func(v: bool) -> void: key_edit.secret = not v)
	key_row.add_child(reveal)

	box.add_child(key_row)

	# chat model row
	box.add_child(_build_model_row(provider, "Model:", false))

	# image model row (openai + gemini only)
	if provider == "openai" or provider == "gemini":
		box.add_child(_build_model_row(provider, "Image model:", true))

	# fetch controls
	var fetch_row := HBoxContainer.new()
	fetch_row.add_theme_constant_override("separation", 6)
	var fetch_spacer := Control.new()
	fetch_spacer.custom_minimum_size = Vector2(90, 0)
	fetch_row.add_child(fetch_spacer)

	var fetch_btn := Button.new()
	fetch_btn.text = "Fetch available models"
	fetch_btn.tooltip_text = "Query the provider's /models endpoint using your API key and pick from a list."
	fetch_btn.pressed.connect(func() -> void: _on_fetch(provider, fetch_btn))
	fetch_row.add_child(fetch_btn)

	var status := Label.new()
	status.text = ""
	status.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fetch_row.add_child(status)
	_fetch_status[provider] = status

	box.add_child(fetch_row)

	return box


func _build_model_row(provider: String, label_text: String, is_image: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(90, 0)
	row.add_child(lbl)

	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_image:
		edit.text = Settings.image_model_for(provider)
		edit.placeholder_text = _default_image_model_placeholder(provider)
		edit.text_changed.connect(func(t: String) -> void: Settings.set_image_model_for(provider, t))
		_image_models[provider] = edit
	else:
		edit.text = Settings.model_for(provider)
		edit.placeholder_text = _default_model_placeholder(provider)
		edit.text_changed.connect(func(t: String) -> void: Settings.set_model_for(provider, t))
		_models[provider] = edit
	row.add_child(edit)

	var pick_btn := Button.new()
	pick_btn.text = "Pick..."
	pick_btn.tooltip_text = "Choose from the fetched model list."
	pick_btn.pressed.connect(func() -> void: _on_pick(provider, is_image, pick_btn))
	row.add_child(pick_btn)

	return row


func _on_fetch(provider: String, btn: Button) -> void:
	var status: Label = _fetch_status.get(provider, null)
	btn.disabled = true
	if status:
		status.text = "Fetching..."
	var pf: Variant = ProviderFactory.create(provider)
	if pf == null:
		if status:
			status.text = "Unknown provider."
		btn.disabled = false
		return
	var result: Dictionary = await pf.list_models(self)
	btn.disabled = false
	if not result.get("ok", false):
		if status:
			status.text = "Failed: " + String(result.get("error", "unknown error"))
		return
	_models_cache[provider] = {
		"chat": result.get("chat", []),
		"image": result.get("image", []),
	}
	var chat_count: int = _models_cache[provider].chat.size()
	var img_count: int = _models_cache[provider].image.size()
	if status:
		if provider == "anthropic":
			status.text = "Found %d chat models." % chat_count
		else:
			status.text = "Found %d chat, %d image models." % [chat_count, img_count]


func _on_pick(provider: String, is_image: bool, anchor: Button) -> void:
	var cache: Dictionary = _models_cache.get(provider, {})
	var items: Array = cache.get("image" if is_image else "chat", [])
	if items.is_empty():
		var status: Label = _fetch_status.get(provider, null)
		if status:
			status.text = "No cached models — click Fetch first."
		return

	var menu := PopupMenu.new()
	add_child(menu)
	for i in items.size():
		var m: Dictionary = items[i]
		var lbl := String(m.get("label", m.get("id", "")))
		var id_str := String(m.get("id", ""))
		if lbl != id_str and lbl != "":
			menu.add_item("%s  (%s)" % [lbl, id_str], i)
		else:
			menu.add_item(id_str, i)
	menu.id_pressed.connect(func(idx: int) -> void:
		var picked: Dictionary = items[idx]
		var id_str := String(picked.get("id", ""))
		if is_image:
			Settings.set_image_model_for(provider, id_str)
			if _image_models.has(provider):
				_image_models[provider].text = id_str
		else:
			Settings.set_model_for(provider, id_str)
			if _models.has(provider):
				_models[provider].text = id_str
		menu.queue_free())
	menu.close_requested.connect(func() -> void: menu.queue_free())

	var pos: Vector2 = anchor.get_screen_position()
	menu.position = Vector2i(int(pos.x), int(pos.y + anchor.size.y))
	menu.popup()


func _default_model_placeholder(provider: String) -> String:
	match provider:
		"anthropic": return Settings.DEFAULT_MODEL_ANTHROPIC
		"openai": return Settings.DEFAULT_MODEL_OPENAI
		"gemini": return Settings.DEFAULT_MODEL_GEMINI
	return ""


func _default_image_model_placeholder(provider: String) -> String:
	match provider:
		"openai": return Settings.DEFAULT_IMAGE_MODEL_OPENAI
		"gemini": return Settings.DEFAULT_IMAGE_MODEL_GEMINI
	return ""


func _on_close() -> void:
	closed.emit()
	hide()


func _on_reset_system_prompt() -> void:
	Settings.set_system_prompt(Settings.DEFAULT_SYSTEM_PROMPT)
	if is_instance_valid(_system_prompt_edit):
		_system_prompt_edit.text = Settings.DEFAULT_SYSTEM_PROMPT
