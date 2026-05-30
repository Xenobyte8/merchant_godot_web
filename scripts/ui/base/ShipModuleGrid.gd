extends Control
class_name ShipModuleGrid

# Отображает схему корабля в виде сетки модулей.
# Каждый модуль — ячейка с изображением, закрашенная по прогрессу.

signal module_tapped(module: Dictionary)

# ── Цвета по прогрессу ───────────────────────────────────────────────────────
const COLOR_NOT_STARTED := Color(0.1, 0.12, 0.22)      # тёмно-синий
const COLOR_IN_PROGRESS := Color(0.55, 0.38, 0.05)     # янтарный
const COLOR_DONE        := Color(0.08, 0.38, 0.35)     # тёмный тил
const COLOR_FILL_NOT_STARTED := Color(0.15, 0.18, 0.32)
const COLOR_FILL_IN_PROGRESS := Color(0.75, 0.55, 0.08)
const COLOR_FILL_DONE        := Color(0.12, 0.62, 0.55)
const COLOR_BORDER      := Color(0.3, 0.5, 0.8, 0.7)
const COLOR_HOVER       := Color(1.0, 1.0, 1.0, 0.18)

# ── Сетка: 7 колонок × 6 строк ──────────────────────────────────────────────
const GRID_COLS := 7
const GRID_ROWS := 6
const CELL_PAD  := 4

var _modules:     Array = []           # Array[Dictionary] from API
var _cell_size:   float = 64.0
var _origin:      Vector2 = Vector2.ZERO
var _hover_cell:  Vector2i = Vector2i(-1, -1)
var _sprite_cache: Dictionary = {}     # url → ImageTexture|null

func set_modules(modules: Array) -> void:
	_modules = modules
	queue_redraw()
	# Start loading images for any module that has an image_url
	for m in _modules:
		var url: String = str(m.get("image_url", ""))
		if not url.is_empty() and not _sprite_cache.has(url):
			_sprite_cache[url] = null   # mark as loading
			_fetch_sprite(url)


func _draw() -> void:
	if _modules.is_empty():
		return

	var avail := size
	_cell_size = clamp(
		min(avail.x / float(GRID_COLS), avail.y / float(GRID_ROWS)),
		32.0, 120.0
	)
	var total_w := _cell_size * GRID_COLS
	var total_h := _cell_size * GRID_ROWS
	_origin = Vector2((avail.x - total_w) * 0.5, (avail.y - total_h) * 0.5)

	# Build lookup by (col, row)
	var by_pos: Dictionary = {}
	for m in _modules:
		var key := Vector2i(int(m.get("grid_col", 0)), int(m.get("grid_row", 0)))
		by_pos[key] = m

	for row in GRID_ROWS:
		for col in GRID_COLS:
			var key := Vector2i(col, row)
			var m = by_pos.get(key, null)
			if m == null:
				continue   # empty cell — skip
			_draw_module_cell(col, row, m)


func _draw_module_cell(col: int, row: int, m: Dictionary) -> void:
	var pct: float = float(m.get("progress_pct", 0.0))
	var is_done: bool = bool(m.get("is_done", false))

	var rect := _cell_rect(col, row)
	var inner := rect.grow(-CELL_PAD)

	# Background fill
	var fill_color: Color
	var border_color: Color
	if is_done:
		fill_color   = COLOR_FILL_DONE
		border_color = Color(0.2, 0.9, 0.8)
	elif pct > 0:
		fill_color   = COLOR_FILL_IN_PROGRESS
		border_color = Color(1.0, 0.75, 0.1)
	else:
		fill_color   = COLOR_FILL_NOT_STARTED
		border_color = COLOR_BORDER

	draw_rect(inner, fill_color, true, -1.0)

	# Texture sprite (tinted by state)
	var url: String = str(m.get("image_url", ""))
	var tex = _sprite_cache.get(url, null) as ImageTexture
	if tex != null:
		var img_color := Color.WHITE
		if is_done:
			img_color = Color(0.7, 1.0, 0.95)
		elif pct > 0:
			img_color = Color(1.0, 0.85, 0.35)
		else:
			img_color = Color(0.3, 0.35, 0.55)
		draw_texture_rect(tex, inner, false, img_color)

	# Progress bar at bottom (if in progress)
	if pct > 0 and not is_done:
		var bar_h := 5.0
		var bar_bg := Rect2(inner.position + Vector2(0, inner.size.y - bar_h), Vector2(inner.size.x, bar_h))
		draw_rect(bar_bg, Color(0.1, 0.1, 0.1, 0.7), true, -1.0)
		var bar_fg := Rect2(bar_bg.position, Vector2(bar_bg.size.x * pct / 100.0, bar_h))
		draw_rect(bar_fg, Color(1.0, 0.7, 0.0), true, -1.0)

	# Border
	draw_rect(inner, border_color, false, 1.5)

	# Hover highlight
	if _hover_cell == Vector2i(col, row):
		draw_rect(inner, COLOR_HOVER, true, -1.0)
		draw_rect(inner, Color(1.0, 1.0, 1.0, 0.6), false, 2.0)

	# Module name (small text at bottom)
	var fs: int = clamp(int(_cell_size * 0.14), 9, 18)
	var mod_name := str(m.get("name", ""))
	# Draw a small translucent label strip
	var name_rect := Rect2(inner.position + Vector2(0, inner.size.y - fs - 6),
						   Vector2(inner.size.x, fs + 6))
	draw_rect(name_rect, Color(0.0, 0.0, 0.0, 0.55), true, -1.0)
	draw_string(
		ThemeDB.fallback_font,
		inner.position + Vector2(4, inner.size.y - 4),
		mod_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		inner.size.x - 8,
		fs,
		Color(0.9, 0.95, 1.0)
	)

	# Done checkmark
	if is_done:
		var cs: int = clamp(int(_cell_size * 0.3), 14, 36)
		draw_string(
			ThemeDB.fallback_font,
			inner.position + Vector2(inner.size.x - cs - 2, cs + 2),
			"✓",
			HORIZONTAL_ALIGNMENT_LEFT,
			cs + 4,
			cs,
			Color(0.2, 1.0, 0.8)
		)


func _cell_rect(col: int, row: int) -> Rect2:
	return Rect2(
		_origin + Vector2(col * _cell_size, row * _cell_size),
		Vector2(_cell_size, _cell_size)
	)


func _cell_at(pos: Vector2) -> Vector2i:
	var rel := pos - _origin
	var col := int(rel.x / _cell_size)
	var row := int(rel.y / _cell_size)
	if col < 0 or col >= GRID_COLS or row < 0 or row >= GRID_ROWS:
		return Vector2i(-1, -1)
	return Vector2i(col, row)


func _module_at(col: int, row: int):
	for m in _modules:
		if int(m.get("grid_col", -1)) == col and int(m.get("grid_row", -1)) == row:
			return m
	return null


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell := _cell_at(event.position)
		var mod = _module_at(cell.x, cell.y) if cell != Vector2i(-1, -1) else null
		var new_hover := cell if mod != null else Vector2i(-1, -1)
		if new_hover != _hover_cell:
			_hover_cell = new_hover
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _cell_at(event.position)
		if cell == Vector2i(-1, -1):
			return
		var mod = _module_at(cell.x, cell.y)
		if mod != null:
			module_tapped.emit(mod)


func _fetch_sprite(rel_url: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	var full_url := Session.api_base + rel_url
	http.request(full_url)
	var result: Array = await http.request_completed
	http.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		return
	var img := Image.new()
	if img.load_png_from_buffer(result[3]) != OK:
		return
	var tex := ImageTexture.create_from_image(img)
	_sprite_cache[rel_url] = tex
	queue_redraw()
