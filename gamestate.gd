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
signal game_log(what : String)

func _ready():
	Steam.steamInitEx(true, 480)
	#peer = SteamMultiplayerPeer.new()
	
	# Keep connections defined locally, if they aren't likely to be used
	# anywhere else, such as with a lambda function for readability.
	
	multiplayer.peer_connected.connect(
		func(id : int):
			# Tell the connected peer that we have also joined
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
		if response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
			lobby_id = new_lobby_id
			var id = Steam.getLobbyOwner(new_lobby_id)
			if id != Steam.getSteamID():
				connect_socket(id)
				register_player.rpc(player_name)
				players[multiplayer.get_unique_id()] = player_name
		else:
			# Get the failure reason
			var FAIL_REASON: String
			match response:
				Steam.CHAT_ROOM_ENTER_RESPONSE_DOESNT_EXIST:
					FAIL_REASON = "This lobby no longer exists."
				Steam.CHAT_ROOM_ENTER_RESPONSE_NOT_ALLOWED:
					FAIL_REASON = "You don't have permission to join this lobby."
				Steam.CHAT_ROOM_ENTER_RESPONSE_FULL:
					FAIL_REASON = "The lobby is now full."
				Steam.CHAT_ROOM_ENTER_RESPONSE_ERROR:
					FAIL_REASON = "Uh... something unexpected happened!"
				Steam.CHAT_ROOM_ENTER_RESPONSE_BANNED:
					FAIL_REASON = "You are banned from this lobby."
				Steam.CHAT_ROOM_ENTER_RESPONSE_LIMITED:
					FAIL_REASON = "You cannot join due to having a limited account."
				Steam.CHAT_ROOM_ENTER_RESPONSE_CLAN_DISABLED:
					FAIL_REASON = "This lobby is locked or disabled."
				Steam.CHAT_ROOM_ENTER_RESPONSE_COMMUNITY_BAN:
					FAIL_REASON = "This lobby is community locked."
				Steam.CHAT_ROOM_ENTER_RESPONSE_MEMBER_BLOCKED_YOU:
					FAIL_REASON = "A user in the lobby has blocked you from joining."
				Steam.CHAT_ROOM_ENTER_RESPONSE_YOU_BLOCKED_MEMBER:
					FAIL_REASON = "A user you have blocked is in the lobby."
			game_log.emit(FAIL_REASON)
	)
	Steam.lobby_created.connect(
		func(status: int, new_lobby_id: int):
			if status == 1:
				#lobby_id = new_lobby_id
				Steam.setLobbyData(new_lobby_id, "name", 
					str(Steam.getPersonaName(), "'s Spectabulous Test Server"))
				create_socket()
			else:
				game_error.emit("Error on create lobby!")
	)

func _process(_delta : float):
	Steam.run_callbacks()

# Lobby management functions.
@rpc("call_local", "any_peer")
func register_player(new_player_name : String):
	var id = multiplayer.get_remote_sender_id()
	players[id] = _make_string_unique(new_player_name)
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

	get_tree().set_pause(false) # Unpause and unleash the game!

#region Lobbies

func host_lobby(new_player_name : String):
	player_name = new_player_name
	players[1] = new_player_name
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, MAX_PEERS)


func join_lobby(new_lobby_id : int, new_player_name : String):
	player_name = new_player_name
	Steam.joinLobby(new_lobby_id)

#endregion

func begin_game():
	#Ensure that this is only running on the server; if it isn't, we need
	#to check our code.
	assert(multiplayer.is_server())
	
	#call load_world on all clients
	load_world.rpc()
	
	#grab the world node and player scene
	var world : Node2D = get_tree().get_root().get_node("World")
	#var player_scene := load("res://player.tscn")
	var player_scene := load("res://new_player.tscn")
	
	#Iterate over our connected peer ids
	var spawn_index = 0
	
	for peer_id in players:
		print("PEER ID: ", peer_id)
		var player : CharacterBody2D = player_scene.instantiate()
		
		player.set_player_name(players[peer_id])
		# "true" forces a readable name, which is important, as we can't have sibling nodes
		# with the same name.
		world.get_node("Players").add_child(player, true)
		player.set_authority.rpc(peer_id)
		var target : Vector2 = world.get_node("SpawnPoints").get_child(spawn_index).position
		print("Target point: ", target)
		
		#TODO: Remove this check when we're done with Player
		if player is Player:
			player.position = target
		elif player is NewPlayer:
			player.teleport.rpc_id(peer_id, target)
		
		print("Player ", peer_id, " global position: ", player.global_position)
		
		spawn_index += 1
	
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
	peer = ENetMultiplayerPeer.new()
	(peer as ENetMultiplayerPeer).create_server(DEFAULT_PORT)
	player_name = new_player_name
	players[1] = new_player_name
	multiplayer.set_multiplayer_peer(peer)

func create_enet_client(new_player_name : String, address : String):
	peer = ENetMultiplayerPeer.new()
	(peer as ENetMultiplayerPeer).create_client(address, DEFAULT_PORT)
	multiplayer.set_multiplayer_peer(peer)
	await multiplayer.connected_to_server
	register_player.rpc(new_player_name)
	players[multiplayer.get_unique_id()] = new_player_name

#region Utility

func _make_string_unique(query : String) -> String:
	var count := 2
	var trial := query
	if gamestate.players.values().has(trial):
		trial = query + ' ' + str(count)
		count += 1
	return trial

@rpc("call_local", "any_peer")
func get_player_name() -> String:
	return players[multiplayer.get_remote_sender_id()]

func is_game_in_progress() -> bool:
	return has_node("/root/World")

func end_game():
	if is_game_in_progress():
		get_node("/root/World").queue_free()
	
	game_ended.emit()
	players.clear()

#endregion
