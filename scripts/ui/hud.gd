extends CanvasLayer
## BounceFlux neo-noir pixel HUD.
## Builds its UI in _ready(); bundled typography is supplied by pixel_theme.gd.
## Public contract (unchanged):
##   set_stage_name(title), set_evidence(count, total = 5), set_rewind_fraction(val),
##   set_hint(text), set_death_visible(is_dead), set_paused(is_paused)
## Every method is safe to call before the node enters the tree; state is applied in _ready().

const PT := preload("res://scripts/ui/pixel_theme.gd")

## [key, action] rows shown on the pause overlay. Edit to match your real bindings.
var pause_hints: Array = [
	["P / ESC", "RESUME"],
	["A D / ARROWS", "MOVE"],
	["SPACE / W", "JUMP"],
	["HOLD R", "REWIND TIME"],
]

# ── State (stored so setters work before _ready) ─────────────────────
var _stage := ""
var _count := 0
var _total := 5
var _rewind := 1.0
var _hint := ""
var _dead := false
var _paused := false
var _built := false
var _dead_shown := false

# ── Nodes ────────────────────────────────────────────────────────────
var _root: Control
var _stage_label: Label
var _rewind_bar: RewindBar
var _pips: EvidencePips
var _evidence_tail: Label
var _hint_panel: PanelContainer
var _hint_label: Label
var _death_layer: Control
var _death_text: Label
var _pause_layer: Control
var _death_tween: Tween


# ── Custom-drawn widgets ─────────────────────────────────────────────

## Stepped-border rewind bar: cyan fill, 1px highlight, segment ticks.
## Turns hazard red when nearly empty.
class RewindBar extends Control:
	const TICK := 10.0
	var fraction: float = 1.0:
		set(value):
			var v := clampf(value, 0.0, 1.0)
			if is_equal_approx(v, fraction):
				return
			fraction = v
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(200, 20)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var w := size.x
		var h := size.y
		PT.draw_notched(self, Rect2(0, 0, w, h), PT.CYAN.darkened(0.45))      # outer stepped border
		PT.draw_notched(self, Rect2(2, 2, w - 4, h - 4), PT.INK)              # dark track
		var inner := Rect2(4, 4, w - 8, h - 8)
		var fill_w := floorf(inner.size.x * fraction / 2.0) * 2.0             # snap to 2px steps
		if fraction > 0.0 and fill_w < 2.0:
			fill_w = 2.0
		if fill_w <= 0.0:
			return
		var col: Color = PT.CYAN if fraction > 0.2 else PT.RED
		draw_rect(Rect2(inner.position, Vector2(fill_w, inner.size.y)), col)
		draw_rect(Rect2(inner.position, Vector2(fill_w, 1.0)), col.lightened(0.55))                 # 1px highlight
		draw_rect(Rect2(inner.position.x, inner.end.y - 1.0, fill_w, 1.0), col.darkened(0.35))      # 1px underside
		var x := inner.position.x + TICK
		while x < inner.position.x + fill_w:
			draw_rect(Rect2(x, inner.position.y + 1.0, 1.0, inner.size.y - 1.0), Color(PT.INK, 0.4))
			x += TICK


## Row of evidence squares: gold filled = collected, dim outline = missing.
class EvidencePips extends Control:
	const SQ := 14
	const GAP := 6
	var count := 0
	var total := 5

	func _init() -> void:
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		configure(0, 5)

	func configure(c: int, t: int) -> void:
		count = c
		total = t
		custom_minimum_size = Vector2(maxi(t * (SQ + GAP) - GAP, 0), SQ)
		queue_redraw()

	func _draw() -> void:
		for i in total:
			var r := Rect2(i * (SQ + GAP), 0, SQ, SQ)
			if i < count:
				draw_rect(r, PT.GOLD)
				draw_rect(Rect2(r.position.x, r.position.y, SQ, 1), PT.GOLD.lightened(0.5))
				draw_rect(Rect2(r.position.x, r.end.y - 1.0, SQ, 1), PT.GOLD.darkened(0.4))
			else:
				PT.draw_outline(self, r, PT.GOLD.darkened(0.45))


# ── Lifecycle ────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 10                                   # above gameplay
	process_mode = Node.PROCESS_MODE_ALWAYS      # stay alive while the tree is paused

	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_root.theme = PT.build_theme()
	add_child(_root)

	_build_dossier()
	_build_hint()
	_build_death_banner()
	_build_pause_overlay()

	_ignore_mouse(_root)                         # keyboard-only: never intercept input
	_built = true
	_apply_all()


# ── Public contract ──────────────────────────────────────────────────

func set_stage_name(title: String) -> void:
	_stage = title
	if _built:
		_stage_label.text = title.to_upper()


func set_evidence(count: int, total: int = 5) -> void:
	var gained := count > _count
	_total = maxi(total, 1)
	_count = clampi(count, 0, _total)
	if not _built:
		return
	_pips.configure(_count, _total)
	_evidence_tail.text = "] %d/%d" % [_count, _total]
	if gained:
		var t := create_tween()
		_pips.modulate = Color(2.2, 2.0, 1.4)    # quick gold flash on pickup
		t.tween_property(_pips, "modulate", Color.WHITE, 0.35)


func set_rewind_fraction(val: float) -> void:
	_rewind = clampf(val, 0.0, 1.0)
	if _built:
		_rewind_bar.fraction = _rewind


func set_hint(text: String) -> void:
	_hint = text
	if _built:
		_hint_label.text = text
		_hint_panel.visible = not text.strip_edges().is_empty()


func set_death_visible(is_dead: bool) -> void:
	_dead = is_dead
	if not _built or is_dead == _dead_shown:
		return
	_dead_shown = is_dead
	_death_layer.visible = is_dead
	if _death_tween:
		_death_tween.kill()
		_death_tween = null
	_death_text.modulate.a = 1.0
	if is_dead:
		_death_tween = create_tween().set_loops()
		_death_tween.tween_property(_death_text, "modulate:a", 0.55, 0.45)
		_death_tween.tween_property(_death_text, "modulate:a", 1.0, 0.45)


func set_paused(is_paused: bool) -> void:
	_paused = is_paused
	if _built:
		_pause_layer.visible = is_paused


# ── Builders ─────────────────────────────────────────────────────────

func _apply_all() -> void:
	set_stage_name(_stage)
	set_evidence(_count, _total)
	set_rewind_fraction(_rewind)
	set_hint(_hint)
	set_death_visible(_dead)
	set_paused(_paused)


func _build_dossier() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	_root.add_child(panel)

	var box := VBoxContainer.new()
	panel.add_child(box)

	box.add_child(_make_label("CASE FILE", 11, PT.CYAN.darkened(0.2)))
	_stage_label = _make_label("", 20, PT.TEXT)
	box.add_child(_stage_label)

	var rule := ColorRect.new()
	rule.color = PT.CYAN.darkened(0.6)
	rule.custom_minimum_size = Vector2(0, 2)
	box.add_child(rule)

	var rewind_row := HBoxContainer.new()
	box.add_child(rewind_row)
	var rewind_title := _make_label("REWIND", 14, PT.CYAN)
	rewind_title.custom_minimum_size = Vector2(68, 0)
	rewind_row.add_child(rewind_title)
	_rewind_bar = RewindBar.new()
	rewind_row.add_child(_rewind_bar)

	# [EVIDENCE: ■ ■ □ □ □] 2/5   (squares are drawn, so no font glyph dependency)
	var ev_row := HBoxContainer.new()
	ev_row.add_theme_constant_override("separation", 6)
	box.add_child(ev_row)
	ev_row.add_child(_make_label("[EVIDENCE:", 14, PT.GOLD))
	_pips = EvidencePips.new()
	ev_row.add_child(_pips)
	_evidence_tail = _make_label("] 0/5", 14, PT.GOLD)
	ev_row.add_child(_evidence_tail)


func _build_hint() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_bottom", 28)
	_root.add_child(margin)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_END
	margin.add_child(column)

	var center := CenterContainer.new()
	column.add_child(center)

	_hint_panel = PanelContainer.new()
	_hint_panel.add_theme_stylebox_override("panel", PT.panel_box(PT.GOLD.darkened(0.5), 0.85, 8))
	_hint_panel.visible = false
	center.add_child(_hint_panel)

	_hint_label = _make_label("", 16, PT.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_hint_panel.add_child(_hint_label)


func _build_death_banner() -> void:
	_death_layer = Control.new()
	_death_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_layer.visible = false
	_root.add_child(_death_layer)

	var tint := ColorRect.new()                   # faint hazard wash over the scene
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint.color = Color(PT.RED, 0.10)
	_death_layer.add_child(tint)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_layer.add_child(center)

	var banner := PanelContainer.new()
	banner.custom_minimum_size = Vector2(640, 96)
	banner.add_theme_stylebox_override("panel", PT.ink_box(PT.RED, 0.93, 14))
	center.add_child(banner)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	banner.add_child(box)

	box.add_child(_make_label("- CASE INTERRUPTED -", 13, PT.RED, HORIZONTAL_ALIGNMENT_CENTER))
	_death_text = _make_label("HOLD [R] TO REWIND TIME", 30, PT.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_death_text)


func _build_pause_overlay() -> void:
	_pause_layer = Control.new()
	_pause_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.visible = false
	_root.add_child(_pause_layer)

	var dim := ColorRect.new()                    # semi-transparent dark charcoal
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.055, 0.063, 0.078, 0.82)
	_pause_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	panel.add_theme_stylebox_override("panel", PT.panel_box(PT.GOLD.darkened(0.3), 0.95, 22))
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	box.add_child(_make_label("PAUSED", 34, PT.GOLD, HORIZONTAL_ALIGNMENT_CENTER))

	var rule := ColorRect.new()
	rule.color = PT.GOLD.darkened(0.55)
	rule.custom_minimum_size = Vector2(0, 2)
	box.add_child(rule)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)

	for row in pause_hints:
		var key := _make_label("[%s]" % row[0], 16, PT.CYAN, HORIZONTAL_ALIGNMENT_RIGHT)
		key.custom_minimum_size = Vector2(170, 0)
		grid.add_child(key)
		grid.add_child(_make_label(row[1], 16, PT.TEXT))


# ── Helpers ──────────────────────────────────────────────────────────

func _make_label(text: String, font_size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	if font_size >= 20:
		l.add_theme_font_override("font", PT.HEADING_FONT)
	l.add_theme_color_override("font_color", color)
	return l


## Guarantees no HUD element can swallow keyboard-adjacent/UI focus or mouse events.
func _ignore_mouse(n: Node) -> void:
	if n is Control:
		var c := n as Control
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.focus_mode = Control.FOCUS_NONE
	for child in n.get_children():
		_ignore_mouse(child)
