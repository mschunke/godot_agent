extends Area2D

func _ready():
	var tex_size = $Sprite2D.texture.get_size()
	$Sprite2D.scale = Vector2(12.0 / tex_size.x, 12.0 / tex_size.y)

func _on_body_entered(body):
	if body.is_in_group("player"):
		# Increase score
		var main = get_tree().get_root().get_node("Main")
		if main:
			main.add_score(10)
		queue_free()
