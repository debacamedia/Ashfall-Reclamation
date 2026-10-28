class_name ZoneMap
extends Resource
## A zone's map (Increment 17): a picture of the zone seen from straight
## above, and the stretch of ground it covers. The map screen draws it, with
## the places, markers and the parts you haven't explored on top.
##
## Rendered by tools/render_map.gd into levels/<zone>/map.webp and map.tres.

## Shown on the map screen ("Early Zone").
@export var title := ""
## The picture: north is up, east is right.
@export var texture: Texture2D
## The ground it covers: position = the north-west corner (x, z),
## size = metres east and south.
@export var world_rect := Rect2()


## Where world point (x, z) falls on the picture, 0–1 each way.
func uv_of(p: Vector2) -> Vector2:
	return (p - world_rect.position) / world_rect.size


## The world point (x, z) at picture position `uv` (0–1 each way).
func world_of(uv: Vector2) -> Vector2:
	return world_rect.position + uv * world_rect.size
