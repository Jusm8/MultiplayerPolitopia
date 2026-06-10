extends Node

var players:  Dictionary = {}
var map_seed: int = 0 

func get_player_ids() -> Array[int]:
	var ids: Array[int] = []
	for id in players.keys():
		ids.append(int(id))
	return ids
