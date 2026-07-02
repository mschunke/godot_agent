@tool
extends RefCounted
class_name GodotAgentSignalTools

# Node signal wiring in the currently edited scene. Connections are made with
# CONNECT_PERSIST so they are saved into the .tscn on save, matching what the
# Node dock's Signals panel does when the user wires a signal in the editor.


static func connect_signal(input: Dictionary) -> Dictionary:
	var source_path: String = input.get("source_path", "")
	var signal_name: String = input.get("signal", "")
	var target_path: String = input.get("target_path", "")
	var method: String = input.get("method", "")
	if source_path == "" or signal_name == "" or target_path == "" or method == "":
		return {"ok": false, "error": "source_path, signal, target_path and method are required"}

	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"ok": false, "error": "no scene is currently open"}
	var source: Node = _resolve(root, source_path)
	if source == null:
		return {"ok": false, "error": "source node not found: %s" % source_path}
	var target: Node = _resolve(root, target_path)
	if target == null:
		return {"ok": false, "error": "target node not found: %s" % target_path}
	if not source.has_signal(signal_name):
		return {"ok": false, "error": "signal not found on source: %s" % signal_name}
	if not target.has_method(method):
		return {"ok": false, "error": "target has no method: %s" % method}

	var callable: Callable = Callable(target, method)
	if source.is_connected(signal_name, callable):
		return {"ok": false, "error": "already connected"}

	var flags: int = Object.CONNECT_PERSIST

	var ur: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
	if ur == null:
		var err: int = source.connect(signal_name, callable, flags)
		if err != OK:
			return {"ok": false, "error": "connect failed: %d" % err}
	else:
		ur.create_action("Connect %s.%s -> %s.%s" % [String(source.name), signal_name, String(target.name), method])
		ur.add_do_method(source, "connect", signal_name, callable, flags)
		ur.add_undo_method(source, "disconnect", signal_name, callable)
		ur.commit_action()

	return {
		"ok": true,
		"source_path": source_path,
		"signal": signal_name,
		"target_path": target_path,
		"method": method,
	}


static func disconnect_signal(input: Dictionary) -> Dictionary:
	var source_path: String = input.get("source_path", "")
	var signal_name: String = input.get("signal", "")
	var target_path: String = input.get("target_path", "")
	var method: String = input.get("method", "")
	if source_path == "" or signal_name == "" or target_path == "" or method == "":
		return {"ok": false, "error": "source_path, signal, target_path and method are required"}

	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"ok": false, "error": "no scene is currently open"}
	var source: Node = _resolve(root, source_path)
	if source == null:
		return {"ok": false, "error": "source node not found: %s" % source_path}
	var target: Node = _resolve(root, target_path)
	if target == null:
		return {"ok": false, "error": "target node not found: %s" % target_path}

	var callable: Callable = Callable(target, method)
	if not source.is_connected(signal_name, callable):
		return {"ok": false, "error": "not connected"}

	# Re-derive the persist flag from the live connection so undo restores it faithfully.
	var flags: int = Object.CONNECT_PERSIST
	for c in source.get_signal_connection_list(signal_name):
		var cc: Callable = c.get("callable")
		if cc == callable:
			flags = int(c.get("flags", flags))
			break

	var ur: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
	if ur == null:
		source.disconnect(signal_name, callable)
	else:
		ur.create_action("Disconnect %s.%s -> %s.%s" % [String(source.name), signal_name, String(target.name), method])
		ur.add_do_method(source, "disconnect", signal_name, callable)
		ur.add_undo_method(source, "connect", signal_name, callable, flags)
		ur.commit_action()

	return {
		"ok": true,
		"source_path": source_path,
		"signal": signal_name,
		"target_path": target_path,
		"method": method,
	}


static func list_signal_connections(input: Dictionary) -> Dictionary:
	var path: String = input.get("path", "")
	var include_incoming: bool = bool(input.get("include_incoming", true))
	var include_outgoing: bool = bool(input.get("include_outgoing", true))
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"ok": false, "error": "no scene is currently open"}
	var node: Node = _resolve(root, path)
	if node == null:
		return {"ok": false, "error": "node not found: %s" % path}

	var outgoing: Array = []
	if include_outgoing:
		for sig in node.get_signal_list():
			var sname: String = sig.name
			for c in node.get_signal_connection_list(sname):
				var callable: Callable = c.get("callable")
				var obj: Object = callable.get_object()
				var target_path: String = ""
				if obj is Node and (obj as Node).is_inside_tree():
					target_path = String(root.get_path_to(obj))
				outgoing.append({
					"signal": sname,
					"target_path": target_path,
					"target_type": obj.get_class() if obj != null else "",
					"method": String(callable.get_method()),
					"flags": int(c.get("flags", 0)),
				})

	var incoming: Array = []
	if include_incoming:
		for c in node.get_incoming_connections():
			var sig_variant: Signal = c.get("signal")
			var callable_in: Callable = c.get("callable")
			var src: Object = sig_variant.get_object()
			var src_path: String = ""
			if src is Node and (src as Node).is_inside_tree():
				src_path = String(root.get_path_to(src))
			incoming.append({
				"signal": String(sig_variant.get_name()),
				"source_path": src_path,
				"source_type": src.get_class() if src != null else "",
				"method": String(callable_in.get_method()),
				"flags": int(c.get("flags", 0)),
			})

	return {
		"ok": true,
		"path": path,
		"outgoing": outgoing,
		"incoming": incoming,
	}


static func _resolve(root: Node, path: String) -> Node:
	if path == "" or path == "." or path == "/":
		return root
	if root.has_node(path):
		return root.get_node(path)
	if root.name == path.get_slice("/", 0) and root.has_node(path.substr(String(root.name).length() + 1)):
		return root.get_node(path.substr(String(root.name).length() + 1))
	return null
