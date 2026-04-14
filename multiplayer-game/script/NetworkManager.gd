extends Node

enum Mode { LOCAL, STEAM }
var mode: Mode = Mode.LOCAL

func host_local(port: int, max_players: int) -> int:
	mode = Mode.LOCAL
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_server(port, max_players)
	if err == OK:
		multiplayer.multiplayer_peer = enet
	return err

func join_local(ip: String, port: int) -> int:
	mode = Mode.LOCAL
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_client(ip, port)
	if err == OK:
		multiplayer.multiplayer_peer = enet
	return err

func host_steam() -> bool:
	mode = Mode.STEAM

	# Si tu build no trae SteamMultiplayerPeer, esto te lo dirá claro:
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		push_error("SteamMultiplayerPeer no existe en tu build de GodotSteam.")
		return false

	var peer := SteamMultiplayerPeer.new()

	# Nombres más comunes en builds recientes:
	# - create_host()
	# - create_server()
	if peer.has_method("create_host"):
		peer.create_host()
	elif peer.has_method("create_server"):
		peer.create_server()
	else:
		push_error("SteamMultiplayerPeer no tiene create_host/create_server.")
		return false

	multiplayer.multiplayer_peer = peer
	return true

func join_steam(host_steam_id: int) -> bool:
	mode = Mode.STEAM

	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		push_error("SteamMultiplayerPeer no existe en tu build de GodotSteam.")
		return false

	var peer := SteamMultiplayerPeer.new()

	# Nombres más comunes:
	# - create_client(steam_id)
	# - create_connection(steam_id)
	if peer.has_method("create_client"):
		peer.create_client(host_steam_id)
	elif peer.has_method("create_connection"):
		peer.create_connection(host_steam_id)
	else:
		push_error("SteamMultiplayerPeer no tiene create_client/create_connection.")
		return false

	multiplayer.multiplayer_peer = peer
	return true
