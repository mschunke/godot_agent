@tool
extends SceneTree

func _init():
	var path = OS.get_user_data_dir() + "/logs/godot.log"
	var f = FileAccess.open(path, FileAccess.READ)
	if f:
		var content = f.get_as_text()
		# We want the last 2000 characters
		if content.length() > 2000:
			print("LOG: ", content.substr(content.length() - 2000, 2000))
		else:
			print("LOG: ", content)
	else:
		print("No log found at " + path)
	quit()
