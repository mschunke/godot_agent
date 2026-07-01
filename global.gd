extends Node

var current_score: int = 0
var high_score: int = 0
const SAVE_PATH = "user://highscore.save"

func _ready():
	load_score()

func reset_score():
	current_score = 0

func add_score(amount: int):
	current_score += amount
	if current_score > high_score:
		high_score = current_score
		save_score()

func save_score():
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_32(high_score)

func load_score():
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file:
			high_score = file.get_32()
