extends HBoxContainer

#BUG: Identical names lead to the wrong player getting points.

var player_labels = {} # id : int to {name, label}

func _process(_delta):
	var rocks_left = $"../Rocks".get_child_count()
	if rocks_left == 0:
		var winner_name = ""
		var winner_score = 0
		for p in player_labels:
			if player_labels[p].score > winner_score:
				winner_score = player_labels[p].score
				winner_name = player_labels[p].name

		$"../Winner".set_text("THE WINNER IS:\n" + winner_name)
		$"../Winner".show()


func increase_score(for_who : int):
	assert(for_who in player_labels)
	var pl = player_labels[for_who]
	pl.score += 1
	pl.label.set_text(pl.name + "\n" + str(pl.score))


func add_player(id, new_player_name):
	var l = Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_text(new_player_name + "\n" + "0")
	l.set_h_size_flags(SIZE_EXPAND_FILL)
	var font = preload("res://montserrat.otf")
	l.set("custom_fonts/font", font)
	l.set("custom_font_size/font_size", 18)
	add_child(l)

	player_labels[id] = { name = new_player_name, label = l, score = 0 }


func _ready():
	for player in gamestate.players:
		#TODO: Does not seem to be called for client?
		add_player(player, gamestate.players[player])
	$"../Winner".hide()
	set_process(true)


func _on_exit_game_pressed():
	gamestate.end_game()
