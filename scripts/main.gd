extends Control
## Oyun akışı: Minigame -> Sonuç/coin -> Market -> Market özeti -> (Savaş) -> tekrar.
## Akış otomatik: sunucu süreleri sayar, geçişleri RPC ile herkese bildirir.
## Hiçbir oyuncunun "devam et" butonu yok.

enum Phase { MINIGAME, RESULTS, SHOP, SHOP_DONE, BATTLE, BATTLE_DONE, MATCH_DONE }

const MINIGAMES := [
	"res://minigames/reaction.tscn",
	"res://minigames/run.tscn",
	"res://minigames/coins.tscn",
]
const SHOP_SCENE := "res://shop/shop.tscn"
const BATTLE_SCENE := "res://battle/battle.tscn"
const RESULTS_TIME := 6.0  # sonuç ekranı
const SUMMARY_TIME := 5.0  # market özeti
## Maç yapısı: ilk bu kadar SAVAŞ kazanan takım maçı kazanır (en fazla 2*N-1 tur).
## Eşyalar kalıcı olduğu için kısa maç tercih edildi (uzun maçta öndeki hep öne geçer).
## Test için `towin=N` argümanıyla değiştirilebilir.
const ROUNDS_TO_WIN := 2
const MATCH_END_TIME := 12.0  # maç sonu ekranı, sonra oda lobisine dönülür

var phase: Phase = Phase.MINIGAME
var ready_peers: Dictionary = {}
var first_round_started := false
var match_ended := false
var got_phase := false  # istemci: sunucudan ilk faz mesajı geldi mi
var current: Node  # aktif faz sahnesi (minigame / market)
var overlay: Control
var countdown_label: Label
var countdown_text := ""
var countdown_left := 0.0
var auto_test := "auto" in OS.get_cmdline_user_args()
var full_match := "fullmatch" in OS.get_cmdline_user_args()  # test: ilk savaştan sonra çıkma, maç sonuna kadar oyna
var rounds_to_win := ROUNDS_TO_WIN
var round_wins: Array = [0, 0]  # takım başına kazanılan savaş sayısı (her istemcide aynı olaylardan türetilir)


func _ready() -> void:
	var ui_theme := Theme.new()
	ui_theme.default_font_size = 12
	theme = ui_theme
	Game.reset()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("towin="):
			rounds_to_win = maxi(1, int(a.get_slice("=", 1)))
	Net.lost_connection.connect(_on_lost_connection)
	# Herkes sahneyi yükleyince sunucu ilk turu başlatır.
	if multiplayer.is_server():
		Net.players_changed.connect(_on_roster_changed)
		_mark_ready(1)
	else:
		_announce_ready()


## İstemci: host kapandı / bağlantı koptu. Donup kalmak yerine lobiye dön.
func _on_lost_connection() -> void:
	if auto_test:
		print("[main ", multiplayer.get_unique_id(), "] BAĞLANTI KOPTU: lobiye dönülüyor")
		get_tree().quit(0)
		return
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


## Sunucu: biri ayrıldı. Rakip takım kalmadıysa maçı bitir, yoksa bekleyen el sıkışmayı yeniden kontrol et.
func _on_roster_changed() -> void:
	if match_ended:
		return
	if Net.team_count(0) == 0 or Net.team_count(1) == 0:
		match_ended = true
		_end_match.rpc("Rakip takım kalmadı, maç sona erdi.")
		return
	_try_first_round()


## Herkes: maç bitti, odaya (lobiye) dön. Bağlantı sürer, kalan oyuncular aynı odada kalır.
@rpc("authority", "call_local", "reliable")
func _end_match(reason: String) -> void:
	if auto_test:
		print("[main ", multiplayer.get_unique_id(), "] MAÇ BİTTİ: ", reason)
		if not "keeplobby" in OS.get_cmdline_user_args():  # keeplobby: lobiye dönüşü gözle görmek için çıkma
			get_tree().quit(0)
			return
	Net.in_game = false
	Net.last_notice = reason
	if multiplayer.is_server():
		Net.reset_ready()
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


## Sunucunun Main sahnesi henüz yüklenmemişse mesaj kaybolur. Bu yüzden ilk faz
## mesajı gelene kadar "hazırım" bilgisini tekrar tekrar yollarız.
func _announce_ready() -> void:
	while not got_phase and is_inside_tree():
		_srv_ready.rpc_id(1)
		await get_tree().create_timer(0.5).timeout


func _process(delta: float) -> void:
	if is_instance_valid(countdown_label) and countdown_left > 0.0:
		countdown_left = maxf(0.0, countdown_left - delta)
		countdown_label.text = "%s %d sn" % [countdown_text, ceili(countdown_left)]


@rpc("any_peer", "reliable")
func _srv_ready() -> void:
	if multiplayer.is_server():
		_mark_ready(multiplayer.get_remote_sender_id())


func _mark_ready(id: int) -> void:
	ready_peers[id] = true
	_try_first_round()


## "Herkes hazır" kontrolü üyelik bazlı (sayı bazlı değil): biri ayrılırsa erken başlamaz, takılmaz.
func _try_first_round() -> void:
	if not first_round_started and Net.all_in(ready_peers):
		first_round_started = true
		_next_round()


func _next_round() -> void:
	if multiplayer.is_server():
		_begin_minigame.rpc(_pick_minigame())


## Test için host'a `minigame=run` gibi bir argüman verilirse o minigame seçilir.
func _pick_minigame() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("minigame="):
			var path := "res://minigames/%s.tscn" % a.get_slice("=", 1)
			if MINIGAMES.has(path):
				return path
	return MINIGAMES.pick_random()


func _go_shop() -> void:
	if multiplayer.is_server():
		_begin_shop.rpc()


func _go_battle() -> void:
	if multiplayer.is_server():
		_begin_battle.rpc()


## Sunucu: süre dolunca, hâlâ aynı fazdaysak sonraki adımı çağır.
func _after(seconds: float, expected: Phase, next: Callable) -> void:
	if not multiplayer.is_server():
		return
	await get_tree().create_timer(seconds).timeout
	if phase == expected:
		next.call()


# --- Fazlar ---

@rpc("authority", "call_local", "reliable")
func _begin_minigame(path: String) -> void:
	got_phase = true
	_clear()
	Game.round_no += 1
	phase = Phase.MINIGAME
	current = load(path).instantiate()
	current.name = "Minigame"  # tüm oyuncularda aynı yol: RPC için şart
	add_child(current)
	current.finished.connect(_on_minigame_finished)


@rpc("authority", "call_local", "reliable")
func _begin_shop() -> void:
	_clear()
	phase = Phase.SHOP
	current = load(SHOP_SCENE).instantiate()
	current.name = "Shop"
	add_child(current)
	current.finished.connect(_on_shop_finished)


@rpc("authority", "call_local", "reliable")
func _begin_battle() -> void:
	_clear()
	phase = Phase.BATTLE
	current = load(BATTLE_SCENE).instantiate()
	current.name = "Battle"
	add_child(current)
	current.finished.connect(_on_battle_finished)


func _clear() -> void:
	# remove_child: isim hemen boşalsın ki yeni sahnenin adı çakışmasın
	for n in [current, overlay]:
		if is_instance_valid(n):
			remove_child(n)
			n.queue_free()
	current = null
	overlay = null
	countdown_label = null


func _on_minigame_finished(ranking: Array, labels: Dictionary) -> void:
	phase = Phase.RESULTS
	Game.award(ranking)
	var lines: Array = []
	var my_id := multiplayer.get_unique_id()
	for i in ranking.size():
		var id: int = ranking[i]
		lines.append("%s%d. %s - %s   +%d coin (toplam %d)" % [
			"> " if id == my_id else "  ", i + 1, _name_of(id), labels.get(id, ""),
			Game.coins_for_rank(i), Game.coins.get(id, 0)])
	var wait := 1.0 if auto_test else RESULTS_TIME
	lines.push_front(_score_line())
	_show_overlay("TUR %d SONUÇLARI" % Game.round_no, lines, "Market", wait)
	_after(wait, Phase.RESULTS, _go_shop)
	if auto_test:
		print("[main ", my_id, "] SONUÇ: ", ranking, " ", labels, " coin: ", Game.coins)


func _on_shop_finished() -> void:
	phase = Phase.SHOP_DONE
	var lines: Array = []
	var my_id := multiplayer.get_unique_id()
	for id in Game.last_ranking:
		lines.append("%s%s: %s   (kalan %d coin)" % [
			"> " if id == my_id else "  ", _name_of(id), Game.inventory_text(id), Game.coins.get(id, 0)])
	var wait := 1.0 if auto_test else SUMMARY_TIME
	lines.push_front(_score_line())
	_show_overlay("MARKET BİTTİ", lines, "Savaş", wait)
	_after(wait, Phase.SHOP_DONE, _go_battle)
	if auto_test:
		print("[main ", my_id, "] MARKET: ", Game.inventory, " coin: ", Game.coins)


func _on_battle_finished(winner: int, scores: Array) -> void:
	round_wins[winner] += 1
	var match_over: bool = round_wins[winner] >= rounds_to_win
	phase = Phase.MATCH_DONE if match_over else Phase.BATTLE_DONE
	var lines: Array = [
		_score_line(),
		"Savaşı %s Takım kazandı (bayrak %d - %d). Senin takımın: %s" % [
			Net.TEAM_NAMES[winner], scores[0], scores[1], Net.TEAM_NAMES[Net.my_team()]],
		"Kalan birimler (ölenler kalıcı gitti):",
	]
	for id in Game.last_ranking:
		lines.append("  %s: %d birim" % [_name_of(id), Game.unit_count(id)])
	var in_test := auto_test and not full_match  # test: ilk savaştan sonra çık
	if match_over:
		var end_wait := 1.0 if auto_test else MATCH_END_TIME
		lines.push_front("*** MAÇI %s TAKIM KAZANDI ***" % Net.TEAM_NAMES[winner].to_upper())
		_show_overlay("MAÇ BİTTİ", lines, "Lobiye dönüş", end_wait)
		_after(end_wait, Phase.MATCH_DONE, _finish_match.bind(winner))
	else:
		var next_wait := 1.0 if auto_test else RESULTS_TIME
		_show_overlay("SAVAŞ BİTTİ", lines, "Sonraki tur", next_wait)
		_after(next_wait, Phase.BATTLE_DONE, _next_round)
	if auto_test:
		print("[main ", multiplayer.get_unique_id(), "] SAVAŞ BİTTİ: kazanan=", Net.TEAM_NAMES[winner], " skor=", scores)
	if in_test:
		await get_tree().create_timer(0.5).timeout
		get_tree().quit(0)


## Sunucu: maç sonu ekranı bitti, herkesi aynı odanın lobisine döndür (bağlantı sürer).
func _finish_match(winner: int) -> void:
	if not multiplayer.is_server() or match_ended:
		return
	match_ended = true
	_end_match.rpc("Maç bitti: %s Takım kazandı (%d - %d)." % [
		Net.TEAM_NAMES[winner], round_wins[0], round_wins[1]])


func _score_line() -> String:
	return "Maç: %s %d - %d %s   (ilk %d savaşı kazanan)" % [
		Net.TEAM_NAMES[0], round_wins[0], round_wins[1], Net.TEAM_NAMES[1], rounds_to_win]


# --- Ortak ekran ---

func _name_of(id: int) -> String:
	return Net.players.get(id, {}).get("name", "?")


func _show_overlay(title: String, lines: Array, next_text: String, seconds: float) -> void:
	if is_instance_valid(overlay):
		remove_child(overlay)
		overlay.queue_free()
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.12, 0.16)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	overlay.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)  # 5v5'te 18+ satır ekrana sığsın
	margin.add_child(box)

	var title_label := Label.new()
	title_label.text = title
	box.add_child(title_label)
	for line in lines:
		var row := Label.new()
		row.text = line
		box.add_child(row)

	countdown_text = "Sıradaki: " + next_text + " -"
	countdown_left = seconds
	countdown_label = Label.new()
	countdown_label.text = "%s %d sn" % [countdown_text, ceili(seconds)]
	box.add_child(countdown_label)
