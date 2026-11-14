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

func click_at(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = point
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)

func test_release() -> void:
	for stage in [2, 5]:
		await load_stage(stage)
		var release = current_scene.get_node("World/TrapRelease")
		var marker := release.get_node("Marker") as Polygon2D
		var collider := release.get_node("Collider") as CollisionShape2D
		var trap = current_scene.get_node("CrateTrap" if stage == 2 else "BossCrateTrap")
		trap.set_physics_process(false)
		check(collider.position == marker.position and collider.shape.size == Vector2(40,8), "Stage %d: Release touch collider exactly matches marker" % stage)
		var initial: Dictionary = trap.capture_rewind_state()
		for window_size in [Vector2i(1280,720), Vector2i(960,540), Vector2i(1920,1080)]:
			root.size = window_size
			await process_frame
			# Canvas transform includes viewport/window stretch, plus authored marker offset.
			var transform: Transform2D = marker.get_global_transform_with_canvas()
			for point in [Vector2(-20.1,0),Vector2(20.1,0),Vector2(0,-4.1),Vector2(0,4.1)]:
				trap.restore_rewind_state(initial)
				click_at(transform * point)
				check(not trap.triggered, "Stage %d: outside click %s ignored at %s" % [stage, point, window_size])
			for point in [Vector2.ZERO,Vector2(-19.9,-3.9),Vector2(19.9,3.9)]:
				trap.restore_rewind_state(initial)
				click_at(transform * point)
				check(trap.triggered, "Stage %d: inside click %s activates at %s" % [stage, point, window_size])
		trap.restore_rewind_state(initial)
		rewind.is_rewinding = true
		click_at(marker.get_global_transform_with_canvas() * Vector2.ZERO)
		check(not trap.triggered, "Release click suppressed during rewind")
		rewind.is_rewinding = false
		var player = current_scene.get_node("Player")
		player.set_physics_process(false)
		player.global_position = marker.global_position + Vector2(0,-26.1)
		await ticks(4)
		check(not trap.triggered, "Player outside compact marker cannot trigger an invisible touch zone")
		player.global_position = marker.global_position + Vector2(0,-25.5)
		await ticks(4)
		check(trap.triggered, "Player touching the visible marker can still activate it")
	root.size = Vector2i(1280,720)

func test_catwalks() -> void:
	for stage in [2,5]:
		await load_stage(stage)
		var catwalk := current_scene.get_node("World/ReleaseCatwalk") as StaticBody2D
		var collider := catwalk.get_node("Collider") as CollisionShape2D
		check(not collider.one_way_collision, "Stage %d: authored catwalk is solid" % stage)
		var player = current_scene.get_node("Player")
		player.set_physics_process(false)
		var center: Vector2 = catwalk.global_position
		var half: Vector2 = collider.shape.size / 2
		for direction in [Vector2.DOWN,Vector2.UP,Vector2.LEFT,Vector2.RIGHT]:
			var distance := (half.y if direction.y != 0 else half.x) + 60
			player.global_position = center - direction * distance
			await ticks(2)
			var hit = player.move_and_collide(direction * 120)
			check(hit != null and hit.get_collider() == catwalk, "Stage %d: swept ball collision from %s" % [stage, -direction])
		player.global_position = center + Vector2(0,70)
		player.velocity = Vector2(0,-1500)
		player.set_physics_process(true)
		await ticks(10)
		check(player.position.y >= center.y + half.y + 21 and player.velocity.y >= 0, "Actual high-speed upward player motion hits the catwalk underside")
		player.global_position = center - Vector2(0,70)
		player.velocity = Vector2(0,1500)
		await ticks(10)
		check(player.is_on_floor() and player.position.y < center.y, "Actual high-speed downward player motion lands on the catwalk")
		player.set_physics_process(false)
		var other := current_scene.get_node("World/Shelf1/Collider" if stage == 2 else "World/EntranceLedge/Collider")
		check(other.one_way_collision, "Other intentionally one-way platforms remain one-way")

func run() -> void:
	gm = root.get_node("GameManager")
	rewind = root.get_node("RewindManager")
	await test_release()
	await test_catwalks()
	print("TARGETED FIXES failures=", failures)
	quit(failures)
