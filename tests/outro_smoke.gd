extends SceneTree

var failures: int = 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	print("--- TESTING OUTRO CUTSCENE & Q SKIP ---")
	var ending_scene: PackedScene = load("res://scenes/ending.tscn")
	check(ending_scene != null, "Ending scene must exist and load")
	
	var ending_inst: Control = ending_scene.instantiate()
	root.add_child(ending_inst)
	await process_frame
	
	var outro_node: VideoStreamPlayer = ending_inst.get_node("OutroPlayer")
	check(outro_node != null, "Outro VideoStreamPlayer must exist")
	check(outro_node.stream != null, "VideoStream must be assigned")
	
	var skip_label: Label = ending_inst.get_node("SkipLabel")
	check(skip_label != null, "Skip label must exist")
	check("Q" in skip_label.text, "Skip label must mention [Q] key")
	
	# Simulate pressing Q key
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_Q
	ev.pressed = true
	ending_inst._unhandled_input(ev)
	
	check(ending_inst._outro_finished, "Pressing Q must finish outro")
	check(ending_inst.get_node("Center").visible, "Center container must be visible after outro")
	
	ending_inst.queue_free()
	print("OUTRO SMOKE FAILURES = ", failures)
	quit(failures)
