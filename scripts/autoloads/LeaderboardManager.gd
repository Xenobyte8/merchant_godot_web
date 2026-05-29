extends Node

## Синглтон для работы с лидербордами Yandex Games.
##
## Использование:
##   LeaderboardManager.submit_score(int(total_profit))
##
## Имя лидерборда должно совпадать с тем, что создано
## в консоли разработчика Яндекс Игр.

const LEADERBOARD_NAME := "total_profit"

## Храним ссылку на JS-колбэк, чтобы GC его не удалил.
var _set_score_cb = null


## Отправляет очки текущего игрока в лидерборд.
## Безопасно вызывать когда SDK недоступен — вызов игнорируется.
func submit_score(score: int) -> void:
	if not YandexSDK.is_available():
		return
	var bridge = JavaScriptBridge.get_interface("ysdk_bridge")
	if bridge == null:
		return
	var js_cb = JavaScriptBridge.create_callback(_on_score_submitted)
	_set_score_cb = js_cb
	bridge.setLeaderboardScore(LEADERBOARD_NAME, score, js_cb)


func _on_score_submitted(args: Array) -> void:
	var success: bool = args[0] if args.size() > 0 else false
	if not success:
		push_warning("[LeaderboardManager] Не удалось записать очки в лидерборд")
