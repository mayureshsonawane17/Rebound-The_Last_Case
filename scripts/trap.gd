extends CharacterBody2D

signal trap_triggered
signal trap_landed

enum TrapType { CRATE, ELECTRICAL, CRUSH_BLOCK }

@export var trap_type: TrapType = TrapType.CRATE
@export var trigger_delay: float = 0.2
@export var fall_speed: float = 750.0
@export var cycle_time: float = 2.0
@export var texture: Texture2D

var initial_position: Vector2 = Vector2.ZERO
var triggered: bool = false
var landed: bool = false
var time_elapsed: float = 0.0
var active_hazard: bool = false

func _ready() -> void:
	add_to_group("rewindable")
	add_to_group("traps")
	initial_position = position
	if not texture:
		match trap_type:
			TrapType.CRATE:
				if ResourceLoader.exists("res://assets/sprites/props/crate/00.png"):
					texture = load("res://assets/sprites/props/crate/00.png")
				elif ResourceLoader.exists("res://assets/props/crate.png"):
					texture = load("res://assets/props/crate.png")
			TrapType.ELECTRICAL:
				if ResourceLoader.exists("res://assets/sprites/hazards/power_node/00.png"):
					texture = load("res://assets/sprites/hazards/power_node/00.png")
				elif ResourceLoader.exists("res://assets/props/hazard_electric.png"):
					texture = load("res://assets/props/hazard_electric.png")

func _physics_process(delta: float) -> void:
	if RewindManager.is_rewinding:
		queue_redraw()
		return

	time_elapsed += delta

	match trap_type:
		TrapType.CRATE:
			_process_crate(delta)
		TrapType.ELECTRICAL:
			_process_electrical(delta)
		TrapType.CRUSH_BLOCK:
			_process_crush_block(delta)

	queue_redraw()

func _process_crate(delta: float) -> void:
	if triggered and not landed:
		velocity.y = move_toward(velocity.y, fall_speed, 1200.0 * delta)
		var collision := move_and_collide(velocity * delta)
		if collision:
			landed = true
			velocity = Vector2.ZERO
			trap_landed.emit()
			var collider := collision.get_collider()
			if collider:
				if collider.has_method("knock_out"):
					collider.knock_out()
				elif collider.is_in_group("player") or collider.name == "Player":
					if "dead" in collider:
						collider.dead = true
	else:
		velocity = Vector2.ZERO

func _process_electrical(delta: float) -> void:
	# Cycles on and off deterministically based on cycle_time
	var cycle_pos: float = fmod(time_elapsed, cycle_time)
	var was_active := active_hazard
	active_hazard = cycle_pos < (cycle_time * 0.5)

	if active_hazard:
		# Check overlap with player
		var space_state := get_world_2d().direct_space_state
		var query := PhysicsShapeQueryParameters2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(40, 60)
		query.shape = shape
		query.transform = transform
		query.collision_mask = 2 # Player layer
		var results := space_state.intersect_shape(query, 1)
		for res in results:
			var collider = res.collider
			if collider and (collider.is_in_group("player") or collider.name == "Player"):
				if "dead" in collider:
					collider.dead = true

func _process_crush_block(delta: float) -> void:
	# Periodic descending block (e.g. Headquarters / rooftops)
	var t: float = sin(time_elapsed * 2.0)
	var target_y := initial_position.y + maxf(0.0, t) * 160.0
	position.y = target_y
	
	# Check collision with player below
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()
		if collider and (collider.is_in_group("player") or collider.name == "Player"):
			if collision.get_normal().y < -0.5: # Crushing down
				if "dead" in collider:
					collider.dead = true

func trigger_trap() -> void:
	if not triggered:
		triggered = true
		trap_triggered.emit()

func capture_rewind_state() -> Dictionary:
	return {
		"position": position,
		"velocity": velocity,
		"triggered": triggered,
		"landed": landed,
		"time_elapsed": time_elapsed,
		"active_hazard": active_hazard
	}

func restore_rewind_state(state: Dictionary) -> void:
	position = state.position
	velocity = state.velocity
	triggered = state.triggered
	landed = state.landed
	time_elapsed = state.time_elapsed
	active_hazard = state.active_hazard
	queue_redraw()

func _draw() -> void:
	match trap_type:
		TrapType.CRATE:
			if texture:
				draw_texture_rect(texture, Rect2(-24, -24, 48, 48), false)
				return
			# Pixelated shipping crate (48x48)
			var wood_dark := Color("543216")
			var wood_mid := Color("855127")
			var wood_light := Color("a66b37")
			# Outer rim
			draw_rect(Rect2(-24, -24, 48, 48), wood_dark)
			draw_rect(Rect2(-20, -20, 40, 40), wood_mid)
			# Pixel corner reinforcements
			draw_rect(Rect2(-24, -24, 8, 8), wood_dark)
			draw_rect(Rect2(16, -24, 8, 8), wood_dark)
			draw_rect(Rect2(-24, 16, 8, 8), wood_dark)
			draw_rect(Rect2(16, 16, 8, 8), wood_dark)
			# Stepped pixel diagonal braces
			for i in range(-16, 16, 4):
				draw_rect(Rect2(i, i, 4, 4), wood_dark)
				draw_rect(Rect2(-i - 4, i, 4, 4), wood_dark)
			# Center plank highlight
			draw_rect(Rect2(-16, -2, 32, 4), wood_light)

		TrapType.ELECTRICAL:
			if texture:
				draw_texture_rect(texture, Rect2(-24, -28, 48, 56), false)
				if active_hazard:
					var cyan_glow := Color(0.2, 0.8, 0.95, 0.35)
					draw_rect(Rect2(-16, -20, 32, 40), cyan_glow)
				else:
					draw_rect(Rect2(-3, -3, 6, 6), Color("e04545"))
				return

			# Pixelated electrical emitter node
			draw_rect(Rect2(-16, -28, 32, 56), Color("121926"))
			draw_rect(Rect2(-12, -24, 24, 48), Color("1a2436"))
			draw_rect(Rect2(-14, -28, 28, 6), Color("2c3b54"))
			draw_rect(Rect2(-14, 22, 28, 6), Color("2c3b54"))

			if active_hazard:
				# Stepped cyan pixel lightning bolt
				var cyan_core := Color("61e3ec")
				var cyan_glow := Color(0.2, 0.8, 0.95, 0.3)
				draw_rect(Rect2(-10, -18, 20, 36), cyan_glow)
				draw_rect(Rect2(-6, -18, 4, 10), cyan_core)
				draw_rect(Rect2(-2, -10, 8, 4), cyan_core)
				draw_rect(Rect2(2, -8, 4, 12), cyan_core)
				draw_rect(Rect2(-4, 2, 8, 4), cyan_core)
				draw_rect(Rect2(-4, 4, 4, 12), cyan_core)
			else:
				draw_rect(Rect2(-2, -2, 4, 4), Color("e04545"))

		TrapType.CRUSH_BLOCK:
			# Pixelated metal crush block
			draw_rect(Rect2(-32, -32, 64, 64), Color("1e2633"))
			draw_rect(Rect2(-28, -28, 56, 56), Color("2d394d"))
			# Stepped pixel hazard stripes
			draw_rect(Rect2(-24, 20, 12, 8), Color("e9ae55"))
			draw_rect(Rect2(-4, 20, 12, 8), Color("e9ae55"))
			draw_rect(Rect2(16, 20, 12, 8), Color("e9ae55"))
			draw_rect(Rect2(-26, -26, 4, 4), Color("0f141c"))
			draw_rect(Rect2(22, -26, 4, 4), Color("0f141c"))
