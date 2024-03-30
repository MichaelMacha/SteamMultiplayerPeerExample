extends CharacterBody2D

@export var stunned : bool = false

const SPEED = 300.0

func _enter_tree():
	#I still don't like using the name to keep the peer ID. This should be sync'ed.
	set_multiplayer_authority(str(name).to_int())

func _ready():
	set_multiplayer_authority(str(name).to_int())

func _physics_process(_delta : float):
	var spawner = get_node("../../BombSpawner")
	#TODO: This could still be better— it's two string conversions
	# per physics update. It might be better to store the peer ID
	# in a local, synchronized field.
	
	# This is a mistake. We want to check for input on the client
	# side, but do velocity and updates on the host.
	#if str(multiplayer.get_unique_id()) == str(name):
	if is_multiplayer_authority():
		# Get the input direction and handle the movement/deceleration.
		if stunned:
			velocity = Vector2.ZERO
		else:
			var direction : Vector2 = Input.get_vector(
				"move_left", "move_right", 
				"move_up", "move_down")
			if direction:
				velocity = direction * SPEED
			else:
				velocity = velocity.move_toward(Vector2.ZERO, SPEED)
		
		#Handle bombs
		if Input.is_action_just_pressed("set_bomb"):
			drop_bomb.rpc_id(1, [position, str(name).to_int()])
	
	_handle_animation()
	
	move_and_slide()

@rpc("any_peer", "call_local")
func drop_bomb(data : Array) -> void:
	var spawner = get_node("../../BombSpawner")
	spawner.spawn([position, str(name).to_int()])

func _handle_animation():
	var player : AnimationPlayer = $AnimationPlayer
	if not stunned:
		if velocity.x > 0.0:
			player.play("walk right")
		elif velocity.x < 0.0:
			player.play("walk left")
		elif velocity.y > 0.0:
			player.play("walk down")
		elif velocity.y < 0.0:
			player.play("walk up")
		else:
			player.play("standing")
	elif $AnimationPlayer.current_animation != "stunned":
		player.play("stunned")
	
func set_player_name(value : String):
	$Label.text = value

@rpc("call_local")
func exploded(_by_who):
	stunned = true
