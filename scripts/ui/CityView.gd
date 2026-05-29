extends CanvasLayer
class_name CityView

# Экран города в стиле HoMM: панорама с кликабельными зданиями.
# Открывается при тапе по планете; сигналит о выборе здания.

signal market_requested(planet_id: int)
signal closed

var _planet_id:   int    = 0
var _planet_name: String = ""

var _title_label: Label


func _ready() -> void:
	layer   = 10
	visible = false
	_build_ui()


func show_city(planet: Dictionary) -> void:
	_planet_id   = int(planet.get("id", 0))
	_planet_name = str(planet.get("name", ""))
	_title_label.text = _planet_name
	visible = true


func hide_city() -> void:
	visible = false
	closed.emit()


# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color        = Color(0.04, 0.06, 0.18, 0.97)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left   =  24
	root.offset_right  = -24
	root.offset_top    =  48
	root.offset_bottom = -32
	root.add_theme_constant_override("separation", 20)
	overlay.add_child(root)

	# ── Шапка ────────────────────────────────────────────────────────────────
	var header := HBoxContainer.new()
	root.add_child(header)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 38)
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.add_theme_font_size_override("font_size", 30)
	close_btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	close_btn.pressed.connect(hide_city)
	header.add_child(close_btn)

	# ── Подпись ───────────────────────────────────────────────────────────────
	var subtitle := Label.new()
	subtitle.text = "Выберите здание"
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", Color(0.45, 0.55, 0.75))
	root.add_child(subtitle)

	# ── Ряд зданий ────────────────────────────────────────────────────────────
	var buildings_row := HBoxContainer.new()
	buildings_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buildings_row.add_theme_constant_override("separation", 20)
	root.add_child(buildings_row)

	buildings_row.add_child(_make_building("🏪", "Рынок",   _on_market_pressed, false))
	buildings_row.add_child(_make_building("⚙️", "Верфь",   func(): pass,       true))
	buildings_row.add_child(_make_building("🍺", "Таверна", func(): pass,       true))
	buildings_row.add_child(_make_building("🏦", "Банк",    func(): pass,       true))


func _make_building(emoji: String, label_text: String, callback: Callable, disabled: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(110, 140)

	var btn := Button.new()
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.flat     = true
	btn.disabled = disabled
	if not disabled:
		btn.pressed.connect(callback)
	panel.add_child(btn)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.add_child(vbox)

	var emoji_lbl := Label.new()
	emoji_lbl.text                    = emoji
	emoji_lbl.horizontal_alignment    = HORIZONTAL_ALIGNMENT_CENTER
	emoji_lbl.add_theme_font_size_override("font_size", 52)
	emoji_lbl.mouse_filter            = Control.MOUSE_FILTER_PASS
	vbox.add_child(emoji_lbl)

	var name_lbl := Label.new()
	name_lbl.text                  = label_text
	name_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.mouse_filter          = Control.MOUSE_FILTER_PASS
	if disabled:
		name_lbl.add_theme_color_override("font_color", Color(0.35, 0.35, 0.45))
	else:
		name_lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	vbox.add_child(name_lbl)

	return panel


func _on_market_pressed() -> void:
	market_requested.emit(_planet_id)
