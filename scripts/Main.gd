extends Node2D

# Корневой композитор сцены: связывает ApiClient, Galaxy и StatusOverlay.
# Не содержит ни HTTP, ни рендеринга — только последовательность действий.

@onready var api:            ApiClient         = $ApiClient
@onready var galaxy:         Galaxy            = $Galaxy
@onready var status:         StatusOverlay     = $StatusOverlay
@onready var bottom_panel:   BottomPanel       = $BottomPanel
@onready var city_view:      CityView          = $CityView
@onready var market_screen:  MarketScreen      = $MarketScreen
@onready var quests_inbox:   QuestsInboxScreen = $QuestsInboxScreen
@onready var camera:         MapCamera         = $MapCamera
@onready var top_bar:        TopBar            = $TopBar

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
	market_screen.trade_completed.connect(_refresh_after_trade)
	quests_inbox.closed.connect(_on_quests_inbox_closed)
	camera.map_tapped.connect(_on_map_tapped)
	top_bar.messages_pressed.connect(func(): quests_inbox.open())
	_start()


func _start() -> void:
	await Session.ensure_ready()
	status.show_status("Авторизация...", 0.05)
	var auth := await api.auth_test_user()
	if auth.is_empty():
		return

	status.show_status("Загрузка карты...", 0.35)
	if not await _refresh_map():
		return

	status.show_status("Загрузка изображений...", 0.70)
	await galaxy.wait_textures_loaded()

	status.show_status("Готово!", 1.0)
	_refresh_balance()
	await get_tree().create_timer(0.3).timeout
	status.clear()
	YandexSDK.signal_loaded()
	galaxy.preload_location_cards()  # фоновый прекэш картинок планет
	_start_polling()


func _refresh_map() -> bool:
	var data := await api.get_map_state()
	if data.is_empty():
		return false
	galaxy.set_state(data)
	return true


func _refresh_after_trade() -> void:
	_refresh_balance()
	if not await _refresh_map():
		return
	if _current_planet_id > 0:
		var updated_ships := galaxy.ships_at_planet(_current_planet_id)
		_current_planet_ships = updated_ships
		bottom_panel.show_planet(_current_planet_name, _current_planet_id, _current_planet_slug, updated_ships)


func _refresh_balance() -> void:
	var profile := await api.get_profile()
	if not profile.is_empty() and profile.has("balance"):
		top_bar.set_balance(float(profile["balance"]))


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


func _on_destination_selected(ship_id: int, planet_id: int) -> void:
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
	market_screen.open(planet_id, ship, api, _current_planet_ships)


func _on_api_failed(message: String) -> void:
	status.show_error(message)


func _on_quests_inbox_closed() -> void:
	pass   # при необходимости — обновить карту или статус
