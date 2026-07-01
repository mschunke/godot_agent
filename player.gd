extends CharacterBody2D

var speed = 150.0
var tile_size = 32.0

var direction = Vector2.ZERO
var next_direction = Vector2.ZERO
var start_pos = Vector2.ZERO

@onready var ray = $RayCast2D

func _ready():
	start_pos = position
	ray.top_level = true # Detach so we can place it accurately
	var tex_size = $Sprite2D.texture.get_size()
	$Sprite2D.scale = Vector2(28.0 / tex_size.x, 28.0 / tex_size.y)

func reset():
	position = start_pos
	direction = Vector2.ZERO
	next_direction = Vector2.ZERO
	rotation = 0

func _process(_delta):
	if Input.is_action_pressed("ui_right"):
		next_direction = Vector2.RIGHT
	elif Input.is_action_pressed("ui_left"):
		next_direction = Vector2.LEFT
	elif Input.is_action_pressed("ui_down"):
		next_direction = Vector2.DOWN
	elif Input.is_action_pressed("ui_up"):
		next_direction = Vector2.UP

func _physics_process(delta):
	if next_direction != Vector2.ZERO and next_direction == -direction:
		direction = next_direction
	
	# Compute current tile center (assuming grid starts at 0,0 with tile size 32, centers at 16, 48, etc)
	# But in main.gd, we will position nodes at center of tiles (e.g. x*32 + 16)
	var tx = floor(position.x / tile_size)
	var ty = floor(position.y / tile_size)
	var tile_center = Vector2(tx * tile_size + tile_size/2, ty * tile_size + tile_size/2)
	
	var dist_to_center = position.distance_to(tile_center)
	var move_step = speed * delta
	
	if dist_to_center <= move_step + 1.0:
		if next_direction != Vector2.ZERO and next_direction != direction:
			if not is_wall_in_direction(next_direction, tile_center):
				position = tile_center
				direction = next_direction
		
		# Check if hitting a wall in current direction
		if direction != Vector2.ZERO and is_wall_in_direction(direction, tile_center):
			position = tile_center
			direction = Vector2.ZERO

	velocity = direction * speed
	if direction != Vector2.ZERO:
		rotation = direction.angle()
		
	move_and_slide()

func is_wall_in_direction(dir: Vector2, from_pos: Vector2) -> bool:
	ray.global_position = get_parent().to_global(from_pos)
	ray.target_position = dir * tile_size * 0.9 # Just enough to reach the next tile
	ray.force_raycast_update()
	var col = ray.get_collider()
	if col and col.is_in_group("wall"):
		return true
	return false

func die():
	var main = get_tree().get_root().get_node("Main")
	if main:
		main.game_over()
	queue_free()
