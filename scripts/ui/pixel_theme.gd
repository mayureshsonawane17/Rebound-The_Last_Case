extends RefCounted
## BounceFlux neo-noir pixel theme helper (Godot 4.x).
## No class_name on purpose: load it with
##   const PT := preload("res://scripts/ui/pixel_theme.gd")
## Everything is static; typography uses bundled, OFL-licensed fonts.

const UI_FONT := preload("res://assets/fonts/SpaceGrotesk-Regular.tres")
const HEADING_FONT := preload("res://assets/fonts/Rajdhani-Bold.ttf")

# ── Mandatory palette ────────────────────────────────────────────────
const INK := Color("#101827")     # background dark ink
const PANEL := Color("#1D2940")   # panel / secondary dark
const CYAN := Color("#48D9E8")    # rewind / time
const GOLD := Color("#F0C674")    # evidence
const RED := Color("#E66B55")     # hazard / warning
const TEXT := Color("#E9EDF2")    # off-white text


## Hard-cornered, non-antialiased pixel panel with a chunky border and a
## 3px offset drop shadow (no blur).
static func panel_box(border: Color = CYAN.darkened(0.5), bg_alpha: float = 0.88, margin: int = 10, border_w: int = 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(PANEL.r, PANEL.g, PANEL.b, bg_alpha)
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(0)
	s.anti_aliasing = false
	s.set_content_margin_all(margin)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 1
	s.shadow_offset = Vector2(3, 3)
	return s


## Darker "ink" variant, used for banners and tracks.
static func ink_box(border: Color, bg_alpha: float = 0.92, margin: int = 12, border_w: int = 2) -> StyleBoxFlat:
	var s := panel_box(border, bg_alpha, margin, border_w)
	s.bg_color = Color(INK.r, INK.g, INK.b, bg_alpha)
	return s


## Flat filled box (no border), e.g. progress fills.
static func flat_box(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(0)
	s.anti_aliasing = false
	return s


## Theme for the whole HUD tree. Also usable for future menus.
static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = UI_FONT
	t.set_default_font_size(16)

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", INK)
	t.set_constant("outline_size", "Label", 2)
	t.set_constant("line_spacing", "Label", 2)

	t.set_stylebox("panel", "PanelContainer", panel_box())

	t.set_constant("separation", "HBoxContainer", 8)
	t.set_constant("separation", "VBoxContainer", 6)

	# Handy if ProgressBars are used elsewhere in the UI.
	t.set_stylebox("background", "ProgressBar", flat_box(INK))
	t.set_stylebox("fill", "ProgressBar", flat_box(CYAN))
	t.set_color("font_color", "ProgressBar", TEXT)
	return t


# ── Pixel drawing helpers (call only from inside a _draw()) ─────────

## Rectangle with the corners stepped (notched) by 2px: classic pixel-art frame.
static func draw_notched(ci: CanvasItem, r: Rect2, c: Color) -> void:
	ci.draw_rect(Rect2(r.position.x + 2.0, r.position.y, r.size.x - 4.0, r.size.y), c)
	ci.draw_rect(Rect2(r.position.x, r.position.y + 2.0, r.size.x, r.size.y - 4.0), c)
	ci.draw_rect(Rect2(r.position.x + 1.0, r.position.y + 1.0, r.size.x - 2.0, r.size.y - 2.0), c)


## 1px crisp outline built from four strips (avoids half-pixel line widths).
static func draw_outline(ci: CanvasItem, r: Rect2, c: Color) -> void:
	ci.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1.0), c)
	ci.draw_rect(Rect2(r.position.x, r.end.y - 1.0, r.size.x, 1.0), c)
	ci.draw_rect(Rect2(r.position.x, r.position.y, 1.0, r.size.y), c)
	ci.draw_rect(Rect2(r.end.x - 1.0, r.position.y, 1.0, r.size.y), c)

