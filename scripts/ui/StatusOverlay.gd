extends CanvasLayer
class_name StatusOverlay

# UI-оверлей для статусных сообщений (загрузка / ошибки).

const COLOR_NORMAL := Color(0.8, 0.9, 1.0)
const COLOR_ERROR  := Color(1.0, 0.6, 0.5)

var _label: Label


func _ready() -> void:
	layer = 10
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", COLOR_NORMAL)
	add_child(_label)


func show_status(text: String) -> void:
	_label.add_theme_color_override("font_color", COLOR_NORMAL)
	_label.text = text


func show_error(text: String) -> void:
	_label.add_theme_color_override("font_color", COLOR_ERROR)
	_label.text = text


func clear() -> void:
	_label.text = ""
