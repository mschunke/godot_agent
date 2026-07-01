@tool
extends RefCounted
class_name GodotAgentLogger

signal log_emitted(level: String, message: String)

const LEVEL_DEBUG := "debug"
const LEVEL_INFO := "info"
const LEVEL_WARN := "warn"
const LEVEL_ERROR := "error"

var verbose: bool = false


func debug(msg: String) -> void:
	if verbose:
		_emit(LEVEL_DEBUG, msg)


func info(msg: String) -> void:
	_emit(LEVEL_INFO, msg)


func warn(msg: String) -> void:
	_emit(LEVEL_WARN, msg)


func error(msg: String) -> void:
	_emit(LEVEL_ERROR, msg)
	push_error("[godot_agent] " + msg)


func _emit(level: String, msg: String) -> void:
	print("[godot_agent][%s] %s" % [level, msg])
	log_emitted.emit(level, msg)
