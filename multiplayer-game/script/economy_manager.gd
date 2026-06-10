## economy_manager.gd
## Sistema de economía: recursos por jugador e ingresos al final de turno.
extends Node

signal resources_updated(player_id: int)

var map: Node = null

const START_WOOD:           int = 10
const START_STONE:          int = 5
const DEFAULT_WOOD_INCOME:  int = 10
const DEFAULT_STONE_INCOME: int = 5

var player_resources: Dictionary = {}
var player_income:    Dictionary = {}

func init_player_economy(player_ids: Array[int]) -> void:
	player_resources.clear()
	player_income.clear()
	for pid in player_ids:
		player_resources[pid] = {"wood": START_WOOD,          "stone": START_STONE}
		player_income[pid]    = {"wood": DEFAULT_WOOD_INCOME, "stone": DEFAULT_STONE_INCOME}

func apply_end_turn_income(player_id: int) -> void:
	if not player_resources.has(player_id) or not player_income.has(player_id):
		return
	player_resources[player_id]["wood"]  += int(player_income[player_id]["wood"])
	player_resources[player_id]["stone"] += int(player_income[player_id]["stone"])

func spend(player_id: int, wood: int, stone: int) -> bool:
	if not player_resources.has(player_id):
		return false
	var w: int = int(player_resources[player_id]["wood"])
	var s: int = int(player_resources[player_id]["stone"])
	if w < wood or s < stone:
		return false
	player_resources[player_id]["wood"]  = w - wood
	player_resources[player_id]["stone"] = s - stone
	return true

func get_resources(player_id: int) -> Dictionary:
	return player_resources.get(player_id, {"wood": 0, "stone": 0})

func can_afford(player_id: int, wood_cost: int, stone_cost: int) -> bool:
	var r: Dictionary = get_resources(player_id)
	return int(r["wood"]) >= wood_cost and int(r["stone"]) >= stone_cost

@rpc("any_peer", "call_local")
func sync_economy(remote_resources: Dictionary, remote_income: Dictionary, remote_round: int) -> void:
	player_resources = remote_resources.duplicate(true)
	player_income    = remote_income.duplicate(true)

	for pid in player_resources.keys():
		resources_updated.emit(int(pid))

	var city_menu: CityMenu = map.city_menu
	if city_menu.visible:
		var my_id:   int        = multiplayer.get_unique_id()
		var r:       Dictionary = get_resources(my_id)
		var cell:    Vector2i   = city_menu.get_city_cell()
		var key:     String     = MapData.cell_key(cell)
		var can_buy: bool       = not map.city_manager.city_bought_this_turn.has(key)
		city_menu.open_for_city(cell, map.city_manager.unit_db, int(r["wood"]), int(r["stone"]), can_buy)
