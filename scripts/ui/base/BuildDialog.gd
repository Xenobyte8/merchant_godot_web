extends Control
class_name BuildDialog

## Popup overlay: choose a building type to construct at a selected grid cell.

signal build_requested(building_type_id: int, col: int, row: int)
signal cancelled

var _col:            int   = 0
var _row:            int   = 0
var _building_types: Array = []
var _buildings:      Array = []   # existing placed buildings for footprint check

var _title_label: Label
var _list:        VBoxContainer
var _msg_label:   Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func show_for(col: int, row: int, building_types: Array, existing_buildings: Array) -> void:
	_col             = col
	_row             = row
	_building_types  = building_types
	_buildings       = existing_buildings
	_title_label.text = "Клетка [%d, %d] — выберите постройку" % [col, row]
	_msg_label.text  = ""
	_msg_label.visible = false
	_populate()
	visible = true


# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Full-screen dimmer
	var dimmer := ColorRect.new()
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0, 0, 0, 0.65)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dimmer)

	# Centered panel
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(420, 0)
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

	# Header row
	var header := HBoxContainer.new()
	vbox.add_child(header)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_title_label)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.add_theme_font_size_override("font_size", 24)
	close_btn.pressed.connect(_on_cancel)
	header.add_child(close_btn)

	vbox.add_child(HSeparator.new())

	# Scrollable building type list
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 280)
	vbox.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)

	_msg_label = Label.new()
	_msg_label.add_theme_font_size_override("font_size", 16)
	_msg_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	_msg_label.visible = false
	vbox.add_child(_msg_label)


# ── List population ───────────────────────────────────────────────────────────

func _populate() -> void:
	for c in _list.get_children():
		c.queue_free()

	if _building_types.is_empty():
		var lbl := Label.new()
		lbl.text = "Нет доступных построек"
		lbl.add_theme_font_size_override("font_size", 18)
		_list.add_child(lbl)
		return

	for bt in _building_types:
		_list.add_child(_make_type_row(bt))


func _make_type_row(bt: Dictionary) -> Control:
	var sw   := int(bt.get("size_w", 1))
	var sh   := int(bt.get("size_h", 1))
	var fits := _check_fits(_col, _row, sw, sh)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 78)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	margin.add_child(hb)

	var emoji_lbl := Label.new()
	emoji_lbl.text = str(bt.get("emoji", "🏗️"))
	emoji_lbl.add_theme_font_size_override("font_size", 38)
	emoji_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(emoji_lbl)

	var info_vb := VBoxContainer.new()
	info_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vb.add_theme_constant_override("separation", 3)
	hb.add_child(info_vb)

	var name_lbl := Label.new()
	name_lbl.text = str(bt.get("name", ""))
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	info_vb.add_child(name_lbl)

	var effect := str(bt.get("effect_label", bt.get("effect_key", "")))
	var cost   := float(bt.get("cost", 0))
	var sub_lbl := Label.new()
	sub_lbl.text = "%s · %.0f кр · %d×%d кл." % [effect, cost, sw, sh]
	sub_lbl.add_theme_font_size_override("font_size", 15)
	sub_lbl.add_theme_color_override("font_color", Color(0.58, 0.75, 0.95))
	info_vb.add_child(sub_lbl)

	if not fits:
		var no_fit := Label.new()
		no_fit.text = "⚠ Не хватает места"
		no_fit.add_theme_font_size_override("font_size", 14)
		no_fit.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3))
		info_vb.add_child(no_fit)

	var build_btn := Button.new()
	build_btn.text = "Построить"
	build_btn.add_theme_font_size_override("font_size", 18)
	build_btn.disabled = not fits
	build_btn.pressed.connect(func(): _on_build(int(bt.get("id", 0))))
	hb.add_child(build_btn)

	if not fits:
		panel.modulate.a = 0.5

	return panel


# ── Footprint check ───────────────────────────────────────────────────────────

func _check_fits(start_col: int, start_row: int, sw: int, sh: int) -> bool:
	var occupied := {}
	for b in _buildings:
		var bc := int(b.get("col", b.get("grid_x", 0)))
		var br := int(b.get("row", b.get("grid_y", 0)))
		var bw := int(b.get("size_w", 1))
		var bh := int(b.get("size_h", 1))
		for dc in bw:
			for dr in bh:
				occupied["%d,%d" % [bc + dc, br + dr]] = true

	var grid_size := 6  # always 6 from backend
	for dc in sw:
		for dr in sh:
			var c := start_col + dc
			var r := start_row + dr
			if c >= grid_size or r >= grid_size:
				return false
			if occupied.has("%d,%d" % [c, r]):
				return false
	return true


# ── Actions ───────────────────────────────────────────────────────────────────

func _on_build(type_id: int) -> void:
	visible = false
	build_requested.emit(type_id, _col, _row)


func _on_cancel() -> void:
	visible = false
	cancelled.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey \
			and event.pressed and event.keycode == KEY_ESCAPE:
		_on_cancel()
		accept_event()
