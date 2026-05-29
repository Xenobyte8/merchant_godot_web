extends CanvasLayer
class_name BottomPanel

# Нижняя панель управления в стиле классических RTS.
# Заменяет PlanetPanel + FlightPanel: три состояния (EMPTY / PLANET / SHIP).
# Layout: [иконка объекта] | [название + характеристики] | [список действий (скролл)]

signal ship_selected(ship: Dictionary)
signal destination_selected(planet_id: int)
signal enter_city_requested(planet_id: int)

const SHIP_ASSETS_URL_PATH := "/assets/images/"
const RESOURCE_ICON_URL    := "/assets/images/resources/{id}/icon.png"
const CARGO_ICON_SIZE      := 36
const EXPANDED_H  := 320.0
const COLLAPSED_H :=  80.0

enum State { EMPTY, PLANET, SHIP }

## Текущий выбранный корабль — читается из Main.gd при отправке
var current_ship: Dictionary = {}
var current_planet_id: int = 0

var _state:     State = State.EMPTY
var _api:       ApiClient
var _fetch_seq: int = 0   # инкрементируется при каждом show_ship; отменяет устаревшие ответы

var _panel:       Panel
var _bar_btn:     Button
var _bar_label:   Label
var _main_row:    HBoxContainer
var _icon:        TextureRect
var _title:       Label
var _subtitle:    Label
var _extra:       Label
var _action_list: VBoxContainer
var _tween:       Tween


func _ready() -> void:
	layer = 5
	_build_ui()
	get_viewport().size_changed.connect(_on_viewport_resized)


# ── Public API ─────────────────────────────────────────────────────────────────

func show_planet(planet_name: String, planet_id: int, planet_slug: String, ships: Array) -> void:
	_fetch_seq        += 1
	_state             = State.PLANET
	current_ship       = {}
	current_planet_id  = planet_id
	_icon.texture      = null
	if not planet_slug.is_empty():
		var cached = Session.texture_cache.get(planet_slug)
		if cached is ImageTexture:
			_icon.texture = cached
		elif OS.has_feature("web"):
			_load_icon_http_cached(_icon, planet_slug,
				Session.api_base + SHIP_ASSETS_URL_PATH + planet_slug + "/location_card.png")
	_title.text        = planet_name
	_subtitle.text     = ""
	_extra.text        = ""
	_bar_label.text    = "▼  " + planet_name
	_clear_actions()

	# ── Заголовок: название планеты слева, кнопка входа справа ──────────────
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 12)
	_action_list.add_child(header)

	var planet_lbl := Label.new()
	planet_lbl.text = planet_name
	planet_lbl.add_theme_font_size_override("font_size", 30)
	planet_lbl.add_theme_color_override("font_color", Color(0.95, 1.0, 1.0))
	planet_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	planet_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	header.add_child(planet_lbl)

	var city_btn := Button.new()
	city_btn.text                = "🏙  Войти в город"
	city_btn.flat                = false
	city_btn.custom_minimum_size = Vector2(0, 64)
	city_btn.add_theme_font_size_override("font_size", 24)
	city_btn.add_theme_color_override("font_color", Color(0.9, 1.0, 0.8))
	city_btn.pressed.connect(func() -> void: enter_city_requested.emit(planet_id))
	header.add_child(city_btn)

	# ── Список кораблей в два столбца ───────────────────────────────────────
	if ships.is_empty():
		var lbl := Label.new()
		lbl.text = "Кораблей нет"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_action_list.add_child(lbl)
	else:
		var ships_sep := HSeparator.new()
		ships_sep.add_theme_color_override("color", Color(0.3, 0.45, 0.7, 0.5))
		_action_list.add_child(ships_sep)

		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		_action_list.add_child(grid)
		for ship in ships:
			grid.add_child(_make_ship_btn(ship))
	_expand()


func show_ship(ship: Dictionary, api: ApiClient) -> void:
	_fetch_seq  += 1
	var my_seq  := _fetch_seq
	_state       = State.SHIP
	current_ship = ship
	_api         = api

	_icon.texture  = null
	_title.text    = ship.get("name", "Корабль")
	var used: float = ship.get("cargo_used", 0.0)
	var cap:  float = ship.get("cargo_capacity", 0.0)
	_subtitle.text  = "Груз: %.0f / %.0f т" % [used, cap]
	_extra.text     = ship.get("slug", ship.get("ship_type_slug", ""))
	_bar_label.text = "▼  " + _title.text

	_clear_actions()
	_load_ship_icon(ship)
	_expand()

	var loading := Label.new()
	loading.text = "Загрузка маршрутов..."
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading.add_theme_font_size_override("font_size", 24)
	loading.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_action_list.add_child(loading)

	var ship_id: int  = ship.get("id", 0)
	var times: Array  = await api.get_flight_times(ship_id)
	if my_seq != _fetch_seq:
		return  # состояние сменилось, пока загружали маршруты
	loading.queue_free()
	for entry in times:
		_action_list.add_child(_make_destination_btn(entry))


func collapse() -> void:
	if _state == State.EMPTY and not _is_expanded():
		return
	_fetch_seq  += 1
	_state       = State.EMPTY
	current_ship = {}
	_bar_label.text = "▲  Выберите планету"
	_animate_panel(COLLAPSED_H)


# ── Build UI ───────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var vp      := get_viewport()
	var vp_size := vp.get_visible_rect().size if vp else Vector2(480, 854)

	# Корень — Panel (не Container), размер задаётся вручную
	_panel          = Panel.new()
	_panel.size     = Vector2(vp_size.x, EXPANDED_H)
	_panel.position = Vector2(0.0, vp_size.y - COLLAPSED_H)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color           = Color(0.06, 0.08, 0.14, 0.97)
	panel_style.border_color       = Color(0.35, 0.55, 0.9, 1.0)
	panel_style.border_width_top   = 3
	panel_style.border_width_left  = 0
	panel_style.border_width_right = 0
	panel_style.border_width_bottom = 0
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	# VBoxContainer заполняет Panel полностью
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	_panel.add_child(vbox)

	# ── Полоска-триггер (всегда видна) ──────────────────────────────────────
	_bar_btn = Button.new()
	_bar_btn.flat = true
	_bar_btn.custom_minimum_size    = Vector2(0, COLLAPSED_H)
	_bar_btn.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	_bar_btn.pressed.connect(_on_bar_pressed)
	vbox.add_child(_bar_btn)

	_bar_label = Label.new()
	_bar_label.text = "▲  Выберите планету"
	_bar_label.add_theme_font_size_override("font_size", 26)
	_bar_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_bar_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_bar_btn.add_child(_bar_label)

	var bar_sep := HSeparator.new()
	bar_sep.add_theme_color_override("color", Color(0.35, 0.55, 0.9, 0.6))
	bar_sep.add_theme_constant_override("separation", 2)
	vbox.add_child(bar_sep)

	# ── Основная строка контента ─────────────────────────────────────────────
	_main_row = HBoxContainer.new()
	_main_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_row.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_main_row.add_theme_constant_override("separation", 16)
	vbox.add_child(_main_row)

	# Иконка объекта — фиксированный квадрат
	var icon_wrap := PanelContainer.new()
	icon_wrap.custom_minimum_size      = Vector2(220, 220)
	icon_wrap.size_flags_horizontal    = Control.SIZE_SHRINK_BEGIN
	icon_wrap.size_flags_vertical      = Control.SIZE_SHRINK_BEGIN
	_main_row.add_child(icon_wrap)

	_icon = TextureRect.new()
	_icon.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_wrap.add_child(_icon)

	# Список действий (прокручиваемый) — 50% оставшегося
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal    = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.0
	scroll.size_flags_vertical      = Control.SIZE_EXPAND_FILL
	_main_row.add_child(scroll)

	_action_list = VBoxContainer.new()
	_action_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_list.add_theme_constant_override("separation", 10)
	var action_margin := MarginContainer.new()
	action_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_margin.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	action_margin.add_theme_constant_override("margin_left",   12)
	action_margin.add_theme_constant_override("margin_right",  12)
	action_margin.add_theme_constant_override("margin_top",    10)
	action_margin.add_theme_constant_override("margin_bottom", 10)
	action_margin.add_child(_action_list)
	scroll.add_child(action_margin)

	# Информация об объекте — 50% оставшегося
	var info_box := VBoxContainer.new()
	info_box.size_flags_horizontal    = Control.SIZE_EXPAND_FILL
	info_box.size_flags_stretch_ratio = 1.0
	info_box.size_flags_vertical  = Control.SIZE_SHRINK_CENTER
	info_box.add_theme_constant_override("separation", 10)
	_main_row.add_child(info_box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 32)
	_title.add_theme_color_override("font_color", Color(0.95, 1.0, 1.0))
	_title.clip_text = true
	info_box.add_child(_title)

	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 24)
	_subtitle.add_theme_color_override("font_color", Color(0.6, 0.85, 0.6))
	_subtitle.clip_text = true
	info_box.add_child(_subtitle)

	_extra = Label.new()
	_extra.add_theme_font_size_override("font_size", 22)
	_extra.add_theme_color_override("font_color", Color(0.55, 0.65, 0.8))
	_extra.clip_text = true
	info_box.add_child(_extra)


# ── Internals ──────────────────────────────────────────────────────────────────

func _on_bar_pressed() -> void:
	if _state == State.EMPTY:
		return
	if _is_expanded():
		_animate_panel(COLLAPSED_H)
		_bar_label.text = "▲  " + _title.text
	else:
		_animate_panel(EXPANDED_H)
		_bar_label.text = "▼  " + _title.text


func _expand() -> void:
	_animate_panel(EXPANDED_H)


func _is_expanded() -> bool:
	var vp_h := get_viewport().get_visible_rect().size.y
	return _panel.position.y <= vp_h - EXPANDED_H + 5.0


func _animate_panel(target_h: float) -> void:
	var vp_h     := get_viewport().get_visible_rect().size.y
	var target_y := vp_h - target_h
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_panel, "position:y", target_y, 0.2)


func _on_viewport_resized() -> void:
	var vp := get_viewport().get_visible_rect().size
	_panel.size.x = vp.x
	var current_h := EXPANDED_H if _is_expanded() else COLLAPSED_H
	_panel.position.y = vp.y - current_h


func _clear_actions() -> void:
	for child in _action_list.get_children():
		child.queue_free()


func _make_ship_btn(ship: Dictionary) -> Control:
	var btn := Button.new()
	btn.flat                  = false
	btn.alignment             = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size   = Vector2(0, 100)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func() -> void: ship_selected.emit(ship))

	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0.1, 0.13, 0.22, 0.95)
	sn.border_color = Color(0.3, 0.48, 0.75, 0.9)
	sn.set_border_width_all(2)
	sn.set_corner_radius_all(8)
	sn.content_margin_left   = 10.0
	sn.content_margin_right  = 10.0
	sn.content_margin_top    = 8.0
	sn.content_margin_bottom = 8.0
	var sh := sn.duplicate() as StyleBoxFlat
	sh.bg_color    = Color(0.16, 0.22, 0.38, 0.98)
	sh.border_color = Color(0.55, 0.75, 1.0, 1.0)
	var sp := sn.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.07, 0.09, 0.16, 0.98)
	btn.add_theme_stylebox_override("normal",  sn)
	btn.add_theme_stylebox_override("hover",   sh)
	btn.add_theme_stylebox_override("pressed", sp)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	# отступы внутри кнопки
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   = 10.0
	vbox.offset_top    = 8.0
	vbox.offset_right  = -10.0
	vbox.offset_bottom = -8.0
	btn.add_child(vbox)

	# Название корабля
	var name_lbl := Label.new()
	name_lbl.text = ship.get("name", "Корабль")
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	name_lbl.clip_text    = true
	name_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(name_lbl)

	# Строка груза: иконка + количество для каждого ресурса
	var cargo: Array = ship.get("cargo", [])
	if cargo.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "пусто"
		empty_lbl.add_theme_font_size_override("font_size", 20)
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		empty_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		vbox.add_child(empty_lbl)
	else:
		var cargo_row := HBoxContainer.new()
		cargo_row.add_theme_constant_override("separation", 10)
		cargo_row.mouse_filter = Control.MOUSE_FILTER_PASS
		vbox.add_child(cargo_row)
		for item in cargo:
			var qty: float = item.get("quantity", 0.0)
			if qty <= 0.0:
				continue
			var res_id: int = item.get("resource_id", 0)
			# icon + qty label
			var cell := HBoxContainer.new()
			cell.add_theme_constant_override("separation", 4)
			cell.mouse_filter = Control.MOUSE_FILTER_PASS
			cargo_row.add_child(cell)
			var icon_rect := TextureRect.new()
			icon_rect.custom_minimum_size = Vector2(CARGO_ICON_SIZE, CARGO_ICON_SIZE)
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			icon_rect.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
			icon_rect.mouse_filter = Control.MOUSE_FILTER_PASS
			cell.add_child(icon_rect)
			if res_id > 0:
				_load_resource_icon(icon_rect, res_id)
			var item_lbl := Label.new()
			item_lbl.text = "%.0f" % qty
			item_lbl.add_theme_font_size_override("font_size", 22)
			item_lbl.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
			item_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			item_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
			cell.add_child(item_lbl)

	return btn


func _make_destination_btn(entry: Dictionary) -> Control:
	var planet_id:   int    = entry.get("planet_id", 0)
	var planet_name: String = entry.get("planet_name", "")
	var image_slug:  String = entry.get("image_slug", "")
	var seconds             = entry.get("seconds")  # null = текущая планета

	# Обёртка с серой рамкой
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.18, 0.9)
	style.border_color = Color(0.45, 0.45, 0.5, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left   = 8.0
	style.content_margin_right  = 8.0
	style.content_margin_top    = 6.0
	style.content_margin_bottom = 6.0
	frame.add_theme_stylebox_override("panel", style)

	if seconds == null:
		frame.modulate = Color(0.5, 0.5, 0.55)

	# Полупрозрачное фоновое изображение планеты
	var bg := TextureRect.new()
	bg.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bg.modulate     = Color(1, 1, 1, 0.18)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not image_slug.is_empty() and OS.has_feature("web"):
		_load_icon_http(bg, Session.api_base + SHIP_ASSETS_URL_PATH + image_slug + "/map_icon.png")
	frame.add_child(bg)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 2)
	frame.add_child(content)

	var name_lbl := Label.new()
	name_lbl.text = planet_name + ("  (здесь)" if seconds == null else "")
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 1.0, 1.0))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(name_lbl)

	if seconds != null:
		var time_lbl := Label.new()
		time_lbl.text = _format_seconds(int(seconds))
		time_lbl.add_theme_font_size_override("font_size", 20)
		time_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
		time_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		content.add_child(time_lbl)

		# Прозрачная кнопка поверх всего содержимого
		var btn := Button.new()
		btn.flat = true
		btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		btn.pressed.connect(func() -> void:
			destination_selected.emit(planet_id)
			collapse()
		)
		frame.add_child(btn)

	return frame


func _load_resource_icon(target: TextureRect, resource_id: int) -> void:
	var cache_key := "resource_%d" % resource_id
	var cached = Session.texture_cache.get(cache_key)
	if cached is ImageTexture:
		target.texture = cached
		return
	if Session.texture_cache.get(cache_key) == false:
		return
	var url := Session.api_base + RESOURCE_ICON_URL.replace("{id}", str(resource_id))
	if Session.texture_cache.get(cache_key) == null and cache_key in Session.texture_cache:
		return  # already loading
	Session.texture_cache[cache_key] = null
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty():
				Session.texture_cache[cache_key] = false
				return
			var img := Image.new()
			if img.load_png_from_buffer(body) != OK:
				Session.texture_cache[cache_key] = false
				return
			var tex := ImageTexture.create_from_image(img)
			Session.texture_cache[cache_key] = tex
			if is_instance_valid(target) and target.texture == null:
				target.texture = tex
	)
	http.request(url)


func _load_ship_icon(ship: Dictionary) -> void:
	var slug: String = ship.get("slug", ship.get("ship_type_slug", ""))
	if slug.is_empty():
		return
	if OS.has_feature("web"):
		_load_icon_http(_icon, Session.api_base + SHIP_ASSETS_URL_PATH + "_shared/ships/" + slug + ".png")
	else:
		var path := ProjectSettings.globalize_path(
			"res://../merchant_mobile_app/assets/images/ships/" + slug + ".png")
		var img := Image.load_from_file(path)
		if img != null:
			_icon.texture = ImageTexture.create_from_image(img)


func _load_icon_http(target: TextureRect, url: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				return
			var img := Image.new()
			if img.load_png_from_buffer(body) != OK:
				return
			target.texture = ImageTexture.create_from_image(img)
	)
	http.request(url)


## Загружает изображение по URL и сохраняет в Session.texture_cache[slug].
func _load_icon_http_cached(target: TextureRect, slug: String, url: String) -> void:
	Session.texture_cache[slug] = null  # помечаем «в загрузке»
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS or code != 200:
				Session.texture_cache.erase(slug)
				return
			var img := Image.new()
			if img.load_png_from_buffer(body) != OK:
				Session.texture_cache.erase(slug)
				return
			var tex := ImageTexture.create_from_image(img)
			Session.texture_cache[slug] = tex
			target.texture = tex
	)
	http.request(url)


static func _format_seconds(s: int) -> String:
	if s < 60:
		return "%d сек" % s
	var m := s / 60
	var sec := s % 60
	if m < 60:
		return "%d мин %d сек" % [m, sec] if sec > 0 else "%d мин" % m
	var h := m / 60
	var min_left := m % 60
	return "%d ч %d мин" % [h, min_left] if min_left > 0 else "%d ч" % h
