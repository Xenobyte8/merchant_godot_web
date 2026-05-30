extends Control
class_name ShipModuleGrid

# Отображает схему корабля (Нормандия) через дочерние Control-узлы сцены.
# Каждый узел называется по slug модуля (bow, bridge, …).
# Позиции модулей задаются в редакторе сцены scenes/ui/ShipModuleGrid.tscn.

signal module_tapped(module: Dictionary)

# ── Цвета статусов ────────────────────────────────────────────────────────────
const COLOR_DONE      := Color(0.10, 0.55, 0.48)   # бирюзово-зелёный — готово
const COLOR_AVAILABLE := Color(0.18, 0.38, 0.62)   # синий — можно строить
const COLOR_LOCKED    := Color(0.10, 0.10, 0.16)   # почти чёрный — закрыто

const TEXTURES: Dictionary = {
	"bow":                 preload("res://assets/images/ship_modules/bow.png"),
	"bridge":              preload("res://assets/images/ship_modules/bridge.png"),
	"port_nacelle":        preload("res://assets/images/ship_modules/starboard_nacelle.png"),
	"starboard_nacelle":   preload("res://assets/images/ship_modules/starboard_nacelle.png"),
	"forward_hull":        preload("res://assets/images/ship_modules/forward_hull.png"),
	"port_wing":           preload("res://assets/images/ship_modules/port_wing.png"),
	"starboard_wing":      preload("res://assets/images/ship_modules/starboard_wing.png"),
	"mid_hull":            preload("res://assets/images/ship_modules/mid_hull.png"),
	"aft_hull":            preload("res://assets/images/ship_modules/aft_hull.png"),
	"port_thruster":       preload("res://assets/images/ship_modules/starboard_thruster.png"),
	"starboard_thruster":  preload("res://assets/images/ship_modules/starboard_thruster.png"),
	"main_drive":          preload("res://assets/images/ship_modules/main_drive.png"),
}

var _modules_by_slug: Dictionary = {}   # slug → Dictionary (данные модуля)


func _ready() -> void:
	for child in get_children():
		if child is Control:
			_setup_module_node(child as Control)


# ── Публичный API ────────────────────────────────────────────────────────────

func set_modules(modules: Array) -> void:
	_modules_by_slug.clear()
	for m in modules:
		_modules_by_slug[str(m.get("slug", ""))] = m
	_update_all()


# ── Построение визуальных узлов ──────────────────────────────────────────────

func _setup_module_node(node: Control) -> void:
	node.clip_contents = true
	node.mouse_filter = Control.MOUSE_FILTER_STOP

	# Фон — создаём только если нет в сцене
	if not node.has_node("Bg"):
		var bg := ColorRect.new()
		bg.name = "Bg"
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.color = COLOR_LOCKED
		node.add_child(bg)

	# Иконка — создаём только если нет в сцене
	if not node.has_node("Icon"):
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_bottom = -20.0
		icon.modulate = Color(0.4, 0.45, 0.65)
		node.add_child(icon)

	# Тёмная подложка под метку
	if not node.has_node("LabelBg"):
		var lbl_bg := ColorRect.new()
		lbl_bg.name = "LabelBg"
		lbl_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl_bg.color = Color(0.0, 0.0, 0.0, 0.45)
		lbl_bg.set_anchor(SIDE_LEFT, 0.0)
		lbl_bg.set_anchor(SIDE_RIGHT, 1.0)
		lbl_bg.set_anchor(SIDE_TOP, 1.0)
		lbl_bg.set_anchor(SIDE_BOTTOM, 1.0)
		lbl_bg.offset_top = -24.0
		lbl_bg.offset_bottom = 0.0
		node.add_child(lbl_bg)

	# Метка — создаём только если нет в сцене
	if not node.has_node("NameLabel"):
		var lbl := Label.new()
		lbl.name = "NameLabel"
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.set_anchor(SIDE_LEFT, 0.0)
		lbl.set_anchor(SIDE_RIGHT, 1.0)
		lbl.set_anchor(SIDE_TOP, 1.0)
		lbl.set_anchor(SIDE_BOTTOM, 1.0)
		lbl.offset_top = -22.0
		lbl.offset_bottom = -2.0
		lbl.offset_left = 2.0
		lbl.offset_right = -2.0
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.autowrap_mode        = TextServer.AUTOWRAP_OFF
		lbl.clip_text            = true
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
		node.add_child(lbl)

	# Полоска прогресса — всегда создаём (не видна в редакторе, динамическая)
	if not node.has_node("Bar"):
		var bar := ProgressBar.new()
		bar.name = "Bar"
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.min_value = 0.0
		bar.max_value = 100.0
		bar.value = 0.0
		bar.show_percentage = false
		bar.set_anchor(SIDE_LEFT, 0.0)
		bar.set_anchor(SIDE_RIGHT, 1.0)
		bar.set_anchor(SIDE_TOP, 1.0)
		bar.set_anchor(SIDE_BOTTOM, 1.0)
		bar.offset_top = -8.0
		bar.offset_bottom = 0.0
		bar.visible = false
		node.add_child(bar)

	# Галочка «готово»
	if not node.has_node("DoneLabel"):
		var done_lbl := Label.new()
		done_lbl.name = "DoneLabel"
		done_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		done_lbl.text = "✓"
		done_lbl.set_anchor(SIDE_LEFT, 1.0)
		done_lbl.set_anchor(SIDE_RIGHT, 1.0)
		done_lbl.set_anchor(SIDE_TOP, 0.0)
		done_lbl.set_anchor(SIDE_BOTTOM, 0.0)
		done_lbl.offset_left = -30.0
		done_lbl.offset_right = -4.0
		done_lbl.offset_top = 2.0
		done_lbl.offset_bottom = 28.0
		done_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		done_lbl.add_theme_font_size_override("font_size", 22)
		done_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.85))
		done_lbl.visible = false
		node.add_child(done_lbl)

	# Обработка кликов
	node.gui_input.connect(func(ev: InputEvent) -> void: _on_module_input(node.name, ev))


# ── Обновление состояния ─────────────────────────────────────────────────────

func _update_all() -> void:
	for child in get_children():
		if not (child is Control):
			continue
		var slug := str(child.name)
		var m: Dictionary = _modules_by_slug.get(slug, {})
		if m.is_empty():
			continue
		_update_module_node(child as Control, m)
		# Текстура из bundled ресурсов
		var icon: TextureRect = (child as Control).get_node_or_null("Icon")
		if icon and TEXTURES.has(slug):
			icon.texture = TEXTURES[slug]


func _update_module_node(node: Control, m: Dictionary) -> void:
	var mod_status: String = str(m.get("status", "locked"))
	var is_done:    bool   = (mod_status == "done")

	var bg_color:   Color
	var icon_tint:  Color
	match mod_status:
		"done":
			bg_color  = COLOR_DONE
			icon_tint = Color(0.7, 1.0, 0.92)
		"available":
			bg_color  = COLOR_AVAILABLE
			icon_tint = Color(0.65, 0.85, 1.0)
		_:   # locked
			bg_color  = COLOR_LOCKED
			icon_tint = Color(0.25, 0.27, 0.35)

	var bg: ColorRect = node.get_node_or_null("Bg")
	if bg:
		bg.color = bg_color

	var icon: TextureRect = node.get_node_or_null("Icon")
	if icon:
		icon.modulate = icon_tint

	# Замок-оверлей для locked-модулей
	var lock_lbl: Label = node.get_node_or_null("LockLabel")
	if lock_lbl == null and mod_status == "locked":
		lock_lbl = Label.new()
		lock_lbl.name = "LockLabel"
		lock_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock_lbl.text = "🔒"
		lock_lbl.set_anchor(SIDE_LEFT,  0.0)
		lock_lbl.set_anchor(SIDE_RIGHT, 1.0)
		lock_lbl.set_anchor(SIDE_TOP,   0.0)
		lock_lbl.set_anchor(SIDE_BOTTOM,0.0)
		lock_lbl.offset_top    = 2.0
		lock_lbl.offset_bottom = 28.0
		lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lock_lbl.add_theme_font_size_override("font_size", 16)
		node.add_child(lock_lbl)
	elif lock_lbl != null:
		lock_lbl.visible = (mod_status == "locked")

	var lbl: Label = node.get_node_or_null("NameLabel")
	if lbl:
		lbl.text = str(m.get("name", str(node.name)))

	# Полоска прогресса и галочка больше не нужны — статус отражается цветом
	var bar: ProgressBar = node.get_node_or_null("Bar")
	if bar:
		bar.visible = false

	var check_lbl: Label = node.get_node_or_null("DoneLabel")
	if check_lbl:
		check_lbl.visible = is_done


# ── Ввод ─────────────────────────────────────────────────────────────────────

func _on_module_input(slug: String, ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var m: Dictionary = _modules_by_slug.get(slug, {})
		if not m.is_empty():
			module_tapped.emit(m)
