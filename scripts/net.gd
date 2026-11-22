extends Node
## Ağ katmanı (autoload: Net). Sunucu otoriterdir: takım ve oyuncu listesi
## sunucuda tutulur, istemciler sadece istek gönderir.

signal players_changed
signal game_started
signal join_failed
signal lost_connection

const PORT := 7777
const MAX_PLAYERS := 10  # 5v5
const TEAM_SIZE := 5
const TEAM_NAMES := ["Mavi", "Kırmızı"]

## peer_id -> {name: String, team: int}
var players: Dictionary = {}
var local_name := "Oyuncu"
var in_game := false


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --- Herkese açık API ---

func host(player_name: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		return err
	local_name = _clean_name(player_name)
	multiplayer.multiplayer_peer = peer
	in_game = false
	players = {1: {"name": local_name, "team": 0, "ready": true}}  # host başlatan kişi, hep hazır
	players_changed.emit()
	return OK


func join(ip: String, player_name: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(), PORT)
	if err != OK:
		return err
	local_name = _clean_name(player_name)
	multiplayer.multiplayer_peer = peer
	in_game = false
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	in_game = false


func request_team(team: int) -> void:
	if multiplayer.is_server():
		_srv_set_team(team)
	else:
		_srv_set_team.rpc_id(1, team)


func set_my_ready(is_ready: bool) -> void:
	if multiplayer.is_server():
		_srv_set_ready(is_ready)
	else:
		_srv_set_ready.rpc_id(1, is_ready)


func my_ready() -> bool:
	return players.get(multiplayer.get_unique_id(), {}).get("ready", false)


## Hata mesajı döner; başarılıysa boş string.
func start_game() -> String:
	if not multiplayer.is_server():
		return "Sadece host oyunu başlatabilir."
	for t in 2:
		if team_count(t) == 0:
			return "Her takımda en az 1 oyuncu olmalı."
	for p in players.values():
		if not p.ready:
			return "Herkes hazır olmalı."
	_begin_game.rpc()
	return ""


func team_count(team: int) -> int:
	var n := 0
	for p in players.values():
		if p.team == team:
			n += 1
	return n


func my_team() -> int:
	var me: Dictionary = players.get(multiplayer.get_unique_id(), {})
	return me.get("team", 0)


# --- Sunucu tarafı ---

@rpc("any_peer", "reliable")
func _srv_register(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if in_game or players.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	players[id] = {"name": _clean_name(player_name), "team": _smaller_team(), "ready": false}
	_broadcast()


@rpc("any_peer", "reliable")
func _srv_set_team(team: int) -> void:
	if not multiplayer.is_server() or in_game:
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1  # host kendi çağırdı
	if not players.has(id) or team < 0 or team > 1:
		return
	if players[id].team != team and team_count(team) >= TEAM_SIZE:
		return
	players[id].team = team
	_broadcast()


@rpc("any_peer", "reliable")
func _srv_set_ready(is_ready: bool) -> void:
	if not multiplayer.is_server() or in_game:
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	if players.has(id) and id != 1:
		players[id].ready = is_ready
		_broadcast()


func _broadcast() -> void:
	_sync_players.rpc(players)
	players_changed.emit()


func _smaller_team() -> int:
	return 0 if team_count(0) <= team_count(1) else 1


func _clean_name(n: String) -> String:
	n = n.strip_edges().left(16)
	return n if n != "" else "Oyuncu"


# --- İstemciye giden ---

@rpc("authority", "call_remote", "reliable")
func _sync_players(data: Dictionary) -> void:
	players = data
	players_changed.emit()


@rpc("authority", "call_local", "reliable")
func _begin_game() -> void:
	in_game = true
	game_started.emit()


# --- Bağlantı olayları ---

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server() and players.erase(id):
		_broadcast()


func _on_connected_to_server() -> void:
	_srv_register.rpc_id(1, local_name)


func _on_connection_failed() -> void:
	leave()
	join_failed.emit()


func _on_server_disconnected() -> void:
	leave()
	lost_connection.emit()
