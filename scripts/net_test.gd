extends Node
## Başsız ağ testi: 1 host + N istemci, her biri ayrı işlem.
##   godot --headless --path . res://scenes/net_test.tscn -- host [players=N] [auto] [fast]
##   godot --headless --path . res://scenes/net_test.tscn -- join [idx=I] [auto] [fast]
##
## Argümanlar (hepsi isteğe bağlı, "anahtar=değer" ya da bayrak):
##   players=N    host: toplam oyuncu sayısı (host dahil). Varsayılan 2.
##   idx=I        join: istemci numarası (ad "Istemci<I>"). Varsayılan 1.
##   joindelay=S  join: bağlanmadan önce S sn bekle (geç katılan oyuncu).
##   loaddelay=S  herkes: oyun başladıktan sonra main.tscn'i S sn gecikmeli yükle
##                (sahne yüklenmeden gelen mesajların kaybolması yarışını zorlar).
##   quitafter=S  oyun başladıktan S sn sonra bu işlem aniden çıkar (oyuncu ayrılma testi).
##   timeout=S    lobi aşaması zaman aşımı (varsayılan 10 + joindelay).
##   auto         tam tur: minigame -> market -> savaş (main.gd sonucu yazıp çıkar).
##   fast         savaşı hızlandır (battle.gd okur).
## Çıkış kodu: 0 başarılı, 1 zaman aşımı / hata.

var role := "host"
var opts: Dictionary = {}
var t := 0.0
var start_requested := false
var expected_players := 2
var lobby_timeout := 10.0
var loading := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		role = args[0]
	for a in args:
		if "=" in a:
			var kv: PackedStringArray = a.split("=", true, 1)
			opts[kv[0]] = kv[1]
	expected_players = int(opts.get("players", 2))
	lobby_timeout = float(opts.get("timeout", 10.0 + float(opts.get("joindelay", 0.0))))
	var tag := _tag()
	Net.game_started.connect(_on_started)
	Net.players_changed.connect(func():
		print("[", tag, "] oyuncular: ", Net.players.size(), " ", Net.players)
		if role != "host" and Net.players.has(multiplayer.get_unique_id()) and not Net.my_ready():
			Net.set_my_ready(true))
	if role == "host":
		print("[host] kur: ", Net.host("Host"))
	else:
		var jd := float(opts.get("joindelay", 0.0))
		if jd > 0.0:
			print("[", tag, "] ", jd, " sn sonra bağlanacak")
			await get_tree().create_timer(jd).timeout
		print("[", tag, "] katıl: ", Net.join("127.0.0.1", "Istemci" + str(opts.get("idx", 1))))


func _tag() -> String:
	return "host" if role == "host" else "join" + str(opts.get("idx", 1))


func _process(delta: float) -> void:
	if loading:
		return
	t += delta
	if role == "host" and not start_requested and Net.players.size() == expected_players \
			and Net.players.values().all(func(p): return p.ready):
		start_requested = true
		var counts := [Net.team_count(0), Net.team_count(1)]
		print("[host] takımlar: ", counts)
		print("[host] başlat sonucu: '", Net.start_game(), "'")
	if t > lobby_timeout:
		print("[", _tag(), "] ZAMAN AŞIMI (lobi)")
		get_tree().quit(1)


func _on_started() -> void:
	print("[", _tag(), "] OYUN BAŞLADI, oyuncular: ", Net.players.size())
	if opts.has("quitafter"):
		get_tree().create_timer(float(opts.quitafter)).timeout.connect(Callable(get_tree(), "quit"))
	if "auto" in OS.get_cmdline_user_args():
		# Tam tur testi: gerçek oyun sahnesine geç, main.gd sonucu yazıp çıkar
		loading = true
		var ld := float(opts.get("loaddelay", 0.0))
		if ld > 0.0:
			print("[", _tag(), "] main.tscn ", ld, " sn gecikmeli yüklenecek")
			await get_tree().create_timer(ld).timeout
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		return
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)
