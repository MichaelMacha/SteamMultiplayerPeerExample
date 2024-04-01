extends AnimationTree

@export var player : Node2D

var last_position : Vector2 = Vector2.ZERO
var up : bool = false
var down : bool = false
var left : bool = false
var right : bool = false

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	#Get our immediate displacement vector first
	var motion := player.global_position - last_position
	last_position = player.global_position
	
	# Update animation tree with parameters for cardinal directions and stunned
	self.set("parameters/up/blend_amount", 
		1.0 if motion.dot(Vector2.UP) > 0.0 else 0.0)
	self.set("parameters/down/blend_amount",
		1.0 if motion.dot(Vector2.DOWN) > 0.0 else 0.0)
	self.set("parameters/left/blend_amount",
		1.0 if motion.dot(Vector2.LEFT) > 0.0 else 0.0)
	self.set("parameters/right/blend_amount",
		1.0 if motion.dot(Vector2.RIGHT) > 0.0 else 0.0)
	self.set("parameters/stunned/blend_amount",
		1.0 if player.stunned else 0.0)

