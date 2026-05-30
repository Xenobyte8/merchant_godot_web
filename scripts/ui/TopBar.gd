extends CanvasLayer
class_name TopBar

# Глобальная верхняя плашка: баланс игрока (слева) + кнопка сообщений (справа).
# Всегда поверх карты, ниже полноэкранных оверлеев (layer = 9).

signal messages_pressed

const BAR_HEIGHT      := 52
const SIDE_PADDING    := 16
const BG_COLOR        := Color(0.04, 0.07, 0.20, 0.92)
const BORDER_COLOR    := Color(0.20, 0.30, 0.60, 0.70)
const BALANCE_COLOR   := Color(0.92, 0.85, 0.30, 1.0)   # золотистый
const BTN_NORMAL_COLOR := Color(0.10, 0.16, 0.38, 0.92)
const BTN_BORDER_COLOR := Color(0.30, 0.45, 0.85, 0.80)

var _balance_label: Label
var _messages_btn: Button


func _ready() -> void:
	layer = 9
	_build_ui()


func set_balance(amount: float) -> void:
	_balance_label.text = "₿ %s" % _format_number(amount)


func set_messages_badge(count: int) -> void:
	if count > 0:
		_messages_btn.text = "📋 %d" % count
	else:
		_messages_btn.text = "📋"


# ── Private ───────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Фоновая панель
	var bar := Panel.new()
	bar.anchor_right = 1.0
	bar.offset_bottom = BAR_HEIGHT
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = BG_COLOR
	bg_style.border_color = BORDER_COLOR
	bg_style.set_border_width_all(0)
	bg_style.border_width_bottom = 1
	bar.add_theme_stylebox_override("panel", bg_style)
	add_child(bar)

	# HBoxContainer внутри панели
	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left  = SIDE_PADDING
	hbox.offset_right = -SIDE_PADDING
	hbox.add_theme_constant_override("separation", 8)
	bar.add_child(hbox)

	# ── Левая часть: баланс ──────────────────────────────────────────────────
	_balance_label = Label.new()
	_balance_label.text = "₿ —"
	_balance_label.add_theme_font_size_override("font_size", 26)
	_balance_label.add_theme_color_override("font_color", BALANCE_COLOR)
	_balance_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_balance_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_balance_label)

	# ── Правая часть: кнопка сообщений ──────────────────────────────────────
	_messages_btn = Button.new()
	_messages_btn.text = "📋"
	_messages_btn.add_theme_font_size_override("font_size", 22)
	_messages_btn.custom_minimum_size = Vector2(48, 36)
	_messages_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = BTN_NORMAL_COLOR
	normal_style.border_color = BTN_BORDER_COLOR
	normal_style.set_border_width_all(1)
	normal_style.set_corner_radius_all(8)
	_messages_btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.16, 0.24, 0.52, 0.95)
	hover_style.border_color = Color(0.50, 0.68, 1.0, 0.90)
	hover_style.set_border_width_all(1)
	hover_style.set_corner_radius_all(8)
	_messages_btn.add_theme_stylebox_override("hover", hover_style)

	_messages_btn.pressed.connect(func(): messages_pressed.emit())
	hbox.add_child(_messages_btn)


func _format_number(n: float) -> String:
	var i := int(n)
	if i >= 1_000_000:
		return "%.1f М" % (i / 1_000_000.0)
	elif i >= 1_000:
		# Разбиваем тысячи пробелом: 12 400
		var thousands := i / 1000
		var remainder := i % 1000
		return "%d %03d" % [thousands, remainder]
	return str(i)
