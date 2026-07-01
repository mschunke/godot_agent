@tool
extends EditorScript

func _run():
	var file = FileAccess.open("user://logs/godot.log", FileAccess.READ)
	if file:
		print("LOG CONTENT:")
		var text = file.get_as_text()
		# print last 2000 chars
		if text.length() > 2000:
			print(text.substr(text.length() - 2000, 2000))
		else:
			print(text)
	else:
		print("No log file found at user://logs/godot.log")
