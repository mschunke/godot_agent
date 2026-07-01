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


static func _type_name(t: int) -> String:
	if t == TYPE_NIL:
		return "void"
	return type_string(t)
