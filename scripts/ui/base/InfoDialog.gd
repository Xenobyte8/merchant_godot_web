extends Control
class_name InfoDialog

## Popup overlay: shows details about a placed building when tapped.

signal closed

var _building: Dictionary = {}

var _title_label: Label
var _content:     VBoxContainer


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func show_for(building: Dictionary) -> void:
	_building = building
	_populate()
	visible = true


# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Full-screen dimmer
	var dimmer := ColorRect.new()
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0, 0, 0, 0.60)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dimmer)

	# Centered panel
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(380, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical   = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	# Header
	var header := HBoxContainer.new()
	vbox.add_child(header)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 26)
	_title_label.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.add_theme_font_size_override("font_size", 24)
	close_btn.pressed.connect(_on_close)
	header.add_child(close_btn)

	vbox.add_child(HSeparator.new())

	# Key-value info rows
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	vbox.add_child(_content)

	vbox.add_child(HSeparator.new())

	# Upgrade placeholder
	var upgrade_lbl := Label.new()
	upgrade_lbl.text = "🔧 Апгрейд здания — скоро"
	upgrade_lbl.add_theme_font_size_override("font_size", 16)
	upgrade_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	vbox.add_child(upgrade_lbl)

	var close_btn2 := Button.new()
	close_btn2.text = "Закрыть"
	close_btn2.add_theme_font_size_override("font_size", 20)
	close_btn2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_btn2.pressed.connect(_on_close)
	vbox.add_child(close_btn2)


# ── Content population ────────────────────────────────────────────────────────

func _populate() -> void:
	var emoji := str(_building.get("emoji", "🏗️"))
	var bld_name := str(_building.get("name", "Здание"))
	_title_label.text = "%s %s" % [emoji, bld_name]

	for c in _content.get_children():
		c.queue_free()

	var sw := int(_building.get("size_w", 1))
	var sh := int(_building.get("size_h", 1))
	var col := int(_building.get("col", _building.get("grid_x", 0)))
	var row := int(_building.get("row", _building.get("grid_y", 0)))

	var rows: Array = [
		["Эффект",  str(_building.get("effect_label", "—"))],
		["Размер",  "%d×%d клеток" % [sw, sh]],
		["Позиция", "колонка %d, ряд %d" % [col, row]],
	]

	var is_prod: bool = bool(_building.get("is_production_active", false))
	if is_prod:
		rows.append(["Производство", "✅ Активно"])
		var salary := float(_building.get("worker_salary_multiplier", 1.0))
		rows.append(["Зарплата рабочих", "%.1f×" % salary])
		var total := float(_building.get("total_produced", 0.0))
		if total > 0:
			rows.append(["Всего произведено", "%.1f ед." % total])
	else:
		var ek := str(_building.get("effect_key", ""))
		if ek in ["grow_grapes", "produce_beer", "produce_wine"]:
			rows.append(["Производство", "⏸ Не активно"])

	for row_data in rows:
		_content.add_child(_make_info_row(str(row_data[0]), str(row_data[1])))


func _make_info_row(key: String, value: String) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)

	var key_lbl := Label.new()
	key_lbl.text = key + ":"
	key_lbl.add_theme_font_size_override("font_size", 17)
	key_lbl.add_theme_color_override("font_color", Color(0.58, 0.75, 0.95))
	key_lbl.custom_minimum_size = Vector2(150, 0)
	hb.add_child(key_lbl)

	var val_lbl := Label.new()
	val_lbl.text = value
	val_lbl.add_theme_font_size_override("font_size", 17)
	val_lbl.add_theme_color_override("font_color", Color(0.92, 0.92, 1.0))
	val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hb.add_child(val_lbl)

	return hb


# ── Actions ───────────────────────────────────────────────────────────────────

func _on_close() -> void:
	visible = false
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey \
			and event.pressed and event.keycode == KEY_ESCAPE:
		_on_close()
		accept_event()
