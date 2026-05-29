extends Node2D
class_name Galaxy

# Контейнер галактической карты: управляет жизненным циклом сущностей
# (планет и кораблей). Координаты — в мировых единицах, зум/пан
# контролируются Camera2D (см. MapCamera).

signal planet_tapped(planet_id: int, planet_name: String, planet_slug: String, ships: Array)

var _planets: Dictionary = {}  # id -> Planet
var _ships:   Dictionary = {}  # id -> Ship


func _ready() -> void:
	pass


func _process(_delta: float) -> void:
	# Корабли двигаются плавно между поллингами — пересчитываем их позицию
	# каждый кадр на основе системного времени.
	if _ships.is_empty():
		return
	var proj := _make_projection()
	for s in _ships.values():
		s.update_layout(proj)


func set_state(data: Dictionary) -> void:
	_sync(data.get("planets", []), _planets, Planet)
	_sync(data.get("ships",   []), _ships,   Ship)
	_relayout()


## Ждёт завершения всех HTTP-загрузок текстур планет и кораблей.
## Вызывать один раз после первого set_state(), до показа игры.
func wait_textures_loaded() -> void:
	for p in _planets.values():
		if p._texture_loading:
			await p.texture_ready
	for s in _ships.values():
		if s._texture_loading:
			await s.texture_ready


func ships_at_planet(planet_id: int) -> Array:
	var result: Array = []
	print("[Galaxy] ships_at_planet planet_id=%d  total_ships=%d" % [planet_id, _ships.size()])
	for s in _ships.values():
		print("  ship id=%d name='%s' in_transit=%s location_id=%d" % [s.ship_id, s.ship_name, s.is_in_transit, s.location_id])
		if not s.is_in_transit and s.location_id == planet_id:
			result.append({
				"id":            s.ship_id,
				"name":          s.ship_name,
				"slug":          s.slug,
				"cargo_used":    s.cargo_used,
				"cargo_capacity": s.cargo_capacity,
				"location_id":   s.location_id,
			})
	print("  -> found %d ships" % result.size())
	return result


# ── internals ────────────────────────────────────────────────────────────────

func _make_projection() -> MapProjection:
	return MapProjection.new()


func _sync(items: Array, store: Dictionary, NodeClass) -> void:
	# Diff-апдейт: создаём новые, обновляем существующие, удаляем лишние.
	var seen := {}
	for raw in items:
		if not (raw is Dictionary):
			continue
		var id := int(raw.get("id", 0))
		seen[id] = true

		var node = store.get(id)
		if node == null:
			node = NodeClass.new()
			add_child(node)
			store[id] = node
			if node is Planet:
				node.pressed.connect(_on_planet_pressed)
		node.apply_data(raw)

	for id in store.keys():
		if not seen.has(id):
			store[id].queue_free()
			store.erase(id)


func _relayout() -> void:
	var proj := _make_projection()
	for p in _planets.values():
		p.update_layout(proj)

	# Назначить dock_index каждому стоящему кораблю (группировка по location_id)
	var dock_counts: Dictionary = {}
	for s in _ships.values():
		if not s.is_in_transit:
			var lid: int = s.location_id
			s.dock_index = dock_counts.get(lid, 0)
			dock_counts[lid] = s.dock_index + 1

	for s in _ships.values():
		s.update_layout(proj)


func _on_planet_pressed(planet_id: int) -> void:
	var planet = _planets.get(planet_id)
	if planet == null:
		return
	var ships := ships_at_planet(planet_id)
	planet_tapped.emit(planet_id, planet.planet_name, planet.slug, ships)
