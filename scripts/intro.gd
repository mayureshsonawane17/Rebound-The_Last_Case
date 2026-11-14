extends Control

@onready var video_player: VideoStreamPlayer = $VideoStreamPlayer
@onready var skip_label: Label = $SkipLabel

var _has_advanced: bool = false

func _ready() -> void:
	if AudioManager:
		AudioManager.stop_music()
	video_player.finished.connect(_on_video_finished)
	video_player.play()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_Q or event.keycode == KEY_Q:
			_advance()
		elif event.is_action_pressed("ui_cancel") or event.physical_keycode == KEY_ESCAPE:
			_advance()

func _on_video_finished() -> void:
	_advance()

func _advance() -> void:
	if _has_advanced:
		return
	_has_advanced = true
	if video_player:
		video_player.stop()
	if AudioManager:
		AudioManager.play_music()
	GameManager.new_game()
