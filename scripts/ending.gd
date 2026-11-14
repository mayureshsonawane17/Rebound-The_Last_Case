extends Control

@onready var center_box: Control = $Center
@onready var restart_btn: Button = $Center/VBox/RestartBtn
@onready var menu_btn: Button = $Center/VBox/MenuBtn
@onready var outro_player: VideoStreamPlayer = $OutroPlayer
@onready var skip_label: Label = $SkipLabel

var _outro_finished: bool = false

func _ready() -> void:
	restart_btn.pressed.connect(_on_restart_pressed)
	menu_btn.pressed.connect(_on_menu_pressed)

	if outro_player and ResourceLoader.exists("res://assets/video/outro.ogv"):
		if AudioManager:
			AudioManager.stop_music()
		center_box.visible = false
		skip_label.visible = true
		outro_player.visible = true
		outro_player.finished.connect(_on_outro_finished)
		outro_player.play()
	else:
		_show_results()

func _unhandled_input(event: InputEvent) -> void:
	if not _outro_finished:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode == KEY_Q or event.keycode == KEY_Q or event.is_action_pressed("ui_cancel") or event.physical_keycode == KEY_ESCAPE:
				_on_outro_finished()
	else:
		if event.is_action_pressed("ui_accept"):
			_on_restart_pressed()

func _on_outro_finished() -> void:
	if _outro_finished:
		return
	_outro_finished = true
	if outro_player:
		outro_player.stop()
		outro_player.visible = false
	if skip_label:
		skip_label.visible = false
	_show_results()

func _show_results() -> void:
	_outro_finished = true
	center_box.visible = true
	restart_btn.grab_focus()
	if AudioManager:
		AudioManager.play_music("noir_theme")

func _on_restart_pressed() -> void:
	GameManager.new_game()

func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
