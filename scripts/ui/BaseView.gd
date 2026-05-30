extends CanvasLayer
class_name BaseView

# Экран базы игрока — отображает личный проект постройки корабля (Нормандия)
# и склад базы.

signal closed

var _api:             ApiClient
var _planet_id:       int    = 0
var _planet_name:     String = ""
var _storage:         Array  = []
var _storage_capacity: float = 0.0
var _storage_used:    float  = 0.0
var _docked_ships:    Array  = []
var _selected_ship_id: int   = 0
var _busy:            bool   = false

# ── Данные проекта ───────────────────────────────────────────────────────────
var _ship_project: Dictionary = {}   # полный ответ от /api/ship_project/status

const _SHIP_GRID_SCENE = preload("res://scenes/ui/ShipModuleGrid.tscn")

# ── UI узлы ──────────────────────────────────────────────────────────────────
var _title_label:       Label
var _progress_label:    Label
var _ship_grid:         ShipModuleGrid
var _storage_list:      VBoxContainer
var _storage_header:    Label
var _ship_picker:       OptionButton
var _msg_label:         Label
var _module_info_panel: Control


func _ready() -> void:
	layer = 11
	visible = false
	_build_ui()


# ── Публичный API ────────────────────────────────────────────────────────────

func open(planet_id: int, planet_name: String, api: ApiClient, docked_ships: Array) -> void:
	_api = api
	_planet_id = planet_id
	_planet_name = planet_name
	_docked_ships = docked_ships
	_title_label.text = "🚀 " + planet_name
	visible = true
	_refresh_ship_picker()
	await _refresh_all()


func close_view() -> void:
	visible = false
	closed.emit()


# ── UI ────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.04, 0.05, 0.12, 0.99)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left   =  20
	root.offset_right  = -20
	root.offset_top    =  28
	root.offset_bottom = -20
	root.add_theme_constant_override("separation", 8)
	overlay.add_child(root)

	# ── Шапка ────────────────────────────────────────────────────────────────
	var header := HBoxContainer.new()
	root.add_child(header)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 30)
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.add_theme_font_size_override("font_size", 30)
	close_btn.pressed.connect(close_view)
	header.add_child(close_btn)

	# ── Прогресс корабля ──────────────────────────────────────────────────────
	_progress_label = Label.new()
	_progress_label.text = "🛸 Постройка корабля — загрузка…"
	_progress_label.add_theme_font_size_override("font_size", 19)
	_progress_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	root.add_child(_progress_label)

	_msg_label = Label.new()
	_msg_label.add_theme_font_size_override("font_size", 17)
	_msg_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	_msg_label.visible = false
	root.add_child(_msg_label)

	# ── Схема корабля ─────────────────────────────────────────────────────────
	_ship_grid = _SHIP_GRID_SCENE.instantiate() as ShipModuleGrid
	_ship_grid.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_ship_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ship_grid.mouse_filter = Control.MOUSE_FILTER_STOP
	_ship_grid.module_tapped.connect(_on_module_tapped)
	root.add_child(_ship_grid)

	# ── Склад (панель снизу) ───────────────────────────────────────────────────
	var stor_panel := PanelContainer.new()
	stor_panel.custom_minimum_size = Vector2(0, 160)
	root.add_child(stor_panel)

	var stor_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		stor_margin.add_theme_constant_override("margin_" + side, 10)
	stor_panel.add_child(stor_margin)

	var stor_col := VBoxContainer.new()
	stor_col.add_theme_constant_override("separation", 6)
	stor_margin.add_child(stor_col)

	_storage_header = Label.new()
	_storage_header.text = "📦 Склад"
	_storage_header.add_theme_font_size_override("font_size", 20)
	_storage_header.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	stor_col.add_child(_storage_header)

	var ship_row := HBoxContainer.new()
	stor_col.add_child(ship_row)

	var ship_lbl := Label.new()
	ship_lbl.text = "Корабль:"
	ship_lbl.add_theme_font_size_override("font_size", 17)
	ship_row.add_child(ship_lbl)

	_ship_picker = OptionButton.new()
	_ship_picker.add_theme_font_size_override("font_size", 17)
	_ship_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ship_picker.item_selected.connect(_on_ship_selected)
	ship_row.add_child(_ship_picker)

	var stor_scroll := ScrollContainer.new()
	stor_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stor_col.add_child(stor_scroll)

	_storage_list = VBoxContainer.new()
	_storage_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_storage_list.add_theme_constant_override("separation", 5)
	stor_scroll.add_child(_storage_list)

	# ── Попап информации о модуле ─────────────────────────────────────────────
	_module_info_panel = _build_module_info_panel()
	add_child(_module_info_panel)


func _build_module_info_panel() -> Control:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(360, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.visible = false
	panel.set_meta("_content_col", null)  # placeholder

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)
	panel.set_meta("_content_col", col)

	var close_row := HBoxContainer.new()
	col.add_child(close_row)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_row.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.pressed.connect(func(): panel.visible = false)
	close_row.add_child(close_btn)

	return panel


# ── Загрузка состояния ───────────────────────────────────────────────────────

func _refresh_all() -> void:
	if _api == null or _planet_id <= 0:
		return
	_busy = true
	var proj := await _api.get_ship_project()
	var s    := await _api.get_base_storage(_planet_id)
	_busy = false

	if proj.has("_error"):
		_show_msg(_extract_err(proj))
		return
	_ship_project = proj

	if not s.has("_error"):
		_storage          = s.get("items", [])
		_storage_capacity = float(s.get("capacity", 0.0))
		_storage_used     = float(s.get("used", 0.0))

	_redraw()


func _redraw() -> void:
	# ── Корабль ───────────────────────────────────────────────────────────────
	var modules: Array = _ship_project.get("modules", [])
	var ship_name: String = str(_ship_project.get("ship_name", "Нормандия"))
	var pct: float = float(_ship_project.get("progress_pct", 0.0))
	var done_count := modules.filter(func(m): return bool(m.get("is_done", false))).size()
	_title_label.text = "🚀 " + _planet_name + "  •  " + ship_name
	_progress_label.text = "Сборка корабля: %d / %d модулей  (%.0f%%)" % [done_count, modules.size(), pct]
	_ship_grid.set_modules(modules)

	# ── Склад ────────────────────────────────────────────────────────────────
	_storage_header.text = "📦 Склад · %.1f / %.1f т" % [_storage_used, _storage_capacity]

	for child in _storage_list.get_children():
		child.queue_free()

	if _storage.is_empty():
		var empty := Label.new()
		empty.text = "Склад пуст."
		empty.add_theme_font_size_override("font_size", 17)
		empty.add_theme_color_override("font_color", Color(0.55, 0.65, 0.8))
		_storage_list.add_child(empty)
	else:
		for item in _storage:
			_storage_list.add_child(_make_storage_row(item))

	if _selected_ship_id > 0:
		var ship := _find_ship(_selected_ship_id)
		var ship_cargo: Array = ship.get("cargo", []) if not ship.is_empty() else []
		for item in ship_cargo:
			_storage_list.add_child(_make_ship_cargo_row(item))


# ── Модуль — попап информации ────────────────────────────────────────────────

func _on_module_tapped(module: Dictionary) -> void:
	_show_module_info(module)


func _show_module_info(m: Dictionary) -> void:
	var col: VBoxContainer = _module_info_panel.get_meta("_content_col") as VBoxContainer
	if col == null:
		return

	# Clear all children except the close button row (first child)
	var children := col.get_children()
	for i in range(1, children.size()):
		children[i].queue_free()

	var pct: float   = float(m.get("progress_pct", 0.0))
	var is_done: bool = bool(m.get("is_done", false))

	var name_lbl := Label.new()
	name_lbl.text = str(m.get("name", "Модуль"))
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	col.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = str(m.get("description", ""))
	desc_lbl.add_theme_font_size_override("font_size", 17)
	desc_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.9))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(desc_lbl)

	var status_lbl := Label.new()
	if is_done:
		status_lbl.text = "✅ Готово"
		status_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.8))
	elif pct > 0:
		status_lbl.text = "🔧 В работе — %.0f%%" % pct
		status_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	else:
		status_lbl.text = "⏳ Не начат"
		status_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.8))
	status_lbl.add_theme_font_size_override("font_size", 20)
	col.add_child(status_lbl)

	_module_info_panel.visible = true


# ── Склад — вспомогательные функции ──────────────────────────────────────────

func _make_storage_row(item: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var lbl := Label.new()
	lbl.text = "%s %s × %d" % [
		str(item.get("emoji", "📦")),
		str(item.get("name", "")),
		int(item.get("quantity", 0)),
	]
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	if _selected_ship_id > 0:
		var btn := Button.new()
		btn.text = "→ корабль"
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(func(): _on_transfer_to_ship(int(item.get("resource_id", 0)), int(item.get("quantity", 0))))
		row.add_child(btn)

	return row


func _make_ship_cargo_row(item: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var lbl := Label.new()
	var item_name  := str(item.get("name", ""))
	var item_emoji := str(item.get("emoji", "📦"))
	var qty        := int(item.get("quantity", 0))
	lbl.text = "← %s %s × %d (в трюме)" % [item_emoji, item_name, qty]
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.7))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var btn := Button.new()
	btn.text = "→ склад"
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(func(): _on_load_from_ship(int(item.get("resource_id", 0)), qty))
	row.add_child(btn)

	return row


func _refresh_ship_picker() -> void:
	_ship_picker.clear()
	_selected_ship_id = 0
	if _docked_ships.is_empty():
		_ship_picker.add_item("Нет кораблей на базе")
		_ship_picker.disabled = true
		return
	_ship_picker.disabled = false
	for i in _docked_ships.size():
		var s: Dictionary = _docked_ships[i]
		_ship_picker.add_item(str(s.get("name", "Корабль")), int(s.get("id", 0)))
	_ship_picker.select(0)
	_selected_ship_id = int(_docked_ships[0].get("id", 0))


func _on_ship_selected(index: int) -> void:
	_selected_ship_id = _ship_picker.get_item_id(index)
	_redraw()


# ── Действия (склад) ─────────────────────────────────────────────────────────

func _on_transfer_to_ship(resource_id: int, max_qty: int) -> void:
	if _busy or _selected_ship_id <= 0 or resource_id <= 0 or max_qty <= 0:
		return
	_busy = true
	var res := await _api.base_storage_transfer_to_ship(_planet_id, _selected_ship_id, resource_id, max_qty)
	_busy = false
	if res.has("_error"):
		_show_msg(_extract_err(res))
		return
	_show_msg(str(res.get("message", "Перенесено")))
	await _refresh_all()


func _on_load_from_ship(resource_id: int, max_qty: int) -> void:
	if _busy or _selected_ship_id <= 0 or resource_id <= 0 or max_qty <= 0:
		return
	_busy = true
	var res := await _api.base_storage_load_from_ship(_planet_id, _selected_ship_id, resource_id, max_qty)
	_busy = false
	if res.has("_error"):
		_show_msg(_extract_err(res))
		return
	_show_msg(str(res.get("message", "Перенесено")))
	await _refresh_all()


# ── Хелперы ──────────────────────────────────────────────────────────────────

func _find_ship(ship_id: int) -> Dictionary:
	for s in _docked_ships:
		if int(s.get("id", 0)) == ship_id:
			return s
	return {}


func _show_msg(text: String) -> void:
	_msg_label.text    = text
	_msg_label.visible = true


func _hide_msg() -> void:
	_msg_label.visible = false


func _extract_err(d: Dictionary) -> String:
	return str(d.get("detail", "Ошибка"))
