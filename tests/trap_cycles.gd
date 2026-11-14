extends SceneTree

var failures := 0
var gm: Node
var rewind: Node

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func ticks(count: int) -> void:
	for tick in range(count):
		await physics_frame

func load_stage(stage: int) -> void:
	gm.load_level(stage)
	await process_frame
	await process_frame
	await ticks(3)

func wait_state(trap: Node, state: int, limit: int = 240) -> bool:
	for tick in range(limit):
		if trap.crate_state == state:
			return true
		await physics_frame
	return false

func test_electric() -> void:
	await load_stage(3)
	var pole = current_scene.get_node("ElectricTrap1")
	var player = current_scene.get_node("Player")
	player.set_physics_process(false)
	pole.time_elapsed = 0
	rewind.clear_history()
	await ticks(20)
	check(pole.electric_phase == pole.ElectricPhase.CHARGING and not pole.active_hazard, "Electric cycle starts with a safe charging warning")
	await ticks(22)
	check(pole.electric_phase == pole.ElectricPhase.DISCHARGE and pole.active_hazard, "Charge predictably becomes discharge")
	Input.action_press("rewind")
	await ticks(23)
	check(pole.electric_phase == pole.ElectricPhase.CHARGING and not pole.active_hazard, "Actual rewind reverses discharge back into charging")
	Input.action_release("rewind")
	await ticks(24)
	check(pole.active_hazard, "Releasing rewind resumes the electrical cycle")
	await ticks(40)
	check(pole.electric_phase == pole.ElectricPhase.COOLDOWN and not pole.active_hazard, "Cooldown provides a predictable safe window")
	var before: float = pole.time_elapsed
	paused = true
	await ticks(10)
	check(pole.time_elapsed == before, "Pause freezes electrical timing")
	paused = false
	# Isolate exact visible field boundaries, including a translated/rotated parent.
	var parent := Node2D.new()
	parent.position = Vector2(400,-300)
	parent.rotation = 0.3
	current_scene.add_child(parent)
	var transformed = load("res://scenes/trap.tscn").instantiate()
	transformed.trap_type = transformed.TrapType.ELECTRICAL
	transformed.position = Vector2(100,20)
	parent.add_child(transformed)
	for point in [Vector2(42.1,0),Vector2(-42.1,0),Vector2(0,52.1),Vector2(0,-52.1)]:
		player.dead = false
		player.global_position = transformed.global_transform * point
		transformed.time_elapsed = 0.7
		await ticks(3)
		check(not player.dead, "Outside visible electric field is safe: %s" % point)
	for point in [Vector2.ZERO,Vector2(41.5,0),Vector2(-41.5,0),Vector2(0,51.5),Vector2(0,-51.5)]:
		player.dead = false
		player.global_position = transformed.global_transform * point
		transformed.time_elapsed = 0.7
		await ticks(3)
		check(player.dead and transformed.hit_flash > 0, "Active visible field damages only on overlap and flashes: %s" % point)
	for time in [0.1,1.4]:
		player.dead = false
		player.global_position = transformed.global_position
		transformed.time_elapsed = time
		await ticks(3)
		check(not player.dead, "Charging/cooldown contact is safe at %.1f seconds" % time)
	# Exhaust history while holding R: no electrical clock should continue.
	player.global_position = Vector2(100,560)
	player.dead = false
	Input.action_press("rewind")
	await ticks(210)
	var frozen: float = pole.time_elapsed
	await ticks(10)
	check(pole.time_elapsed == frozen, "Electrical clock remains frozen when rewind history runs out")
	Input.action_release("rewind")
	await ticks(4)
	check(pole.time_elapsed > frozen, "Electrical clock resumes after exhausted rewind is released")

func test_crates() -> void:
	await load_stage(2)
	var crate = current_scene.get_node("CrateTrap")
	var player = current_scene.get_node("Player")
	player.set_physics_process(false)
	for guard in get_nodes_in_group("guards"):
		guard.set_physics_process(false)
	rewind.clear_history()
	await ticks(10)
	crate.trigger_trap()
	await ticks(6)
	check(crate.crate_state == crate.CrateState.WARNING and crate.position == crate.initial_position, "Crate honors warning delay without moving")
	var warning_time: float = crate.state_time
	Input.action_press("rewind")
	await ticks(3)
	check(crate.crate_state == crate.CrateState.WARNING and crate.state_time < warning_time, "Warning countdown rewinds")
	Input.action_release("rewind")
	check(await wait_state(crate,crate.CrateState.FALLING), "Warning resumes into falling")
	await ticks(12)
	var falling_y: float = crate.position.y
	var falling_speed: float = crate.velocity.y
	Input.action_press("rewind")
	await ticks(6)
	check(crate.position.y < falling_y and crate.velocity.y < falling_speed, "Falling position and velocity both rewind")
	Input.action_release("rewind")
	check(await wait_state(crate,crate.CrateState.IMPACT), "Box lands after rewind release")
	await ticks(6)
	Input.action_press("rewind")
	await ticks(3)
	check(crate.crate_state == crate.CrateState.IMPACT, "Impact state survives rewind within impact history")
	Input.action_release("rewind")
	# Occupy the reset destination with a real physics body.
	var blocker := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(60,60)
	shape.shape = rectangle
	blocker.add_child(shape)
	current_scene.add_child(blocker)
	blocker.global_position = crate.get_parent().to_global(crate.initial_position)
	check(await wait_state(crate,crate.CrateState.RESETTING), "Impact advances to resetting")
	await ticks(8)
	check(crate.position != crate.initial_position and not crate.reset_trap(), "Occupied reset destination prevents teleporting into a solid")
	Input.action_press("rewind")
	await ticks(3)
	check(crate.crate_state == crate.CrateState.RESETTING, "Reset retry state also rewinds safely")
	Input.action_release("rewind")
	await ticks(3)
	blocker.queue_free()
	await process_frame
	check(await wait_state(crate,crate.CrateState.READY), "Box automatically resets once its destination is clear")
	check(crate.position == crate.initial_position and crate.velocity == Vector2.ZERO and not crate.triggered and not crate.landed, "Reset restores position, velocity and flags")
	var impacts := [0]
	crate.trap_landed.connect(func(): impacts[0] += 1)
	for cycle in range(3):
		crate.trigger_trap()
		crate.trigger_trap()
		check(await wait_state(crate,crate.CrateState.IMPACT), "Repeat cycle %d reaches impact" % cycle)
		check(await wait_state(crate,crate.CrateState.READY), "Repeat cycle %d returns ready" % cycle)
	check(impacts[0] == 3 and get_nodes_in_group("traps").size() == 1, "Repeated triggering creates no duplicate impacts or boxes")
	crate.trigger_trap()
	await ticks(4)
	player.reset_checkpoint()
	var reset_warning_time: float = crate.state_time
	Input.action_press("rewind")
	await ticks(12)
	check(crate.state_time == reset_warning_time, "Checkpoint history reset while R is held freezes the box without corrupting its warning")
	Input.action_release("rewind")
	check(await wait_state(crate,crate.CrateState.IMPACT), "Box resumes and impacts after rewind with empty history is released")
	check(await wait_state(crate,crate.CrateState.READY), "Box rearms after checkpoint/time-control reset")
	# Already-overlapping players can rearm after a rewind restore to READY.
	var ready: Dictionary = crate.capture_rewind_state()
	player.position = current_scene.get_node("World/TrapRelease/Marker").global_position
	await ticks(4)
	check(crate.triggered, "Keyboard touch still activates the compact Release marker")
	crate.restore_rewind_state(ready)
	await ticks(3)
	check(crate.triggered, "Release rearms an already-overlapping player after restoring READY")

func test_extra_guard() -> void:
	await load_stage(2)
	var guard = current_scene.get_node("CargoGuard")
	var crate = current_scene.get_node("CrateTrap")
	check(not guard.disabled and absf(guard.position.x - 520) < 10, "Extra guard starts away from spawn in the cargo lane")
	crate.trigger_trap()
	await ticks(100)
	check(guard.disabled, "New guard can be defeated by the existing crate at natural patrol timing")
	var state: Dictionary = guard.capture_rewind_state()
	state.disabled = false
	guard.restore_rewind_state(state)
	var level := current_scene
	level._on_evidence_collected("evidence_2")
	level._on_exit_reached()
	await process_frame
	await process_frame
	check(gm.current_level == 3, "Extra guard is optional and cannot lock progression")

func run() -> void:
	gm = root.get_node("GameManager")
	rewind = root.get_node("RewindManager")
	await test_electric()
	await test_crates()
	await test_extra_guard()
	print("TRAP CYCLES failures=", failures)
	quit(failures)
