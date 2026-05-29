extends CanvasLayer
class_name MarketScreen

# Экран торговли: покупка ресурсов с планеты / продажа из трюма.
# Открывается из CityView при клике по зданию Рынка.

signal closed

var _planet_id:   int        = 0
var _ship:        Dictionary = {}
var _api:         ApiClient
var _market_data: Dictionary = {}
var _tab:         String     = "buy"   # "buy" | "sell"
var _fetch_seq:   int        = 0

var _title_label:    Label
var _cargo_label:    Label
var _buy_tab_btn:    Button
var _sell_tab_btn:   Button
var _list_container: VBoxContainer


func _ready() -> void:
	layer   = 20
	visible = false
	_build_ui()


# ── Public API ────────────────────────────────────────────────────────────────

func open(planet_id: int, ship: Dictionary, api: ApiClient) -> void:
	_planet_id   = planet_id
	_ship        = ship.duplicate(true)
	_api         = api
	_tab         = "buy"
	_market_data = {}
	visible      = true
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


# ── Tabs ──────────────────────────────────────────────────────────────────────

func _set_tab_buttons(tab: String) -> void:
	_tab = tab
	_buy_tab_btn.flat  = (tab != "buy")
	_sell_tab_btn.flat = (tab != "sell")


func _switch_tab(tab: String) -> void:
	_set_tab_buttons(tab)
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
	var cargo: Array = _ship.get("cargo", [])
	if cargo.is_empty():
		_add_placeholder("Трюм пуст")
		return
	# Индекс потребляемых ресурсов по id
	var consumes: Array = _market_data.get("consumes", [])
	var consume_map: Dictionary = {}
	for c in consumes:
		consume_map[int(c.get("resource_id", c.get("id", 0)))] = c

	var any_sellable := false
	for cargo_item in cargo:
		var rid := int(cargo_item.get("resource_id", 0))
		if consume_map.has(rid):
			_list_container.add_child(_make_sell_row(cargo_item, consume_map[rid]))
			any_sellable = true
	if not any_sellable:
		_add_placeholder("Здесь не покупают ваш груз")


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
	var resource_id := int(item.get("resource_id", item.get("id", 0)))
	var name_text   := str(item.get("resource_name", item.get("name", "?")))
	var emoji       := str(item.get("emoji", "📦"))
	var price: float = item.get("price", item.get("base_price", 0.0))
	var stock: float = item.get("stock", item.get("availability", 0.0))
	var weight: float = item.get("weight", 1.0)

	var row := _make_row_base(emoji, name_text, price, "В наличии: %.0f т" % stock)

	var qty_box := _make_qty_box(1, 999)
	var qty_lbl: Label = qty_box.get_node("QtyLabel")
	row.add_child(qty_box)

	var btn := Button.new()
	btn.text = "Купить"
	btn.custom_minimum_size = Vector2(100, 0)
	btn.add_theme_font_size_override("font_size", 22)
	btn.pressed.connect(func(): _do_buy(resource_id, float(qty_lbl.text), weight))
	row.add_child(btn)

	return row


func _make_sell_row(cargo_item: Dictionary, market_item: Dictionary) -> Control:
	var resource_id  := int(cargo_item.get("resource_id", 0))
	var name_text    := str(cargo_item.get("resource_name", "?"))
	var emoji        := str(cargo_item.get("emoji", "📦"))
	var price: float  = market_item.get("price", market_item.get("base_price", 0.0))
	var in_hold: int  = int(cargo_item.get("quantity", 0))
	var weight: float = cargo_item.get("weight_per_unit", 1.0)

	var row := _make_row_base(emoji, name_text, price, "В трюме: %d т" % in_hold)

	var qty_box := _make_qty_box(1, in_hold)
	var qty_lbl: Label = qty_box.get_node("QtyLabel")
	row.add_child(qty_box)

	var btn := Button.new()
	btn.text = "Продать"
	btn.custom_minimum_size = Vector2(100, 0)
	btn.add_theme_font_size_override("font_size", 22)
	btn.pressed.connect(func(): _do_sell(resource_id, float(qty_lbl.text), weight))
	row.add_child(btn)

	return row


func _make_row_base(emoji: String, name_text: String, price: float, detail: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)

	var info_box := VBoxContainer.new()
	info_box.custom_minimum_size = Vector2(180, 0)
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_box.add_theme_constant_override("separation", 2)
	row.add_child(info_box)

	var name_lbl := Label.new()
	name_lbl.text = emoji + "  " + name_text
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


func _make_qty_box(min_val: int, max_val: int) -> HBoxContainer:
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
	)
	plus.pressed.connect(func():
		var v := int(qty_lbl.text)
		if v < max_val:
			qty_lbl.text = str(v + 1)
	)

	return box


# ── Trade actions ─────────────────────────────────────────────────────────────

func _do_buy(resource_id: int, quantity: float, weight_per_unit: float) -> void:
	var ship_id := int(_ship.get("id", 0))
	var result  := await _api.trade_buy(ship_id, _planet_id, resource_id, quantity)
	if result.is_empty():
		return
	var actual_qty: float = result.get("quantity", quantity)
	_ship["cargo_used"] = float(_ship.get("cargo_used", 0.0)) + actual_qty * weight_per_unit
	_add_to_cargo(resource_id, actual_qty, str(result.get("resource", "")))
	_update_cargo_label()
	_load_market()


func _do_sell(resource_id: int, quantity: float, weight_per_unit: float) -> void:
	var ship_id := int(_ship.get("id", 0))
	var result  := await _api.trade_sell(ship_id, _planet_id, resource_id, quantity)
	if result.is_empty():
		return
	var actual_qty: float = result.get("quantity", quantity)
	_ship["cargo_used"] = maxf(0.0, float(_ship.get("cargo_used", 0.0)) - actual_qty * weight_per_unit)
	_remove_from_cargo(resource_id, actual_qty)
	_update_cargo_label()
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


func _remove_from_cargo(resource_id: int, qty: float) -> void:
	var cargo: Array = _ship.get("cargo", [])
	for i in range(cargo.size()):
		if int(cargo[i].get("resource_id", 0)) == resource_id:
			cargo[i]["quantity"] = float(cargo[i].get("quantity", 0.0)) - qty
			if cargo[i]["quantity"] <= 0:
				cargo.remove_at(i)
			return


func _update_cargo_label() -> void:
	var used: float = _ship.get("cargo_used", 0.0)
	var cap:  float = _ship.get("effective_cargo_capacity",
		_ship.get("cargo_capacity", 0.0))
	_cargo_label.text = "%s  •  Груз: %.0f / %.0f т" % [
		_ship.get("name", "Корабль"), used, cap]


# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color        = Color(0.02, 0.04, 0.14, 0.98)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left   =  18
	root.offset_right  = -18
	root.offset_top    =  28
	root.offset_bottom = -20
	root.add_theme_constant_override("separation", 10)
	overlay.add_child(root)

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

	# ── Прокручиваемый список ─────────────────────────────────────────────────
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_list_container = VBoxContainer.new()
	_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_container.add_theme_constant_override("separation", 18)
	scroll.add_child(_list_container)
