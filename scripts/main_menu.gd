extends Control

@onready var start_button: Button = $Center/VBox/StartBtn
@onready var quit_button: Button = $Center/VBox/QuitBtn

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	start_button.grab_focus()
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_on_start_pressed()

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/intro.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
