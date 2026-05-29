extends CanvasLayer
class_name QuestsInboxScreen

# Экран «Общие задания» — список квестов от НПС в стиле почтового инбокса.
# Пока работает только на шаблонных данных, без обращения к бэкенду.

signal closed

# ── Шаблонные данные ──────────────────────────────────────────────────────────

const MOCK_QUESTS := [
	{
		"id": 1,
		"npc_name":   "Харун аль-Рашид",
		"npc_role":   "Торговый магнат",
		"npc_color":  Color(0.42, 0.36, 0.91),
		"received":   "12 мин. назад",
		"title":      "Срочная поставка кристаллов",
		"body":       "Мне срочно нужно 500 единиц энергетических кристаллов на планете Сигма-7. Мои конкуренты уже в пути — кто доставит первым, получит двойную цену.",
		"reward":     "₿ 12 400",
		"status":     "pending",   # pending | accepted | declined
	},
	{
		"id": 2,
		"npc_name":   "Адмирал Весна",
		"npc_role":   "Командующий 3-го флота",
		"npc_color":  Color(0.06, 0.55, 0.73),
		"received":   "1 ч. 34 мин. назад",
		"title":      "Военный контракт: провиант для флота",
		"body":       "Третий флот Альянса испытывает нехватку провизии. Требуется доставить 1 200 рационов питания на базу «Орион-Прим» в течение 48 часов. Контракт оплачивается авансом.",
		"reward":     "₿ 8 750 + репутация",
		"status":     "pending",
	},
	{
		"id": 3,
		"npc_name":   "Доктор Мира Солей",
		"npc_role":   "Главный медик колонии",
		"npc_color":  Color(0.05, 0.72, 0.46),
		"received":   "3 ч. 5 мин. назад",
		"title":      "Медикаменты для колонии Новая Надежда",
		"body":       "На колонии Новая Надежда вспышка лихорадки Денеб. Нам нужны антипиретики и регенеративные сыворотки. Пожалуйста, доставьте 300 единиц медикаментов как можно скорее. Жизни людей на кону.",
		"reward":     "₿ 6 200 + благодарность",
		"status":     "pending",
	},
	{
		"id": 4,
		"npc_name":   "Феликс Дарк",
		"npc_role":   "Независимый брокер",
		"npc_color":  Color(0.88, 0.44, 0.21),
		"received":   "7 ч. назад",
		"title":      "Редкие артефакты с Пояса Обломков",
		"body":       "Один мой клиент платит большие деньги за артефакты с Пояса Обломков. Нужно собрать 15 единиц реликвий и доставить на станцию «Тёмный Мост». Вопросов не задаю.",
		"reward":     "₿ 18 000",
		"status":     "pending",
	},
	{
		"id": 5,
		"npc_name":   "Губернатор Таль",
		"npc_role":   "Правитель системы Кета",
		"npc_color":  Color(0.46, 0.73, 1.00),
		"received":   "1 день назад",
		"title":      "Восстановление инфраструктуры",
		"body":       "После последнего пиратского набега нам требуются строительные материалы для восстановления орбитальных доков. Заказ на 800 единиц металлических сплавов. Срок — 72 часа.",
		"reward":     "₿ 9 100 + торговая лицензия",
		"status":     "pending",
	},
]

# ── Состояние ─────────────────────────────────────────────────────────────────

var _quests: Array = []
var _card_nodes: Dictionary = {}   # id -> card root node
var _list: VBoxContainer


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer   = 15
	visible = false
	_quests = MOCK_QUESTS.duplicate(true)
	_build_ui()


func open() -> void:
	visible = true


func close_screen() -> void:
	visible = false
	closed.emit()


# ── UI Build ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# ── Полноэкранный фон ────────────────────────────────────────────────────
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color        = Color(0.04, 0.06, 0.18, 0.97)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	# ── Корневой контейнер ───────────────────────────────────────────────────
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left   =  28
	root.offset_right  = -28
	root.offset_top    =  52
	root.offset_bottom = -24
	root.add_theme_constant_override("separation", 14)
	overlay.add_child(root)

	# ── Шапка: заголовок + кнопка закрытия ──────────────────────────────────
	var header := HBoxContainer.new()
	root.add_child(header)

	var title_lbl := Label.new()
	title_lbl.text = "📋  Общие задания"
	title_lbl.add_theme_font_size_override("font_size", 32)
	title_lbl.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.add_theme_font_size_override("font_size", 26)
	close_btn.add_theme_color_override("font_color", Color(0.55, 0.60, 0.72))
	close_btn.pressed.connect(close_screen)
	header.add_child(close_btn)

	# ── Разделитель ──────────────────────────────────────────────────────────
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(0.2, 0.25, 0.45))
	root.add_child(sep)

	# ── Скролл-список ────────────────────────────────────────────────────────
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_list)

	# ── Карточки квестов ─────────────────────────────────────────────────────
	for q in _quests:
		var card := _build_quest_card(q)
		_card_nodes[q["id"]] = card
		_list.add_child(card)


func _build_quest_card(q: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()

	var bg := StyleBoxFlat.new()
	bg.bg_color              = Color(0.08, 0.11, 0.24, 1.0)
	bg.border_color          = Color(0.18, 0.24, 0.50, 1.0)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(8)
	bg.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", bg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)

	# ── Строка: аватар + имя/роль + дата ────────────────────────────────────
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 10)
	vbox.add_child(top_row)

	# Аватар — цветной круг с первой буквой имени
	var avatar := _build_avatar(q["npc_name"], q["npc_color"])
	top_row.add_child(avatar)

	# Имя + роль
	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.add_theme_constant_override("separation", 2)
	top_row.add_child(name_col)

	var name_lbl := Label.new()
	name_lbl.text = q["npc_name"]
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(0.98, 0.82, 0.42))
	name_col.add_child(name_lbl)

	var role_lbl := Label.new()
	role_lbl.text = q["npc_role"]
	role_lbl.add_theme_font_size_override("font_size", 12)
	role_lbl.add_theme_color_override("font_color", Color(0.45, 0.52, 0.68))
	name_col.add_child(role_lbl)

	# Дата
	var date_lbl := Label.new()
	date_lbl.text = q["received"]
	date_lbl.add_theme_font_size_override("font_size", 11)
	date_lbl.add_theme_color_override("font_color", Color(0.40, 0.46, 0.62))
	date_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_row.add_child(date_lbl)

	# ── Горизонтальная линия ─────────────────────────────────────────────────
	var divider := HSeparator.new()
	divider.add_theme_color_override("color", Color(0.15, 0.20, 0.42))
	vbox.add_child(divider)

	# ── Заголовок квеста ─────────────────────────────────────────────────────
	var title_lbl := Label.new()
	title_lbl.text = q["title"]
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", Color(0.55, 0.82, 1.0))
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(title_lbl)

	# ── Текст квеста ─────────────────────────────────────────────────────────
	var body_lbl := Label.new()
	body_lbl.text = q["body"]
	body_lbl.add_theme_font_size_override("font_size", 13)
	body_lbl.add_theme_color_override("font_color", Color(0.62, 0.68, 0.82))
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(body_lbl)

	# ── Блок награды ─────────────────────────────────────────────────────────
	var reward_panel := PanelContainer.new()
	var reward_style := StyleBoxFlat.new()
	reward_style.bg_color = Color(0.06, 0.14, 0.22, 1.0)
	reward_style.set_corner_radius_all(6)
	reward_style.set_content_margin_all(8)
	reward_panel.add_theme_stylebox_override("panel", reward_style)
	vbox.add_child(reward_panel)

	var reward_row := HBoxContainer.new()
	reward_panel.add_child(reward_row)

	var trophy_lbl := Label.new()
	trophy_lbl.text = "🏆"
	trophy_lbl.add_theme_font_size_override("font_size", 14)
	reward_row.add_child(trophy_lbl)

	var reward_lbl := Label.new()
	reward_lbl.text = "  Награда: " + q["reward"]
	reward_lbl.add_theme_font_size_override("font_size", 13)
	reward_lbl.add_theme_color_override("font_color", Color(0.38, 0.92, 0.62))
	reward_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reward_row.add_child(reward_lbl)

	# ── Кнопки или статус ────────────────────────────────────────────────────
	if q["status"] == "pending":
		var btn_row := HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 10)
		vbox.add_child(btn_row)

		var decline_btn := Button.new()
		decline_btn.text = "Отказать"
		decline_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(decline_btn, Color(0.72, 0.22, 0.22, 0.25), Color(0.90, 0.40, 0.40))
		decline_btn.pressed.connect(_on_decline.bind(q["id"]))
		btn_row.add_child(decline_btn)

		var accept_btn := Button.new()
		accept_btn.text = "Принять"
		accept_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(accept_btn, Color(0.16, 0.44, 0.76, 0.9), Color(0.88, 0.96, 1.0))
		accept_btn.pressed.connect(_on_accept.bind(q["id"]))
		btn_row.add_child(accept_btn)
	else:
		var status_lbl := Label.new()
		var is_accepted: bool = q["status"] == "accepted"
		status_lbl.text = "✓  Задание принято" if is_accepted else "✗  Задание отклонено"
		status_lbl.add_theme_font_size_override("font_size", 12)
		status_lbl.add_theme_color_override(
			"font_color",
			Color(0.38, 0.92, 0.62) if is_accepted else Color(0.52, 0.56, 0.68)
		)
		vbox.add_child(status_lbl)

	return card


func _build_avatar(npc_name: String, color: Color) -> Control:
	var container := Control.new()
	container.custom_minimum_size = Vector2(48, 48)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = color.darkened(0.3)
	container.add_child(bg)

	var initial_lbl := Label.new()
	initial_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	initial_lbl.text = npc_name.left(1).to_upper()
	initial_lbl.add_theme_font_size_override("font_size", 22)
	initial_lbl.add_theme_color_override("font_color", Color.WHITE)
	initial_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	container.add_child(initial_lbl)

	# Скруглим через ClipContents + StyleBox
	var clip_panel := PanelContainer.new()
	clip_panel.custom_minimum_size = Vector2(48, 48)
	var clip_style := StyleBoxFlat.new()
	clip_style.bg_color = color.darkened(0.3)
	clip_style.set_corner_radius_all(24)
	clip_style.set_content_margin_all(0)
	clip_panel.add_theme_stylebox_override("panel", clip_style)

	var lbl2 := Label.new()
	lbl2.text = npc_name.left(1).to_upper()
	lbl2.add_theme_font_size_override("font_size", 22)
	lbl2.add_theme_color_override("font_color", Color.WHITE)
	lbl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl2.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl2.custom_minimum_size  = Vector2(48, 48)
	clip_panel.add_child(lbl2)

	return clip_panel


func _style_button(btn: Button, bg: Color, fg: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(8)
	var hover := StyleBoxFlat.new()
	hover.bg_color = bg.lightened(0.15)
	hover.set_corner_radius_all(6)
	hover.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover",  hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_font_size_override("font_size", 14)


# ── Обработка кнопок ─────────────────────────────────────────────────────────

func _on_accept(quest_id: int) -> void:
	_set_quest_status(quest_id, "accepted")


func _on_decline(quest_id: int) -> void:
	_set_quest_status(quest_id, "declined")


func _set_quest_status(quest_id: int, new_status: String) -> void:
	for q in _quests:
		if q["id"] == quest_id:
			q["status"] = new_status
			break

	# Перестраиваем карточку
	var old_card: Node = _card_nodes.get(quest_id)
	if old_card == null:
		return
	var idx := old_card.get_index()
	old_card.queue_free()

	var updated_q: Dictionary = {}
	for q in _quests:
		if q["id"] == quest_id:
			updated_q = q
			break

	var new_card := _build_quest_card(updated_q)
	_card_nodes[quest_id] = new_card
	_list.add_child(new_card)
	_list.move_child(new_card, idx)
