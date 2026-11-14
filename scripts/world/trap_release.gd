extends Area2D

signal activated

@export_node_path("CharacterBody2D") var trap_path: NodePath

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(_delta: float) -> void:
	# Rewinding can restore READY while a player is already standing on the
	# marker, so body_entered alone is not enough to rearm the mechanism.
	for body in get_overlapping_bodies():
		_on_body_entered(body)

func _on_body_entered(body: Node2D) -> void:
	if RewindManager.is_rewinding or not body.is_in_group("player") or body.dead:
		return
	_activate()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	var marker := $Marker as Polygon2D
	var point: Vector2 = marker.get_global_transform_with_canvas().affine_inverse() * event.position
	if Geometry2D.is_point_in_polygon(point, marker.polygon):
		_activate()
		get_viewport().set_input_as_handled()

func _activate() -> void:
	if RewindManager.is_rewinding or get_tree().paused:
		return
	var player := get_tree().get_first_node_in_group("player")
	if not player or player.dead:
		return
	var trap := get_node_or_null(trap_path)
	if trap and trap.has_method("trigger_trap") and not trap.triggered:
		trap.trigger_trap()
		activated.emit()
