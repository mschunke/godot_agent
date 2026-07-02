@tool
extends RefCounted
class_name GodotAgentProjectTools


static func list_project_files(input: Dictionary) -> Dictionary:
	var path: String = input.get("path", "res://")
	var extensions: Array = input.get("extensions", [])
	var max_results: int = int(input.get("max_results", 500))
	if not path.begins_with("res://"):
		path = "res://" + path.lstrip("/")

	var results: Array = []
	_walk(path, extensions, results, max_results)
	return {"ok": true, "count": results.size(), "files": results}


static func _walk(dir_path: String, extensions: Array, out: Array, cap: int) -> void:
	if out.size() >= cap:
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			# skip common junk
			if name == ".godot" or name == ".import":
				name = dir.get_next()
				continue
			_walk(full, extensions, out, cap)
		else:
			if extensions.is_empty() or extensions.has(name.get_extension()):
				out.append(full)
				if out.size() >= cap:
					dir.list_dir_end()
					return
		name = dir.get_next()
	dir.list_dir_end()


static func read_file(input: Dictionary) -> Dictionary:
	var path: String = input.get("path", "")
	if path == "":
		return {"ok": false, "error": "path is required"}
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "file not found: %s" % path}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "cannot open: %s (err %d)" % [path, FileAccess.get_open_error()]}
	var content := f.get_as_text()
	f.close()
	return {"ok": true, "path": path, "content": content, "size": content.length()}


static func write_file(input: Dictionary) -> Dictionary:
	var path: String = input.get("path", "")
	var content: String = input.get("content", "")
	var create_dirs: bool = input.get("create_dirs", true)
	if path == "":
		return {"ok": false, "error": "path is required"}
	if not path.begins_with("res://") and not path.begins_with("user://"):
		return {"ok": false, "error": "path must be under res:// or user://"}

	if create_dirs:
		var dir_path := path.get_base_dir()
		if dir_path != "":
			var err := DirAccess.make_dir_recursive_absolute(dir_path)
			if err != OK and err != ERR_ALREADY_EXISTS:
				return {"ok": false, "error": "mkdir failed: %d" % err}

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "cannot open for write: %s (err %d)" % [path, FileAccess.get_open_error()]}
	f.store_string(content)
	f.close()

	# Refresh Godot's filesystem cache so newly created assets are visible.
	var fs := EditorInterface.get_resource_filesystem()
	if fs:
		fs.scan()

	return {"ok": true, "path": path, "bytes_written": content.length()}


static func create_directory(input: Dictionary) -> Dictionary:
	var path: String = input.get("path", "")
	if path == "" or not (path.begins_with("res://") or path.begins_with("user://")):
		return {"ok": false, "error": "path must be under res:// or user://"}
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return {"ok": false, "error": "mkdir failed: %d" % err}
	return {"ok": true, "path": path}


static func get_project_tree(input: Dictionary) -> Dictionary:
	# Walks Godot's EditorFileSystem index (the same tree the FileSystem dock shows),
	# not the raw folder on disk. Returns a nested {name, path, dirs, files} structure.
	var max_depth: int = int(input.get("max_depth", 8))
	var include_types: bool = bool(input.get("include_types", false))
	var subpath: String = input.get("path", "res://")
	if not subpath.begins_with("res://"):
		subpath = "res://" + subpath.lstrip("/")

	var fs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if fs == null:
		return {"ok": false, "error": "EditorFileSystem unavailable"}

	var root_dir: EditorFileSystemDirectory = fs.get_filesystem()
	if root_dir == null:
		return {"ok": false, "error": "filesystem root not indexed yet"}

	var target: EditorFileSystemDirectory = root_dir
	if subpath != "res://":
		target = fs.get_filesystem_path(subpath)
		if target == null:
			return {"ok": false, "error": "directory not found in editor filesystem: %s" % subpath}

	var tree: Dictionary = _describe_fs_dir(target, 0, max_depth, include_types)
	return {"ok": true, "tree": tree}


static func _describe_fs_dir(dir: EditorFileSystemDirectory, depth: int, max_depth: int, include_types: bool) -> Dictionary:
	var entry: Dictionary = {
		"name": dir.get_name(),
		"path": dir.get_path(),
	}
	if depth >= max_depth:
		entry["dirs_omitted"] = dir.get_subdir_count()
		entry["files_omitted"] = dir.get_file_count()
		return entry

	var dirs: Array = []
	for i in dir.get_subdir_count():
		dirs.append(_describe_fs_dir(dir.get_subdir(i), depth + 1, max_depth, include_types))
	entry["dirs"] = dirs

	var files: Array = []
	for i in dir.get_file_count():
		var f: Dictionary = {
			"name": dir.get_file(i),
			"path": dir.get_file_path(i),
		}
		if include_types:
			f["type"] = dir.get_file_type(i)
		files.append(f)
	entry["files"] = files
	return entry
