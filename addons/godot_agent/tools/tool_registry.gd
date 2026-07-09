@tool
extends RefCounted
class_name GodotAgentToolRegistry

# Dispatches canonical tool names to their implementation.
# Kept as a facade so providers only speak the canonical name/input schema.

const ProjectTools := preload("res://addons/godot_agent/tools/project_tools.gd")
const SceneTools := preload("res://addons/godot_agent/tools/scene_tools.gd")
const ScriptTools := preload("res://addons/godot_agent/tools/script_tools.gd")
const EditorTools := preload("res://addons/godot_agent/tools/editor_tools.gd")
const SignalTools := preload("res://addons/godot_agent/tools/signal_tools.gd")
const ImageTools := preload("res://addons/godot_agent/tools/image_tools.gd")
const InputTools := preload("res://addons/godot_agent/tools/input_tools.gd")


static func dispatch(parent: Node, name: String, input: Dictionary) -> Dictionary:
	# `input` is JSON-parsed; ensure it's a Dictionary.
	if typeof(input) != TYPE_DICTIONARY:
		input = {}

	match name:
		# filesystem
		"list_project_files": return ProjectTools.list_project_files(input)
		"read_file": return ProjectTools.read_file(input)
		"write_file": return ProjectTools.write_file(input)
		"create_directory": return ProjectTools.create_directory(input)
		"get_project_tree": return ProjectTools.get_project_tree(input)

		# scene
		"get_current_scene": return SceneTools.get_current_scene(input)
		"get_scene_tree": return SceneTools.get_scene_tree(input)
		"get_node": return SceneTools.get_node(input)
		"open_scene": return SceneTools.open_scene(input)
		"save_scene": return SceneTools.save_scene(input)
		"create_node": return SceneTools.create_node(input)
		"delete_node": return SceneTools.delete_node(input)
		"set_node_property": return SceneTools.set_node_property(input)
		"attach_script": return SceneTools.attach_script(input)
		"duplicate_node": return SceneTools.duplicate_node(input)
		"reparent_node": return SceneTools.reparent_node(input)
		"instantiate_scene": return SceneTools.instantiate_scene(input)

		# scripts
		"create_script": return ScriptTools.create_script(input)
		"patch_script": return ScriptTools.patch_script(input)

		# editor
		"run_project": return EditorTools.run_project(input)
		"stop_project": return EditorTools.stop_project(input)
		"screenshot_game": return EditorTools.screenshot_game(input)
		"send_input":
			var input_result: Dictionary = await InputTools.send_input(parent, input)
			return input_result
		"get_class_docs": return EditorTools.get_class_docs(input)
		"list_singletons": return EditorTools.list_singletons(input)
		"read_console_logs": return EditorTools.read_console_logs(input)
		"set_main_scene": return EditorTools.set_main_scene(input)
		"get_editor_selection": return EditorTools.get_editor_selection(input)
		"set_editor_selection": return EditorTools.set_editor_selection(input)
		"open_script": return EditorTools.open_script(input)

		# signals
		"connect_signal": return SignalTools.connect_signal(input)
		"disconnect_signal": return SignalTools.disconnect_signal(input)
		"list_signal_connections": return SignalTools.list_signal_connections(input)

		# assets — async (image gen calls a REST API)
		"generate_image":
			var result: Dictionary = await ImageTools.generate_image(parent, input)
			return result

	return {"ok": false, "error": "unknown tool: %s" % name}
