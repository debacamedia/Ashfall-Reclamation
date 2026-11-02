class_name NpcStep
## Lets a walking NPC (settler or raider) step up a low ledge: a stair, a
## kerb, the side of a ramp or a doorstep (Increment 22.1). Characters slide
## along anything that isn't a slope, so without this a step a hand high
## stopped them dead while the navmesh said the way was open.
##
## Called after move_and_slide(). If they walked into something low, and
## there's room to stand on top of it, they're lifted onto it; the next
## move carries them forward.

## The highest step taken (m). Under a bed or bench top, so they don't climb
## the furniture.
const MAX_STEP := 0.42


static func step_up(body: CharacterBody3D, max_step := MAX_STEP) -> bool:
	var h := Vector3(body.velocity.x, 0.0, body.velocity.z)
	if h.length() < 0.3 or body.velocity.y > 0.5:
		return false
	var feet := body.global_position.y
	var blocked := false
	for i in body.get_slide_collision_count():
		var k := body.get_slide_collision(i)
		var n := k.get_normal()
		if n.y < 0.7 and Vector3(n.x, 0.0, n.z).dot(h) < -0.05 and k.get_position().y - feet < max_step + 0.05:
			blocked = true
			break
	if not blocked:
		return false
	var fwd := h.normalized() * 0.3
	var xf := body.global_transform
	var up := Vector3.UP * max_step
	if body.test_move(xf, up):
		return false  # no headroom
	var raised := xf.translated(up)
	if body.test_move(raised, fwd):
		return false  # taller than a step
	var res := KinematicCollision3D.new()
	if not body.test_move(raised.translated(fwd), -up, res):
		return false  # nothing to stand on
	if res.get_normal().y < cos(body.floor_max_angle):
		return false
	var rise := max_step - res.get_travel().length()
	if rise <= 0.02:
		return false
	body.global_position.y += rise + 0.01
	body.velocity.y = 0.0
	return true
