@tool
extends RefCounted
class_name GodotAgentSettings

# All settings live in EditorSettings so API keys stay user-scoped
# (never written into the project or committed).

const PREFIX := "godot_agent/"

const K_PROVIDER := PREFIX + "provider"
const K_MODEL := PREFIX + "model"
const K_WEB_ENABLED := PREFIX + "web_enabled"
const K_MAX_TURNS := PREFIX + "max_tool_turns"
const K_CONFIRM_DESTRUCTIVE := PREFIX + "confirm_destructive"

const K_KEY_ANTHROPIC := PREFIX + "keys/anthropic"
const K_KEY_OPENAI := PREFIX + "keys/openai"
const K_KEY_GEMINI := PREFIX + "keys/gemini"

const K_MODEL_ANTHROPIC := PREFIX + "models/anthropic"
const K_MODEL_OPENAI := PREFIX + "models/openai"
const K_MODEL_GEMINI := PREFIX + "models/gemini"

const K_IMAGE_PROVIDER := PREFIX + "image_provider"

const DEFAULT_MODEL_ANTHROPIC := "claude-sonnet-4-5-20250929"
const DEFAULT_MODEL_OPENAI := "gpt-5"
const DEFAULT_MODEL_GEMINI := "gemini-2.5-pro"

const PROVIDERS := ["anthropic", "openai", "gemini"]


static func _es() -> EditorSettings:
	return EditorInterface.get_editor_settings()


static func _read(key: String, default_value: Variant) -> Variant:
	var es := _es()
	if es == null:
		return default_value
	if not es.has_setting(key):
		es.set_setting(key, default_value)
		return default_value
	return es.get_setting(key)


static func _write(key: String, value: Variant) -> void:
	var es := _es()
	if es == null:
		return
	es.set_setting(key, value)


static func provider() -> String:
	return String(_read(K_PROVIDER, "anthropic"))


static func set_provider(value: String) -> void:
	_write(K_PROVIDER, value)


static func api_key(p: String) -> String:
	match p:
		"anthropic": return String(_read(K_KEY_ANTHROPIC, ""))
		"openai": return String(_read(K_KEY_OPENAI, ""))
		"gemini": return String(_read(K_KEY_GEMINI, ""))
	return ""


static func set_api_key(p: String, value: String) -> void:
	match p:
		"anthropic": _write(K_KEY_ANTHROPIC, value)
		"openai": _write(K_KEY_OPENAI, value)
		"gemini": _write(K_KEY_GEMINI, value)


static func model_for(p: String) -> String:
	match p:
		"anthropic": return String(_read(K_MODEL_ANTHROPIC, DEFAULT_MODEL_ANTHROPIC))
		"openai": return String(_read(K_MODEL_OPENAI, DEFAULT_MODEL_OPENAI))
		"gemini": return String(_read(K_MODEL_GEMINI, DEFAULT_MODEL_GEMINI))
	return ""


static func set_model_for(p: String, value: String) -> void:
	match p:
		"anthropic": _write(K_MODEL_ANTHROPIC, value)
		"openai": _write(K_MODEL_OPENAI, value)
		"gemini": _write(K_MODEL_GEMINI, value)


static func web_enabled() -> bool:
	return bool(_read(K_WEB_ENABLED, false))


static func set_web_enabled(value: bool) -> void:
	_write(K_WEB_ENABLED, value)


static func max_tool_turns() -> int:
	return int(_read(K_MAX_TURNS, 25))


static func set_max_tool_turns(value: int) -> void:
	_write(K_MAX_TURNS, value)


static func confirm_destructive() -> bool:
	return bool(_read(K_CONFIRM_DESTRUCTIVE, true))


static func set_confirm_destructive(value: bool) -> void:
	_write(K_CONFIRM_DESTRUCTIVE, value)


static func image_provider() -> String:
	# "auto" = try chat provider, fall back to whichever image-capable provider has a key.
	return String(_read(K_IMAGE_PROVIDER, "auto"))


static func set_image_provider(value: String) -> void:
	_write(K_IMAGE_PROVIDER, value)


static func resolve_image_provider() -> String:
	var chosen := image_provider()
	if chosen != "auto":
		return chosen
	var chat := provider()
	# Anthropic has no image gen — skip it in auto mode.
	if chat != "anthropic" and api_key(chat) != "":
		return chat
	if api_key("openai") != "":
		return "openai"
	if api_key("gemini") != "":
		return "gemini"
	return ""
