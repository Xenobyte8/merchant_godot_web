extends Node2D

# Корневой композитор сцены: связывает ApiClient, Galaxy и StatusOverlay.
# Не содержит ни HTTP, ни рендеринга — только последовательность действий.

@onready var api:           ApiClient    = $ApiClient
@onready var galaxy:        Galaxy       = $Galaxy
@onready var status:        StatusOverlay = $StatusOverlay
@onready var bottom_panel:  BottomPanel  = $BottomPanel
@onready var city_view:     CityView     = $CityView
@onready var market_screen: MarketScreen = $MarketScreen
@onready var camera:        MapCamera    = $MapCamera

const POLL_INTERVAL_SEC := 10.0

var _current_planet_id:    int   = 0
var _current_planet_name:  String = ""
var _current_planet_slug:  String = ""
var _current_planet_ships: Array  = []
# Флаг: подавляет очередной map_tapped, если он пришёл от отпускания после тапа по планете
var _planet_just_tapped: bool = false


func _ready() -> void:
	api.request_failed.connect(_on_api_failed)
	galaxy.planet_tapped.connect(_on_planet_tapped)
	bottom_panel.ship_selected.connect(_on_ship_selected)
	bottom_panel.destination_selected.connect(_on_destination_selected)
	bottom_panel.enter_city_requested.connect(_on_enter_city_requested)
	city_view.market_requested.connect(_on_market_requested)
	city_view.closed.connect(func(): bottom_panel.collapse())
	market_screen.closed.connect(func(): city_view.visible = true)
	camera.map_tapped.connect(_on_map_tapped)
	_start()


func _start() -> void:
	await Session.ensure_ready()
	status.show_status("Авторизация...")
	var auth := await api.auth_test_user()
	if auth.is_empty():
		return

	status.show_status("Загрузка карты...")
	if not await _refresh_map():
		return

	status.show_status("Загрузка изображений...")
	await galaxy.wait_textures_loaded()

	status.clear()
	YandexSDK.signal_loaded()
	_start_polling()


func _refresh_map() -> bool:
	var data := await api.get_map_state()
	if data.is_empty():
		return false
	galaxy.set_state(data)
	return true


func _start_polling() -> void:
	var timer := Timer.new()
	timer.wait_time = POLL_INTERVAL_SEC
	timer.autostart = true
	timer.timeout.connect(_refresh_map)
	add_child(timer)


func _on_planet_tapped(planet_id: int, planet_name: String, planet_slug: String, ships: Array) -> void:
	_planet_just_tapped    = true
	_current_planet_id    = planet_id
	_current_planet_name  = planet_name
	_current_planet_slug  = planet_slug
	_current_planet_ships = ships
	bottom_panel.show_planet(planet_name, planet_id, planet_slug, ships)


func _on_ship_selected(ship: Dictionary) -> void:
	bottom_panel.show_ship(ship, api)


func _on_destination_selected(planet_id: int) -> void:
	var ship_id: int = bottom_panel.current_ship.get("id", 0)
	var result := await api.fly_ship(ship_id, planet_id)
	if not result.is_empty():
		await _refresh_map()


func _on_enter_city_requested(planet_id: int) -> void:
	city_view.show_city({"id": planet_id, "name": _current_planet_name})


func _on_map_tapped() -> void:
	# Игнорируем: этот сигнал — отпускание той же кнопки, что открыла планету
	if _planet_just_tapped:
		_planet_just_tapped = false
		return
	if not city_view.visible and not market_screen.visible:
		bottom_panel.collapse()


func _on_market_requested(planet_id: int) -> void:
	# Используем выбранный корабль, иначе — первый корабль на планете
	var ship: Dictionary = bottom_panel.current_ship
	if ship.is_empty() and not _current_planet_ships.is_empty():
		ship = _current_planet_ships[0]
	if ship.is_empty():
		return
	city_view.visible = false
	market_screen.open(planet_id, ship, api)


func _on_api_failed(message: String) -> void:
	status.show_error(message)
