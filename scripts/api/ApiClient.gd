extends Node
class_name ApiClient

# Тонкая обёртка над HTTPRequest. Знает про сервер и форматы тела;
# не знает ничего об игровой логике.

signal request_failed(message: String)


func auth_test_user() -> Dictionary:
	return await _post("/api/users/auth", {
		"telegram_id": Session.telegram_id,
		"username":    Session.username,
		"first_name":  Session.first_name,
		"last_name":   Session.last_name,
	})


func get_map_state() -> Dictionary:
	return await _post("/api/map/state", {"telegram_id": Session.telegram_id})


func get_profile() -> Dictionary:
	return await _get_request("/api/users/me?telegram_id=%d" % Session.telegram_id)


func fly_ship(ship_id: int, destination_id: int) -> Dictionary:
	return await _post("/api/ships/fly", {
		"telegram_id":    Session.telegram_id,
		"ship_id":        ship_id,
		"destination_id": destination_id,
	})


func get_flight_times(ship_id: int) -> Array:
	return await _post_array("/api/ships/flight_times", {
		"telegram_id": Session.telegram_id,
		"ship_id":     ship_id,
	})


func get_planet_market(planet_id: int) -> Dictionary:
	return await _get_request("/api/planets/%d/market?telegram_id=%d" % [planet_id, Session.telegram_id])


func trade_buy(ship_id: int, planet_id: int, resource_id: int, quantity: float) -> Dictionary:
	return await _post("/api/trade/buy", {
		"telegram_id": Session.telegram_id,
		"ship_id":     ship_id,
		"planet_id":   planet_id,
		"resource_id": resource_id,
		"quantity":    quantity,
	})


func trade_sell(ship_id: int, planet_id: int, resource_id: int, quantity: float) -> Dictionary:
	return await _post("/api/trade/sell", {
		"telegram_id": Session.telegram_id,
		"ship_id":     ship_id,
		"planet_id":   planet_id,
		"resource_id": resource_id,
		"quantity":    quantity,
	})


# ── internals ────────────────────────────────────────────────────────────────

func _post(path: String, body: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)

	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := http.request(
		Session.api_base + path,
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(body),
	)
	if err != OK:
		http.queue_free()
		request_failed.emit("Ошибка запроса (%d) %s" % [err, path])
		return {}

	var result: Array = await http.request_completed
	http.queue_free()

	var http_result: int = result[0]
	var code: int        = result[1]
	var raw: PackedByteArray = result[3]

	if http_result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit("Ошибка сети %s" % path)
		return {}

	if code != 200:
		var detail := "Ошибка HTTP %d" % code
		var json2 := JSON.new()
		if json2.parse(raw.get_string_from_utf8()) == OK:
			var d = json2.get_data()
			if d is Dictionary and d.has("detail"):
				detail = str(d["detail"])
		return {"_error": true, "detail": detail}

	var json := JSON.new()
	if json.parse(raw.get_string_from_utf8()) != OK:
		request_failed.emit("Ошибка разбора ответа %s" % path)
		return {}

	var data = json.get_data()
	return data if data is Dictionary else {}


func _post_array(path: String, body: Dictionary) -> Array:
	var http := HTTPRequest.new()
	add_child(http)

	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := http.request(
		Session.api_base + path,
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(body),
	)
	if err != OK:
		http.queue_free()
		request_failed.emit("Ошибка запроса (%d) %s" % [err, path])
		return []

	var result: Array = await http.request_completed
	http.queue_free()

	var http_result: int     = result[0]
	var code: int            = result[1]
	var raw: PackedByteArray = result[3]

	if http_result != HTTPRequest.RESULT_SUCCESS or code != 200:
		request_failed.emit("HTTP %d %s" % [code, path])
		return []

	var json := JSON.new()
	if json.parse(raw.get_string_from_utf8()) != OK:
		request_failed.emit("Ошибка разбора ответа %s" % path)
		return []

	var data = json.get_data()
	return data if data is Array else []


func _get_request(path: String) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)

	var err := http.request(Session.api_base + path)
	if err != OK:
		http.queue_free()
		request_failed.emit("Ошибка запроса (%d) %s" % [err, path])
		return {}

	var result: Array = await http.request_completed
	http.queue_free()

	var http_result: int     = result[0]
	var code: int            = result[1]
	var raw: PackedByteArray = result[3]

	if http_result != HTTPRequest.RESULT_SUCCESS or code != 200:
		request_failed.emit("HTTP %d %s" % [code, path])
		return {}

	var json := JSON.new()
	if json.parse(raw.get_string_from_utf8()) != OK:
		request_failed.emit("Ошибка разбора ответа %s" % path)
		return {}

	var data = json.get_data()
	return data if data is Dictionary else {}


func _post_query(path: String, params: Dictionary) -> Dictionary:
	var url := Session.api_base + path + "?" + _encode_query(params)
	var http := HTTPRequest.new()
	add_child(http)

	var err := http.request(url, PackedStringArray([]), HTTPClient.METHOD_POST, "")
	if err != OK:
		http.queue_free()
		request_failed.emit("Ошибка запроса (%d) %s" % [err, path])
		return {}

	var result: Array = await http.request_completed
	http.queue_free()

	var http_result: int     = result[0]
	var code: int            = result[1]
	var raw: PackedByteArray = result[3]

	if http_result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit("Ошибка сети %s" % path)
		return {}

	if code != 200:
		var detail := "Ошибка HTTP %d" % code
		var json2 := JSON.new()
		if json2.parse(raw.get_string_from_utf8()) == OK:
			var d = json2.get_data()
			if d is Dictionary and d.has("detail"):
				detail = str(d["detail"])
		return {"_error": true, "detail": detail}

	var json := JSON.new()
	if json.parse(raw.get_string_from_utf8()) != OK:
		request_failed.emit("Ошибка разбора ответа %s" % path)
		return {}

	var data = json.get_data()
	return data if data is Dictionary else {}


static func _encode_query(params: Dictionary) -> String:
	var parts := PackedStringArray()
	for key in params:
		parts.append(str(key) + "=" + str(params[key]))
	return "&".join(parts)
