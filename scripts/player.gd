extends CharacterBody2D

@export var texture: Texture2D
@export var dead_texture: Texture2D
const SPEED: float = 330.0
const ACCELERATION: float = 1800.0
const GRAVITY: float = 1500.0
# The tallest required step is the power-station gantry (157 px).
const JUMP_SPEED: float = -720.0

@export_group("Movement")
@export var move_speed: float = SPEED
@export var acceleration: float = ACCELERATION
@export var gravity: float = GRAVITY
@export var jump_speed: float = JUMP_SPEED
@export var sprite_scale: Vector2 = Vector2(1.15, 1.15)
@export var sprite_offset: Vector2 = Vector2.ZERO

var coyote: float = 0.0
var jump_buffer: float = 0.0
var dead: bool = false
var visual_angle: float = 0.0
var stretch := Vector2.ONE
var checkpoint := Vector2(100, 560)
var _was_rewinding: bool = false

@onready var anim_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var rewind_vfx: AnimatedSprite2D = get_node_or_null("RewindVFX")

func _ready() -> void:
	add_to_group("rewindable")
	add_to_group("player")
	checkpoint = position
	if not texture and ResourceLoader.exists("res://assets/characters/ball.png"):
		texture = load("res://assets/characters/ball.png")
	if not dead_texture and ResourceLoader.exists("res://assets/characters/ball_dead.png"):
		dead_texture = load("res://assets/characters/ball_dead.png")

func _physics_process(delta: float) -> void:
	_update_animation(delta)
	if RewindManager.is_rewinding:
		queue_redraw()
		return
	if dead:
		if RewindManager.history.is_empty() or Input.is_action_just_pressed("jump"):
			reset_checkpoint()
		return

	coyote = 0.10 if is_on_floor() else maxf(0.0, coyote - delta)
	jump_buffer = 0.10 if Input.is_action_just_pressed("jump") else maxf(0.0, jump_buffer - delta)
	var axis := Input.get_axis("move_left", "move_right")
	velocity.x = move_toward(velocity.x, axis * move_speed, acceleration * delta)
	velocity.y += gravity * delta
	if coyote > 0.0 and jump_buffer > 0.0:
		velocity.y = jump_speed
		coyote = 0.0
		jump_buffer = 0.0
		stretch = Vector2(0.78, 1.22)
		if has_node("/root/AudioManager"):
			get_node("/root/AudioManager").play_sfx("jump", 0.08)

	var was_grounded := is_on_floor()
	var fall_v := velocity.y
	move_and_slide()
	if not was_grounded and is_on_floor():
		stretch = Vector2(1.25, 0.75)
		if has_node("/root/AudioManager"):
			if fall_v > 280.0:
				get_node("/root/AudioManager").play_sfx("bounce", 0.08)
			else:
				get_node("/root/AudioManager").play_sfx("land", 0.05)
	stretch = stretch.lerp(Vector2.ONE, minf(delta * 12.0, 1.0))
	visual_angle += velocity.x * delta / 22.0

	if position.y > 850:
		die()

	queue_redraw()

func die() -> void:
	if not dead:
		dead = true
		velocity = Vector2.ZERO
		if has_node("/root/AudioManager"):
			get_node("/root/AudioManager").play_sfx("death")
		queue_redraw()

func reset_checkpoint() -> void:
	position = checkpoint
	velocity = Vector2.ZERO
	dead = false
	coyote = 0.0
	jump_buffer = 0.0
	RewindManager.clear_history()

func capture_rewind_state() -> Dictionary:
	return {
		"position": position,
		"velocity": velocity,
		"dead": dead,
		"angle": visual_angle,
		"stretch": stretch,
		"coyote": coyote,
		"buffer": jump_buffer
	}

func restore_rewind_state(state: Dictionary) -> void:
	position = state.position
	velocity = state.velocity
	dead = state.dead
	visual_angle = state.angle
	stretch = state.stretch
	coyote = state.coyote
	jump_buffer = state.buffer
	_update_animation(0.0)
	queue_redraw()

func _update_animation(_delta: float) -> void:
	if RewindManager.is_rewinding:
		if not _was_rewinding:
			_was_rewinding = true
			if has_node("/root/AudioManager"):
				get_node("/root/AudioManager").play_sfx("rewind_start")
				get_node("/root/AudioManager").start_rewind_loop()
		if rewind_vfx:
			rewind_vfx.visible = true
			if rewind_vfx.animation != "effect":
				rewind_vfx.play("effect")
		if anim_sprite:
			if anim_sprite.animation != "idle":
				anim_sprite.play("idle")
		return

	if _was_rewinding:
		_was_rewinding = false
		if has_node("/root/AudioManager"):
			get_node("/root/AudioManager").stop_rewind_loop()
			get_node("/root/AudioManager").play_sfx("rewind_end")

	if rewind_vfx and rewind_vfx.visible:
		rewind_vfx.visible = false

	if not anim_sprite:
		return

	anim_sprite.scale = stretch * sprite_scale
	anim_sprite.offset = sprite_offset

	if dead:
		if anim_sprite.animation != "death":
			anim_sprite.play("death")
		return

	if not is_on_floor():
		if velocity.y < -50.0:
			if anim_sprite.animation != "jump":
				anim_sprite.play("jump")
		elif velocity.y > 50.0:
			if anim_sprite.animation != "fall":
				anim_sprite.play("fall")
	else:
		if abs(velocity.x) > 20.0:
			if anim_sprite.animation != "run":
				anim_sprite.play("run")
			anim_sprite.flip_h = (velocity.x < 0.0)
		else:
			if anim_sprite.animation != "idle":
				anim_sprite.play("idle")

func _draw() -> void:
	if anim_sprite and anim_sprite.visible and anim_sprite.sprite_frames:
		return

	if dead:
		if dead_texture:
			draw_texture_rect(dead_texture, Rect2(-24, -24, 48, 48), false)
			return
		# 2D Pixelated minimalist dead ball
		var body_col := Color("e0536c")
		var shadow_col := Color("6e2433")
		draw_rect(Rect2(-14, -22, 28, 44), body_col)
		draw_rect(Rect2(-20, -18, 40, 36), body_col)
		draw_rect(Rect2(-22, -14, 44, 28), body_col)
		draw_rect(Rect2(-12, 16, 24, 4), shadow_col)
		draw_rect(Rect2(-18, 12, 36, 4), shadow_col)
		return

	draw_set_transform(Vector2.ZERO, visual_angle, stretch)
	if texture:
		draw_texture_rect(texture, Rect2(-22, -22, 44, 44), false)
	else:
		# 2D Pixelated minimalist ball
		var body_col := Color("4deeea")
		var shadow_col := Color("1f5c6b")
		var eye_col := Color("0b1726")
		var glint_col := Color("d8ffff")
		
		# Stepped pixel-circle silhouette (radius ~22)
		draw_rect(Rect2(-14, -22, 28, 44), body_col)
		draw_rect(Rect2(-20, -18, 40, 36), body_col)
		draw_rect(Rect2(-22, -14, 44, 28), body_col)
		
		# Pixel bottom shadow / bevel
		draw_rect(Rect2(-12, 16, 24, 4), shadow_col)
		draw_rect(Rect2(-18, 12, 36, 4), shadow_col)
		
		# Detective fedora / visor glint line (pixel-aligned)
		draw_rect(Rect2(-6, -14, 8, 4), glint_col)
		# Slit gaze / investigator eye band
		draw_rect(Rect2(-10, -4, 20, 6), eye_col)
		draw_rect(Rect2(-6, -2, 6, 4), Color("e8d07a")) # amber focus glint
	draw_set_transform(Vector2.ZERO)
