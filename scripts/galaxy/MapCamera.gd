extends Camera2D
class_name MapCamera

## Эмитируется при одиночном клике на карту (без перетаскивания).
signal map_tapped

# Камера карты: зум и пан.
# - колесо мыши / pinch — зум к точке курсора
# - ЛКМ/СКМ/ПКМ перетаскивание — пан
# - PanGesture (тачпады) — пан

const MIN_ZOOM_FACTOR     := 0.25
const MAX_ZOOM_FACTOR     := 6.0
const DEFAULT_ZOOM_FACTOR := 0.8
const WHEEL_STEP          := 1.04
const PAN_THRESHOLD       := 4.0  # px — минимальное смещение, после которого drag считается паном
const MOMENTUM_DURATION   := 0.5  # секунд — время дотормаживания зума после последнего тика
# Для TRANS_QUAD EASE_OUT интеграл нормированной кривой = 1/3,
# поэтому MOMENTUM_SCALE = 3 / MOMENTUM_DURATION гарантирует,
# что суммарный зум за одно нажатие = log(WHEEL_STEP) — ровно столько, сколько было раньше.
const MOMENTUM_SCALE      := 6.0  # = 3.0 / MOMENTUM_DURATION

var _fit_zoom: float = 1.0   # масштаб, при котором карта вписана в окно
var _panning:  bool = false
var _dragging: bool = false
var _pan_start_mouse: Vector2 = Vector2.ZERO
var _pan_start_pos:   Vector2 = Vector2.ZERO

var _zoom_vel:   float   = 0.0          # накопленная скорость зума (в log-пространстве)
var _zoom_vel_pos: Vector2 = Vector2.ZERO  # точка экрана, к которой зумируем
var _zoom_mtween: Tween                 # tween плавного торможения


func _ready() -> void:
	position = Vector2(MapProjection.WORLD_SIZE, MapProjection.WORLD_SIZE) * 0.5
	_recompute_fit_zoom()
	zoom = Vector2.ONE * (_fit_zoom * DEFAULT_ZOOM_FACTOR)
	make_current()


func _recompute_fit_zoom() -> void:
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		_fit_zoom = 1.0
		return
	# Вписываем мировой квадрат WORLD_SIZE × WORLD_SIZE в окно с небольшим запасом
	_fit_zoom = min(vp.x, vp.y) / MapProjection.WORLD_SIZE * 0.9


# ── input ────────────────────────────────────────────────────────────────────

# _input: колесо, жесты, движение, нажатие и отпускание кнопок.
# Планеты расположены выше камеры в сцене (Galaxy → Planet) и вызывают
# set_input_as_handled() до того, как _input дойдёт до MapCamera.
# Поэтому get_viewport().is_input_handled() == true при клике на планету.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed and not _mouse_over_ui():
					_add_zoom_momentum(log(WHEEL_STEP), mb.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed and not _mouse_over_ui():
					_add_zoom_momentum(-log(WHEEL_STEP), mb.position)
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					_panning         = true
					_dragging        = false
					_pan_start_mouse = mb.position
					_pan_start_pos   = position
				else:
					# Одиночный клик (без перетаскивания) по пустому пространству карты
					if mb.button_index == MOUSE_BUTTON_LEFT and _panning and not _dragging:
						map_tapped.emit()
					_panning  = false
					_dragging = false
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventMagnifyGesture:
		_apply_zoom(event.factor, event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture:
		position -= event.delta / zoom.x
		get_viewport().set_input_as_handled()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _panning:
		return
	var delta := event.position - _pan_start_mouse
	if not _dragging and delta.length() < PAN_THRESHOLD:
		return
	_dragging = true
	position = _pan_start_pos - delta / zoom.x
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if abs(_zoom_vel) > 0.00001:
		_apply_zoom(exp(_zoom_vel * delta * MOMENTUM_SCALE), _zoom_vel_pos)


func _add_zoom_momentum(log_step: float, screen_pos: Vector2) -> void:
	_zoom_vel     += log_step
	_zoom_vel_pos  = screen_pos
	if _zoom_mtween:
		_zoom_mtween.kill()
	_zoom_mtween = create_tween()
	_zoom_mtween.tween_property(self, "_zoom_vel", 0.0, MOMENTUM_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# Возвращает true, если мышь над UI-оверлеем (CanvasLayer с layer > 0).
# Фоновый ColorRect в BackgroundLayer (layer=-10) не считается UI.
func _mouse_over_ui() -> bool:
	var ctrl := get_viewport().gui_get_hovered_control()
	if ctrl == null:
		return false
	var node: Node = ctrl
	while node != null:
		if node is CanvasLayer:
			return (node as CanvasLayer).layer > 0
		node = node.get_parent()
	return false


func _apply_zoom(factor: float, screen_pos: Vector2) -> void:
	var min_zoom := _fit_zoom * MIN_ZOOM_FACTOR
	var max_zoom := _fit_zoom * MAX_ZOOM_FACTOR
	var old_z: float = zoom.x
	var new_z: float = clampf(old_z * factor, min_zoom, max_zoom)
	if is_equal_approx(new_z, old_z):
		return
	# Удерживаем точку под курсором на месте при зуме
	var vp_center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var world_under_cursor: Vector2 = position + (screen_pos - vp_center) / old_z
	zoom = Vector2(new_z, new_z)
	position = world_under_cursor - (screen_pos - vp_center) / new_z
