extends Node

# BounceFlux neo-noir procedural audio manager.
# Autoloaded as AudioManager. Handles polyphonic SFX voice pool, music streaming,
# pause-safety (PROCESS_MODE_ALWAYS), M-key mute toggle, and browser audio unlocking.

const SFX_PATH := "res://assets/audio/sfx/"
const MUSIC_PATH := "res://assets/audio/music/"

const SFX_VOLUME_DB := -6.0
const MUSIC_VOLUME_DB := -14.0

var _sfx_cache: Dictionary = {}
var _music_cache: Dictionary = {}

var _voice_pool: Array[AudioStreamPlayer] = []
var _voice_index: int = 0
var _music_player: AudioStreamPlayer
var _rewind_loop_player: AudioStreamPlayer

var is_muted: bool = false
var audio_unlocked: bool = false
var pending_music: String = "noir_theme"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_audio_buses()
	_create_players()
	_preload_audio()
	# In desktop builds, audio is already unlocked; in web, unlock on first keypress
	if not OS.has_feature("web"):
		audio_unlocked = true
		play_music("noir_theme")

func _input(event: InputEvent) -> void:
	if not audio_unlocked:
		if event is InputEventKey and event.is_pressed():
			audio_unlocked = true
			if pending_music != "":
				play_music(pending_music)

	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_M:
			toggle_mute()

func _setup_audio_buses() -> void:
	if AudioServer.get_bus_index("SFX") == -1:
		var sfx_bus := AudioServer.bus_count
		AudioServer.add_bus(sfx_bus)
		AudioServer.set_bus_name(sfx_bus, "SFX")
		AudioServer.set_bus_volume_db(sfx_bus, SFX_VOLUME_DB)
	if AudioServer.get_bus_index("Music") == -1:
		var music_bus := AudioServer.bus_count
		AudioServer.add_bus(music_bus)
		AudioServer.set_bus_name(music_bus, "Music")
		AudioServer.set_bus_volume_db(music_bus, MUSIC_VOLUME_DB)

func _create_players() -> void:
	for i in range(8):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_voice_pool.append(p)

	_rewind_loop_player = AudioStreamPlayer.new()
	_rewind_loop_player.bus = "SFX"
	_rewind_loop_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_rewind_loop_player)

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_player)

func _preload_audio() -> void:
	var sfx_files: Array[String] = [
		"jump", "bounce", "land", "evidence_collect", "checkpoint",
		"hit", "death", "rewind_start", "rewind_loop", "rewind_end",
		"power_node_hum", "arc_zap", "guard_alert", "guard_shoot",
		"guard_defeat", "portal", "stage_clear", "ui_move", "ui_select", "ui_back"
	]
	for sname: String in sfx_files:
		var p: String = SFX_PATH + sname + ".wav"
		if ResourceLoader.exists(p):
			_sfx_cache[sname] = load(p)

	var m_path: String = MUSIC_PATH + "noir_theme.wav"
	if ResourceLoader.exists(m_path):
		_music_cache["noir_theme"] = load(m_path)

func play_sfx(sname: String, pitch_variation: float = 0.0) -> void:
	if not _sfx_cache.has(sname):
		return
	var stream: AudioStream = _sfx_cache[sname]
	var player := _voice_pool[_voice_index]
	_voice_index = (_voice_index + 1) % _voice_pool.size()

	player.stop()
	player.stream = stream
	if pitch_variation > 0.0:
		player.pitch_scale = randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
	else:
		player.pitch_scale = 1.0
	player.play()

func play_music(mname: String = "noir_theme") -> void:
	pending_music = mname
	if not audio_unlocked and OS.has_feature("web"):
		return
	if not _music_cache.has(mname):
		return
	var stream: AudioStream = _music_cache[mname]
	if _music_player.stream != stream or not _music_player.playing:
		_music_player.stream = stream
		_music_player.play()

func start_rewind_loop() -> void:
	if _sfx_cache.has("rewind_loop"):
		_rewind_loop_player.stream = _sfx_cache["rewind_loop"]
		if not _rewind_loop_player.playing:
			_rewind_loop_player.play()

func stop_rewind_loop() -> void:
	if _rewind_loop_player.playing:
		_rewind_loop_player.stop()

func toggle_mute() -> void:
	is_muted = not is_muted
	var master_idx := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(master_idx, is_muted)

func _exit_tree() -> void:
	for p in _voice_pool:
		if is_instance_valid(p):
			p.queue_free()
	_voice_pool.clear()
	if is_instance_valid(_music_player):
		_music_player.queue_free()
	if is_instance_valid(_rewind_loop_player):
		_rewind_loop_player.queue_free()
	_sfx_cache.clear()
	_music_cache.clear()
