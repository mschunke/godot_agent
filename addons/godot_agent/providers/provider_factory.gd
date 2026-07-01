@tool
extends RefCounted
class_name GodotAgentProviderFactory

const Anthropic := preload("res://addons/godot_agent/providers/provider_anthropic.gd")
const OpenAI := preload("res://addons/godot_agent/providers/provider_openai.gd")
const Gemini := preload("res://addons/godot_agent/providers/provider_gemini.gd")


static func create(name: String):
	match name:
		"anthropic": return Anthropic.new()
		"openai": return OpenAI.new()
		"gemini": return Gemini.new()
	push_error("[godot_agent] unknown provider: %s" % name)
	return null
