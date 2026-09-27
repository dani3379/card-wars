extends "res://scripts/scenes/GameOver.gd"
## QA-only host for the production deck-strip builder. Suppressing the inherited
## screen _ready lets the focused probe call _populate_deck_strip in isolation.


func _ready() -> void:
	pass
