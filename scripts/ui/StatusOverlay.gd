extends CanvasLayer
class_name StatusOverlay

# UI-оверлей загрузки: центрированный лоадер с прогрессбаром + угловой лейбл для ошибок.

const COLOR_NORMAL  := Color(0.82, 0.91, 1.00)
const COLOR_ERROR   := Color(1.00, 0.58, 0.48)
const FONT_SIZE     := 21          # 16 * 1.3, округлено
const BAR_W         := 300.0
const BAR_H         := 14.0
const BAR_FG        := Color(0.30, 0.62, 1.00)
const BAR_BG        := Color(0.10, 0.14, 0.28)

var _overlay:       Control
var _load_label:    Label
var _progress_bar:  ProgressBar
var _error_label:   Label


func _ready() -> void:
	layer = 10
	_build_ui()


# ── Public API ────────────────────────────────────────────────────────────────

## Показывает экран загрузки с текстом и прогрессом (0.0 – 1.0).
func show_status(text: String, progress: float = -1.0) -> void:
	_error_label.visible = false
	_overlay.visible     = true
	_load_label.text     = text
	if progress >= 0.0:
		_progress_bar.value = progress


func show_error(text: String) -> void:
	_overlay.visible = false
	_error_label.add_theme_color_override("font_color", COLOR_ERROR)
	_error_label.text    = text
	_error_label.visible = true


func clear() -> void:
	_overlay.visible     = false
	_error_label.visible = false


# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# ── Ошибка в верхнем левом углу ──────────────────────────────────────────
	_error_label = Label.new()
	_error_label.position = Vector2(16, 16)
	_error_label.add_theme_font_size_override("font_size", 16)
	_error_label.add_theme_color_override("font_color", COLOR_ERROR)
	_error_label.visible = false
	add_child(_error_label)

	# ── Полноэкранный оверлей загрузки ───────────────────────────────────────
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.04, 0.14, 0.88)
	_overlay.add_child(bg)

	# Центральный вертикальный контейнер
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical   = Control.GROW_DIRECTION_BOTH
	vbox.custom_minimum_size = Vector2(BAR_W, 0)
	vbox.add_theme_constant_override("separation", 18)
	_overlay.add_child(vbox)

	_load_label = Label.new()
	_load_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_load_label.add_theme_color_override("font_color", COLOR_NORMAL)
	_load_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_load_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value          = 0.0
	_progress_bar.max_value          = 1.0
	_progress_bar.value              = 0.0
	_progress_bar.show_percentage    = false
	_progress_bar.custom_minimum_size = Vector2(BAR_W, BAR_H)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = BAR_FG
	fill_style.set_corner_radius_all(int(BAR_H / 2))
	_progress_bar.add_theme_stylebox_override("fill", fill_style)

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = BAR_BG
	bg_style.set_corner_radius_all(int(BAR_H / 2))
	_progress_bar.add_theme_stylebox_override("background", bg_style)

	vbox.add_child(_progress_bar)
