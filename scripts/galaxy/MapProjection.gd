class_name MapProjection
extends RefCounted

# Чистая функция координат: 0..100 (логические) → 0..WORLD_SIZE (мировые).
# Не зависит от размера окна — масштаб контролируется Camera2D.

const WORLD_SIZE := 6000.0


func world_to_screen(x: float, y: float) -> Vector2:
	return Vector2(x * WORLD_SIZE / 100.0, y * WORLD_SIZE / 100.0)
