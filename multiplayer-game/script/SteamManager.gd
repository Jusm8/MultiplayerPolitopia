extends Node
var steam_ok := false

func _ready():
	if not Engine.has_singleton("Steam"):
		push_error("No existe el singleton Steam: la GDExtension no está cargando.")
		return

	var res: Dictionary = Steam.steamInitEx(480, true) # <- importante
	print("Steam init:", res)

	steam_ok = (int(res.get("status", 1)) == 0)
	if not steam_ok:
		push_error("Steam NO inicializó. status=%s verbal=%s" % [str(res.get("status")), str(res.get("verbal"))])
		return

	print("Steam persona:", Steam.getPersonaName())
