@tool
extends RefCounted
class_name GodotAgentImageTools

const Settings := preload("res://addons/godot_agent/core/settings.gd")
const Http := preload("res://addons/godot_agent/core/http_client.gd")


static func generate_image(parent: Node, input: Dictionary) -> Dictionary:
	var prompt: String = input.get("prompt", "")
	var path: String = input.get("path", "")
	var size: String = input.get("size", "1024x1024")
	if prompt == "" or path == "":
		return {"ok": false, "error": "prompt and path are required"}
	if not path.begins_with("res://") or not path.ends_with(".png"):
		return {"ok": false, "error": "path must be a res:// path ending in .png"}

	var provider := Settings.resolve_image_provider()
	if provider == "":
		return {"ok": false, "error": "no image-capable provider has an API key configured"}

	var bytes: PackedByteArray
	match provider:
		"openai":
			bytes = await _gen_openai(parent, prompt, size)
		"gemini":
			bytes = await _gen_gemini(parent, prompt)
		_:
			return {"ok": false, "error": "provider %s does not support image generation" % provider}

	if bytes.is_empty():
		return {"ok": false, "error": "image generation returned no bytes"}

	var dir_path := path.get_base_dir()
	if dir_path != "":
		DirAccess.make_dir_recursive_absolute(dir_path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "cannot open %s for write" % path}
	f.store_buffer(bytes)
	f.close()

	var fs := EditorInterface.get_resource_filesystem()
	if fs:
		fs.scan()

	return {"ok": true, "path": path, "bytes": bytes.size(), "provider": provider}


static func _gen_openai(parent: Node, prompt: String, size: String) -> PackedByteArray:
	var key := Settings.api_key("openai")
	if key == "":
		return PackedByteArray()
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + key,
	])
	var body := {
		"model": Settings.image_model_for("openai"),
		"prompt": prompt,
		"size": size,
		"n": 1,
	}
	var resp: Dictionary = await Http.post_json(parent, "https://api.openai.com/v1/images/generations", headers, body)
	if not resp.get("ok", false):
		push_error("[godot_agent] openai image failed: " + str(resp))
		return PackedByteArray()
	var data: Variant = resp.get("body", {})
	if typeof(data) != TYPE_DICTIONARY:
		return PackedByteArray()
	var items: Array = data.get("data", [])
	if items.is_empty():
		return PackedByteArray()
	var first: Dictionary = items[0]
	var b64: String = first.get("b64_json", "")
	if b64 == "":
		return PackedByteArray()
	return Marshalls.base64_to_raw(b64)


static func _gen_gemini(parent: Node, prompt: String) -> PackedByteArray:
	var key := Settings.api_key("gemini")
	if key == "":
		return PackedByteArray()
	# User-configured Imagen model (default: imagen-4.0-generate-001). Older
	# models like imagen-3.0-generate-002 were retired and now return 404.
	var model := Settings.image_model_for("gemini")
	var url := "https://generativelanguage.googleapis.com/v1beta/models/%s:predict?key=%s" % [model, key]
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := {
		"instances": [{"prompt": prompt}],
		"parameters": {"sampleCount": 1},
	}
	var resp: Dictionary = await Http.post_json(parent, url, headers, body)
	if not resp.get("ok", false):
		push_error("[godot_agent] gemini image failed: " + str(resp))
		return PackedByteArray()
	var data: Variant = resp.get("body", {})
	if typeof(data) != TYPE_DICTIONARY:
		return PackedByteArray()
	var predictions: Array = data.get("predictions", [])
	if predictions.is_empty():
		return PackedByteArray()
	var first: Dictionary = predictions[0]
	var b64: String = first.get("bytesBase64Encoded", "")
	if b64 == "":
		return PackedByteArray()
	return Marshalls.base64_to_raw(b64)
