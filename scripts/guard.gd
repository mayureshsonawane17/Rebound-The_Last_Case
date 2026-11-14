extends CharacterBody2D

signal player_touched

@export var patrol_distance: float = 180.0
@export var speed: float = 110.0
@export var is_boss: bool = false
@export var texture: Texture2D
@export var disabled_texture: Texture2D

var origin_x: float = 0.0
var direction: float = 1.0
var disabled: bool = false
var anim_phase: float = 0.0

@onready var anim_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")

func _ready() -> void:
	add_to_group("rewindable")
	add_to_group("guards")
	origin_x = position.x
	if anim_sprite:
		if is_boss:
			if ResourceLoader.exists("res://assets/sprites/boss/boss_frames.tres"):
				anim_sprite.sprite_frames = load("res://assets/sprites/boss/boss_frames.tres")
				anim_sprite.position = Vector2(0, -64)
		else:
			anim_sprite.position = Vector2(0, -48)
	if not texture:
		var tex_path := "res://assets/characters/boss.png" if is_boss else "res://assets/characters/guard.png"
		if ResourceLoader.exists(tex_path):
			texture = load(tex_path)
	if not disabled_texture:
		var dis_path := "res://assets/characters/boss_disabled.png" if is_boss else "res://assets/characters/guard_disabled.png"
		if ResourceLoader.exists(dis_path):
			disabled_texture = load(dis_path)

func _physics_process(delta: float) -> void:
	_update_animation()
	if RewindManager.is_rewinding:
		queue_redraw()
		return

	if disabled:
		velocity = Vector2.ZERO
		queue_redraw()
		return

	anim_phase += delta * 6.0
	velocity.x = direction * speed
	velocity.y = 900.0 * delta # light gravity in case placed on uneven ground

	var moved := move_and_slide()

	if position.x > origin_x + patrol_distance:
		direction = -1.0
	elif position.x < origin_x - patrol_distance:
		direction = 1.0
	elif is_on_wall():
		direction *= -1.0

	# Check collision with player
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()
		if collider and (collider.is_in_group("player") or collider.name == "Player"):
			player_touched.emit()
			if collider.has_method("die"):
				collider.die()
			elif "dead" in collider:
				collider.dead = true

	queue_redraw()

func knock_out() -> void:
	if not disabled:
		disabled = true
		velocity = Vector2.ZERO
		_update_animation()
		queue_redraw()

func capture_rewind_state() -> Dictionary:
	return {
		"position": position,
		"velocity": velocity,
		"direction": direction,
		"disabled": disabled,
		"anim_phase": anim_phase
	}

func restore_rewind_state(state: Dictionary) -> void:
	position = state.position
	velocity = state.velocity
	direction = state.direction
	disabled = state.disabled
	anim_phase = state.anim_phase
	_update_animation()
	queue_redraw()

func _update_animation() -> void:
	if not anim_sprite or not anim_sprite.sprite_frames:
		return

	anim_sprite.flip_h = (direction < 0.0)

	if disabled:
		if anim_sprite.sprite_frames.has_animation("defeat"):
			if anim_sprite.animation != "defeat":
				anim_sprite.play("defeat")
		return

	if is_boss:
		if anim_sprite.sprite_frames.has_animation("attack"):
			if anim_sprite.animation != "attack":
				anim_sprite.play("attack")
		elif anim_sprite.sprite_frames.has_animation("idle"):
			if anim_sprite.animation != "idle":
				anim_sprite.play("idle")
	else:
		if abs(velocity.x) > 10.0:
			if anim_sprite.sprite_frames.has_animation("walk"):
				if anim_sprite.animation != "walk":
					anim_sprite.play("walk")
		else:
			if anim_sprite.sprite_frames.has_animation("idle"):
				if anim_sprite.animation != "idle":
					anim_sprite.play("idle")

func _draw() -> void:
	if anim_sprite and anim_sprite.visible and anim_sprite.sprite_frames:
		return

	var active_tex: Texture2D = disabled_texture if disabled and disabled_texture else texture
	if active_tex:
		var flip_scale := Vector2(direction if not disabled else 1.0, 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, flip_scale)
		if is_boss:
			var boss_rect := Rect2(-57, -36, 114, 72) if disabled else Rect2(-33, -70, 67, 85)
			draw_texture_rect(active_tex, boss_rect, false)
		else:
			var guard_rect := Rect2(-36, -24, 73, 47) if disabled else Rect2(-21, -65, 43, 85)
			draw_texture_rect(active_tex, guard_rect, false)
		draw_set_transform(Vector2.ZERO)
		return

	if is_boss:
		# Pixelated Crime Boss silhouette
		var coat_col := Color("181224") if not disabled else Color("383244")
		var lapel_col := Color("912c48") if not disabled else Color("4d313c")
		var hat_col := Color("120d1c") if not disabled else Color("2c2635")
		var gold_trim := Color("e8d07a")

		# Trenchcoat torso
		draw_rect(Rect2(-22, -44, 44, 44), coat_col)
		# Red lapels
		draw_rect(Rect2(-6, -40, 12, 34), lapel_col)
		# Shoulders
		draw_rect(Rect2(-26, -44, 52, 14), coat_col)
		# Boss Fedora (stepped pixels)
		draw_rect(Rect2(-24, -48, 48, 4), hat_col) # brim
		draw_rect(Rect2(-16, -58, 32, 10), hat_col) # crown
		draw_rect(Rect2(-16, -50, 32, 2), gold_trim) # hatband
		# Eyes / shadow
		draw_rect(Rect2(-10, -46, 20, 2), Color("000000"))
		if disabled:
			# Pixel stun stars
			draw_rect(Rect2(-8, -66, 4, 4), gold_trim)
			draw_rect(Rect2(4, -68, 4, 4), gold_trim)
	else:
		# Pixelated Standard Guard
		var armor_col := Color("182333") if not disabled else Color("2a3442")
		var visor_col := Color("e04545") if not disabled else Color("594040")
		var shadow_col := Color("0d141e")

		# Boots / legs
		draw_rect(Rect2(-12, -8, 8, 8), shadow_col)
		draw_rect(Rect2(4, -8, 8, 8), shadow_col)
		# Torso / tactical vest
		draw_rect(Rect2(-14, -36, 28, 28), armor_col)
		draw_rect(Rect2(-10, -32, 20, 18), shadow_col)
		# Helmet
		draw_rect(Rect2(-12, -48, 24, 12), armor_col)
		# Red visor horizontal pixel slit
		draw_rect(Rect2(-10, -42, 20, 4), visor_col)
		if disabled:
			draw_rect(Rect2(-2, -56, 4, 4), Color("e8d07a"))
