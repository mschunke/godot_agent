extends Node

var current_score: int = 0
var high_score: int = 0

func reset_score():
	current_score = 0

func add_score(amount: int):
	current_score += amount
	if current_score > high_score:
		high_score = current_score
