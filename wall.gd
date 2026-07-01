extends StaticBody2D

func _ready():
	var tex_size = $Sprite2D.texture.get_size()
	$Sprite2D.scale = Vector2(32.0 / tex_size.x, 32.0 / tex_size.y)
