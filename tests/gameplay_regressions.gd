extends SceneTree

var failures := 0

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

func run() -> void:
	var gm = root.get_node("GameManager")
	var rewind = root.get_node("RewindManager")
	for stage in [2,5]:
		gm.load_level(stage)
		await process_frame
		await process_frame
		await ticks(30)
		var level := current_scene
		var guard = level.get_node("Guard" if stage == 2 else "BossGuard")
		var crate = level.get_node("CrateTrap" if stage == 2 else "BossCrateTrap")
		var player = level.get_node("Player")
		var before: Vector2 = guard.position
		var timer: float = crate.time_elapsed
		paused = true
		await ticks(20)
		check(guard.position == before and crate.time_elapsed == timer, "Stage %d: pause freezes guard and trap" % stage)
		paused = false
		# Isolate crate/guard contact beneath the real level's release shaft.
		guard.position.x = crate.position.x
		guard.speed = 0
		crate.trigger_trap()
		await ticks(100)
		check(crate.landed and crate.position.y > 500, "Stage %d: crate reaches lower floor past catwalks" % stage)
		check(guard.disabled, "Stage %d: falling crate disables guard" % stage)
		# Contact death in a fresh level, independent of the disabled guard.
		gm.load_level(stage)
		await process_frame
		await process_frame
		await ticks(10)
		level = current_scene
		guard = level.get_node("Guard" if stage == 2 else "BossGuard")
		player = level.get_node("Player")
		player.position = guard.position + Vector2(35,-25)
		Input.action_press("move_left")
		await ticks(20)
		Input.action_release("move_left")
		check(player.dead, "Stage %d: active guard contact kills player" % stage)
	gm.load_level(3)
	await process_frame
	await process_frame
	await ticks(5)
	var electric = current_scene.get_node("ElectricTrap1")
	var victim = current_scene.get_node("Player")
	electric.time_elapsed = 0.6 # After the new half-second charging warning.
	victim.position = electric.position + Vector2(0, -47)
	await ticks(3)
	check(victim.dead, "Active electrical hazard kills on physical overlap")
	victim.dead = false
	victim.velocity = Vector2.ZERO
	victim.position = electric.position + Vector2(0, -47)
	electric.time_elapsed = 1.2
	await ticks(3)
	check(not victim.dead, "Inactive electrical hazard permits contact")
	gm.new_game()
	await process_frame
	await process_frame
	await ticks(40)
	var level := current_scene
	var player = level.get_node("Player")
	var evidence = level.get_node("Evidence")
	player.position = evidence.position
	await ticks(6)
	check(evidence.collected and not level.exit_door.locked, "Evidence contact unlocks exit")
	Input.action_press("rewind")
	await ticks(15)
	level._on_exit_reached()
	await process_frame
	check(current_scene == level and gm.evidence_count == 0, "Rewind cannot complete or commit level")
	Input.action_release("rewind")
	await ticks(3)
	await process_frame
	check(not evidence.collected and not level.level_evidence_collected and level.exit_door.locked, "Rewinding collection restores evidence and locks exit")
	player.die()
	await ticks(1)
	var history_size: int = rewind.history.size()
	await ticks(200)
	check(rewind.history.size() == history_size and history_size > 0, "Death prompt preserves living rewind history")
	Input.action_press("rewind")
	await ticks(5)
	Input.action_release("rewind")
	await ticks(2)
	check(not player.dead, "Rewind recovers death after waiting over three seconds")
	print("GAMEPLAY REGRESSIONS failures=", failures)
	quit(failures)
