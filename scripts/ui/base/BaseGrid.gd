extends Control
class_name BaseGrid

## Изометрическая сетка базы игрока.
## Renders a 6×6 isometric diamond grid, loads building sprites via HTTP,
## and emits cell_tapped when the player clicks a cell.

signal cell_tapped(col: int, row: int, building)  # building is Dictionary or null

# ── Palette ───────────────────────────────────────────────────────────────────
const TILE_EMPTY_FILL   := Color(0.05, 0.09, 0.20, 0.88)
const TILE_EMPTY_BORDER := Color(0.25, 0.45, 0.80, 0.7)
const TILE_HOVER_BORDER := Color(0.55, 0.85, 1.00, 1.0)
const TILE_OCC_BORDER   := Color(0.90, 0.95, 1.00, 0.7)

const EFFECT_COLORS := {
	"base_storage":  Color(0.12, 0.48, 0.28, 0.88),
	"grow_grapes":   Color(0.38, 0.12, 0.58, 0.88),
	"produce_beer":  Color(0.52, 0.36, 0.07, 0.88),
	"produce_wine":  Color(0.42, 0.07, 0.17, 0.88),
}
const DEFAULT_OCC_COLOR := Color(0.28, 0.28, 0.48, 0.88)

# ── State ─────────────────────────────────────────────────────────────────────
var _grid_size:    int      = 6
var _buildings:    Array    = []
var _occupied:     Dictionary = {}   # "col,row" → building dict
var _sprite_cache: Dictionary = {}   # image_url → ImageTexture or null
var _hover_cell:   Vector2i = Vector2i(-1, -1)

# ── Layout (computed each draw) ───────────────────────────────────────────────
var _tw:          float = 80.0   # tile full width
var _th:          float = 40.0   # tile full height  (= _tw / 2)
var _grid_origin: Vector2 = Vector2.ZERO

# ── Public ────────────────────────────────────────────────────────────────────

func set_data(buildings: Array, grid_size: int) -> void:
	_grid_size = grid_size
	_buildings = buildings
	_rebuild_occupied()
	_load_missing_sprites()
	queue_redraw()


# ── Layout ────────────────────────────────────────────────────────────────────

func _recompute_layout() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	var avail_w := size.x - 16.0
	var avail_h := size.y - 16.0
	# Grid pixel width  = grid_size * _tw
	# Grid pixel height = grid_size * _th  (th = tw/2)
	var tw_from_w := avail_w / float(_grid_size)
	var tw_from_h := 2.0 * avail_h / float(_grid_size)
	_tw = clamp(min(tw_from_w, tw_from_h), 32.0, 160.0)
	_th = _tw / 2.0
	# Grid iso-center = iso_pos(2.5, 2.5) = Vector2(0, 2.5 * _th)
	var iso_center := Vector2(0.0, (_grid_size - 1) / 2.0 * _th)
	_grid_origin = size / 2.0 - iso_center


func _iso_pos(c: float, r: float) -> Vector2:
	return _grid_origin + Vector2((c - r) * _tw * 0.5, (c + r) * _th * 0.5)


func _diamond_pts(c: float, r: float) -> PackedVector2Array:
	var center := _iso_pos(c, r)
	return PackedVector2Array([
		center + Vector2(0.0,       -_th * 0.5),  # top
		center + Vector2(_tw * 0.5,  0.0),        # right
		center + Vector2(0.0,        _th * 0.5),  # bottom
		center + Vector2(-_tw * 0.5, 0.0),        # left
	])


# ── Draw ──────────────────────────────────────────────────────────────────────

func _draw() -> void:
	_recompute_layout()

	# Build draw order: back-to-front (col+row ascending)
	var cells: Array = []
	for r in _grid_size:
		for c in _grid_size:
			cells.append(Vector2i(c, r))
	cells.sort_custom(func(a, b): return a.x + a.y < b.x + b.y)

	# Pass 1: tiles
	for cell in cells:
		_draw_tile(cell.x, cell.y)

	# Pass 2: building sprites (on top of tiles)
	for cell in cells:
		var key := "%d,%d" % [cell.x, cell.y]
		var b = _occupied.get(key, null)
		if b != null and _is_anchor(b, cell.x, cell.y):
			_draw_building_sprite(b, cell.x, cell.y)


func _draw_tile(col: int, row: int) -> void:
	var key := "%d,%d" % [col, row]
	var building = _occupied.get(key, null)
	var pts := _diamond_pts(col, row)
	if building == null:
		# Empty cell
		draw_colored_polygon(pts, TILE_EMPTY_FILL)
		var border_col := TILE_HOVER_BORDER if _hover_cell == Vector2i(col, row) else TILE_EMPTY_BORDER
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), border_col, 1.5)
	else:
		# Occupied cell
		var ek := str(building.get("effect_key", ""))
		var fill: Color = EFFECT_COLORS.get(ek, DEFAULT_OCC_COLOR)
		draw_colored_polygon(pts, fill)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), TILE_OCC_BORDER, 2.0)
		if _hover_cell == Vector2i(col, row):
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), TILE_HOVER_BORDER, 3.0)


func _draw_building_sprite(b: Dictionary, col: int, row: int) -> void:
	var image_url: String = str(b.get("image_url", ""))
	if image_url.is_empty() or not _sprite_cache.has(image_url) or _sprite_cache[image_url] == null:
		_draw_building_emoji(b, col, row)
		return

	var tex: ImageTexture = _sprite_cache[image_url]
	var sw := int(b.get("size_w", 1))
	var sh := int(b.get("size_h", 1))
	# Center of bounding box in grid coords
	var cc := col + (sw - 1) * 0.5
	var cr := row + (sh - 1) * 0.5
	var center := _iso_pos(cc, cr)

	# Scale sprite to fit within the bounding box width
	var display_w: float = _tw * float(max(sw, sh))
	var tex_size: Vector2 = tex.get_size()
	var scale_f: float   = display_w / float(max(tex_size.x, 1))
	var draw_size: Vector2 = tex_size * scale_f

	# Place sprite so its vertical center sits just above the tile center
	var draw_pos := center - Vector2(draw_size.x * 0.5, draw_size.y * 0.82)
	draw_texture_rect(tex, Rect2(draw_pos, draw_size), false)


func _draw_building_emoji(b: Dictionary, col: int, row: int) -> void:
	var sw := int(b.get("size_w", 1))
	var sh := int(b.get("size_h", 1))
	var cc := col + (sw - 1) * 0.5
	var cr := row + (sh - 1) * 0.5
	var pos := _iso_pos(cc, cr) + Vector2(-20, -12)
	var fs: int = clamp(int(_tw * 0.35), 14, 40)
	draw_string(ThemeDB.fallback_font, pos, str(b.get("emoji", "🏗️")),
		HORIZONTAL_ALIGNMENT_CENTER, -1, fs)


# ── Occupied map ──────────────────────────────────────────────────────────────

func _rebuild_occupied() -> void:
	_occupied.clear()
	for b in _buildings:
		var bc := int(b.get("col", b.get("grid_x", 0)))
		var br := int(b.get("row", b.get("grid_y", 0)))
		var sw := int(b.get("size_w", 1))
		var sh := int(b.get("size_h", 1))
		for dc in sw:
			for dr in sh:
				_occupied["%d,%d" % [bc + dc, br + dr]] = b


func _is_anchor(b: Dictionary, col: int, row: int) -> bool:
	return int(b.get("col", b.get("grid_x", 0))) == col \
		and int(b.get("row", b.get("grid_y", 0))) == row


# ── Sprite loading ────────────────────────────────────────────────────────────

func _load_missing_sprites() -> void:
	for b in _buildings:
		var url: String = str(b.get("image_url", ""))
		if url.is_empty() or _sprite_cache.has(url):
			continue
		_sprite_cache[url] = null  # mark in-flight
		_fetch_sprite(url)


func _fetch_sprite(rel_url: String) -> void:
	var full_url: String = Session.api_base + rel_url
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result, _code, _headers, body):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or _code != 200:
			return
		var img := Image.new()
		if img.load_png_from_buffer(body) != OK:
			return
		_sprite_cache[rel_url] = ImageTexture.create_from_image(img)
		queue_redraw()
	)
	http.request(full_url)


# ── Input ─────────────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell := _screen_to_grid(event.position)
		var new_hover := cell if _in_bounds(cell) else Vector2i(-1, -1)
		if new_hover != _hover_cell:
			_hover_cell = new_hover
			queue_redraw()
		return

	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _screen_to_grid(event.position)
		if _in_bounds(cell):
			var key := "%d,%d" % [cell.x, cell.y]
			var building = _occupied.get(key, null)
			cell_tapped.emit(cell.x, cell.y, building)
			accept_event()


func _screen_to_grid(local_pos: Vector2) -> Vector2i:
	var p  := local_pos - _grid_origin
	var fc := p.x / _tw + p.y / _th
	var fr := p.y / _th - p.x / _tw
	return Vector2i(int(round(fc)), int(round(fr)))


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < _grid_size and cell.y >= 0 and cell.y < _grid_size
