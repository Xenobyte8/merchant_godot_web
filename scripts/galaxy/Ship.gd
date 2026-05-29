extends Node2D
class_name Ship

# Один корабль на карте.
signal texture_ready
# Если is_in_transit — позиция интерполируется клиентски между departed_at
# и arrives_at (как в mobile_app), иначе используется статичная location.

const SIZE := 48.0
const ASSETS_URL_PATH := "/assets/images/"
const DOCK_SPACING := 52.0   # горизонтальный шаг между пристыкованными кораблями
const DOCK_OFFSET_Y := 44.0  # сдвиг вниз от центра планеты

var ship_id: int = 0
var slug:    String = "torgovets"
var ship_name: String = ""
var is_in_transit: bool = false
var location_id: int = 0
var cargo_used: float = 0.0
var cargo_capacity: float = 0.0
var dock_index: int = 0  # порядковый номер в ряду кораблей на планете

# Статичная позиция (когда корабль стоит на планете)
var location_x: float = 50.0
var location_y: float = 50.0

# Данные транзита
var from_x: float = 0.0
var from_y: float = 0.0
var to_x:   float = 0.0
var to_y:   float = 0.0
var departed_at_unix: float = 0.0
var arrives_at_unix:  float = 0.0
var flight_path: Array = []  # Array[Vector2] в координатах 0..100

var _sprite: Sprite2D
var _loaded_slug: String = ""
var _texture_loading: bool = false


func _ready() -> void:
	_sprite = Sprite2D.new()
	add_child(_sprite)
	_refresh_texture()


func apply_data(d: Dictionary) -> void:
	ship_id       = int(d.get("id", 0))
	slug          = _to_s(d.get("ship_type_slug"), "torgovets")
	ship_name     = _to_s(d.get("name"), "")
	is_in_transit = bool(d.get("is_in_transit", false))
	location_id   = int(d.get("location_id", 0))
	cargo_used    = _to_f(d.get("cargo_used"), 0.0)
	cargo_capacity = _to_f(d.get("cargo_capacity"), 0.0)

	location_x = _to_f(d.get("location_x"), 50.0)
	location_y = _to_f(d.get("location_y"), 50.0)

	from_x = _to_f(d.get("from_x"), location_x)
	from_y = _to_f(d.get("from_y"), location_y)
	to_x   = _to_f(d.get("to_x"),   _to_f(d.get("destination_x"), location_x))
	to_y   = _to_f(d.get("to_y"),   _to_f(d.get("destination_y"), location_y))

	departed_at_unix = _parse_iso(d.get("departed_at"))
	arrives_at_unix  = _parse_iso(d.get("arrives_at"))

	flight_path = _parse_flight_path(d.get("flight_path"))

	if is_inside_tree():
		_refresh_texture()


func update_layout(proj: MapProjection) -> void:
	var world_pos := _current_world_position()
	position = proj.world_to_screen(world_pos.x, world_pos.y)
	if is_in_transit:
		_sprite.rotation = _current_heading() + PI * 0.5  # спрайты смотрят вверх
	else:
		# Сдвигаем корабль вправо и вниз от центра планеты
		var total_w := DOCK_SPACING * dock_index
		position += Vector2(total_w - 0.0, DOCK_OFFSET_Y)
		_sprite.rotation = 0.0


# ── internals ────────────────────────────────────────────────────────────────

func _current_world_position() -> Vector2:
	if not is_in_transit or arrives_at_unix <= departed_at_unix:
		return Vector2(location_x, location_y)

	var progress := _progress()
	if flight_path.size() >= 2:
		return _point_on_polyline(flight_path, progress)
	return Vector2(
		from_x + (to_x - from_x) * progress,
		from_y + (to_y - from_y) * progress,
	)


func _current_heading() -> float:
	if flight_path.size() >= 2:
		var d := _heading_on_polyline(flight_path, _progress())
		return atan2(d.y, d.x)
	return atan2(to_y - from_y, to_x - from_x)


func _progress() -> float:
	var now := Time.get_unix_time_from_system()
	var total := arrives_at_unix - departed_at_unix
	if total <= 0.0:
		return 1.0
	return clampf((now - departed_at_unix) / total, 0.0, 1.0)


func _refresh_texture() -> void:
	if slug == _loaded_slug:
		return
	_sprite.texture = null
	_loaded_slug = slug
	if slug.is_empty():
		return
	if OS.has_feature("web"):
		_texture_loading = true
		_load_texture_http(Session.api_base + ASSETS_URL_PATH + "_shared/ships/" + slug + ".png")
	else:
		var path := ProjectSettings.globalize_path(
			"res://../merchant_mobile_app/assets/images/ships/" + slug + ".png")
		var img := Image.load_from_file(path)
		if img != null:
			_sprite.texture = ImageTexture.create_from_image(img)
			var s := SIZE / float(max(img.get_width(), 1))
			_sprite.scale = Vector2(s, s)
		texture_ready.emit()


func _load_texture_http(url: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			_texture_loading = false
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				texture_ready.emit()
				return
			var img := Image.new()
			if img.load_png_from_buffer(body) != OK:
				texture_ready.emit()
				return
			var tex := ImageTexture.create_from_image(img)
			_sprite.texture = tex
			var s := SIZE / float(max(img.get_width(), 1))
			_sprite.scale = Vector2(s, s)
			texture_ready.emit()
	)
	http.request(url)


# ── parsing helpers ──────────────────────────────────────────────────────────

static func _parse_iso(v) -> float:
	if v == null:
		return 0.0
	var s := str(v)
	if s.is_empty():
		return 0.0
	# Поддерживает ISO 8601 ("2026-04-26T10:00:00")
	return Time.get_unix_time_from_datetime_string(s)


static func _parse_flight_path(v) -> Array:
	if not (v is Array):
		return []
	var pts: Array = []
	for item in v:
		if item is Array and item.size() >= 2:
			pts.append(Vector2(float(item[0]), float(item[1])))
		elif item is Dictionary:
			pts.append(Vector2(
				float(item.get("x", 0.0)),
				float(item.get("y", 0.0)),
			))
	return pts


# ── polyline math ────────────────────────────────────────────────────────────

static func _polyline_length(pts: Array) -> float:
	var total := 0.0
	for i in range(pts.size() - 1):
		total += (pts[i + 1] - pts[i]).length()
	return total


static func _point_on_polyline(pts: Array, progress: float) -> Vector2:
	var total := _polyline_length(pts)
	if total <= 0.0:
		return pts[0]
	var target := total * clampf(progress, 0.0, 1.0)
	var travelled := 0.0
	for i in range(pts.size() - 1):
		var seg_len: float = (pts[i + 1] - pts[i]).length()
		if travelled + seg_len >= target:
			var t := 0.0 if seg_len == 0.0 else (target - travelled) / seg_len
			return pts[i].lerp(pts[i + 1], t)
		travelled += seg_len
	return pts[pts.size() - 1]


static func _heading_on_polyline(pts: Array, progress: float) -> Vector2:
	var total := _polyline_length(pts)
	if total <= 0.0:
		return Vector2.RIGHT
	var target := total * clampf(progress, 0.0, 1.0)
	var travelled := 0.0
	for i in range(pts.size() - 1):
		var seg_len: float = (pts[i + 1] - pts[i]).length()
		if travelled + seg_len >= target:
			return (pts[i + 1] - pts[i]).normalized()
		travelled += seg_len
	return (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()


# ── coercion ─────────────────────────────────────────────────────────────────

static func _to_f(v, fallback: float) -> float:
	return float(v) if v != null else fallback


static func _to_s(v, fallback: String) -> String:
	return str(v) if v != null else fallback
