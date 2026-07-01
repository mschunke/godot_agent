@tool
extends RefCounted
class_name GodotAgentConversationStore

const Conversation := preload("res://addons/godot_agent/core/conversation.gd")

const STORE_DIR := "res://addons/godot_agent/conversations/"


static func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(STORE_DIR):
		DirAccess.make_dir_recursive_absolute(STORE_DIR)


static func _path_for(id: String) -> String:
	return STORE_DIR + id + ".json"


static func save(convo: Conversation) -> Dictionary:
	if convo == null or convo.id == "":
		return {"ok": false, "error": "invalid conversation"}
	# Don't write empty (no user turn yet) conversations to avoid cluttering history.
	if convo.is_empty():
		return {"ok": true, "skipped": true}
	_ensure_dir()
	var path := _path_for(convo.id)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "cannot open %s for write" % path}
	f.store_string(JSON.stringify(convo.to_dict(), "\t"))
	f.close()
	return {"ok": true, "path": path}


static func load_by_id(id: String) -> Dictionary:
	var path := _path_for(id)
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "conversation not found: %s" % id}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "cannot read %s" % path}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "corrupt conversation file"}
	return {"ok": true, "data": parsed}


static func list_summaries() -> Array:
	# Returns [{id, title, created_at, updated_at, message_count}, ...], most recent first.
	_ensure_dir()
	var out: Array = []
	var dir := DirAccess.open(STORE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.begins_with(".") and name.ends_with(".json") and not dir.current_is_dir():
			var full := STORE_DIR + name
			var f := FileAccess.open(full, FileAccess.READ)
			if f != null:
				var text := f.get_as_text()
				f.close()
				var parsed: Variant = JSON.parse_string(text)
				if typeof(parsed) == TYPE_DICTIONARY:
					var msgs: Variant = parsed.get("messages", [])
					var count: int = msgs.size() if typeof(msgs) == TYPE_ARRAY else 0
					out.append({
						"id": String(parsed.get("id", name.get_basename())),
						"title": String(parsed.get("title", "(untitled)")),
						"created_at": int(parsed.get("created_at", 0)),
						"updated_at": int(parsed.get("updated_at", 0)),
						"message_count": count,
					})
		name = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a, b): return int(a.updated_at) > int(b.updated_at))
	return out


static func delete_by_id(id: String) -> Dictionary:
	var path := _path_for(id)
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "not found"}
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		return {"ok": false, "error": "remove failed: %d" % err}
	return {"ok": true}
