extends Node

## Синглтон для доступа к Yandex Games SDK через JavaScriptBridge.
##
## Если игра запущена не в вебе или SDK недоступен — все методы
## no-op, is_available() возвращает false. Это позволяет запускать
## проект в редакторе без изменений.

signal sdk_ready
signal game_paused
signal game_resumed

var _bridge = null
var _poll_timer: Timer = null

## Ссылки на JS-колбэки храним в полях, иначе GC их удалит.
var _pause_cb = null
var _resume_cb = null
var _player_cb = null


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	_setup_pause_events()
	_try_connect_bridge()


func _try_connect_bridge() -> void:
	_bridge = JavaScriptBridge.get_interface("ysdk_bridge")
	if _bridge != null:
		sdk_ready.emit()
		return
	# bridge.js загружен, но window.ysdk ещё не готов — опрашиваем
	_poll_timer = Timer.new()
	_poll_timer.wait_time = 0.5
	_poll_timer.timeout.connect(_poll_bridge)
	add_child(_poll_timer)
	_poll_timer.start()


func _poll_bridge() -> void:
	_bridge = JavaScriptBridge.get_interface("ysdk_bridge")
	if _bridge == null or not _bridge.isReady():
		return
	_poll_timer.queue_free()
	_poll_timer = null
	sdk_ready.emit()


func _setup_pause_events() -> void:
	_pause_cb = JavaScriptBridge.create_callback(_on_js_pause)
	_resume_cb = JavaScriptBridge.create_callback(_on_js_resume)
	var win = JavaScriptBridge.get_interface("window")
	win["__godot_ysdk_pause_cb"] = _pause_cb
	win["__godot_ysdk_resume_cb"] = _resume_cb
	JavaScriptBridge.eval("""
		window.addEventListener('__ysdk_pause', function () {
			if (window.__godot_ysdk_pause_cb) window.__godot_ysdk_pause_cb();
		});
		window.addEventListener('__ysdk_resume', function () {
			if (window.__godot_ysdk_resume_cb) window.__godot_ysdk_resume_cb();
		});
	""")


## Возвращает true, если SDK инициализирован и bridge готов.
func is_available() -> bool:
	return _bridge != null and _bridge.isReady()


## Вызывать один раз после полной загрузки игры.
## Сигнализирует платформе, что игра готова (убирает экран загрузки Яндекса).
## Также всегда скрывает HTML-лоадер, вне зависимости от наличия SDK.
func signal_loaded() -> void:
	if not OS.has_feature("web"):
		return
	if _bridge != null:
		# signalLoaded в bridge.js скрывает лоадер и вызывает ysdk.ready() если доступен
		_bridge.signalLoaded()
	else:
		# bridge.js ещё не подгрузился — прячем лоадер напрямую через eval
		JavaScriptBridge.eval(
			"var l=document.getElementById('game-loader');" +
			"if(l){l.classList.add('hidden');setTimeout(function(){l.remove();},450);}"
		)


## Асинхронно получает данные игрока.
## callback вызывается с JavaScriptObject { unique_id, name, is_authorized }
## или null, если SDK недоступен или произошла ошибка.
func get_player_async(callback: Callable) -> void:
	if not is_available():
		callback.call(null)
		return
	var js_cb = JavaScriptBridge.create_callback(func(args: Array) -> void:
		callback.call(args[0] if args.size() > 0 else null)
	)
	_player_cb = js_cb  # держим ссылку чтобы GC не удалил
	_bridge.getPlayer(js_cb)


func _on_js_pause(_args: Array) -> void:
	game_paused.emit()


func _on_js_resume(_args: Array) -> void:
	game_resumed.emit()
