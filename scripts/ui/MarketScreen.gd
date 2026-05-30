extends CanvasLayer
class_name MarketScreen

# Экран торговли: покупка ресурсов с планеты / продажа из трюма.
# Открывается из CityView при клике по зданию Рынка.

signal closed
signal trade_completed

const RESOURCE_ICON_URL := "/assets/images/resources/{id}/icon.png"
const ICON_SIZE := 48

var _planet_id:   int        = 0
var _ship:        Dictionary = {}   # default ship for buying
var _all_ships:   Array      = []   # all user ships at this planet
var _sell_ship_idx: int      = -1   # -1 = all ships, >=0 = index in _all_ships
var _view_only:   bool       = false  # true = no ship on planet, prices only
var _api:         ApiClient
var _market_data: Dictionary = {}
var _tab:         String     = "buy"   # "buy" | "sell"
var _fetch_seq:   int        = 0

var _title_label:    Label
var _cargo_label:    Label
var _buy_tab_btn:    Button
var _sell_tab_btn:   Button
var _list_container: VBoxContainer
var _error_toast:    PanelContainer


func _ready() -> void:
	layer   = 20
	visible = false
	_build_ui()


# ── Public API ────────────────────────────────────────────────────────────────

func open(planet_id: int, ship: Dictionary, api: ApiClient, all_ships: Array = []) -> void:
	_planet_id  = planet_id
	_view_only  = ship.is_empty()
	_ship       = ship.duplicate(true)
	if _view_only:
		_all_ships     = []
		_sell_ship_idx = 0
	else:
		_all_ships     = all_ships.duplicate(true) if not all_ships.is_empty() else [ship.duplicate(true)]
		_sell_ship_idx = -1 if _all_ships.size() > 1 else 0
	_api           = api
	_tab           = "buy"
	_market_data   = {}
	visible        = true
	_sell_tab_btn.disabled = _view_only
	_update_cargo_label()
	_set_tab_buttons("buy")
	_load_market()


func close_screen() -> void:
	visible = false
	closed.emit()


# ── Loading ───────────────────────────────────────────────────────────────────

func _load_market() -> void:
	_fetch_seq += 1
	var my_seq := _fetch_seq
	_show_loading()
	var data: Dictionary = await _api.get_planet_market(_planet_id)
	if my_seq != _fetch_seq:
		return
	if data.is_empty():
		_show_error("Не удалось загрузить данные рынка")
		return
	_market_data = data
	_title_label.text = "🏪 " + str(data.get("planet_name", "Рынок"))
	_rebuild_list()


func _show_loading() -> void:
	_clear_list()
	var lbl := Label.new()
	lbl.text = "Загрузка..."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	_list_container.add_child(lbl)


func _show_error(msg: String) -> void:
	_clear_list()
	var lbl := Label.new()
	lbl.text = msg
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
	_list_container.add_child(lbl)


func _show_trade_error(msg: String) -> void:
	if _error_toast == null:
		return
	var lbl: Label = _error_toast.get_child(0)
	if lbl:
		lbl.text = "⚠  " + msg
	_error_toast.visible = true
	var tween := create_tween()
	tween.tween_interval(4.0)
	tween.tween_callback(func(): _error_toast.visible = false)


# ── Tabs ──────────────────────────────────────────────────────────────────────

func _set_tab_buttons(tab: String) -> void:
	_tab = tab
	_buy_tab_btn.flat  = (tab != "buy")
	_sell_tab_btn.flat = (tab != "sell")


func _switch_tab(tab: String) -> void:
	_set_tab_buttons(tab)
	_update_cargo_label()
	if not _market_data.is_empty():
		_rebuild_list()


# ── List building ─────────────────────────────────────────────────────────────

func _clear_list() -> void:
	for child in _list_container.get_children():
		child.queue_free()


func _rebuild_list() -> void:
	_clear_list()
	if _tab == "buy":
		_build_buy_list()
	else:
		_build_sell_list()


func _build_buy_list() -> void:
	var items: Array = _market_data.get("produces", [])
	if items.is_empty():
		_add_placeholder("Здесь нечего купить")
		return
	for item in items:
		_list_container.add_child(_make_buy_row(item))


func _build_sell_list() -> void:
	if _view_only:
		_add_placeholder("Нет корабля на планете — продажа недоступна")
		return
	# ── Селектор корабля (только если кораблей больше одного) ────────────────
	if _all_ships.size() > 1:
		var selector := HBoxContainer.new()
		selector.add_theme_constant_override("separation", 6)
		_list_container.add_child(selector)

		var _make_sel_btn := func(label: String, idx: int) -> Button:
			var b := Button.new()
			b.text = label
			b.flat = (_sell_ship_idx != idx)
			b.custom_minimum_size = Vector2(0, 44)
			b.add_theme_font_size_override("font_size", 20)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.pressed.connect(func():
				_sell_ship_idx = idx
				_rebuild_list()
			)
			return b

		selector.add_child(_make_sel_btn.call("Все трюмы", -1))
		for i in range(_all_ships.size()):
			var short_name: String = _all_ships[i].get("name", "Корабль %d" % i)
			if short_name.length() > 12:
				short_name = short_name.substr(0, 11) + "…"
			selector.add_child(_make_sel_btn.call(short_name, i))

		var sep := HSeparator.new()
		sep.add_theme_color_override("color", Color(0.3, 0.45, 0.7, 0.4))
		_list_container.add_child(sep)

	# ── Индекс покупаемых ресурсов ────────────────────────────────────────────
	var consumes: Array = _market_data.get("consumes", [])
	var consume_map: Dictionary = {}
	for c in consumes:
		consume_map[int(c.get("resource_id", c.get("id", 0)))] = c

	# ── Список товаров ─────────────────────────────────────────────────────────
	if _sell_ship_idx == -1:
		# Все трюмы: секция на каждый корабль
		var any_sellable := false
		for ship in _all_ships:
			var cargo: Array = ship.get("cargo", [])
			var ship_rows := []
			for cargo_item in cargo:
				var rid := int(cargo_item.get("resource_id", 0))
				if consume_map.has(rid) and float(cargo_item.get("quantity", 0)) > 0:
					ship_rows.append(_make_sell_row(ship, cargo_item, consume_map[rid]))
			if ship_rows.is_empty():
				continue
			any_sellable = true
			# Заголовок секции корабля
			var used: float = ship.get("cargo_used", 0.0)
			var cap:  float = ship.get("cargo_capacity", ship.get("effective_cargo_capacity", 0.0))
			var hdr := Label.new()
			hdr.text = "🚀  %s   (%.0f / %.0f т)" % [ship.get("name", "?"), used, cap]
			hdr.add_theme_font_size_override("font_size", 20)
			hdr.add_theme_color_override("font_color", Color(0.65, 0.80, 1.0))
			hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_list_container.add_child(hdr)
			for row in ship_rows:
				_list_container.add_child(row)
		if not any_sellable:
			_add_placeholder("Здесь не покупают ваш груз")
	else:
		# Конкретный корабль
		var ship: Dictionary = _all_ships[_sell_ship_idx]
		var cargo: Array = ship.get("cargo", [])
		var any_sellable := false
		for cargo_item in cargo:
			var rid := int(cargo_item.get("resource_id", 0))
			if consume_map.has(rid) and float(cargo_item.get("quantity", 0)) > 0:
				_list_container.add_child(_make_sell_row(ship, cargo_item, consume_map[rid]))
				any_sellable = true
		if not any_sellable:
			_add_placeholder("Трюм пуст или здесь не покупают ваш груз")


func _add_placeholder(text: String) -> void:
	var lbl := Label.new()
	lbl.text                  = text
	lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.5))
	_list_container.add_child(lbl)


# ── Row factories ─────────────────────────────────────────────────────────────

func _make_buy_row(item: Dictionary) -> Control:
	var resource_id  := int(item.get("resource_id", item.get("id", 0)))
	var name_text    := str(item.get("resource_name", item.get("name", "?")))
	var price: float  = item.get("price", item.get("base_price", 0.0))
	var stock: float  = item.get("stock", item.get("availability", 0.0))
	var weight: float = item.get("weight", 1.0)
	var tax_rate: float = _market_data.get("trade_tax", 0.0)
	var factor: float   = 1.0 + tax_rate  # покупатель платит налог сверху

	var row := _make_row_base(resource_id, name_text, price, "В наличии: %.0f т" % stock)
	var info_box: VBoxContainer = row.get_child(1)

	var total_lbl := Label.new()
	total_lbl.add_theme_font_size_override("font_size", 18)
	total_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	total_lbl.text = "Итого: ≈ %.0f кр" % (price * factor)
	info_box.add_child(total_lbl)

	if _view_only:
		return row

	# MAX = min(запас, место в трюме, хватает денег)
	var free_cargo := float(_ship.get("effective_cargo_capacity", _ship.get("cargo_capacity", 0.0))) \
		- float(_ship.get("cargo_used", 0.0))
	var cargo_max := int(free_cargo / weight) if weight > 0.0 else int(stock)
	var balance_max := int(Session.balance / (price * factor)) if price * factor > 0.0 else int(stock)
	var buy_max := maxi(0, mini(mini(int(stock), cargo_max), balance_max))

	var qty_box := _make_qty_box(mini(1, maxi(buy_max, 1)), maxi(buy_max, 1),
		func(v: int): total_lbl.text = "Итого: ≈ %.0f кр" % (v * price * factor)
	)
	var qty_lbl: Label = qty_box.get_node("QtyLabel")
	row.add_child(qty_box)

	var btn := Button.new()
	btn.text = "Купить"
	btn.custom_minimum_size = Vector2(100, 0)
	btn.add_theme_font_size_override("font_size", 22)
	btn.pressed.connect(func(): _do_buy(resource_id, float(qty_lbl.text), weight))
	row.add_child(btn)

	return row


func _make_sell_row(ship: Dictionary, cargo_item: Dictionary, market_item: Dictionary) -> Control:
	var resource_id  := int(cargo_item.get("resource_id", 0))
	var name_text    := str(cargo_item.get("resource_name", "?"))
	var price: float  = market_item.get("price", market_item.get("base_price", 0.0))
	var in_hold: int  = int(cargo_item.get("quantity", 0))
	var weight: float = cargo_item.get("weight_per_unit", 1.0)
	var tax_rate: float = _market_data.get("trade_tax", 0.0)
	var factor: float   = 1.0 - tax_rate  # продавец получает за вычетом налога

	var row := _make_row_base(resource_id, name_text, price, "В трюме: %d т" % in_hold)
	var info_box: VBoxContainer = row.get_child(1)

	var total_lbl := Label.new()
	total_lbl.add_theme_font_size_override("font_size", 18)
	total_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.55))
	total_lbl.text = "Получите: ≈ %.0f кр" % (price * factor)
	info_box.add_child(total_lbl)

	var qty_box := _make_qty_box(1, in_hold,
		func(v: int): total_lbl.text = "Получите: ≈ %.0f кр" % (v * price * factor)
	)
	var qty_lbl: Label = qty_box.get_node("QtyLabel")
	row.add_child(qty_box)

	var btn := Button.new()
	btn.text = "Продать"
	btn.custom_minimum_size = Vector2(100, 0)
	btn.add_theme_font_size_override("font_size", 22)
	btn.pressed.connect(func(): _do_sell(ship, resource_id, float(qty_lbl.text), weight))
	row.add_child(btn)

	return row


func _make_row_base(resource_id: int, name_text: String, price: float, detail: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)

	# Icon
	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon_rect)
	_load_resource_icon(icon_rect, resource_id)

	var info_box := VBoxContainer.new()
	info_box.custom_minimum_size = Vector2(180, 0)
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_box.add_theme_constant_override("separation", 2)
	row.add_child(info_box)

	var name_lbl := Label.new()
	name_lbl.text = name_text
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	name_lbl.clip_text = true
	info_box.add_child(name_lbl)

	var detail_lbl := Label.new()
	detail_lbl.text = "%.0f кр/т  •  %s" % [price, detail]
	detail_lbl.add_theme_font_size_override("font_size", 18)
	detail_lbl.add_theme_color_override("font_color", Color(0.5, 0.75, 0.5))
	info_box.add_child(detail_lbl)

	return row


func _load_resource_icon(target: TextureRect, resource_id: int) -> void:
	var cache_key := "resource_%d" % resource_id
	var cached = Session.texture_cache.get(cache_key)
	if cached is ImageTexture:
		target.texture = cached
		return
	if Session.texture_cache.get(cache_key) == false:
		return  # previously failed, skip
	var url := Session.api_base + RESOURCE_ICON_URL.replace("{id}", str(resource_id))
	Session.texture_cache[cache_key] = null  # mark as loading
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(result, code, _headers, body):
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


func _make_qty_box(min_val: int, max_val: int, on_change: Callable = Callable()) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.name = "QtyBox"
	box.add_theme_constant_override("separation", 0)

	var minus := Button.new()
	minus.text                  = "−"
	minus.custom_minimum_size   = Vector2(44, 44)
	minus.add_theme_font_size_override("font_size", 26)
	box.add_child(minus)

	var qty_lbl := Label.new()
	qty_lbl.name                 = "QtyLabel"
	qty_lbl.text                 = str(min_val)
	qty_lbl.custom_minimum_size  = Vector2(52, 44)
	qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	qty_lbl.add_theme_font_size_override("font_size", 22)
	qty_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	box.add_child(qty_lbl)

	var plus := Button.new()
	plus.text                 = "+"
	plus.custom_minimum_size  = Vector2(44, 44)
	plus.add_theme_font_size_override("font_size", 26)
	box.add_child(plus)

	minus.pressed.connect(func():
		var v := int(qty_lbl.text)
		if v > min_val:
			qty_lbl.text = str(v - 1)
			if on_change.is_valid():
				on_change.call(v - 1)
	)
	plus.pressed.connect(func():
		var v := int(qty_lbl.text)
		if v < max_val:
			qty_lbl.text = str(v + 1)
			if on_change.is_valid():
				on_change.call(v + 1)
	)

	var max_btn := Button.new()
	max_btn.text                = "MAX"
	max_btn.custom_minimum_size = Vector2(60, 44)
	max_btn.add_theme_font_size_override("font_size", 18)
	box.add_child(max_btn)
	max_btn.pressed.connect(func():
		qty_lbl.text = str(max_val)
		if on_change.is_valid():
			on_change.call(max_val)
	)

	return box


# ── Trade actions ─────────────────────────────────────────────────────────────

func _do_buy(resource_id: int, quantity: float, weight_per_unit: float) -> void:
	var ship_id := int(_ship.get("id", 0))
	var result  := await _api.trade_buy(ship_id, _planet_id, resource_id, quantity)
	if result.get("_error", false):
		_show_trade_error(result.get("detail", "Ошибка покупки"))
		return
	if result.is_empty():
		return
	var actual_qty: float = result.get("quantity", quantity)
	_ship["cargo_used"] = float(_ship.get("cargo_used", 0.0)) + actual_qty * weight_per_unit
	_add_to_cargo(resource_id, actual_qty, str(result.get("resource", "")))
	_update_cargo_label()
	trade_completed.emit()
	_load_market()


func _do_sell(ship: Dictionary, resource_id: int, quantity: float, weight_per_unit: float) -> void:
	var ship_id := int(ship.get("id", 0))
	var result  := await _api.trade_sell(ship_id, _planet_id, resource_id, quantity)
	if result.get("_error", false):
		_show_trade_error(result.get("detail", "Ошибка продажи"))
		return
	if result.is_empty():
		return
	var actual_qty: float = result.get("quantity", quantity)
	ship["cargo_used"] = maxf(0.0, float(ship.get("cargo_used", 0.0)) - actual_qty * weight_per_unit)
	_remove_from_ship_cargo(ship, resource_id, actual_qty)
	_update_cargo_label()
	trade_completed.emit()
	_load_market()


func _add_to_cargo(resource_id: int, qty: float, name_text: String) -> void:
	var cargo: Array = _ship.get("cargo", [])
	for item in cargo:
		if int(item.get("resource_id", 0)) == resource_id:
			item["quantity"] = float(item.get("quantity", 0.0)) + qty
			return
	cargo.append({"resource_id": resource_id, "resource_name": name_text,
		"emoji": "📦", "quantity": qty, "weight_per_unit": 1.0})
	_ship["cargo"] = cargo


func _remove_from_ship_cargo(ship: Dictionary, resource_id: int, qty: float) -> void:
	var cargo: Array = ship.get("cargo", [])
	for i in range(cargo.size()):
		if int(cargo[i].get("resource_id", 0)) == resource_id:
			cargo[i]["quantity"] = float(cargo[i].get("quantity", 0.0)) - qty
			if cargo[i]["quantity"] <= 0:
				cargo.remove_at(i)
			return


func _update_cargo_label() -> void:
	if _view_only:
		_cargo_label.text = "Нет корабля на планете — только цены"
		return
	if _tab == "sell" and _sell_ship_idx == -1 and _all_ships.size() > 1:
		var total_used := 0.0
		var total_cap  := 0.0
		for s in _all_ships:
			total_used += float(s.get("cargo_used", 0.0))
			total_cap  += float(s.get("effective_cargo_capacity", s.get("cargo_capacity", 0.0)))
		_cargo_label.text = "Все корабли (%d)  •  Груз: %.0f / %.0f т" % [_all_ships.size(), total_used, total_cap]
	else:
		var ship: Dictionary = _all_ships[max(0, _sell_ship_idx)] if not _all_ships.is_empty() else _ship
		var used: float = ship.get("cargo_used", 0.0)
		var cap:  float = ship.get("effective_cargo_capacity", ship.get("cargo_capacity", 0.0))
		_cargo_label.text = "%s  •  Груз: %.0f / %.0f т" % [ship.get("name", "Корабль"), used, cap]


# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left   = 1.0
	panel.anchor_right  = 1.0
	panel.anchor_top    = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left   = -650
	panel.offset_right  = 0
	panel.offset_top    = 52
	panel.offset_bottom = -320
	panel.mouse_filter  = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color              = Color(0.02, 0.05, 0.16, 0.97)
	panel_style.border_width_left     = 2
	panel_style.border_color          = Color(0.25, 0.45, 0.75, 0.6)
	panel_style.content_margin_left   = 16
	panel_style.content_margin_right  = 16
	panel_style.content_margin_top    = 12
	panel_style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)

	var root := VBoxContainer.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)

	# ── Шапка ─────────────────────────────────────────────────────────────────
	var header := HBoxContainer.new()
	root.add_child(header)

	_title_label = Label.new()
	_title_label.text = "🏪 Рынок"
	_title_label.add_theme_font_size_override("font_size", 34)
	_title_label.add_theme_color_override("font_color", Color(0.95, 1.0, 0.85))
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.add_theme_font_size_override("font_size", 28)
	close_btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	close_btn.pressed.connect(close_screen)
	header.add_child(close_btn)

	# ── Инфо о трюме ──────────────────────────────────────────────────────────
	_cargo_label = Label.new()
	_cargo_label.add_theme_font_size_override("font_size", 20)
	_cargo_label.add_theme_color_override("font_color", Color(0.55, 0.75, 0.55))
	root.add_child(_cargo_label)

	root.add_child(HSeparator.new())

	# ── Вкладки ───────────────────────────────────────────────────────────────
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	root.add_child(tabs)

	_buy_tab_btn = Button.new()
	_buy_tab_btn.text                   = "  КУПИТЬ  "
	_buy_tab_btn.flat                   = false
	_buy_tab_btn.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	_buy_tab_btn.add_theme_font_size_override("font_size", 24)
	_buy_tab_btn.pressed.connect(func(): _switch_tab("buy"))
	tabs.add_child(_buy_tab_btn)

	_sell_tab_btn = Button.new()
	_sell_tab_btn.text                  = "  ПРОДАТЬ  "
	_sell_tab_btn.flat                  = true
	_sell_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sell_tab_btn.add_theme_font_size_override("font_size", 24)
	_sell_tab_btn.pressed.connect(func(): _switch_tab("sell"))
	tabs.add_child(_sell_tab_btn)

	root.add_child(HSeparator.new())

	# ── Тост с ошибкой торговли ───────────────────────────────────────────────
	_error_toast = PanelContainer.new()
	_error_toast.visible = false
	_error_toast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var toast_style := StyleBoxFlat.new()
	toast_style.bg_color = Color(0.45, 0.08, 0.08, 0.92)
	toast_style.corner_radius_top_left     = 8
	toast_style.corner_radius_top_right    = 8
	toast_style.corner_radius_bottom_left  = 8
	toast_style.corner_radius_bottom_right = 8
	toast_style.content_margin_left   = 16
	toast_style.content_margin_right  = 16
	toast_style.content_margin_top    = 10
	toast_style.content_margin_bottom = 10
	_error_toast.add_theme_stylebox_override("panel", toast_style)
	var toast_lbl := Label.new()
	toast_lbl.add_theme_font_size_override("font_size", 22)
	toast_lbl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.75))
	toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_toast.add_child(toast_lbl)
	root.add_child(_error_toast)

	# ── Прокручиваемый список ─────────────────────────────────────────────────
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_list_container = VBoxContainer.new()
	_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_container.add_theme_constant_override("separation", 18)
	scroll.add_child(_list_container)
