extends CharacterBody2D

var speed = 120.0 # Slightly slower than player
var tile_size = 32.0

var direction = Vector2.ZERO
var start_pos = Vector2.ZERO
var last_decision_tile = Vector2(-1, -1)

@onready var ray = $RayCast2D

var dirs = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]

func _ready():
	start_pos = position
	ray.top_level = true
	var tex_size = $Sprite2D.texture.get_size()
	$Sprite2D.scale = Vector2(28.0 / tex_size.x, 28.0 / tex_size.y)
	# Pick initial random direction
	direction = dirs[randi() % dirs.size()]

func _physics_process(delta):
	var tx = floor(position.x / tile_size)
	var ty = floor(position.y / tile_size)
	var tile_center = Vector2(tx * tile_size + tile_size/2, ty * tile_size + tile_size/2)
	
	var dist_to_center = position.distance_to(tile_center)
	var move_step = speed * delta
	var current_tile = Vector2(tx, ty)
	
	if dist_to_center <= move_step + 1.0 and current_tile != last_decision_tile:
		var available = []
		for d in dirs:
			if not is_wall_in_direction(d, tile_center):
				available.append(d)
		
		# print("Ghost at ", tx, ",", ty, " has available dirs: ", available)
				
		if available.size() > 0:
			# If more than 1 option, remove the reverse direction to avoid backtracking
			if available.size() > 1 and (-direction) in available:
				available.erase(-direction)
				
			# If we must change direction (hit wall) or at intersection (more than 1 option after removing reverse)
			if direction == Vector2.ZERO or is_wall_in_direction(direction, tile_center) or available.size() > 1:
				position = tile_center
				direction = available[randi() % available.size()]
				last_decision_tile = current_tile
		
		# If it's a straight line and we didn't change direction, we still want to mark the tile as visited 
		# so we don't recalculate if we are stuck or something, but wait.
		# If available.size() == 1, we just continue straight (or corner).
		# We should mark the decision tile anyway to avoid checking every frame near the center.
		last_decision_tile = current_tile

	velocity = direction * speed
	move_and_slide()

func is_wall_in_direction(dir: Vector2, from_pos: Vector2) -> bool:
	ray.global_position = get_parent().to_global(from_pos)
	ray.target_position = dir * tile_size * 0.9
	ray.force_raycast_update()
	var col = ray.get_collider()
	if col and col.is_in_group("wall"):
		return true
	return false

func _on_hitbox_body_entered(body):
	if body.is_in_group("player"):
		if body.has_method("die"):
			body.die()
