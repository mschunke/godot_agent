@tool
extends RefCounted
class_name GodotAgentSceneTools


static func get_current_scene(_input: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return {"ok": true, "scene_path": "", "root": null, "note": "no scene is currently open"}
	return {
		"ok": true,
		"scene_path": root.scene_file_path,
		"root": {
			"name": root.name,
			"type": root.get_class(),
			"child_count": root.get_child_count(),
		},
	}


static func get_scene_tree(input: Dictionary) -> Dictionary:
	var scene_path: String = input.get("scene_path", "")
	var max_depth: int = int(input.get("max_depth", 6))
	var root: Node = null
	var opened_temporary := false

	if scene_path == "":
		root = EditorInterface.get_edited_scene_root()
	else:
		if not ResourceLoader.exists(scene_path):
			return {"ok": false, "error": "scene not found: %s" % scene_path}
		var packed: PackedScene = load(scene_path)
		if packed == null:
			return {"ok": false, "error": "failed to load scene: %s" % scene_path}
		root = packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
		opened_temporary = true

	if root == null:
		return {"ok": true, "tree": null, "note": "no scene is currently open"}

	var tree := _describe(root, 0, max_depth)
	if opened_temporary:
		root.free()
	return {"ok": true, "tree": tree}


static func _describe(node: Node, depth: int, max_depth: int) -> Dictionary:
	var d := {
		"name": node.name,
		"type": node.get_class(),
	}
	var script := node.get_script()
	if script:
		d["script"] = script.resource_path
	if depth < max_depth and node.get_child_count() > 0:
		var kids: Array = []
		for c in node.get_children():
			kids.append(_describe(c, depth + 1, max_depth))
		d["children"] = kids
	elif node.get_child_count() > 0:
		d["children_omitted"] = node.get_child_count()
	return d


static func get_node(input: Dictionary) -> Dictionary:
	var path: String = input.get("path", "")
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return {"ok": false, "error": "no scene is currently open"}
	var node := _resolve(root, path)
	if node == null:
		return {"ok": false, "error": "node not found: %s" % path}

	var props: Dictionary = {}
	for p in node.get_property_list():
		var usage: int = p.get("usage", 0)
		if (usage & PROPERTY_USAGE_EDITOR) == 0:
			continue
		var pname: String = p.name
		if pname.begins_with("_"):
			continue
		var value: Variant = node.get(pname)
		# Stringify unsupported types for JSON safety.
		props[pname] = _to_serializable(value)

	var groups: Array = []
	for g in node.get_groups():
		groups.append(g)

	var script_path := ""
	var script := node.get_script()
	if script:
		script_path = script.resource_path

	return {
		"ok": true,
		"path": path,
		"name": node.name,
		"type": node.get_class(),
		"script": script_path,
		"groups": groups,
		"properties": props,
	}


static func open_scene(input: Dictionary) -> Dictionary:
	var path: String = input.get("path", "")
	if path == "":
		return {"ok": false, "error": "path is required"}
	if not ResourceLoader.exists(path):
		return {"ok": false, "error": "scene not found: %s" % path}
	EditorInterface.open_scene_from_path(path)
	return {"ok": true, "path": path}


static func save_scene(input: Dictionary) -> Dictionary:
	var path: String = input.get("path", "")
	if path == "":
		var err: int = EditorInterface.save_scene()
		if err != OK:
			return {"ok": false, "error": "save failed: %d" % err}
	else:
		# save_scene_as returns void in Godot 4.x.
		EditorInterface.save_scene_as(path)
	return {"ok": true, "path": path}


static func create_node(input: Dictionary) -> Dictionary:
	var parent_path: String = input.get("parent_path", "")
	var type_name: String = input.get("type", "")
	var node_name: String = input.get("name", "")
	if type_name == "" or node_name == "":
		return {"ok": false, "error": "type and name are required"}

	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"ok": false, "error": "no scene is currently open"}

	var parent: Node = root
	if parent_path != "" and parent_path != ".":
		parent = _resolve(root, parent_path)
		if parent == null:
			return {"ok": false, "error": "parent not found: %s" % parent_path}

	if not ClassDB.class_exists(type_name):
		return {"ok": false, "error": "unknown class: %s" % type_name}
	if not ClassDB.can_instantiate(type_name):
		return {"ok": false, "error": "class cannot be instantiated: %s" % type_name}

	var new_node: Node = ClassDB.instantiate(type_name)
	new_node.name = node_name

	var ur: EditorUndoRedoManager = _undo_redo()
	if ur == null:
		parent.add_child(new_node)
		new_node.owner = root
		return {"ok": true, "path": String(root.get_path_to(new_node))}

	ur.create_action("Create %s (%s)" % [node_name, type_name])
	ur.add_do_method(parent, "add_child", new_node)
	ur.add_do_method(new_node, "set_owner", root)
	ur.add_undo_method(parent, "remove_child", new_node)
	# Node is out of the tree on undo — keep it alive so redo can re-add it.
	ur.add_undo_reference(new_node)
	ur.commit_action()

	return {"ok": true, "path": String(root.get_path_to(new_node))}


static func delete_node(input: Dictionary) -> Dictionary:
	var path: String = input.get("path", "")
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"ok": false, "error": "no scene is currently open"}
	var node: Node = _resolve(root, path)
	if node == null:
		return {"ok": false, "error": "node not found: %s" % path}
	if node == root:
		return {"ok": false, "error": "refusing to delete the scene root"}

	var parent: Node = node.get_parent()
	var old_index: int = node.get_index()
	var old_owner: Node = node.owner

	var ur: EditorUndoRedoManager = _undo_redo()
	if ur == null:
		parent.remove_child(node)
		node.queue_free()
		return {"ok": true, "path": path}

	ur.create_action("Delete %s" % String(node.name))
	ur.add_do_method(parent, "remove_child", node)
	ur.add_undo_method(parent, "add_child", node)
	ur.add_undo_method(parent, "move_child", node, old_index)
	ur.add_undo_method(node, "set_owner", old_owner)
	# Node is out of the tree after do — keep it alive so undo can re-add it.
	ur.add_do_reference(node)
	ur.commit_action()
	return {"ok": true, "path": path}


static func set_node_property(input: Dictionary) -> Dictionary:
	var path: String = input.get("path", "")
	var property_name: String = input.get("property", "")
	var value: Variant = input.get("value")
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"ok": false, "error": "no scene is currently open"}
	var node: Node = _resolve(root, path)
	if node == null:
		return {"ok": false, "error": "node not found: %s" % path}

	var old_value: Variant = node.get(property_name)
	var coerced: Variant = _coerce_value(value, old_value)

	var ur: EditorUndoRedoManager = _undo_redo()
	if ur == null:
		node.set(property_name, coerced)
	else:
		ur.create_action("Set %s.%s" % [String(node.name), property_name])
		ur.add_do_property(node, property_name, coerced)
		ur.add_undo_property(node, property_name, old_value)
		ur.commit_action()

	return {"ok": true, "path": path, "property": property_name, "value": _to_serializable(node.get(property_name))}


static func attach_script(input: Dictionary) -> Dictionary:
	var node_path: String = input.get("node_path", "")
	var script_path: String = input.get("script_path", "")
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"ok": false, "error": "no scene is currently open"}
	var node: Node = _resolve(root, node_path)
	if node == null:
		return {"ok": false, "error": "node not found: %s" % node_path}
	if not ResourceLoader.exists(script_path):
		return {"ok": false, "error": "script not found: %s" % script_path}
	var script: Variant = load(script_path)
	if script == null:
		return {"ok": false, "error": "failed to load script"}
	var old_script: Variant = node.get_script()

	var ur: EditorUndoRedoManager = _undo_redo()
	if ur == null:
		node.set_script(script)
	else:
		ur.create_action("Attach script to %s" % String(node.name))
		ur.add_do_method(node, "set_script", script)
		ur.add_undo_method(node, "set_script", old_script)
		ur.commit_action()

	return {"ok": true, "node_path": node_path, "script_path": script_path}


static func duplicate_node(input: Dictionary) -> Dictionary:
	var path: String = input.get("path", "")
	var new_name: String = input.get("name", "")
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"ok": false, "error": "no scene is currently open"}
	var node: Node = _resolve(root, path)
	if node == null:
		return {"ok": false, "error": "node not found: %s" % path}
	if node == root:
		return {"ok": false, "error": "cannot duplicate the scene root"}

	var parent: Node = node.get_parent()
	var dup: Node = node.duplicate()
	if new_name != "":
		dup.name = new_name

	# We execute add_child + recursive-owner ourselves because Node.owner
	# requires the node to be in the tree, which makes it awkward to express
	# as a chain of add_do_method calls (owner setter for children can't run
	# before add_child). Register the reverse with UndoRedo via commit(false).
	parent.add_child(dup)
	_set_owner_recursive(dup, root)

	var ur: EditorUndoRedoManager = _undo_redo()
	if ur != null:
		ur.create_action("Duplicate %s" % String(node.name))
		ur.add_do_method(parent, "add_child", dup)
		ur.add_do_reference(dup)
		ur.add_undo_method(parent, "remove_child", dup)
		# Do-methods above will re-add dup on redo, but its children's owners
		# would be lost; keep the subtree kicking in that case too.
		ur.add_undo_reference(dup)
		ur.commit_action(false)

	return {"ok": true, "path": String(root.get_path_to(dup))}


static func reparent_node(input: Dictionary) -> Dictionary:
	var path: String = input.get("path", "")
	var new_parent_path: String = input.get("new_parent_path", "")
	var keep_global: bool = bool(input.get("keep_global_transform", true))
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"ok": false, "error": "no scene is currently open"}
	var node: Node = _resolve(root, path)
	if node == null:
		return {"ok": false, "error": "node not found: %s" % path}
	if node == root:
		return {"ok": false, "error": "cannot reparent the scene root"}
	var new_parent: Node = _resolve(root, new_parent_path)
	if new_parent == null:
		return {"ok": false, "error": "new parent not found: %s" % new_parent_path}
	if new_parent == node or _is_ancestor(node, new_parent):
		return {"ok": false, "error": "new parent cannot be the node itself or a descendant"}

	var old_parent: Node = node.get_parent()
	var old_index: int = node.get_index()

	var ur: EditorUndoRedoManager = _undo_redo()
	if ur == null:
		node.reparent(new_parent, keep_global)
		return {"ok": true, "path": String(root.get_path_to(node))}

	ur.create_action("Reparent %s" % String(node.name))
	ur.add_do_method(node, "reparent", new_parent, keep_global)
	ur.add_undo_method(node, "reparent", old_parent, keep_global)
	ur.add_undo_method(old_parent, "move_child", node, old_index)
	ur.commit_action()

	return {"ok": true, "path": String(root.get_path_to(node))}


static func instantiate_scene(input: Dictionary) -> Dictionary:
	var scene_path: String = input.get("scene_path", "")
	var parent_path: String = input.get("parent_path", "")
	var inst_name: String = input.get("name", "")
	if scene_path == "":
		return {"ok": false, "error": "scene_path is required"}
	if not ResourceLoader.exists(scene_path):
		return {"ok": false, "error": "scene not found: %s" % scene_path}
	var packed: PackedScene = load(scene_path)
	if packed == null:
		return {"ok": false, "error": "failed to load scene: %s" % scene_path}

	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"ok": false, "error": "no scene is currently open"}
	if scene_path == root.scene_file_path:
		return {"ok": false, "error": "cannot instantiate a scene into itself (would recurse)"}

	var parent: Node = root
	if parent_path != "" and parent_path != ".":
		parent = _resolve(root, parent_path)
		if parent == null:
			return {"ok": false, "error": "parent not found: %s" % parent_path}

	# GEN_EDIT_STATE_INSTANCE keeps the instance editable in the current scene.
	var inst: Node = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	if inst == null:
		return {"ok": false, "error": "failed to instantiate scene"}
	if inst_name != "":
		inst.name = inst_name

	var ur: EditorUndoRedoManager = _undo_redo()
	if ur == null:
		parent.add_child(inst)
		inst.owner = root
		return {"ok": true, "path": String(root.get_path_to(inst)), "scene_path": scene_path}

	ur.create_action("Instantiate %s" % scene_path)
	ur.add_do_method(parent, "add_child", inst)
	ur.add_do_method(inst, "set_owner", root)
	ur.add_undo_method(parent, "remove_child", inst)
	ur.add_undo_reference(inst)
	ur.commit_action()

	return {"ok": true, "path": String(root.get_path_to(inst)), "scene_path": scene_path}


# ---------- helpers ----------

static func _undo_redo() -> EditorUndoRedoManager:
	return EditorInterface.get_editor_undo_redo()


static func _is_ancestor(possible_ancestor: Node, n: Node) -> bool:
	var cur: Node = n.get_parent()
	while cur != null:
		if cur == possible_ancestor:
			return true
		cur = cur.get_parent()
	return false


static func _set_owner_recursive(n: Node, new_owner: Node) -> void:
	# Assign owner for `n` and every descendant so a duplicated subtree is
	# visible in the Scene dock and persisted on save.
	if n != new_owner:
		n.owner = new_owner
	for c in n.get_children():
		_set_owner_recursive(c, new_owner)


static func _resolve(root: Node, path: String) -> Node:
	if path == "" or path == "." or path == "/":
		return root
	if root.has_node(path):
		return root.get_node(path)
	# also try including the root's name as prefix
	if root.name == path.get_slice("/", 0) and root.has_node(path.substr(String(root.name).length() + 1)):
		return root.get_node(path.substr(String(root.name).length() + 1))
	return null


static func _to_serializable(v: Variant) -> Variant:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return v
		TYPE_VECTOR2:
			return "Vector2(%s,%s)" % [v.x, v.y]
		TYPE_VECTOR3:
			return "Vector3(%s,%s,%s)" % [v.x, v.y, v.z]
		TYPE_COLOR:
			return "Color(%s,%s,%s,%s)" % [v.r, v.g, v.b, v.a]
		TYPE_ARRAY:
			var out: Array = []
			for item in v:
				out.append(_to_serializable(item))
			return out
		TYPE_DICTIONARY:
			var od: Dictionary = {}
			for k in v.keys():
				od[str(k)] = _to_serializable(v[k])
			return od
		_:
			return str(v)


static func _coerce_value(raw: Variant, current: Variant) -> Variant:
	# If the current value is a Vector2/Vector3/Color and raw is a string shorthand, parse it.
	if typeof(raw) == TYPE_STRING:
		var s: String = raw
		if s.begins_with("Vector2("):
			var nums := _parse_nums(s)
			if nums.size() >= 2:
				return Vector2(nums[0], nums[1])
		elif s.begins_with("Vector3("):
			var nums := _parse_nums(s)
			if nums.size() >= 3:
				return Vector3(nums[0], nums[1], nums[2])
		elif s.begins_with("Color("):
			var nums := _parse_nums(s)
			if nums.size() >= 3:
				var a: float = nums[3] if nums.size() >= 4 else 1.0
				return Color(nums[0], nums[1], nums[2], a)
	# Arrays of numbers matching a Vector-typed current value.
	if typeof(raw) == TYPE_ARRAY:
		var arr: Array = raw
		if typeof(current) == TYPE_VECTOR2 and arr.size() >= 2:
			return Vector2(arr[0], arr[1])
		if typeof(current) == TYPE_VECTOR3 and arr.size() >= 3:
			return Vector3(arr[0], arr[1], arr[2])
		if typeof(current) == TYPE_COLOR and arr.size() >= 3:
			var a: float = arr[3] if arr.size() >= 4 else 1.0
			return Color(arr[0], arr[1], arr[2], a)
	return raw


static func _parse_nums(s: String) -> Array:
	var start := s.find("(")
	var end := s.rfind(")")
	if start == -1 or end == -1:
		return []
	var inner := s.substr(start + 1, end - start - 1)
	var parts := inner.split(",", false)
	var out: Array = []
	for p in parts:
		out.append(float(p.strip_edges()))
	return out
