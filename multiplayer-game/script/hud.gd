extends CanvasLayer
class_name HUD
signal end_turn_confirmed

@onready var label_current_player: Label = $TopBar/VBoxContainer/LabelCurrentPlayer
@onready var label_cities: Label = $TopBar/VBoxContainer/HBoxContainer/LabelCities
@onready var label_wood: Label = $TopBar/VBoxContainer/HBoxContainer/LabelWood
@onready var label_stone: Label = $TopBar/VBoxContainer/HBoxContainer/LabelStone
@onready var label_round: Label = $TopBar/VBoxContainer/HBoxContainer/LabelRound

@onready var bottom_panel: PanelContainer = $TopBar/PanelContainer
@onready var label_title_info: Label = $TopBar/PanelContainer/HBoxContainer/LabelTitleInfo
@onready var actions_container: HBoxContainer = $TopBar/PanelContainer/HBoxContainer/ActionsContainer

@onready var confirm_end_turn_dialog: ConfirmationDialog = $TopBar/ConfirmEndTurnDialog
@onready var end_turn_btn: Button = $TopBar/EndTurnBtn

func _ready() -> void:
	bottom_panel.visible = false
	end_turn_btn.pressed.connect(_on_end_turn_button_pressed)
	confirm_end_turn_dialog.confirmed.connect(_on_confirmed)

func _on_end_turn_button_pressed() -> void:
	confirm_end_turn_dialog.dialog_text = "¿Seguro que quieres pasar turno?"
	confirm_end_turn_dialog.popup_centered()

func _on_confirmed() -> void:
	end_turn_confirmed.emit()

func set_current_player(name: String, is_my_turn: bool) -> void:
	label_current_player.text = "Turno: %s" % name
	label_current_player.modulate = Color.WHITE if is_my_turn else Color(0.8, 0.8, 0.8)
	end_turn_btn.disabled = not is_my_turn

func set_round(round_number: int) -> void:
	label_round.text = "Ronda: %d" % round_number

func set_player_stats(cities: int, wood: int, stone: int) -> void:
	label_cities.text = "Ciudades: %d" % cities
	label_wood.text = "Madera: %d" % wood
	label_stone.text = "Piedra: %d" % stone

func set_selected_tile(cell: Vector2i, terrain: int) -> void:
	var terrain_name := "Desconocido"
	match terrain:
		0: terrain_name = "Campo"
		1: terrain_name = "Ciudad"
		2: terrain_name = "Bosque"
		3: terrain_name = "Agua"
		4: terrain_name = "Montaña"

	label_title_info.text = "Casilla (%d, %d) - %s" % [cell.x, cell.y, terrain_name]
	bottom_panel.visible = true
