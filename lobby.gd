extends Control

@export var persona_name : Label
@export var player_name : LineEdit
@export var error_label : Label
@export var host : Button
@export var address : LineEdit
@export var lobby_container : Container
@export var steam_connect : Control
@export var steam_players : Control

@export var enet_address_entry : LineEdit
@export var enet_start_button : Button

func _ready():
	persona_name.text = Steam.getPersonaName()
	
	# Called every time the node is added to the scene.
	gamestate.connection_failed.connect(self._on_connection_failed)
	gamestate.connection_succeeded.connect(self._on_connection_success)
	gamestate.player_list_changed.connect(self.refresh_lobby)
	gamestate.game_ended.connect(self._on_game_ended)
	gamestate.game_error.connect(self._on_game_error)
	
	# Set player name to Steam username.
	player_name.text = Steam.getPersonaName()
	
	_setup_ui()

func _setup_ui():
	print("Setting up UI")
	
	#Should be customizable, ultimately
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_CLOSE)
	
	Steam.lobby_match_list.connect(
		func(lobbies : Array):
			for sample in lobbies:
				var lobby_name : String = Steam.getLobbyData(sample, "name")
				var member_count : int = Steam.getNumLobbyMembers(sample)
				
				var join_button := Button.new()
				join_button.set_text(str(lobby_name, ": ", 
					member_count, " joined"))
				join_button.set_size(Vector2(100, 5))
				
				lobby_container.add_child(join_button)
				join_button.pressed.connect(
					func():
						steam_connect.hide()
						steam_players.show()
						gamestate.join_lobby(
							sample,
							player_name.text)
				)
	)
	
	_request_lobby_list()

func _request_lobby_list():
	#Clear out lobby list
	for child in lobby_container.get_children():
		child.queue_free()
	
	Steam.requestLobbyList()

func _on_host_pressed():
	steam_connect.hide()
	steam_players.show()
	gamestate.host_lobby(player_name.text)
	#gamestate.host_game(player_name.text)
	refresh_lobby()

func _on_connection_success():
	steam_connect.hide()
	steam_players.show()


func _on_connection_failed():
	host.disabled = false
	error_label.set_text("Connection failed.")


func _on_game_ended():
	show()
	steam_connect.show()
	steam_players.hide()
	host.disabled = false


func _on_game_error(errtxt):
	$ErrorDialog.dialog_text = errtxt
	$ErrorDialog.popup_centered()
	host.disabled = false


func refresh_lobby():
	var players = gamestate.players.values()
	players.sort()
	steam_players.get_node("List").clear()
	for player_name in players:
		var this_name : String = player_name
		if player_name == gamestate.get_player_name():
			this_name += " (You)"
		steam_players.get_node("List").add_item(this_name)

	steam_players.get_node("Start").disabled = not multiplayer.is_server()
	#Ensure we have an actual lobby ID before continuing
	await Steam.lobby_joined
	steam_players.get_node("LobbyID").text = str(gamestate.lobby_id)
	
	_request_lobby_list()
	
func _on_start_pressed():
	gamestate.begin_game()

func _on_enet_host_pressed():
	print("ENet Host Pressed")
	gamestate.create_enet_host(player_name.text)
	
	#Issue: player isn't being added to `players` list
	enet_start_button.disabled = false

func _on_enet_join_pressed():
	print("ENet Join Pressed")
	gamestate.create_enet_client(
		player_name.text,
		"127.0.0.1" if enet_address_entry.text.is_empty()
		else enet_address_entry.text)
