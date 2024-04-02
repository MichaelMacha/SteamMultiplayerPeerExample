class_name NewPlayer
extends CharacterBody2D

@export var stunned : bool = false

const SPEED = 300.0

@rpc("any_peer", "call_local")
func set_authority(id : int) -> void:
	set_multiplayer_authority(id)

func _physics_process(_delta : float):
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
			drop_bomb.rpc_id(1, [position, multiplayer.get_unique_id()])
	
	move_and_slide()

@rpc("any_peer", "call_local")
func drop_bomb(data : Array) -> void:
	var spawner = get_node("../../BombSpawner")
	spawner.spawn(data)

func set_player_name(value : String):
	$Label.text = value

@rpc("any_peer", "call_local")
func teleport(new_position : Vector2) -> void:
	self.position = new_position

@rpc("any_peer", "call_local")
func exploded(_by_who):
	#If we're already stunned, ignore
	if stunned:
		return
	
	#Otherwise, stun us
	stunned = true
	await $AnimationPlayer.animation_finished
	stunned = false
