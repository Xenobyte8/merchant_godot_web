extends CanvasLayer
class_name FrameOverlay

# Декоративный оверлей вокруг игровой карты.
# Три слоя:
#   1. Виньетка — тёмные градиентные края, скрывающие обрезку карты
#   2. Угловые засечки — sci-fi уголки по границам игровой области
#   3. Разделитель у BottomPanel — свечение над нижней панелью

const TOP_BAR_H    := 52.0    # высота TopBar
const BOTTOM_BAR_H := 80.0    # COLLAPSED_H нижней панели

const CORNER_LEN   := 32.0    # длина каждой линии засечки
const CORNER_W     := 2.0     # толщина засечки
const CORNER_INSET := 0.0     # отступ засечек от края экрана

const VIGNETTE_DEPTH := 72.0  # ширина виньетки (px)
const VIGNETTE_STEPS := 18    # количество шагов градиента

const GLOW_STEPS   := 10      # количество строк свечения у BottomPanel

const CORNER_COLOR := Color(0.35, 0.72, 1.00, 0.90)
const VIGNETTE_COLOR := Color(0.02, 0.03, 0.12)
const GLOW_COLOR     := Color(0.35, 0.55, 0.90)


# Используем inner-класс, чтобы переопределить _draw() без отдельного файла
class _Canvas extends Node2D:
	var _overlay: FrameOverlay
	func _draw() -> void:
		if _overlay:
			_overlay._do_draw(get_viewport().get_visible_rect().size)


var _canvas: _Canvas


func _ready() -> void:
	layer = 4   # поверх галактики (0), под панелями (5+)
	_canvas = _Canvas.new()
	_canvas._overlay = self
	add_child(_canvas)
	get_viewport().size_changed.connect(func(): _canvas.queue_redraw())


# ── Главная функция рисования ─────────────────────────────────────────────────

func _do_draw(vp: Vector2) -> void:
	_draw_vignette(vp)
	_draw_corners(vp)
	_draw_bottom_glow(vp)


# ── 1. Виньетка ───────────────────────────────────────────────────────────────
# Тёмные полупрозрачные полосы у краёв игровой области.
# Область карты: от TOP_BAR_H до (vp.y - BOTTOM_BAR_H).

func _draw_vignette(vp: Vector2) -> void:
	var map_top    := TOP_BAR_H
	var map_bottom := vp.y - BOTTOM_BAR_H
	var map_h      := map_bottom - map_top

	for i in range(VIGNETTE_STEPS):
		var t     := float(i) / float(VIGNETTE_STEPS)        # 0 = край, 1 = центр
		var alpha := pow(1.0 - t, 2.2) * 0.82               # квадратичный спад
		var c     := Color(VIGNETTE_COLOR.r, VIGNETTE_COLOR.g, VIGNETTE_COLOR.b, alpha)
		var d     := t * VIGNETTE_DEPTH

		# левый край
		_canvas.draw_rect(Rect2(d, map_top, 1.0, map_h), c)
		# правый край
		_canvas.draw_rect(Rect2(vp.x - d - 1.0, map_top, 1.0, map_h), c)
		# верхний край (сразу под TopBar)
		_canvas.draw_rect(Rect2(0.0, map_top + d, vp.x, 1.0), c)
		# нижний край (сразу над BottomPanel)
		_canvas.draw_rect(Rect2(0.0, map_bottom - d - 1.0, vp.x, 1.0), c)


# ── 2. Угловые засечки ────────────────────────────────────────────────────────
# Тонкие L-образные линии в четырёх углах игровой области.

func _draw_corners(vp: Vector2) -> void:
	var map_top    := TOP_BAR_H    + CORNER_INSET
	var map_bottom := vp.y - BOTTOM_BAR_H - CORNER_INSET
	var map_left   := CORNER_INSET
	var map_right  := vp.x - CORNER_INSET
	var L          := CORNER_LEN
	var W          := CORNER_W

	# Вспомогательная функция: рисует L-образный уголок
	# origin — точка угла, dx/dy — направления двух линий
	var _corner := func(ox: float, oy: float, dx: float, dy: float) -> void:
		_canvas.draw_line(
			Vector2(ox, oy),
			Vector2(ox + dx * L, oy),
			CORNER_COLOR, W, true)
		_canvas.draw_line(
			Vector2(ox, oy),
			Vector2(ox, oy + dy * L),
			CORNER_COLOR, W, true)

	_corner.call(map_left,  map_top,    +1.0, +1.0)  # top-left
	_corner.call(map_right, map_top,    -1.0, +1.0)  # top-right
	_corner.call(map_left,  map_bottom, +1.0, -1.0)  # bottom-left
	_corner.call(map_right, map_bottom, -1.0, -1.0)  # bottom-right

	# Дополнительные короткие засечки посередине сторон (необязательно)
	var cx := vp.x * 0.5
	var half := L * 0.4
	# середина верхней границы
	_canvas.draw_line(Vector2(cx - half, map_top), Vector2(cx + half, map_top),
		Color(CORNER_COLOR.r, CORNER_COLOR.g, CORNER_COLOR.b, 0.35), 1.0)
	# середина нижней границы
	_canvas.draw_line(Vector2(cx - half, map_bottom), Vector2(cx + half, map_bottom),
		Color(CORNER_COLOR.r, CORNER_COLOR.g, CORNER_COLOR.b, 0.35), 1.0)


# ── 3. Свечение у BottomPanel ─────────────────────────────────────────────────
# Мягкое голубоватое свечение, исходящее вверх от верхней границы нижней панели.

func _draw_bottom_glow(vp: Vector2) -> void:
	var y := vp.y - BOTTOM_BAR_H

	# Основная линия (яркая)
	_canvas.draw_line(
		Vector2(0.0, y), Vector2(vp.x, y),
		Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.90), 1.5)

	# Мягкое свечение вверх — каждая строка чуть прозрачнее
	for i in range(1, GLOW_STEPS + 1):
		var alpha := 0.35 * pow(1.0 - float(i) / float(GLOW_STEPS), 1.8)
		_canvas.draw_line(
			Vector2(0.0, y - float(i)),
			Vector2(vp.x,  y - float(i)),
			Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, alpha), 1.0)
