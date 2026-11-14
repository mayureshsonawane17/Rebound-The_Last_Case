extends SceneTree

var failures: int = 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	print("--- TESTING INTRO CUTSCENE & Q SKIP ---")
	var intro_scene: PackedScene = load("res://scenes/intro.tscn")
	check(intro_scene != null, "Intro scene must exist and load")
	
	var intro_inst: Control = intro_scene.instantiate()
	root.add_child(intro_inst)
	await process_frame
	
	var player_node: VideoStreamPlayer = intro_inst.get_node("VideoStreamPlayer")
	check(player_node != null, "VideoStreamPlayer must exist")
	check(player_node.stream != null, "VideoStream must be assigned")
	
	var skip_label: Label = intro_inst.get_node("SkipLabel")
	check(skip_label != null, "Skip label must exist")
	check("Q" in skip_label.text, "Skip label must mention [Q] key")
	
	# Simulate pressing Q key
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_Q
	ev.pressed = true
	intro_inst._unhandled_input(ev)
	
	check(intro_inst._has_advanced, "Pressing Q must trigger _advance()")
	intro_inst.queue_free()
	
	print("INTRO SMOKE FAILURES = ", failures)
	quit(failures)
