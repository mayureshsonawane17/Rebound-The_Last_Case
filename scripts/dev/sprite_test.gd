extends Node2D

# Dev scene to visually inspect all animations on both dark and light backgrounds.
# Left half is BounceFlux dark (#101827), Right half is light (#E9EDF2).

const DARK_COLOR := Color("#101827")
const LIGHT_COLOR := Color("#E9EDF2")

func _ready() -> void:
	# Build layout procedurally if instantiated dynamically, or verify child nodes
	queue_redraw()

func _draw() -> void:
	# Split viewport into dark and light sides
	draw_rect(Rect2(0, 0, 640, 720), DARK_COLOR)
	draw_rect(Rect2(640, 0, 640, 720), LIGHT_COLOR)
	# Center divider
	draw_line(Vector2(640, 0), Vector2(640, 720), Color("#48D9E8"), 2.0)
