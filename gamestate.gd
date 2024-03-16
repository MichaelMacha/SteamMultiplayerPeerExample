extends Node

# Default game server port. Can be any number between 1024 and 49151.
# Not on the list of registered or common ports as of November 2020:
# https://en.wikipedia.org/wiki/List_of_TCP_and_UDP_port_numbers
const DEFAULT_PORT = 10567

# Max number of players.
const MAX_PEERS = 12

var peer : MultiplayerPeer = null

# Name for my player.
var player_name := "The Warrior"

# Names for remote players in id:name format.
var players := {}
## Issue: I don't see any reason why the host couldn't also be in here, and it
## seems like it could simplify code.

var players_ready := []

var lobby_id := -1

# Signals to let lobby GUI know what's going on.
signal player_list_changed()
signal connection_failed()
signal connection_succeeded()
signal game_ended()
signal game_error(what : String)

func _process(_delta : float):
	Steam.run_callbacks()

# Callback from SceneTree.
func _player_connected(id):
	# Registration of a client beings here, tell the connected player that we are here.
	register_player.rpc_id(id, player_name)


# Callback from SceneTree.
func _player_disconnected(id):
	if has_node("/root/World"): # Game is in progress.
		if multiplayer.is_server():
			game_error.emit("Player " + players[id] + " disconnected")
			end_game()
	else: # Game is not in progress.
		# Unregister this player.
		unregister_player(id)


# Callback from SceneTree, only for clients (not server).
func _connected_ok():
	# We just connected to a server
	connection_succeeded.emit()


# Callback from SceneTree, only for clients (not server).
func _server_disconnected():
	game_error.emit("Server disconnected")
	end_game()


# Callback from SceneTree, only for clients (not server).
func _connected_fail():
	multiplayer.multiplayer_peer = null
	#multiplayer.set_network_peer(null) # Remove peer
	connection_failed.emit()


# Lobby management functions.
@rpc("any_peer")
func register_player(new_player_name : String):
	print("registering player")
	var id = multiplayer.get_remote_sender_id()
	players[id] = new_player_name
	player_list_changed.emit()


func unregister_player(id):
	players.erase(id)
	player_list_changed.emit()
	

@rpc("call_local")
func load_world():
	# Change scene.
	var world = load("res://world.tscn").instantiate()
	get_tree().get_root().add_child(world)
	get_tree().get_root().get_node("Lobby").hide()

	# Set up score.
	#world.get_node("Score").add_player(multiplayer.get_unique_id(), player_name)
	for player in players:
		world.get_node("Score").add_player(player, players[player])
	get_tree().set_pause(false) # Unpause and unleash the game!


func host_game(new_player_name : String):
	player_name = new_player_name
	players[1] = new_player_name
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, MAX_PEERS)


func join_game(new_lobby_id : int, new_player_name : String):
	player_name = new_player_name
	Steam.joinLobby(new_lobby_id)


func get_player_list():
	return players.values()


func get_player_name():
	return player_name

func begin_game2():
	#Ensure that this is only running on the server
	assert(multiplayer.is_server())
	
	#call load_world on all clients
	load_world.rpc()
	
	#grab the world node and player scene
	var world : Node2D = get_tree().get_root().get_node("World")
	var player_scene := load("res://player.tscn")
	
	# A more concise way to do this would be to have a version of `players` which
	# includes the host, too.
	var all_players = players.duplicate()
	#all_players[1] = player_name
	
	#Iterate over our connected peer ids
	var index = 0
	for peer_id in all_players:
		print("peer_id == ", peer_id)
		var player : CharacterBody2D = player_scene.instantiate()
		player.synced_position = \
			world.get_node("SpawnPoints").get_child(index).position
		player.name = str(peer_id)
		player.set_player_name(all_players[peer_id])
		world.get_node("Players").add_child(player)
		index += 1
	
#func begin_game():
	#assert(multiplayer.is_server())
	#load_world.rpc()
#
	#var world = get_tree().get_root().get_node("World")
	#var player_scene = load("res://player.tscn")
#
	## Create a dictionary with peer id and respective spawn points, could be improved by randomizing.
	#var spawn_points = {}
	#spawn_points[1] = 0 # Server in spawn point 0.
	#var spawn_point_idx = 1
	#for p in players:
		#spawn_points[p] = spawn_point_idx
		#spawn_point_idx += 1
#
	#for p_id in spawn_points:
		#var spawn_pos = world.get_node("SpawnPoints/" + str(spawn_points[p_id])).position
		#var player = player_scene.instantiate()
		#player.synced_position = spawn_pos
		#player.name = str(p_id)
		#player.set_player_name(player_name if p_id == multiplayer.get_unique_id() else players[p_id])
		#world.get_node("Players").add_child(player)

func end_game():
	if has_node("/root/World"): # Game is in progress.
		# End it
		get_node("/root/World").queue_free()

	game_ended.emit()
	players.clear()


func _ready():
	Steam.steamInitEx(true, 480)
	
	multiplayer.peer_connected.connect(self._player_connected)
	multiplayer.peer_disconnected.connect(self._player_disconnected)
	multiplayer.connected_to_server.connect(self._connected_ok)
	multiplayer.connection_failed.connect(self._connected_fail)
	multiplayer.server_disconnected.connect(self._server_disconnected)
	#Steam.lobby_joined.connect(_on_lobby_joined.bind())
	#Steam.lobby_created.connect(_on_lobby_created.bind())
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_created.connect(_on_lobby_created)

func _on_lobby_created(status: int, new_lobby_id: int):
	if status == 1:
		lobby_id = new_lobby_id
		Steam.setLobbyData(new_lobby_id, "name", "test_server")
		create_socket()
		print("Create lobby id:",str(lobby_id))
	else:
		print("Error on create lobby!")


func _on_lobby_joined(lobby: int, _permissions: int, _locked: bool, response: int):
	if response == 1:
		var id = Steam.getLobbyOwner(lobby)
		if id != Steam.getSteamID():
			connect_socket(id)
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


func create_socket():
	peer = SteamMultiplayerPeer.new()
	peer.create_host(0, [])
	multiplayer.set_multiplayer_peer(peer)

func connect_socket(steam_id : int):
	peer = SteamMultiplayerPeer.new()
	peer.create_client(steam_id, 0, [])
	multiplayer.set_multiplayer_peer(peer)
