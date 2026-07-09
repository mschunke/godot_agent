@tool
extends RefCounted
class_name GodotAgentToolSchemas

# Canonical tool definitions, provider-neutral.
# Each tool: { name, description, parameters (JSON Schema draft-07 subset), destructive }
#
# Providers convert this into their native format:
#   Anthropic → { name, description, input_schema }
#   OpenAI    → { type: "function", function: { name, description, parameters } }
#   Gemini    → { functionDeclarations: [{ name, description, parameters }] }

const IMAGE_TOOL := "generate_image"


static func all() -> Array:
	return [
		# ---------- filesystem ----------
		{
			"name": "list_project_files",
			"description": "Recursively list files in the Godot project (paths are res://-relative). Optionally filter by extensions (e.g. [\"gd\", \"tscn\"]).",
			"destructive": false,
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Directory to walk. Defaults to res://.", "default": "res://"},
					"extensions": {"type": "array", "items": {"type": "string"}, "description": "Optional extension whitelist without dots."},
					"max_results": {"type": "integer", "description": "Cap on the number of returned paths.", "default": 500},
				},
			},
		},
		{
			"name": "read_file",
			"description": "Read a text file from the project (res:// path). Returns UTF-8 content.",
			"destructive": false,
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "Path like res://scripts/player.gd"},
				},
				"required": ["path"],
			},
		},
		{
			"name": "write_file",
			"description": "Create or overwrite a text file. Use for any project asset that is text (.gd, .tres, .cfg, .json, .md, .tscn).",
			"destructive": true,
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string"},
					"content": {"type": "string"},
					"create_dirs": {"type": "boolean", "default": true},
				},
				"required": ["path", "content"],
			},
		},
		{
			"name": "create_directory",
			"description": "Create a directory (and any missing parents) inside res://.",
			"destructive": false,
			"parameters": {
				"type": "object",
				"properties": {"path": {"type": "string"}},
				"required": ["path"],
			},
		},
		{
			"name": "get_project_tree",
			"description": "Return a nested tree of the project's files and folders as seen by Godot's EditorFileSystem (the same index the FileSystem dock shows). Reads the editor's live index, not disk. Prefer this over list_project_files when you want structure.",
			"destructive": false,
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "res:// subdirectory to start from. Defaults to res://.", "default": "res://"},
					"max_depth": {"type": "integer", "default": 8},
					"include_types": {"type": "boolean", "description": "Include the resource type of each file (Script, PackedScene, Texture2D, ...).", "default": false},
				},
			},
		},

		# ---------- scene inspection ----------
		{
			"name": "get_current_scene",
			"description": "Return the path and root node info of the scene currently open in the editor.",
			"destructive": false,
			"parameters": {"type": "object", "properties": {}},
		},
		{
			"name": "get_scene_tree",
			"description": "Return a hierarchical view of a scene. Uses the currently edited scene if scene_path is empty.",
			"destructive": false,
			"parameters": {
				"type": "object",
				"properties": {
					"scene_path": {"type": "string", "default": ""},
					"max_depth": {"type": "integer", "default": 6},
				},
			},
		},
		{
			"name": "get_node",
			"description": "Get properties, groups and attached script of a node in the currently edited scene, by NodePath from the root (e.g. \"Player/Sprite2D\").",
			"destructive": false,
			"parameters": {
				"type": "object",
				"properties": {"path": {"type": "string"}},
				"required": ["path"],
			},
		},

		# ---------- scene editing ----------
		{
			"name": "open_scene",
			"description": "Open a .tscn scene in the editor. Path is res://-relative.",
			"destructive": false,
			"parameters": {
				"type": "object",
				"properties": {"path": {"type": "string"}},
				"required": ["path"],
			},
		},
		{
			"name": "save_scene",
			"description": "Save the currently edited scene. Optionally save-as to a new path.",
			"destructive": true,
			"parameters": {
				"type": "object",
				"properties": {"path": {"type": "string", "default": ""}},
			},
		},
		{
			"name": "create_node",
			"description": "Create a new node under parent_path in the currently edited scene. type must be a valid Godot class (e.g. Node2D, Sprite2D, Label).",
			"destructive": true,
			"parameters": {
				"type": "object",
				"properties": {
					"parent_path": {"type": "string", "description": "NodePath from the scene root. Use \"\" or \".\" for the root itself."},
					"type": {"type": "string"},
					"name": {"type": "string"},
				},
				"required": ["type", "name"],
			},
		},
		{
			"name": "delete_node",
			"description": "Delete a node from the currently edited scene.",
			"destructive": true,
			"parameters": {
				"type": "object",
				"properties": {"path": {"type": "string"}},
				"required": ["path"],
			},
		},
		{
			"name": "set_node_property",
			"description": "Set a property on a node in the currently edited scene. Values are JSON-encoded and coerced (numbers, bools, strings, arrays, and shorthand \"Vector2(x,y)\"/\"Color(r,g,b,a)\" strings).",
			"destructive": true,
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string"},
					"property": {"type": "string"},
					"value": {"description": "Any JSON value or shorthand string."},
				},
				"required": ["path", "property", "value"],
			},
		},
		{
			"name": "attach_script",
			"description": "Attach a script (.gd) to a node in the currently edited scene.",
			"destructive": true,
			"parameters": {
				"type": "object",
				"properties": {
					"node_path": {"type": "string"},
					"script_path": {"type": "string"},
				},
				"required": ["node_path", "script_path"],
			},
		},
		{
			"name": "duplicate_node",
			"description": "Duplicate a node (with its subtree) in the currently edited scene. The clone is added under the same parent; pass `name` to override its auto-generated name. Undoable.",
			"destructive": true,
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "NodePath of the node to duplicate."},
					"name": {"type": "string", "description": "Optional new name for the duplicate."},
				},
				"required": ["path"],
			},
		},
		{
			"name": "reparent_node",
			"description": "Move a node under a new parent within the currently edited scene. keep_global_transform preserves world-space position for Node2D/Node3D. Undoable.",
			"destructive": true,
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string"},
					"new_parent_path": {"type": "string"},
					"keep_global_transform": {"type": "boolean", "default": true},
				},
				"required": ["path", "new_parent_path"],
			},
		},
		{
			"name": "instantiate_scene",
			"description": "Instantiate a .tscn scene as a child under parent_path in the currently edited scene. Use for composing scenes (e.g. spawn a Player.tscn inside Main.tscn). Undoable.",
			"destructive": true,
			"parameters": {
				"type": "object",
				"properties": {
					"scene_path": {"type": "string", "description": "res:// path to the .tscn to instantiate."},
					"parent_path": {"type": "string", "description": "NodePath of the parent inside the edited scene. Defaults to the root.", "default": ""},
					"name": {"type": "string", "description": "Optional name for the instantiated node."},
				},
				"required": ["scene_path"],
			},
		},

		# ---------- scripts ----------
		{
			"name": "create_script",
			"description": "Create or overwrite a GDScript file. Convenience wrapper around write_file with .gd validation.",
			"destructive": true,
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string"},
					"content": {"type": "string"},
				},
				"required": ["path", "content"],
			},
		},
		{
			"name": "patch_script",
			"description": "Apply a search/replace edit to a text file. old_str must appear exactly once. Use this to modify existing scripts without rewriting them.",
			"destructive": true,
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string"},
					"old_str": {"type": "string"},
					"new_str": {"type": "string"},
				},
				"required": ["path", "old_str", "new_str"],
			},
		},

		# ---------- editor ----------
		{
			"name": "run_project",
			"description": "Launch the project via the editor's play button. Use to debug behaviour changes.",
			"destructive": false,
			"parameters": {"type": "object", "properties": {}},
		},
		{
			"name": "stop_project",
			"description": "Stop the running project.",
			"destructive": false,
			"parameters": {"type": "object", "properties": {}},
		},
		{
			"name": "screenshot_game",
			"description": "Capture a PNG screenshot from the running game (or the current screen if the editor uses windowed play). Attaches the image directly to the tool result so you can see it. Saves a copy under user://godot_agent_screenshots/. Optionally provide a screen index (defaults to the primary screen).",
			"destructive": false,
			"parameters": {
				"type": "object",
				"properties": {
					"screen": {"type": "integer", "description": "Screen index to capture. -1 = primary screen.", "default": -1},
					"save_path": {"type": "string", "description": "Optional res:// or user:// path to save the PNG. Defaults to a timestamped file under user://godot_agent_screenshots/."},
				},
			},
		},
		{
			"name": "send_input",
			"description": "Synthesize keyboard/mouse input at the OS level so the running game receives it. Actions run in order. Types: 'key' (keyname like 'space', 'enter', 'a', 'left'), 'text' (types a string), 'mouse_click' (button: 'left'|'right'|'middle'; optional x/y in screen coords), 'wait_ms' (delay). Platform support: macOS (built-in osascript), Linux X11 (requires xdotool), Windows (PowerShell). Focus the game window first with `run_project` or manually.",
			"destructive": false,
			"parameters": {
				"type": "object",
				"properties": {
					"actions": {
						"type": "array",
						"description": "Ordered list of input actions to perform.",
						"items": {
							"type": "object",
							"properties": {
								"type": {"type": "string", "enum": ["key", "text", "mouse_click", "wait_ms"]},
								"key": {"type": "string", "description": "For type=key. e.g. 'space', 'enter', 'esc', 'a', 'left', 'up', 'f1'."},
								"modifiers": {"type": "array", "items": {"type": "string"}, "description": "Optional modifiers: 'shift', 'ctrl', 'alt', 'cmd'."},
								"text": {"type": "string", "description": "For type=text."},
								"button": {"type": "string", "description": "For type=mouse_click. 'left'|'right'|'middle'.", "default": "left"},
								"x": {"type": "integer", "description": "For type=mouse_click. Screen X coord. Omit to click at current cursor."},
								"y": {"type": "integer", "description": "For type=mouse_click. Screen Y coord."},
								"ms": {"type": "integer", "description": "For type=wait_ms. Milliseconds to wait.", "default": 100},
							},
							"required": ["type"],
						},
					},
				},
				"required": ["actions"],
			},
		},
		{
			"name": "get_class_docs",
			"description": "Return the list of properties, methods and signals of a Godot class via ClassDB. Use to look up any API before writing code.",
			"destructive": false,
			"parameters": {
				"type": "object",
				"properties": {"class_name": {"type": "string"}},
				"required": ["class_name"],
			},
		},
		{
			"name": "list_singletons",
			"description": "Return the names of all engine-level singletons (Engine.get_singleton_list) plus project autoloads.",
			"destructive": false,
			"parameters": {"type": "object", "properties": {}},
		},
		{
			"name": "read_console_logs",
			"description": "Read the editor's Output panel (the Godot console) live from the running editor UI. Includes engine prints, errors and stdout from the last project run. Use to inspect runtime behaviour after run_project.",
			"destructive": false,
			"parameters": {
				"type": "object",
				"properties": {
					"max_lines": {"type": "integer", "description": "Return at most this many trailing lines.", "default": 200},
				},
			},
		},
		{
			"name": "set_main_scene",
			"description": "Set the project's default (main) scene — the scene that runs when the user presses Play. Writes application/run/main_scene in ProjectSettings and saves project.godot. The scene must exist and be a .tscn or .scn.",
			"destructive": true,
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "res:// path to the scene, e.g. res://main.tscn"},
				},
				"required": ["path"],
			},
		},
		{
			"name": "get_editor_selection",
			"description": "Return what the user currently has selected: scene nodes selected in the Scene dock and file paths selected in the FileSystem dock, plus the current scene and directory. Call this before edits so you act on what the user is looking at.",
			"destructive": false,
			"parameters": {"type": "object", "properties": {}},
		},
		{
			"name": "set_editor_selection",
			"description": "Select nodes in the currently edited scene and/or a file in the FileSystem dock. Use after creating or modifying something so the user immediately sees it. node_paths clears existing selection first.",
			"destructive": false,
			"parameters": {
				"type": "object",
				"properties": {
					"node_paths": {"type": "array", "items": {"type": "string"}, "description": "NodePaths from the scene root."},
					"file_paths": {"type": "array", "items": {"type": "string"}, "description": "res:// paths to reveal in the FileSystem dock."},
				},
			},
		},
		{
			"name": "open_script",
			"description": "Open a script in the Script editor and optionally jump to a line/column. Use after create_script or patch_script so the user lands on the code you just changed.",
			"destructive": false,
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "res:// path to a .gd (or Script) file."},
					"line": {"type": "integer", "default": -1},
					"column": {"type": "integer", "default": 0},
				},
				"required": ["path"],
			},
		},

		# ---------- signals ----------
		{
			"name": "connect_signal",
			"description": "Wire a signal on source_path (a node in the currently edited scene) to `method` on target_path. Uses CONNECT_PERSIST so the wiring is saved into the .tscn, just like a connection made via the Node dock. Undoable.",
			"destructive": true,
			"parameters": {
				"type": "object",
				"properties": {
					"source_path": {"type": "string", "description": "NodePath of the node emitting the signal."},
					"signal": {"type": "string", "description": "Signal name, e.g. \"pressed\"."},
					"target_path": {"type": "string", "description": "NodePath of the node whose method will be called."},
					"method": {"type": "string", "description": "Method name on the target node."},
				},
				"required": ["source_path", "signal", "target_path", "method"],
			},
		},
		{
			"name": "disconnect_signal",
			"description": "Remove a signal connection from source_path to target_path.method in the currently edited scene. Undoable.",
			"destructive": true,
			"parameters": {
				"type": "object",
				"properties": {
					"source_path": {"type": "string"},
					"signal": {"type": "string"},
					"target_path": {"type": "string"},
					"method": {"type": "string"},
				},
				"required": ["source_path", "signal", "target_path", "method"],
			},
		},
		{
			"name": "list_signal_connections",
			"description": "List signal connections on a node: outgoing (signals this node emits, and where they are wired) and/or incoming (signals from elsewhere connected to this node's methods).",
			"destructive": false,
			"parameters": {
				"type": "object",
				"properties": {
					"path": {"type": "string"},
					"include_outgoing": {"type": "boolean", "default": true},
					"include_incoming": {"type": "boolean", "default": true},
				},
				"required": ["path"],
			},
		},

		# ---------- assets ----------
		{
			"name": IMAGE_TOOL,
			"description": "Generate an image from a text prompt and save it into the project as a PNG. Uses the configured image provider (OpenAI gpt-image / Gemini Imagen). Returns the saved res:// path.",
			"destructive": true,
			"parameters": {
				"type": "object",
				"properties": {
					"prompt": {"type": "string"},
					"path": {"type": "string", "description": "res:// path ending in .png"},
					"size": {"type": "string", "description": "e.g. \"1024x1024\"", "default": "1024x1024"},
				},
				"required": ["prompt", "path"],
			},
		},
	]


static func by_name(n: String) -> Dictionary:
	for t in all():
		if t.name == n:
			return t
	return {}


static func names() -> PackedStringArray:
	var out := PackedStringArray()
	for t in all():
		out.append(t.name)
	return out
