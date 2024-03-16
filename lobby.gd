extends Control

func _ready():
	$"Connect/Persona Name".text = Steam.getPersonaName()
	
	# Called every time the node is added to the scene.
	gamestate.connection_failed.connect(self._on_connection_failed)
	gamestate.connection_succeeded.connect(self._on_connection_success)
	gamestate.player_list_changed.connect(self.refresh_lobby)
	gamestate.game_ended.connect(self._on_game_ended)
	gamestate.game_error.connect(self._on_game_error)
	# Set the player name according to the system username. Fallback to the path.
	if OS.has_environment("USERNAME"):
		$Connect/Name.text = OS.get_environment("USERNAME")
	else:
		#var desktop_path = OS.get_system_dir(0).replace("\\", "/").split("/")
		var desktop_path = OS \
			.get_system_dir(OS.SYSTEM_DIR_DESKTOP) \
			.replace("\\", "/").split("/")
		$Connect/Name.text = desktop_path[desktop_path.size() - 2]


func _on_host_pressed():
	if $Connect/Name.text == "":
		$Connect/ErrorLabel.text = "Invalid name!"
		return

	$Connect.hide()
	$Players.show()
	$Connect/ErrorLabel.text = ""

	var player_name = $Connect/Name.text
	gamestate.host_game(player_name)
	refresh_lobby()


func _on_join_pressed():
	if $Connect/Name.text == "":
		$Connect/ErrorLabel.text = "Invalid name!"
		return

	var ip : int = int($Connect/IPAddress.text)

	$Connect/ErrorLabel.text = ""
	$Connect/Host.disabled = true
	$Connect/Join.disabled = true

	var player_name = $Connect/Name.text
	gamestate.join_game(ip, player_name)


func _on_connection_success():
	$Connect.hide()
	$Players.show()


func _on_connection_failed():
	$Connect/Host.disabled = false
	$Connect/Join.disabled = false
	$Connect/ErrorLabel.set_text("Connection failed.")


func _on_game_ended():
	show()
	$Connect.show()
	$Players.hide()
	$Connect/Host.disabled = false
	$Connect/Join.disabled = false


func _on_game_error(errtxt):
	$ErrorDialog.dialog_text = errtxt
	$ErrorDialog.popup_centered()
	$Connect/Host.disabled = false
	$Connect/Join.disabled = false


func refresh_lobby():
	var players = gamestate.get_player_list()
	players.sort()
	$Players/List.clear()
	for player_name in players:
		var name : String = player_name
		if player_name == gamestate.get_player_name():
			player_name += " (You)"
		$Players/List.add_item(player_name)

	$Players/Start.disabled = not multiplayer.is_server()
	$Players/FindPublicIP.text = "loading lobby id..."
	await get_tree().create_timer(1).timeout
	$Players/FindPublicIP.text = str(gamestate.lobby_id)
	$Players/LobbyID.text = str(gamestate.lobby_id)
	
func _on_start_pressed():
	gamestate.begin_game2()
