extends Control
class_name CityMenu

signal buy_requested(city_cell: Vector2i, unit_id: int)
signal closed

@onready var unit_grid: Control = $Panel/HBox/UnitGrid
var unit_buttons: Array[Button] = []

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

	# Coger botones dentro de UnitGrid
	unit_buttons.clear()
	for child in unit_grid.get_children():
		if child is Button:
			unit_buttons.append(child)

	if unit_buttons.size() < 4:
		push_error("CityMenu: UnitGrid necesita 4 botones (Button). Actualmente: %d" % unit_buttons.size())
		return

	# Conectar botones
	for i in range(unit_buttons.size()):
		var idx := i
		unit_buttons[i].pressed.connect(func(): _select_unit(idx))

	btn_buy.pressed.connect(_on_buy_pressed)
	btn_close.pressed.connect(_on_close_pressed)

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

	var can_afford := _my_wood >= int(u.get("wood_cost", 0)) and _my_stone >= int(u.get("stone_cost", 0))
	btn_buy.disabled = not can_afford

func _on_buy_pressed() -> void:
	if _selected_unit == -1:
		return
	buy_requested.emit(_city_cell, _selected_unit)

func _on_close_pressed() -> void:
	hide()
	closed.emit()
