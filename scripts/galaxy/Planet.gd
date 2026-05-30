extends Node2D
class_name Planet

# Одна планета на карте: спрайт + подпись.
# Содержит свои данные и сама знает, как себя отрисовать и расположить.

signal pressed(planet_id: int)
signal texture_ready

const SIZE := 320.0
const ASSETS_URL_PATH := "/assets/images/"

var planet_id: int   = 0
var map_x:     float = 50.0
var map_y:     float = 50.0
var slug:      String = ""
var planet_name: String = ""

var _sprite: Sprite2D
var _label:  Label
var _loaded_slug: String = ""
var _texture_loading: bool = false


func _ready() -> void:
	_sprite = Sprite2D.new()
	add_child(_sprite)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 33)
	_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.custom_minimum_size  = Vector2(200.0, 0.0)
	_label.position             = Vector2(-100.0, SIZE * 0.5 + 4.0)
	add_child(_label)

	_refresh()


func apply_data(d: Dictionary) -> void:
	planet_id   = int(d.get("id", 0))
	map_x       = _to_f(d.get("x"), 50.0)
	map_y       = _to_f(d.get("y"), 50.0)
	slug        = _to_s(d.get("image_slug"), "")
	planet_name = _to_s(d.get("name"), "")
	if is_inside_tree():
		_refresh()


func update_layout(proj: MapProjection) -> void:
	position = proj.world_to_screen(map_x, map_y)


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	# Hit-test: расстояние от курсора до центра планеты в мировых координатах
	var local := to_local(get_global_mouse_position())
	if local.length() <= SIZE * 0.5:
		pressed.emit(planet_id)
		get_viewport().set_input_as_handled()


# ── internals ────────────────────────────────────────────────────────────────

func _refresh() -> void:
	_label.text = planet_name
	if slug == _loaded_slug:
		return
	_sprite.texture = null
	_loaded_slug = slug
	if slug.is_empty():
		return
	if OS.has_feature("web"):
		_texture_loading = true
		_load_texture_http(Session.api_base + ASSETS_URL_PATH + slug + "/map_icon.png")
	else:
		var path := ProjectSettings.globalize_path(
			"res://../merchant_mobile_app/assets/images/cities/" + slug + ".png")
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


static func _to_f(v, fallback: float) -> float:
	return float(v) if v != null else fallback


static func _to_s(v, fallback: String) -> String:
	return str(v) if v != null else fallback
