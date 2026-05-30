extends Node

## Глобальная сессия игрока.
##
## При запуске в вебе (Yandex Games) данные игрока заполняются через SDK.
## В редакторе и вне Яндекса используются тестовые дефолты.
## Main.gd должен вызвать `await Session.ensure_ready()` перед авторизацией.

signal session_initialized

const DEFAULT_API_BASE := "http://138.124.24.149:8080"
const TEST_TELEGRAM_ID := 112383087

var api_base: String = DEFAULT_API_BASE
var telegram_id: int = TEST_TELEGRAM_ID
var username: String = "test_user"
var first_name: String = "Test"
var last_name: String = "User"

## Баланс игрока — обновляется из Main._refresh_balance()
var balance: float = 0.0

## Кэш текстур планет: slug -> ImageTexture (null = в процессе загрузки)
var texture_cache: Dictionary = {}

var _initialized := false


func _ready() -> void:
	# В веб-сборке используем фиксированный API-домен, чтобы запросы всегда
	# шли на api.sonnegames независимо от origin фронта (stage.sonnegames).
	if OS.has_feature("web"):
		api_base = "https://api.sonnegames.xyz"
	_init_session()


func _init_session() -> void:
	if not OS.has_feature("web"):
		_mark_initialized()
		return

	if YandexSDK.is_available():
		YandexSDK.get_player_async(_on_player_data)
	else:
		# SDK ещё загружается — ждём сигнала, но не дольше 5 секунд
		YandexSDK.sdk_ready.connect(_on_sdk_ready, CONNECT_ONE_SHOT)
		var t := Timer.new()
		t.wait_time = 5.0
		t.one_shot = true
		t.timeout.connect(_mark_initialized)
		add_child(t)
		t.start()


func _on_sdk_ready() -> void:
	YandexSDK.get_player_async(_on_player_data)


func _on_player_data(player_js) -> void:
	if player_js != null:
		var uid := str(player_js["unique_id"])
		if uid != "" and uid != "null":
			# Yandex uniqueID — числовая строка; используем напрямую если помещается в int
			telegram_id = int(uid) if uid.is_valid_int() else abs(uid.hash())
			var display_name := str(player_js["name"])
			username   = display_name if display_name != "" else "player_" + uid.substr(0, 8)
			first_name = username
			last_name  = ""
	_mark_initialized()


func _mark_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	session_initialized.emit()


## Ожидает завершения инициализации сессии.
## Возвращается немедленно, если сессия уже готова.
func ensure_ready() -> void:
	if _initialized:
		return
	await session_initialized
