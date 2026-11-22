extends Node
## Başsız ağ testi: iki işlem çalıştırılır.
## godot --headless --path . res://scenes/net_test.tscn -- host
## godot --headless --path . res://scenes/net_test.tscn -- join

var role := "host"
var t := 0.0
var start_requested := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		role = args[0]
	Net.game_started.connect(_on_started)
	Net.players_changed.connect(func():
		print("[", role, "] oyuncular: ", Net.players)
		if role != "host" and Net.players.has(multiplayer.get_unique_id()) and not Net.my_ready():
			Net.set_my_ready(true))
	if role == "host":
		print("[host] kur: ", Net.host("Host"))
	else:
		print("[join] katıl: ", Net.join("127.0.0.1", "Istemci"))


func _process(delta: float) -> void:
	t += delta
	if role == "host" and Net.players.size() == 2 and not start_requested and Net.players.values().all(func(p): return p.ready):
		start_requested = true
		print("[host] başlat sonucu: '", Net.start_game(), "'")
	if t > 10.0:
		print("[", role, "] ZAMAN AŞIMI")
		get_tree().quit(1)


func _on_started() -> void:
	print("[", role, "] OYUN BAŞLADI, oyuncular: ", Net.players)
	if "auto" in OS.get_cmdline_user_args():
		# Tam tur testi: gerçek oyun sahnesine geç, main.gd sonucu yazıp çıkar
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		return
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)
