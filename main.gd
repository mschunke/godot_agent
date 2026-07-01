extends Node2D

const MAP = [
	"1111111111111111111",
	"1322222221222222231",
	"1211121111111211121",
	"1222222222222222221",
	"1211121211121211121",
	"1222221221221222221",
	"1111121111111211111",
	"1111121111111211111",
	"1111121011101211111",
	"11111200GGG00211111",
	"1111121011101211111",
	"1111121111111211111",
	"1111121211121211111",
	"1222222221222222221",
	"1211121111111211121",
	"122212222P222212221",
	"1112121111111212111",
	"1322222222222222231",
	"1111111111111111111"
]

var tile_size = 32.0

var total_dots = 0

@onready var world = $World
@onready var score_label = $UI/ScoreLabel
@onready var high_score_label = $UI/HighScoreLabel
@onready var game_over_label = $UI/GameOverLabel
@onready var win_label = $UI/WinLabel
@onready var start_label = $UI/StartLabel

var WallScene = preload("res://wall.tscn")
var DotScene = preload("res://dot.tscn")
var FruitScene = preload("res://fruit.tscn")
var PlayerScene = preload("res://player.tscn")
var GhostScene = preload("res://ghost.tscn")

var power_mode_active = false
var power_mode_timer = 0.0

func _ready():
	Global.reset_score()
	score_label.text = "Score: " + str(Global.current_score)
	high_score_label.text = "High Score: " + str(Global.high_score)
	process_mode = Node.PROCESS_MODE_ALWAYS
	$World.process_mode = Node.PROCESS_MODE_PAUSABLE
	randomize()
	build_level()
	get_tree().paused = true
	start_label.visible = true

func build_level():
	# Center the level slightly
	# 19 tiles wide, 19 tiles high
	# 19 * 32 = 608
	# Screen is typically 1152 x 648
	var map_width_px = 19 * tile_size
	var map_height_px = 19 * tile_size
	
	world.position = Vector2(
		(get_viewport_rect().size.x - map_width_px) / 2,
		(get_viewport_rect().size.y - map_height_px) / 2
	)
	
	for y in range(MAP.size()):
		var row = MAP[y]
		for x in range(row.length()):
			var char = row[x]
			var pos = Vector2(x * tile_size + tile_size/2, y * tile_size + tile_size/2)
			
			if char == "1":
				var wall = WallScene.instantiate()
				wall.position = pos
				world.add_child(wall)
			elif char == "2":
				var dot = DotScene.instantiate()
				dot.position = pos
				world.add_child(dot)
				total_dots += 1
			elif char == "3":
				var fruit = FruitScene.instantiate()
				fruit.position = pos
				world.add_child(fruit)
				total_dots += 1
			elif char == "P":
				var player = PlayerScene.instantiate()
				player.position = pos
				world.add_child(player)
			elif char == "G":
				var ghost = GhostScene.instantiate()
				ghost.position = pos
				world.add_child(ghost)

func add_score(pts: int):
	Global.add_score(pts)
	score_label.text = "Score: " + str(Global.current_score)
	high_score_label.text = "High Score: " + str(Global.high_score)

func dot_eaten():
	total_dots -= 1
	if total_dots <= 0:
		win_game()

func game_over():
	game_over_label.visible = true
	get_tree().paused = true

func win_game():
	win_label.visible = true
	get_tree().paused = true

func activate_power_mode():
	power_mode_active = true
	power_mode_timer = 10.0
	for ghost in get_tree().get_nodes_in_group("ghost"):
		if ghost.has_method("set_vulnerable"):
			ghost.set_vulnerable(true)

func deactivate_power_mode():
	power_mode_active = false
	for ghost in get_tree().get_nodes_in_group("ghost"):
		if ghost.has_method("set_vulnerable"):
			ghost.set_vulnerable(false)


func _process(delta):
	if power_mode_active and not get_tree().paused:
		power_mode_timer -= delta
		if power_mode_timer <= 0:
			deactivate_power_mode()

	if Input.is_action_just_pressed("ui_accept"):
		if start_label.visible:
			start_label.visible = false
			get_tree().paused = false
		elif game_over_label.visible or win_label.visible:
			get_tree().paused = false
			get_tree().reload_current_scene()
			
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().quit()
