@tool
extends RefCounted
class_name GodotAgentHttp

# Awaitable HTTP client. Creates a one-shot HTTPRequest child on the given
# parent node and frees it after the response completes.

const DEFAULT_BODY_LIMIT := 32 * 1024 * 1024  # 32 MB (image responses can be big)


static func post_json(parent: Node, url: String, headers: PackedStringArray, body: Variant, body_size_limit: int = DEFAULT_BODY_LIMIT) -> Dictionary:
	return await _request(parent, url, headers, HTTPClient.METHOD_POST, JSON.stringify(body), body_size_limit)


static func get_json(parent: Node, url: String, headers: PackedStringArray, body_size_limit: int = DEFAULT_BODY_LIMIT) -> Dictionary:
	return await _request(parent, url, headers, HTTPClient.METHOD_GET, "", body_size_limit)


static func _request(parent: Node, url: String, headers: PackedStringArray, method: int, body: String, body_size_limit: int) -> Dictionary:
	if not is_instance_valid(parent):
		return {"ok": false, "error": "invalid parent node"}
	var http := HTTPRequest.new()
	http.use_threads = true
	http.body_size_limit = body_size_limit
	http.timeout = 300.0
	parent.add_child(http)

	var err := http.request(url, headers, method, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "request start failed: %d" % err}

	var result: Array = await http.request_completed
	http.queue_free()

	# result = [result_code, response_code, headers, body_bytes]
	var http_result: int = result[0]
	var response_code: int = result[1]
	var response_headers: PackedStringArray = result[2]
	var body_bytes: PackedByteArray = result[3]

	if http_result != HTTPRequest.RESULT_SUCCESS:
		return {
			"ok": false,
			"error": "http result %d" % http_result,
			"code": response_code,
		}

	var text := body_bytes.get_string_from_utf8()
	var parsed: Variant = null
	if text.length() > 0:
		parsed = JSON.parse_string(text)

	var ok := response_code >= 200 and response_code < 300
	return {
		"ok": ok,
		"code": response_code,
		"headers": response_headers,
		"body": parsed,
		"raw": text,
	}
