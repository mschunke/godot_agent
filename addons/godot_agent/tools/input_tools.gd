@tool
extends RefCounted
class_name GodotAgentInputTools

# OS-level input synthesis so the running game (which is a separate process
# from the editor) actually receives keystrokes/clicks.
#
# Platform matrix:
#   macOS  → osascript (System Events). Preinstalled.
#   Linux  → xdotool (X11 only). User must install.
#   Windows→ PowerShell + System.Windows.Forms.SendKeys / mouse_event.
#
# Actions:
#   {type: "key", key: "space", modifiers?: ["shift","ctrl","alt","cmd"]}
#   {type: "text", text: "hello world"}
#   {type: "mouse_click", button?: "left"|"right"|"middle", x?, y?}
#   {type: "wait_ms", ms: 500}


static func send_input(parent: Node, input: Dictionary) -> Dictionary:
	var actions_variant: Variant = input.get("actions", [])
	if typeof(actions_variant) != TYPE_ARRAY:
		return {"ok": false, "error": "actions must be an array"}
	var actions: Array = actions_variant
	if actions.is_empty():
		return {"ok": false, "error": "actions is empty"}

	var os_name: String = OS.get_name()
	var backend: String = _detect_backend(os_name)
	if backend == "":
		return {"ok": false, "error": _no_backend_error(os_name)}

	var log: Array = []
	for raw in actions:
		if typeof(raw) != TYPE_DICTIONARY:
			return {"ok": false, "error": "each action must be an object", "log": log}
		var action: Dictionary = raw
		var t: String = String(action.get("type", ""))
		var step: Dictionary = {"type": t}

		match t:
			"wait_ms":
				var ms: int = int(action.get("ms", 100))
				await _sleep(parent, ms)
				step["ms"] = ms
				step["ok"] = true
			"key":
				var res: Dictionary = _do_key(backend, action)
				step.merge(res, true)
			"text":
				var res_text: Dictionary = _do_text(backend, action)
				step.merge(res_text, true)
			"mouse_click":
				var res_click: Dictionary = _do_mouse_click(backend, action)
				step.merge(res_click, true)
			_:
				return {"ok": false, "error": "unknown action type: %s" % t, "log": log}

		log.append(step)
		if not bool(step.get("ok", false)):
			return {"ok": false, "error": String(step.get("error", "action failed")), "log": log}

	return {"ok": true, "backend": backend, "os": os_name, "log": log}


# ---------- backend selection ----------

static func _detect_backend(os_name: String) -> String:
	match os_name:
		"macOS":
			return "macos"
		"Windows":
			return "windows"
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			# xdotool is X11-only; skip on Wayland.
			var session: String = OS.get_environment("XDG_SESSION_TYPE")
			if session.to_lower() == "wayland":
				return ""
			if _has_command("xdotool"):
				return "xdotool"
			return ""
	return ""


static func _no_backend_error(os_name: String) -> String:
	match os_name:
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			var session: String = OS.get_environment("XDG_SESSION_TYPE")
			if session.to_lower() == "wayland":
				return "input synthesis is not supported on Wayland (Godot's OS.execute cannot reach into the compositor). Switch to an X11 session or run the game in a nested X server."
			return "xdotool is required on Linux for input synthesis. Install it (apt install xdotool / pacman -S xdotool) and retry."
	return "input synthesis is not supported on %s" % os_name


static func _has_command(cmd: String) -> bool:
	var out: Array = []
	var code: int = OS.execute("/bin/sh", ["-c", "command -v %s" % cmd], out, true)
	return code == 0


# ---------- per-backend implementations ----------

static func _do_key(backend: String, action: Dictionary) -> Dictionary:
	var key: String = String(action.get("key", "")).strip_edges()
	if key == "":
		return {"ok": false, "error": "key is required"}
	var modifiers_variant: Variant = action.get("modifiers", [])
	var modifiers: Array = modifiers_variant if typeof(modifiers_variant) == TYPE_ARRAY else []

	match backend:
		"macos": return _macos_key(key, modifiers)
		"xdotool": return _xdotool_key(key, modifiers)
		"windows": return _windows_key(key, modifiers)
	return {"ok": false, "error": "unsupported backend"}


static func _do_text(backend: String, action: Dictionary) -> Dictionary:
	var text: String = String(action.get("text", ""))
	if text == "":
		return {"ok": false, "error": "text is required"}
	match backend:
		"macos": return _macos_text(text)
		"xdotool": return _xdotool_text(text)
		"windows": return _windows_text(text)
	return {"ok": false, "error": "unsupported backend"}


static func _do_mouse_click(backend: String, action: Dictionary) -> Dictionary:
	var button: String = String(action.get("button", "left"))
	var has_xy: bool = action.has("x") and action.has("y")
	var x: int = int(action.get("x", 0))
	var y: int = int(action.get("y", 0))
	match backend:
		"macos": return _macos_click(button, has_xy, x, y)
		"xdotool": return _xdotool_click(button, has_xy, x, y)
		"windows": return _windows_click(button, has_xy, x, y)
	return {"ok": false, "error": "unsupported backend"}


# ---------- macOS (osascript) ----------

# Common named keys mapped to macOS virtual key codes. osascript uses `key code N`
# for special keys and `keystroke "x"` for characters. Full list at
# https://eastmanreference.com/complete-list-of-applescript-key-codes.
const _MACOS_KEY_CODES := {
	"enter": 36, "return": 36,
	"tab": 48,
	"space": 49,
	"delete": 51, "backspace": 51,
	"escape": 53, "esc": 53,
	"left": 123, "right": 124, "down": 125, "up": 126,
	"f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
	"f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
	"home": 115, "end": 119, "page_up": 116, "page_down": 121,
}


static func _macos_key(key: String, modifiers: Array) -> Dictionary:
	var lower: String = key.to_lower()
	var using: String = _macos_modifiers(modifiers)
	var script: String
	if _MACOS_KEY_CODES.has(lower):
		var code: int = int(_MACOS_KEY_CODES[lower])
		if using == "":
			script = "tell application \"System Events\" to key code %d" % code
		else:
			script = "tell application \"System Events\" to key code %d using {%s}" % [code, using]
	else:
		# Single character or literal — use keystroke.
		var esc: String = key.replace("\\", "\\\\").replace("\"", "\\\"")
		if using == "":
			script = "tell application \"System Events\" to keystroke \"%s\"" % esc
		else:
			script = "tell application \"System Events\" to keystroke \"%s\" using {%s}" % [esc, using]
	return _run_osascript(script)


static func _macos_text(text: String) -> Dictionary:
	var esc: String = text.replace("\\", "\\\\").replace("\"", "\\\"")
	var script: String = "tell application \"System Events\" to keystroke \"%s\"" % esc
	return _run_osascript(script)


static func _macos_click(button: String, has_xy: bool, x: int, y: int) -> Dictionary:
	# osascript can't synthesize mouse events without an extra tool. Prefer
	# `cliclick` if the user has it installed; otherwise fall back to a
	# JavaScript-for-Automation click at the current cursor.
	if _has_command("cliclick"):
		var b: String = "c" # left
		match button:
			"right": b = "rc"
			"middle": b = "mc"
			_: b = "c"
		var target: String = "."
		if has_xy:
			target = "%d,%d" % [x, y]
		var out: Array = []
		var code: int = OS.execute("cliclick", ["%s:%s" % [b, target]], out, true)
		if code != 0:
			return {"ok": false, "error": "cliclick failed: %s" % _join(out)}
		return {"ok": true, "backend_tool": "cliclick"}
	# No cliclick — try AppleScript "click at" (only works for left click at a point).
	if button != "left" or not has_xy:
		return {"ok": false, "error": "mouse_click on macOS needs `cliclick` (brew install cliclick) for right/middle or clicks at the current cursor"}
	var script: String = "tell application \"System Events\" to click at {%d, %d}" % [x, y]
	return _run_osascript(script)


static func _macos_modifiers(modifiers: Array) -> String:
	var parts: Array = []
	for m in modifiers:
		match String(m).to_lower():
			"shift": parts.append("shift down")
			"ctrl", "control": parts.append("control down")
			"alt", "option": parts.append("option down")
			"cmd", "command", "meta", "super": parts.append("command down")
	return ", ".join(parts)


static func _run_osascript(script: String) -> Dictionary:
	var out: Array = []
	var code: int = OS.execute("/usr/bin/osascript", ["-e", script], out, true)
	if code != 0:
		return {"ok": false, "error": "osascript failed (code %d): %s" % [code, _join(out)]}
	return {"ok": true}


# ---------- Linux (xdotool) ----------

static func _xdotool_key(key: String, modifiers: Array) -> Dictionary:
	var lower: String = key.to_lower()
	# xdotool uses X keysym names: space, Return, Escape, Left, Up, F1, a, ...
	var mapped: String = _xdotool_keysym(lower)
	var combo: PackedStringArray = PackedStringArray()
	for m in modifiers:
		var mod_name: String = _xdotool_modifier(String(m).to_lower())
		if mod_name != "":
			combo.append(mod_name)
	combo.append(mapped)
	var arg: String = "+".join(combo)
	var out: Array = []
	var code: int = OS.execute("xdotool", ["key", "--clearmodifiers", arg], out, true)
	if code != 0:
		return {"ok": false, "error": "xdotool key failed: %s" % _join(out)}
	return {"ok": true}


static func _xdotool_text(text: String) -> Dictionary:
	var out: Array = []
	var code: int = OS.execute("xdotool", ["type", "--clearmodifiers", "--", text], out, true)
	if code != 0:
		return {"ok": false, "error": "xdotool type failed: %s" % _join(out)}
	return {"ok": true}


static func _xdotool_click(button: String, has_xy: bool, x: int, y: int) -> Dictionary:
	if has_xy:
		var mv_out: Array = []
		OS.execute("xdotool", ["mousemove", str(x), str(y)], mv_out, true)
	var b: String = "1" # left
	match button:
		"right": b = "3"
		"middle": b = "2"
	var out: Array = []
	var code: int = OS.execute("xdotool", ["click", b], out, true)
	if code != 0:
		return {"ok": false, "error": "xdotool click failed: %s" % _join(out)}
	return {"ok": true}


static func _xdotool_keysym(k: String) -> String:
	match k:
		"enter", "return": return "Return"
		"tab": return "Tab"
		"space": return "space"
		"delete", "backspace": return "BackSpace"
		"escape", "esc": return "Escape"
		"left": return "Left"
		"right": return "Right"
		"up": return "Up"
		"down": return "Down"
		"home": return "Home"
		"end": return "End"
		"page_up": return "Prior"
		"page_down": return "Next"
	# f1..f12 stay as F1..F12
	if k.begins_with("f") and k.length() <= 3 and k.substr(1).is_valid_int():
		return "F" + k.substr(1)
	return k


static func _xdotool_modifier(m: String) -> String:
	match m:
		"shift": return "shift"
		"ctrl", "control": return "ctrl"
		"alt", "option": return "alt"
		"cmd", "command", "meta", "super": return "super"
	return ""


# ---------- Windows (PowerShell) ----------

static func _windows_key(key: String, modifiers: Array) -> Dictionary:
	var seq: String = ""
	for m in modifiers:
		match String(m).to_lower():
			"shift": seq += "+"
			"ctrl", "control": seq += "^"
			"alt", "option": seq += "%"
			# SendKeys has no cmd/meta on Windows; skip.
	seq += _windows_sendkeys_token(key)
	return _run_sendkeys(seq)


static func _windows_text(text: String) -> Dictionary:
	# Escape SendKeys metacharacters.
	var escaped: String = ""
	for c in text:
		if "+^%~(){}[]".contains(c):
			escaped += "{%s}" % c
		else:
			escaped += c
	return _run_sendkeys(escaped)


static func _windows_click(button: String, has_xy: bool, x: int, y: int) -> Dictionary:
	# Use mouse_event via P/Invoke through PowerShell.
	var down_flag: String = "2"
	var up_flag: String = "4"
	match button:
		"right":
			down_flag = "8"
			up_flag = "10"
		"middle":
			down_flag = "32"
			up_flag = "64"
	var move: String = ""
	if has_xy:
		move = "[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(%d, %d); " % [x, y]
	var script: String = (
		"Add-Type -AssemblyName System.Windows.Forms; " +
		"Add-Type -AssemblyName System.Drawing; " +
		"Add-Type -MemberDefinition '[DllImport(\"user32.dll\")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, int dwExtraInfo);' -Name U -Namespace W; " +
		move +
		"[W.U]::mouse_event(%s,0,0,0,0); Start-Sleep -Milliseconds 30; [W.U]::mouse_event(%s,0,0,0,0);" % [down_flag, up_flag]
	)
	var out: Array = []
	var code: int = OS.execute("powershell", ["-NoProfile", "-Command", script], out, true)
	if code != 0:
		return {"ok": false, "error": "powershell mouse_event failed: %s" % _join(out)}
	return {"ok": true}


static func _windows_sendkeys_token(key: String) -> String:
	var lower: String = key.to_lower()
	match lower:
		"enter", "return": return "{ENTER}"
		"tab": return "{TAB}"
		"space": return " "
		"delete": return "{DELETE}"
		"backspace": return "{BACKSPACE}"
		"escape", "esc": return "{ESC}"
		"left": return "{LEFT}"
		"right": return "{RIGHT}"
		"up": return "{UP}"
		"down": return "{DOWN}"
		"home": return "{HOME}"
		"end": return "{END}"
		"page_up": return "{PGUP}"
		"page_down": return "{PGDN}"
	if lower.begins_with("f") and lower.length() <= 3 and lower.substr(1).is_valid_int():
		return "{%s}" % lower.to_upper()
	# Single character — escape SendKeys metacharacters.
	if "+^%~(){}[]".contains(key):
		return "{%s}" % key
	return key


static func _run_sendkeys(seq: String) -> Dictionary:
	var script: String = (
		"Add-Type -AssemblyName System.Windows.Forms; " +
		"[System.Windows.Forms.SendKeys]::SendWait('%s')" % seq.replace("'", "''")
	)
	var out: Array = []
	var code: int = OS.execute("powershell", ["-NoProfile", "-Command", script], out, true)
	if code != 0:
		return {"ok": false, "error": "SendKeys failed: %s" % _join(out)}
	return {"ok": true}


# ---------- helpers ----------

static func _sleep(parent: Node, ms: int) -> void:
	if parent == null:
		# Fallback: block briefly. Rare; the agent always passes a parent.
		OS.delay_msec(max(0, ms))
		return
	var tree: SceneTree = parent.get_tree()
	if tree == null:
		OS.delay_msec(max(0, ms))
		return
	var timer: SceneTreeTimer = tree.create_timer(float(ms) / 1000.0)
	await timer.timeout


static func _join(out: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for line in out:
		parts.append(String(line))
	return "\n".join(parts).strip_edges()
