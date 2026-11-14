extends CharacterBody2D

signal trap_triggered
signal trap_landed

enum TrapType { CRATE, ELECTRICAL, CRUSH_BLOCK }
enum CrateState { READY, WARNING, FALLING, IMPACT, RESETTING }
enum ElectricPhase { CHARGING, DISCHARGE, COOLDOWN }

const ELECTRIC_SIZE := Vector2(40, 60)

@export var trap_type: TrapType = TrapType.CRATE
@export var trigger_delay: float = 0.2
@export var fall_speed: float = 750.0
@export var cycle_time: float = 2.0
@export var texture: Texture2D
@export_range(0.1, 10.0, 0.1) var reset_delay: float = 1.25

var initial_position: Vector2 = Vector2.ZERO
var triggered: bool = false
var landed: bool = false
var time_elapsed: float = 0.0
var active_hazard: bool = false
var crate_state: CrateState = CrateState.READY
var state_time: float = 0.0
var electric_phase: ElectricPhase = ElectricPhase.CHARGING
var hit_flash: float = 0.0

func _ready() -> void:
	add_to_group("rewindable")
	add_to_group("traps")
	initial_position = position
	if trap_type == TrapType.ELECTRICAL:
		# The visible field is queried explicitly; the emitter must not block
		# the safe cooldown route or push players outside its damage region.
		collision_layer = 0
		collision_mask = 0
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
	hit_flash = maxf(0.0, hit_flash - delta)

	match trap_type:
		TrapType.CRATE:
			_process_crate(delta)
		TrapType.ELECTRICAL:
			_process_electrical(delta)
		TrapType.CRUSH_BLOCK:
			_process_crush_block(delta)

	queue_redraw()

func _process_crate(delta: float) -> void:
	state_time += delta
	if crate_state == CrateState.WARNING:
		if state_time >= maxf(0.0, trigger_delay):
			_set_crate_state(CrateState.FALLING)
	elif crate_state == CrateState.FALLING:
		velocity.y = move_toward(velocity.y, fall_speed, 1200.0 * delta)
		var collision := move_and_collide(velocity * delta)
		if collision:
			_set_crate_state(CrateState.IMPACT)
			velocity = Vector2.ZERO
			trap_landed.emit()
			var collider := collision.get_collider()
			if collider:
				if collider.has_method("knock_out"):
					collider.knock_out()
				elif collider.is_in_group("player") or collider.name == "Player":
					collider.die()
	elif crate_state == CrateState.IMPACT:
		if state_time >= reset_delay:
			_set_crate_state(CrateState.RESETTING)
	elif crate_state == CrateState.RESETTING:
		reset_trap()
	else:
		velocity = Vector2.ZERO

func _set_crate_state(next_state: CrateState) -> void:
	crate_state = next_state
	state_time = 0.0
	triggered = next_state != CrateState.READY
	landed = next_state == CrateState.IMPACT or next_state == CrateState.RESETTING

func reset_trap() -> bool:
	if trap_type != TrapType.CRATE or RewindManager.is_rewinding or get_tree().paused:
		return false
	var collider := $CollisionShape2D as CollisionShape2D
	var destination := global_transform
	destination.origin = get_parent().to_global(initial_position)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collider.shape
	query.transform = destination * collider.transform
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.margin = 0.1
	if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
		# Leave the box where it landed and retry; never materialize in a body.
		return false
	position = initial_position
	velocity = Vector2.ZERO
	time_elapsed = 0.0
	_set_crate_state(CrateState.READY)
	queue_redraw()
	return true

func _update_electric_phase() -> void:
	var cycle_pos: float = fposmod(time_elapsed, maxf(cycle_time, 0.2)) / maxf(cycle_time, 0.2)
	if cycle_pos < 0.25:
		electric_phase = ElectricPhase.CHARGING
	elif cycle_pos < 0.60:
		electric_phase = ElectricPhase.DISCHARGE
	else:
		electric_phase = ElectricPhase.COOLDOWN
	active_hazard = electric_phase == ElectricPhase.DISCHARGE

func _process_electrical(_delta: float) -> void:
	_update_electric_phase()

	if active_hazard:
		# Check overlap with player
		var space_state := get_world_2d().direct_space_state
		var query := PhysicsShapeQueryParameters2D.new()
		var shape := RectangleShape2D.new()
		shape.size = ELECTRIC_SIZE
		query.shape = shape
		query.transform = global_transform
		query.collision_mask = 2 # Player layer
		var results := space_state.intersect_shape(query, 1)
		for res in results:
			var collider = res.collider
			if collider and (collider.is_in_group("player") or collider.name == "Player"):
				if not collider.dead:
					collider.die()
					hit_flash = 0.15

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
	if RewindManager.is_rewinding or get_tree().paused:
		return
	if not triggered:
		_set_crate_state(CrateState.WARNING)
		trap_triggered.emit()

func capture_rewind_state() -> Dictionary:
	return {
		"position": position,
		"velocity": velocity,
		"triggered": triggered,
		"landed": landed,
		"time_elapsed": time_elapsed,
		"active_hazard": active_hazard,
		"crate_state": crate_state,
		"state_time": state_time,
		"electric_phase": electric_phase,
		"hit_flash": hit_flash
	}

func restore_rewind_state(state: Dictionary) -> void:
	position = state.position
	velocity = state.velocity
	triggered = state.triggered
	landed = state.landed
	time_elapsed = state.time_elapsed
	active_hazard = state.active_hazard
	crate_state = state.crate_state
	state_time = state.state_time
	electric_phase = state.electric_phase
	hit_flash = state.hit_flash
	queue_redraw()

func _draw() -> void:
	match trap_type:
		TrapType.CRATE:
			if texture:
				draw_texture_rect(texture, Rect2(-24, -24, 48, 48), false)
				if crate_state == CrateState.WARNING:
					var warning_alpha := 0.5 + 0.5 * sin(state_time * 30.0)
					draw_rect(Rect2(-24, -24, 48, 48), Color(0.94, 0.78, 0.45, warning_alpha), false, 2)
				elif crate_state == CrateState.RESETTING:
					draw_rect(Rect2(-24, -24, 48, 48), Color("48d9e8"), false, 2)
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
			if crate_state == CrateState.WARNING:
				var warning_alpha := 0.5 + 0.5 * sin(state_time * 30.0)
				draw_rect(Rect2(-24, -24, 48, 48), Color(0.94, 0.78, 0.45, warning_alpha), false, 2)
			elif crate_state == CrateState.RESETTING:
				draw_rect(Rect2(-24, -24, 48, 48), Color("48d9e8"), false, 2)

		TrapType.ELECTRICAL:
			# Pixelated electrical emitter node
			draw_rect(Rect2(-16, -28, 32, 56), Color("121926"))
			draw_rect(Rect2(-12, -24, 24, 48), Color("1a2436"))
			draw_rect(Rect2(-14, -28, 28, 6), Color("2c3b54"))
			draw_rect(Rect2(-14, 22, 28, 6), Color("2c3b54"))
			if texture:
				draw_texture_rect(texture, Rect2(-24, -28, 48, 56), false)
			var field := Rect2(-ELECTRIC_SIZE / 2, ELECTRIC_SIZE)
			if electric_phase == ElectricPhase.CHARGING:
				var charge := fposmod(time_elapsed, maxf(cycle_time, 0.2)) / (maxf(cycle_time, 0.2) * 0.25)
				draw_rect(field, Color(0.94, 0.78, 0.45, 0.15 + charge * 0.25))
				draw_rect(field, Color("f0c674"), false, 1)
				draw_rect(Rect2(-16, 23, 32 * charge, 3), Color("f0c674"))

			if active_hazard:
				# Filled outline is exactly the damaging rectangle, including corners.
				draw_rect(field, Color(0.28, 0.85, 0.91, 0.3))
				draw_rect(field, Color("48d9e8"), false, 1)
				# Stepped cyan pixel lightning bolt
				var cyan_core := Color("61e3ec")
				var cyan_glow := Color(0.2, 0.8, 0.95, 0.3)
				draw_rect(Rect2(-10, -18, 20, 36), cyan_glow)
				draw_rect(Rect2(-6, -18, 4, 10), cyan_core)
				draw_rect(Rect2(-2, -10, 8, 4), cyan_core)
				draw_rect(Rect2(2, -8, 4, 12), cyan_core)
				draw_rect(Rect2(-4, 2, 8, 4), cyan_core)
				draw_rect(Rect2(-4, 4, 4, 12), cyan_core)
				var arc_shift: int = (int(time_elapsed * 24.0) % 3 - 1) * 4
				draw_polyline(PackedVector2Array([Vector2(-18,-28),Vector2(arc_shift,-12),Vector2(-arc_shift,10),Vector2(18,28)]), cyan_core, 2)
			else:
				draw_rect(Rect2(-2, -2, 4, 4), Color("e04545"))
			if hit_flash > 0.0:
				draw_rect(field, Color("e9edf2"), false, 3)

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
