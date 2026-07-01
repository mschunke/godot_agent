@tool
extends EditorPlugin

const MainScreenScript := preload("res://addons/godot_agent/ui/main_screen.gd")

var _main_screen: Control = null


func _enter_tree() -> void:
	_main_screen = MainScreenScript.new()
	_main_screen.name = "GodotAgentMainScreen"
	_main_screen.plugin = self
	EditorInterface.get_editor_main_screen().add_child(_main_screen)
	_make_visible(false)


func _exit_tree() -> void:
	if is_instance_valid(_main_screen):
		_main_screen.queue_free()
		_main_screen = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if is_instance_valid(_main_screen):
		_main_screen.visible = visible


func _get_plugin_name() -> String:
	return "AI"


func _get_plugin_icon() -> Texture2D:
	# Use a built-in editor icon so we don't ship binary assets.
	var theme := EditorInterface.get_editor_theme()
	if theme and theme.has_icon("Sprite2D", "EditorIcons"):
		return theme.get_icon("Sprite2D", "EditorIcons")
	return null
