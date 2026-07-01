extends Area2D

func _ready():
	var tex_size = $Sprite2D.texture.get_size()
	# Make it bigger than normal dots
	$Sprite2D.scale = Vector2(24.0 / tex_size.x, 24.0 / tex_size.y)

func _on_body_entered(body):
	if body.is_in_group("player"):
		var main = get_tree().get_root().get_node("Main")
		if main:
			main.add_score(50)
			if main.has_method("dot_eaten"):
				main.dot_eaten()
			main.activate_power_mode()
		queue_free()
