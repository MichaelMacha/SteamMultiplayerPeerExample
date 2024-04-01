extends Area2D

var in_area: Array = []
var from_player: int

#TODO: We can do this better.
# Called from the animation.
func explode():
	if is_multiplayer_authority(): #Explode only for authority
		for p in in_area:
			#Start by ensuring we've got an explode function to call.
			if p is Rock or p is NewPlayer or p is Player:	#TODO: Remember to 
					#remove Player when we're done with it!
				
				# Check if there is wall in between bomb and the object
				# with a 2D ray cast
				var world_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
				var query := PhysicsRayQueryParameters2D.create(position, p.position)
				# Ensure we can be hit by bombs we're standing on:
				query.hit_from_inside = true
				
				var result: Dictionary  = world_state.intersect_ray(query)
				#Ensure that we haven't hit the wall between our bomb and our target
				if not result.collider is TileMap:
					# Exploded can only be called by the authority, but will also be called locally.
					p.exploded.rpc(from_player)

func done():
	if is_multiplayer_authority():
		queue_free()


func _on_bomb_body_enter(body):
	if not body in in_area:
		in_area.append(body)


func _on_bomb_body_exit(body):
	in_area.erase(body)
