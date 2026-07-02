@tool
extends RefCounted
class_name GodotAgentEditorTools


static func run_project(_input: Dictionary) -> Dictionary:
	EditorInterface.play_main_scene()
	return {"ok": true}


static func stop_project(_input: Dictionary) -> Dictionary:
	EditorInterface.stop_playing_scene()
	return {"ok": true}


static func get_class_docs(input: Dictionary) -> Dictionary:
	# The parameter is named `class_name` in the schema but that's reserved in GDScript,
	# so we read it by key.
	var cls: String = input.get("class_name", "")
	if cls == "" or not ClassDB.class_exists(cls):
		return {"ok": false, "error": "unknown class: %s" % cls}

	var parent := ClassDB.get_parent_class(cls)
	# Second arg is `no_inheritance`. We want inherited members included, so pass false.
	var props: Array = []
	for p in ClassDB.class_get_property_list(cls, false):
		props.append({
			"name": p.name,
			"type": _type_name(p.get("type", TYPE_NIL)),
		})
	var methods: Array = []
	for m in ClassDB.class_get_method_list(cls, false):
		var args: Array = []
		for a in m.get("args", []):
			args.append({"name": a.name, "type": _type_name(a.get("type", TYPE_NIL))})
		methods.append({
			"name": m.name,
			"return_type": _type_name(m.get("return", {}).get("type", TYPE_NIL)),
			"args": args,
		})
	var signals: Array = []
	for s in ClassDB.class_get_signal_list(cls, false):
		signals.append(s.name)

	return {
		"ok": true,
		"class": cls,
		"parent": parent,
		"can_instantiate": ClassDB.can_instantiate(cls),
		"properties": props,
		"methods": methods,
		"signals": signals,
	}


static func list_singletons(_input: Dictionary) -> Dictionary:
	var engine_singletons: Array = []
	for s in Engine.get_singleton_list():
		engine_singletons.append(s)

	var autoloads: Array = []
	var cfg := ConfigFile.new()
	var err := cfg.load("res://project.godot")
	if err == OK and cfg.has_section("autoload"):
		for k in cfg.get_section_keys("autoload"):
			autoloads.append({"name": k, "path": cfg.get_value("autoload", k)})

	return {
		"ok": true,
		"engine_singletons": engine_singletons,
		"autoloads": autoloads,
	}


static func read_console_logs(input: Dictionary) -> Dictionary:
	# Reads the editor's Output panel (EditorLog) directly from the running editor UI,
	# not from a file on disk. The EditorLog is an internal Godot node reachable
	# through the base control tree; its content lives in a RichTextLabel child.
	var max_lines: int = int(input.get("max_lines", 200))
	var base: Control = EditorInterface.get_base_control()
	if base == null:
		return {"ok": false, "error": "editor base control unavailable"}

	var log_node: Node = _find_by_class(base, "EditorLog")
	if log_node == null:
		return {"ok": false, "error": "EditorLog node not found in editor tree"}

	var rt: RichTextLabel = _find_first_rich_text(log_node)
	if rt == null:
		return {"ok": false, "error": "RichTextLabel inside EditorLog not found"}

	var text: String = rt.get_parsed_text()
	var all_lines: PackedStringArray = text.split("\n")
	var total: int = all_lines.size()
	var start: int = max(0, total - max_lines)
	var slice: PackedStringArray = PackedStringArray()
	for i in range(start, total):
		slice.append(all_lines[i])

	return {
		"ok": true,
		"log": "\n".join(slice),
		"line_count": slice.size(),
		"total_lines": total,
		"truncated": start > 0,
	}


static func set_main_scene(input: Dictionary) -> Dictionary:
	# Sets the project's default (main) scene through ProjectSettings, the same
	# setting the editor writes when you use "Set as Main Scene" in the FileSystem dock.
	var path: String = input.get("path", "")
	if path == "":
		return {"ok": false, "error": "path is required"}
	if not path.begins_with("res://"):
		path = "res://" + path.lstrip("/")
	if not path.ends_with(".tscn") and not path.ends_with(".scn"):
		return {"ok": false, "error": "main scene must be a .tscn or .scn file"}
	if not ResourceLoader.exists(path):
		return {"ok": false, "error": "scene not found: %s" % path}

	var previous: String = String(ProjectSettings.get_setting("application/run/main_scene", ""))
	ProjectSettings.set_setting("application/run/main_scene", path)
	var err: int = ProjectSettings.save()
	if err != OK:
		return {"ok": false, "error": "ProjectSettings.save failed: %d" % err}

	return {
		"ok": true,
		"main_scene": path,
		"previous_main_scene": previous,
	}


static func _find_by_class(node: Node, cls: String) -> Node:
	if node.get_class() == cls:
		return node
	for c in node.get_children():
		var found: Node = _find_by_class(c, cls)
		if found != null:
			return found
	return null


static func _find_first_rich_text(node: Node) -> RichTextLabel:
	if node is RichTextLabel:
		return node
	for c in node.get_children():
		var found: RichTextLabel = _find_first_rich_text(c)
		if found != null:
			return found
	return null


static func _type_name(t: int) -> String:
	if t == TYPE_NIL:
		return "void"
	return type_string(t)
