extends Node
var steam_ok := false

func _ready():
	var res: Dictionary = Steam.steamInitEx(480)
	steam_ok = (res.get("status", 1) == 0)
	print("Steam init:", res)

func _process(_d):
	if steam_ok:
		Steam.run_callbacks()
