extends Node

# Default game server port. Can be any number between 1024 and 49151.
# Not on the list of registered or common ports as of November 2020:
# https://en.wikipedia.org/wiki/List_of_TCP_and_UDP_port_numbers
const DEFAULT_PORT = 10567

# Max number of players.
const MAX_PEERS = 12

var peer : MultiplayerPeer = null

# Name for my player.
var player_name : String

# Names for remote players in id:name format.
var players := {}

var players_ready := []

var lobby_id := -1

# Signals to let lobby GUI know what's going on.
signal player_list_changed()
signal connection_failed()
signal connection_succeeded()
signal game_ended()
signal game_error(what : String)

func _ready():
	Steam.steamInitEx(true, 480)
	#peer = SteamMultiplayerPeer.new()
	
	# Keep connections defined locally, if they aren't likely to be used
	# anywhere else, such as with a lambda function for readability.
	
	multiplayer.peer_connected.connect(
		func(id : int):
			print("Peer connected")
			# Tell the connected peer that we have also joined
			
			#TODO: This should come from the text field
			if player_name == null or player_name == "":
				player_name = "Empty String " + str(randi())
			register_player.rpc_id(id, player_name)
	)
	multiplayer.peer_disconnected.connect(
		func(id : int):
			if is_game_in_progress():
				if multiplayer.is_server():
					game_error.emit("Player " + players[id] + " disconnected")
					end_game()
			else:
				# Unregister this player. This doesn't need to be called when the
				# server quits, because the whole player list is cleared anyway!
				unregister_player(id)
	)
	multiplayer.connected_to_server.connect(
		func():
			connection_succeeded.emit()	
	)
	multiplayer.connection_failed.connect(
		func():
			multiplayer.multiplayer_peer = null
			connection_failed.emit()
	)
	multiplayer.server_disconnected.connect(
		func():
			game_error.emit("Server disconnected")
			end_game()
	)
	
	Steam.lobby_joined.connect(
		func (new_lobby_id: int, _permissions: int, _locked: bool, response: int):
		if response == 1:
			lobby_id = new_lobby_id
			var id = Steam.getLobbyOwner(new_lobby_id)
			if id != Steam.getSteamID():
				connect_socket(id)
				register_player.rpc(player_name)
				players[multiplayer.get_unique_id()] = player_name
				print("Multiplayer ID in lobby_joined: ", multiplayer.get_unique_id())
		else:
			# Get the failure reason
			var FAIL_REASON: String
			match response:
				2:  FAIL_REASON = "This lobby no longer exists."
				3:  FAIL_REASON = "You don't have permission to join this lobby."
				4:  FAIL_REASON = "The lobby is now full."
				5:  FAIL_REASON = "Uh... something unexpected happened!"
				6:  FAIL_REASON = "You are banned from this lobby."
				7:  FAIL_REASON = "You cannot join due to having a limited account."
				8:  FAIL_REASON = "This lobby is locked or disabled."
				9:  FAIL_REASON = "This lobby is community locked."
				10: FAIL_REASON = "A user in the lobby has blocked you from joining."
				11: FAIL_REASON = "A user you have blocked is in the lobby."
			print(FAIL_REASON)
	)
	Steam.lobby_created.connect(
		func(status: int, new_lobby_id: int):
			if status == 1:
				#lobby_id = new_lobby_id
				Steam.setLobbyData(new_lobby_id, "name", 
					str(Steam.getPersonaName(), "'s Spectabulous Test Server"))
				create_socket()
				print("Create lobby id:",str(lobby_id))
			else:
				print("Error on create lobby!")
	)

func _process(_delta : float):
	Steam.run_callbacks()

func is_game_in_progress() -> bool:
	return has_node("/root/World")

# Lobby management functions.
@rpc("call_local", "any_peer")
func register_player(new_player_name : String):
	print("registering player : {", multiplayer.get_remote_sender_id(),
		", ", new_player_name, "}")
	var id = multiplayer.get_remote_sender_id()
	players[id] = _make_string_unique(new_player_name)
	player_list_changed.emit()


func unregister_player(id):
	players.erase(id)
	player_list_changed.emit()
	

#@rpc("call_local", "any_peer")
#func add_player(id : int, player_name : String):
	#players[id] = player_name
	##$"/root/World/Score".add_player(id, player_name)

@rpc("call_local")
func load_world():
	# Change scene.
	var world = load("res://world.tscn").instantiate()
	get_tree().get_root().add_child(world)
	get_tree().get_root().get_node("Lobby").hide()

	# Set up score.
	print("Players: ", players)
	for player in players:
		print("ADDING PLAYER: ", player, ": ", players[player])
		#world.get_node("Score").add_player(player, players[player])
	get_tree().set_pause(false) # Unpause and unleash the game!

#region Lobbies

func host_lobby(new_player_name : String):
	player_name = new_player_name
	players[1] = new_player_name
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, MAX_PEERS)


func join_lobby(new_lobby_id : int, new_player_name : String):
	player_name = new_player_name
	print("Multiplayer ID in join_game: ", multiplayer.get_unique_id())
	Steam.joinLobby(new_lobby_id)

#endregion

#func get_player_name():
	#return player_name

func begin_game():
	#Ensure that this is only running on the server; if it isn't, we need
	#to check our code.
	assert(multiplayer.is_server())
	
	#call load_world on all clients
	load_world.rpc()
	
	#grab the world node and player scene
	var world : Node2D = get_tree().get_root().get_node("World")
	var player_scene := load("res://player.tscn")
	#var player_scene := load("res://new_player.tscn")
	
	#Iterate over our connected peer ids
	var spawn_index = 0
	
	for peer_id in players:
		var player : CharacterBody2D = player_scene.instantiate()
		
		#player.synced_position = \
		player.position = \
			world.get_node("SpawnPoints").get_child(spawn_index).position
		
		player.name = str(peer_id)
		player.set_player_name(players[peer_id])
		world.get_node("Players").add_child(player)
		
		spawn_index += 1
	
func end_game():
	if is_game_in_progress():
		get_node("/root/World").queue_free()
	
	game_ended.emit()
	players.clear()

# create_socket and connect_socket both create the multiplayer peer, instead
# of _ready, for the sake of compatibility with other networking services
# such as WebSocket, WebRTC, or Steam or Epic.

func create_socket():
	peer = SteamMultiplayerPeer.new()
	peer.create_host(0, [])
	multiplayer.set_multiplayer_peer(peer)

func connect_socket(steam_id : int):
	peer = SteamMultiplayerPeer.new()
	peer.create_client(steam_id, 0, [])
	multiplayer.set_multiplayer_peer(peer)

func create_enet_host(new_player_name : String):
	print("Creating host on ENet...")
	peer = ENetMultiplayerPeer.new()
	(peer as ENetMultiplayerPeer).create_server(DEFAULT_PORT)
	player_name = new_player_name
	players[1] = new_player_name
	#multiplayer.peer_connected.connect(...)
	multiplayer.set_multiplayer_peer(peer)
	print("Host created, multiplayer peer: ", multiplayer.multiplayer_peer)

func create_enet_client(new_player_name : String, address : String):
	print("Creating client on ENet, IP ", address, "...")
	peer = ENetMultiplayerPeer.new()
	(peer as ENetMultiplayerPeer).create_client(address, DEFAULT_PORT)
	multiplayer.set_multiplayer_peer(peer)
	await multiplayer.connected_to_server
	print("Create ENet Client name: ", new_player_name)
	register_player.rpc(new_player_name)
	players[multiplayer.get_unique_id()] = new_player_name
	print("Client created, multiplayer peer: ", multiplayer.multiplayer_peer)

#region Utility

func _make_string_unique(name : String) -> String:
	var count := 2
	var trial := name
	if gamestate.players.values().has(trial):
		trial = name + ' ' + str(count)
		count += 1
	return trial

@rpc("call_local", "any_peer")
func get_player_name() -> String:
	return players[multiplayer.get_remote_sender_id()]

#endregion
