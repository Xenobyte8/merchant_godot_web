extends CanvasLayer
class_name StarField

# Звёздное небо: CanvasLayer поверх фона.
# Спрайты центрируются на экране и чуть смещаются вслед за Camera2D
# с разным parallax-коэффициентом — создаётся эффект глубины.
# Текстура 6144×6144 даёт ±3072 px запаса — достаточно для любого зума.

const TILE_SIZE := 6144

const LAYERS := [
	{
		"count":   250,
		"min_r":   1.2,
		"max_r":   5.5,
		"min_a":   0.45,
		"max_a":   0.92,
		"motion":  0.08,
		"seed":    7,
	},
	{
		"count":   170,
		"min_r":   2.2,
		"max_r":   8.0,
		"min_a":   0.65,
		"max_a":   1.0,
		"motion":  0.16,
		"seed":    77,
	},
]

# Хранит [{sprite, motion}] для _process
var _entries: Array = []


func _ready() -> void:
	layer = -5  # за галактикой (layer=0), но над фоном (layer=-10)
	for cfg in LAYERS:
		var sprite := Sprite2D.new()
		sprite.centered = true
		sprite.texture  = _build_star_texture(cfg)
		add_child(sprite)
		_entries.append({"sprite": sprite, "motion": float(cfg.motion)})


func _process(_delta: float) -> void:
	var vp     := get_viewport()
	var center := vp.get_visible_rect().size * 0.5
	var cam    := vp.get_camera_2d()
	var cam_pos := Vector2.ZERO
	if cam != null:
		cam_pos = cam.position
	for entry in _entries:
		entry.sprite.position = center - cam_pos * float(entry.motion)


# ── texture generation ──────────────────────────────────────────────────────

static func _build_star_texture(cfg: Dictionary) -> ImageTexture:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg.seed)

	for _i in int(cfg.count):
		var cx := rng.randi_range(0, TILE_SIZE - 1)
		var cy := rng.randi_range(0, TILE_SIZE - 1)
		var radius: float = lerp(float(cfg.min_r), float(cfg.max_r), rng.randf())
		var alpha:  float = lerp(float(cfg.min_a), float(cfg.max_a), rng.randf())
		_paint_star(img, cx, cy, radius, alpha)

	return ImageTexture.create_from_image(img)


static func _paint_star(img: Image, cx: int, cy: int, radius: float, alpha: float) -> void:
	var r := int(ceil(radius)) + 1
	var w := img.get_width()
	var h := img.get_height()
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var dist := sqrt(float(dx * dx + dy * dy))
			if dist > radius + 0.5:
				continue
			var falloff: float = clampf(1.0 - dist / max(radius, 0.001), 0.0, 1.0)
			var a: float = alpha * falloff
			if a <= 0.01:
				continue
			var px := cx + dx
			var py := cy + dy
			if px < 0 or py < 0 or px >= w or py >= h:
				continue
			img.set_pixel(px, py, Color(1, 1, 1, a))
