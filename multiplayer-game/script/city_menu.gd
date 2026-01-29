extends Control
class_name CityMenu

signal buy_requested(city_cell: Vector2i, unit_id: int)
signal closed

@onready var unit_grid: Control = $Panel/HBox/UnitGrid
var unit_buttons: Array[BaseButton] = []

@onready var label_name: Label = $Panel/HBox/Info/LabelName
@onready var label_stats: Label = $Panel/HBox/Info/LabelStats
@onready var label_desc: Label = $Panel/HBox/Info/LabelDesc
@onready var label_cost: Label = $Panel/HBox/Info/LabelCost
@onready var btn_close: Button = $Panel/BottomBar/BtnClose
@onready var btn_buy: Button = $Panel/BottomBar/BtnBuy

var _city_cell: Vector2i
var _selected_unit: int = -1
var _unit_db: Array[Dictionary] = []
var _my_wood: int = 0
var _my_stone: int = 0
var _can_buy_here: bool = true

func _ready() -> void:
	hide()

	# Botones principales
	btn_buy.pressed.connect(_on_buy_pressed)
	btn_close.pressed.connect(_on_close_pressed)

	# 1) Coger botones dentro de UnitGrid (TextureButton o Button)
	unit_buttons.clear()
	for child in unit_grid.get_children():
		if child is BaseButton:
			unit_buttons.append(child)

	print("CityMenu: botones encontrados en UnitGrid =", unit_buttons.size())

	# 2) Cargar icono de ejemplo (Godot)
	var tex: Texture2D = null
	if ResourceLoader.exists("res://icon.svg"):
		tex = load("res://icon.svg")
	elif ResourceLoader.exists("res://icon.png"):
		tex = load("res://icon.png")
	else:
		push_warning("CityMenu: No existe res://icon.svg ni res://icon.png. No puedo poner icono de ejemplo.")

	# 3) Configurar botones + conectar click
	for i in range(unit_buttons.size()):
		var idx := i
		var b := unit_buttons[i]

		# Tamaño mínimo para que se vea sí o sí
		b.custom_minimum_size = Vector2(96, 96)

		# Poner icono según tipo
		if tex != null:
			if b is TextureButton:
				var tb := b as TextureButton
				tb.texture_normal = tex
				tb.ignore_texture_size = true
				tb.stretch_mode = TextureButton.STRETCH_SCALE
			elif b is Button:
				var bt := b as Button
				bt.icon = tex
				bt.expand_icon = true
				bt.text = ""

		# Conectar selección
		b.pressed.connect(func(): _select_unit(idx))

func open_for_city(city_cell: Vector2i, unit_db: Array[Dictionary], my_wood: int, my_stone: int, can_buy_here: bool) -> void:
	_city_cell = city_cell
	_unit_db = unit_db
	_my_wood = my_wood
	_my_stone = my_stone
	_can_buy_here = can_buy_here
	_selected_unit = -1

	label_name.text = "Selecciona tropa"
	label_stats.text = ""
	label_desc.text = ""
	label_cost.text = ""
	btn_buy.disabled = true

	# Desactivar botones si no se puede comprar
	for b in unit_buttons:
		b.disabled = not _can_buy_here

	if not _can_buy_here:
		label_desc.text = "Ya compraste 1 tropa en esta ciudad este turno."
		btn_buy.disabled = true

	show()

func _select_unit(unit_id: int) -> void:
	if not _can_buy_here:
		return
	if unit_id < 0 or unit_id >= _unit_db.size():
		return

	_selected_unit = unit_id
	var u: Dictionary = _unit_db[unit_id]

	label_name.text = str(u.get("name", "Unidad"))
	label_stats.text = "Vida: %d  |  Daño: %d" % [int(u.get("hp", 0)), int(u.get("dmg", 0))]
	label_desc.text = str(u.get("desc", ""))
	label_cost.text = "Coste: %d madera, %d piedra" % [int(u.get("wood_cost", 0)), int(u.get("stone_cost", 0))]

	var wood_cost := int(u.get("wood_cost", 0))
	var stone_cost := int(u.get("stone_cost", 0))
	var can_afford := _my_wood >= wood_cost and _my_stone >= stone_cost

	btn_buy.disabled = not can_afford

func _on_buy_pressed() -> void:
	if _selected_unit == -1:
		return
	if btn_buy.disabled:
		return
	
	buy_requested.emit(_city_cell, _selected_unit)
	# Cerrar para que al abrir de nuevo use recursos nuevos
	hide()
	closed.emit()

func _on_close_pressed() -> void:
	hide()
	closed.emit()

func get_city_cell() -> Vector2i:
	return _city_cell
