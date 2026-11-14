extends Area2D

signal evidence_collected(id: String)

@export var evidence_id: String = "evidence_1"
@export var texture: Texture2D
@export var sprite_scale: Vector2 = Vector2.ONE

var collected: bool = false
var pulse_time: float = 0.0

func _ready() -> void:
	add_to_group("rewindable")
	body_entered.connect(_on_body_entered)
	if not texture:
		if ResourceLoader.exists("res://assets/sprites/props/evidence/00.png"):
			texture = load("res://assets/sprites/props/evidence/00.png")
		elif ResourceLoader.exists("res://assets/props/evidence.png"):
			texture = load("res://assets/props/evidence.png")

func _physics_process(delta: float) -> void:
	if not RewindManager.is_rewinding:
		pulse_time += delta
	queue_redraw()

func _on_body_entered(body: Node2D) -> void:
	if collected or RewindManager.is_rewinding:
		return
	if body.is_in_group("player") or body.name == "Player":
		collected = true
		set_deferred("monitoring", false)
		evidence_collected.emit(evidence_id)
		if has_node("/root/AudioManager"):
			get_node("/root/AudioManager").play_sfx("evidence_collect")

func capture_rewind_state() -> Dictionary:
	return {
		"collected": collected,
		"monitoring": monitoring,
		"pulse_time": pulse_time
	}

func restore_rewind_state(state: Dictionary) -> void:
	collected = state.collected
	set_deferred("monitoring", state.monitoring)
	pulse_time = state.pulse_time
	queue_redraw()

func _draw() -> void:
	if collected:
		return
	var offset_y: float = sin(pulse_time * 3.5) * 3.0
	draw_set_transform(Vector2(0, offset_y), 0.0, sprite_scale)
	var glow_alpha: float = 0.2 + 0.12 * sin(pulse_time * 4.5)
	draw_rect(Rect2(-20, -24, 40, 48), Color(0.94, 0.78, 0.45, glow_alpha))
	if texture:
		draw_texture_rect(texture, Rect2(-18, -22, 36, 44), false)
	else:
		# Pixelated minimalist gold dossier record
		# Outer folder
		draw_rect(Rect2(-14, -18, 28, 36), Color("b89635"))
		draw_rect(Rect2(-12, -16, 24, 32), Color("f5d76e"))
		# Tab
		draw_rect(Rect2(-14, -22, 12, 4), Color("b89635"))
		draw_rect(Rect2(-12, -20, 8, 4), Color("f5d76e"))
		# Internal dossier paper lines
		draw_rect(Rect2(-8, -10, 16, 2), Color("8a6d20"))
		draw_rect(Rect2(-8, -4, 16, 2), Color("8a6d20"))
		draw_rect(Rect2(-8, 2, 12, 2), Color("8a6d20"))
		# Confidential red stamp badge (pixel)
		draw_rect(Rect2(2, 6, 6, 6), Color("d64747"))
	draw_set_transform(Vector2.ZERO)
