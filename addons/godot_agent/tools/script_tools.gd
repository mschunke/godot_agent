@tool
extends RefCounted
class_name GodotAgentScriptTools

const ProjectTools := preload("res://addons/godot_agent/tools/project_tools.gd")


static func create_script(input: Dictionary) -> Dictionary:
	var path: String = input.get("path", "")
	var content: String = input.get("content", "")
	if not path.ends_with(".gd"):
		return {"ok": false, "error": "script path must end with .gd"}
	return ProjectTools.write_file({
		"path": path,
		"content": content,
		"create_dirs": true,
	})


static func patch_script(input: Dictionary) -> Dictionary:
	var path: String = input.get("path", "")
	var old_str: String = input.get("old_str", "")
	var new_str: String = input.get("new_str", "")
	if path == "" or old_str == "":
		return {"ok": false, "error": "path and old_str are required"}
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "file not found: %s" % path}

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "cannot read: %s" % path}
	var content := f.get_as_text()
	f.close()

	var first := content.find(old_str)
	if first == -1:
		return {"ok": false, "error": "old_str not found in file"}
	var second := content.find(old_str, first + old_str.length())
	if second != -1:
		return {"ok": false, "error": "old_str appears multiple times; add more context to make it unique"}

	var patched := content.substr(0, first) + new_str + content.substr(first + old_str.length())
	return ProjectTools.write_file({
		"path": path,
		"content": patched,
		"create_dirs": false,
	})
