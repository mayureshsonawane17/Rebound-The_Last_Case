extends SceneTree

# Real movement, jumps, collisions, collection and exits; no player teleporting.
var failures := 0
var gm: Node

func _initialize() -> void:
	run.call_deferred()

func steer(player: Node2D, target: float) -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	if absf(target - player.position.x) > 5:
		Input.action_press("move_right" if target > player.position.x else "move_left")

func travel(target: Vector2, jump: bool) -> bool:
	var level := current_scene
	var player = level.get_node("Player")
	Input.action_release("jump")
	await physics_frame
	if gm.current_level == 5 and target.x == 700:
		# The crate now honors its warning delay; wait for its descent before
		# crossing the marked drop shaft, just as a player would.
		for wait_tick in range(180):
			if level.get_node("BossCrateTrap").landed:
				break
			await physics_frame
	if gm.current_level == 1 and target.x == 900:
		for wait_tick in range(300):
			steer(player, level.platform.position.x + 20)
			await physics_frame
			if player.is_on_floor() and level.platform.position.x > 650 and cos(level.platform.phase) > 0:
				break
	if jump:
		Input.action_press("jump")
	for tick in range(240):
		var aim := target.x
		if gm.current_level == 1 and target.x == 620:
			aim = level.platform.position.x
		steer(player, aim)
		await physics_frame
		if tick == 2:
			Input.action_release("jump")
		if current_scene != level:
			return true
		if player.dead:
			break
		if tick > 5 and player.is_on_floor() and absf(player.position.x - aim) < 14 and absf(player.position.y - target.y) < 65:
			Input.action_release("move_left")
			Input.action_release("move_right")
			return true
	push_error("Route failed: stage %d target %s actual %s dead=%s" % [gm.current_level, target, player.position, player.dead])
	failures += 1
	Input.action_release("jump")
	Input.action_release("move_left")
	Input.action_release("move_right")
	return false

func run() -> void:
	gm = root.get_node("GameManager")
	# x, expected standing y, jump (1) or walk (0).
	var routes := [
		[[300,558,0],[350,466,1],[620,446,1],[900,446,1],[950,446,0],[1180,558,1]],
		[[180,598,0],[230,486,1],[400,366,1],[500,366,0],[700,286,1],[800,286,0],[1030,426,1],[1080,426,0],[1230,598,1]],
		[[200,578,0],[420,543,1],[660,483,1],[680,326,1],[920,543,1],[1140,578,1],[1200,578,0]],
		[[180,548,0],[290,527,1],[430,483,1],[650,417,1],[820,343,1],[890,343,0],[1130,508,1],[1190,508,0]],
		[[140,598,0],[200,466,1],[230,466,0],[390,326,1],[575,326,0],[700,598,1],[900,446,1],[950,446,0],[1190,598,1]]
	]
	for stage in range(1,6):
		gm.load_level(stage)
		await process_frame
		await process_frame
		for tick in range(40):
			await physics_frame
		var ok := true
		for point in routes[stage-1]:
			if gm.current_level != stage:
				break
			if not await travel(Vector2(point[0],point[1]), point[2] == 1):
				ok = false
				break
		for tick in range(5):
			await physics_frame
		if ok and gm.current_level == stage + 1:
			print("PASS: Stage %d completed using movement and physical evidence/exit contact" % stage)
		elif ok:
			failures += 1
			push_error("Stage %d route did not complete" % stage)
	print("LEVEL ROUTES failures=", failures)
	quit(failures)
