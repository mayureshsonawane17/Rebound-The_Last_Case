@tool
extends Node2D

@export var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()
@export var background_color: Color = Color("#101827"):
	set(value):
		background_color = value
		queue_redraw()
@export var near_color: Color = Color("#1D2940"):
	set(value):
		near_color = value
		queue_redraw()
@export var far_color: Color = Color("#0a0f17"):
	set(value):
		far_color = value
		queue_redraw()
@export var enable_rain: bool = true
@export var enable_vignette: bool = true

var _time: float = 0.0
var _rain: CPUParticles2D

func _ready() -> void:
	if not Engine.is_editor_hint() and enable_rain:
		_setup_rain()
	queue_redraw()

func _setup_rain() -> void:
	if has_node("RainParticles"):
		return
	_rain = CPUParticles2D.new()
	_rain.name = "RainParticles"
	_rain.z_index = 5
	_rain.amount = 60
	_rain.lifetime = 1.4
	_rain.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_rain.emission_rect_extents = Vector2(700, 10)
	_rain.position = Vector2(640, -20)
	_rain.direction = Vector2(-0.25, 1.0).normalized()
	_rain.spread = 4.0
	_rain.gravity = Vector2(0, 400)
	_rain.initial_velocity_min = 550.0
	_rain.initial_velocity_max = 700.0
	_rain.scale_amount_min = 1.0
	_rain.scale_amount_max = 2.0
	_rain.color = Color(0.28, 0.85, 0.91, 0.32)
	add_child(_rain)

func _process(delta: float) -> void:
	_time += delta
	if not Engine.is_editor_hint():
		queue_redraw()

func _draw() -> void:
	if texture:
		draw_texture_rect(texture, Rect2(0, 0, 1280, 720), false)
		_draw_overlays()
		return

	# Deep space sky
	draw_rect(Rect2(0, 0, 1280, 720), background_color)

	# ── 1. Far Parallax Layer (Distant Towers & Beacons) ──
	var far_sky_col := far_color
	for i in range(16):
		var bx: float = i * 85 - 20
		var bh: float = 380 + ((i * 47) % 180)
		draw_rect(Rect2(bx, 720 - bh, 70, bh), far_sky_col)
		if (i % 3) == 0:
			draw_rect(Rect2(bx + 33, 720 - bh - 6, 4, 6), Color("#E66B55"))

	# ── 2. Mid Parallax Layer (Noir Skyscrapers with Flickering Windows) ──
	var mid_col := Color("#141d2d")
	for i in range(11):
		var bx: float = i * 125 - 35
		var bh: float = 280 + ((i * 61) % 220)
		draw_rect(Rect2(bx, 720 - bh, 105, bh), mid_col)
		draw_rect(Rect2(bx, 720 - bh, 105, 2), Color("#2c3b54"))

		for wy in range(int(720 - bh + 16), 680, 24):
			for wx in range(int(bx + 12), int(bx + 90), 18):
				var seed_val: int = wy * 31 + wx * 17 + i * 101
				var is_window: bool = (seed_val % 4) == 0
				if is_window:
					var flicker: float = sin(_time * 2.5 + float(seed_val % 10))
					var win_col: Color
					if (seed_val % 7) == 0:
						win_col = Color("#48D9E8") if flicker > -0.2 else Color("#1a3542")
					else:
						win_col = Color("#F0C674") if flicker > 0.0 else Color("#3d3420")
					draw_rect(Rect2(wx, wy, 8, 12), win_col)

	# ── 3. Near Parallax Layer (Industrial Silhouettes) ──
	for i in range(8):
		var bx: float = i * 175 - 20
		var bh: float = 160 + ((i * 39) % 120)
		draw_rect(Rect2(bx, 720 - bh, 140, bh), near_color)
		draw_rect(Rect2(bx, 720 - bh, 140, 2), Color("#3e5274"))

	_draw_overlays()

func _draw_overlays() -> void:
	for y in range(0, 720, 4):
		draw_rect(Rect2(0, y, 1280, 1), Color(0.0, 0.0, 0.0, 0.08))

	if enable_vignette:
		var vig_col := Color(0.04, 0.06, 0.1, 0.35)
		draw_rect(Rect2(0, 0, 1280, 16), vig_col)
		draw_rect(Rect2(0, 704, 1280, 16), vig_col)
		draw_rect(Rect2(0, 16, 24, 688), vig_col)
		draw_rect(Rect2(1256, 16, 24, 688), vig_col)

	if RewindManager and RewindManager.is_rewinding:
		draw_rect(Rect2(0, 0, 1280, 720), Color(0.28, 0.85, 0.91, 0.14))
