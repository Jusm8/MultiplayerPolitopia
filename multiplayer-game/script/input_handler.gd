## input_handler.gd
## Captura el input del jugador y delega en los sistemas correspondientes.
extends Node

var map: Node = null

func _unhandled_input(event: InputEvent) -> void:
	if map == null:
		return
	if map.turn_manager.game_over_flag:
		return

	var my_id: int = multiplayer.get_unique_id()
	if map.turn_manager.is_eliminated(my_id):
		return
	if not map.turn_manager.is_my_turn():
		return

	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		_handle_left_click()

func _handle_left_click() -> void:
	var world_pos: Vector2  = map.get_global_mouse_position()
	var local_pos: Vector2  = map.global_to_local(world_pos)
	var cell:      Vector2i = map.local_to_cell(local_pos)

	if map.get_terrain_at(cell) == -1:
		return
	if not map.is_point_inside_iso_cell(local_pos, cell):
		return

	if map.unit_manager.is_in_move_mode():
		map.unit_manager.try_move_or_attack(cell)
		return

	if map.unit_manager.try_select_unit(cell):
		return

	var terrain: int = map.get_terrain_at(cell)
	map.hud.set_selected_tile(cell, terrain)

	if terrain == MapData.Terrain.CIUDAD:
		map.city_manager.try_open_city_menu(cell)
