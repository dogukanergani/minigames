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
const Items = preload("res://scripts/items.gd")
const UiTheme = preload("res://scripts/ui_theme.gd")
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
		print("[main] BAĞLANTI KOPTU: lobiye dönülüyor")
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
			# Kapanmadan önce kısa bekle: host hemen çıkarsa istemci bu mesajdan önce "bağlantı koptu" görebilir
			await get_tree().create_timer(0.6).timeout
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
	if not auto_test:
		# Son oyuncu bitirince sonuç ekranına hemen geçme: kısa bir "herkes bitirdi" anı
		var banner := CanvasLayer.new()
		banner.layer = 50
		var lbl := Label.new()
		lbl.text = "HERKES BİTİRDİ!"
		lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
		lbl.grow_vertical = Control.GROW_DIRECTION_BOTH
		lbl.add_theme_font_size_override("font_size", 28)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 6)
		banner.add_child(lbl)
		add_child(banner)
		await get_tree().create_timer(2.2).timeout
		banner.queue_free()
		if phase != Phase.RESULTS:
			return
	var rows: Array = [{"t": "score"}]
	var my_id := multiplayer.get_unique_id()
	for i in ranking.size():
		var id: int = ranking[i]
		rows.append({"t": "rank", "i": i, "id": id, "label": labels.get(id, ""),
			"gain": Game.coins_for_rank(i), "total": Game.coins.get(id, 0)})
	var wait := 1.0 if auto_test else RESULTS_TIME
	_show_overlay("TUR %d SONUÇLARI" % Game.round_no, rows, "Market", wait)
	_after(wait, Phase.RESULTS, _go_shop)
	if auto_test:
		print("[main ", my_id, "] SONUÇ: ", ranking, " ", labels, " coin: ", Game.coins)


func _on_shop_finished() -> void:
	phase = Phase.SHOP_DONE
	var rows: Array = [{"t": "score"}]
	var my_id := multiplayer.get_unique_id()
	for id in Game.last_ranking:
		rows.append({"t": "inv", "id": id, "coins": Game.coins.get(id, 0)})
	var wait := 1.0 if auto_test else SUMMARY_TIME
	_show_overlay("MARKET BİTTİ", rows, "Savaş", wait)
	_after(wait, Phase.SHOP_DONE, _go_battle)
	if auto_test:
		print("[main ", my_id, "] MARKET: ", Game.inventory, " coin: ", Game.coins)


func _on_battle_finished(winner: int, scores: Array) -> void:
	round_wins[winner] += 1
	Game.award_battle(winner)
	var match_over: bool = round_wins[winner] >= rounds_to_win
	phase = Phase.MATCH_DONE if match_over else Phase.BATTLE_DONE
	var rows: Array = [{"t": "score"}]
	if not match_over:
		rows.append({"t": "winner", "team": winner, "text": "SAVAŞI %s TAKIM KAZANDI   (bayrak %d - %d)" % [
			Net.TEAM_NAMES[winner].to_upper(), scores[0], scores[1]]})
	rows.append({"t": "text", "text": "Savaş bonusu: kazanan takım +%d coin, kaybeden +%d coin." % [
		Game.BATTLE_WIN_BONUS, Game.BATTLE_LOSE_BONUS]})
	rows.append({"t": "text", "text": "Birlikler (ölen birimler sonraki savaşta yeniden doğar):"})
	for id in Game.last_ranking:
		rows.append({"t": "units", "id": id})
	var in_test := auto_test and not full_match  # test: ilk savaştan sonra çık
	if match_over:
		var end_wait := 1.0 if auto_test else MATCH_END_TIME
		_show_overlay("MAÇ BİTTİ", rows, "Lobiye dönüş", end_wait, winner)
		_after(end_wait, Phase.MATCH_DONE, _finish_match.bind(winner))
	else:
		var next_wait := 1.0 if auto_test else RESULTS_TIME
		_show_overlay("SAVAŞ BİTTİ", rows, "Sonraki tur", next_wait)
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


# --- Ortak ekran ---

func _name_of(id: int) -> String:
	return Net.players.get(id, {}).get("name", "?")


func _team_of(id: int) -> int:
	return Net.players.get(id, {}).get("team", 0)


## Maç skoru bandı: [Mavi 2] - [1 Kırmızı] + "ilk N savaş".
func _score_band() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	for t in 2:
		var txt := "%s  %d" % [Net.TEAM_NAMES[t].to_upper(), round_wins[t]] if t == 0 else "%d  %s" % [round_wins[t], Net.TEAM_NAMES[t].to_upper()]
		var b := UiTheme.team_banner(t, txt, 13)
		b.custom_minimum_size = Vector2(150, 20)
		if t == 1:
			var mid := UiTheme.make_label("ilk %d savaş" % rounds_to_win, 10, UiTheme.DIM)
			mid.custom_minimum_size = Vector2(60, 0)
			mid.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			h.add_child(mid)
		h.add_child(b)
	return h


## Oyuncu satırı kutusu: kendi satırım altın tonlu, kenarda takım rengi şeridi.
func _row_box(id: int, node_children: Array) -> Control:
	var mine := id == multiplayer.get_unique_id()
	var pc := PanelContainer.new()
	var st := UiTheme.row_box(mine).duplicate()
	if st is StyleBoxTexture:
		st.content_margin_top = 1
		st.content_margin_bottom = 1
		st.content_margin_left = 4
		st.content_margin_right = 5
	pc.add_theme_stylebox_override("panel", st)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	pc.add_child(h)
	var stripe := ColorRect.new()
	stripe.color = UiTheme.TEAM[_team_of(id)]
	stripe.custom_minimum_size = Vector2(3, 10)
	h.add_child(stripe)
	for c in node_children:
		h.add_child(c)
	return pc


func _expand(l: Control, min_w := 0.0) -> Control:
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(min_w, 0)
	return l


func _fixed(l: Control, w: float) -> Control:
	l.custom_minimum_size = Vector2(w, 0)
	return l


func _make_row(r: Dictionary) -> Control:
	var id: int = r.get("id", 0)
	var mine := id == multiplayer.get_unique_id()
	var name_col: Color = UiTheme.GOLD_L if mine else UiTheme.TEXT
	match r.t:
		"score":
			return _score_band()
		"text":
			return UiTheme.make_label(r.text, 11, UiTheme.DIM)
		"winner":
			var wb := UiTheme.team_banner(r.team, r.text, 13)
			wb.custom_minimum_size = Vector2(0, 22)
			return wb
		"rank":
			var i: int = r.i
			var rank_node: Control
			if i < 3 and UiTheme.icon_tex("medal_%d" % (i + 1)) != null:
				rank_node = UiTheme.icon_rect("medal_%d" % (i + 1), 16)
			else:
				var rl := UiTheme.make_label("%d." % (i + 1), 12, UiTheme.DIM)
				rl.custom_minimum_size = Vector2(16, 0)
				rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				rank_node = rl
			var gain := UiTheme.coin_amount("+%d" % r.gain, UiTheme.GREEN, 11)
			gain.custom_minimum_size = Vector2(56, 0)
			var total := UiTheme.coin_amount("%d" % r.total, UiTheme.GOLD_L, 11)
			total.custom_minimum_size = Vector2(46, 0)
			return _row_box(id, [rank_node,
				_expand(UiTheme.make_label(_name_of(id) + ("  (sen)" if mine else ""), 11, name_col), 110),
				UiTheme.make_label(str(r.label), 11, UiTheme.DIM), gain, total])
		"inv":
			var icons := HFlowContainer.new()
			icons.add_theme_constant_override("h_separation", 1)
			icons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for item_id in Game.inventory.get(id, []):
				icons.add_child(UiTheme.icon_rect(item_id, 14))
			if Game.inventory.get(id, []).is_empty():
				icons.add_child(UiTheme.make_label("-", 11, UiTheme.DIM))
			var left := UiTheme.coin_amount(str(r.coins), UiTheme.GOLD_L, 11)
			left.custom_minimum_size = Vector2(46, 0)
			return _row_box(id, [_fixed(UiTheme.make_label(_name_of(id) + ("  (sen)" if mine else ""), 11, name_col), 110), icons, left])
		"units":
			var icons2 := HBoxContainer.new()
			icons2.add_theme_constant_override("separation", 1)
			icons2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for item_id in Game.inventory.get(id, []):
				if Items.get_item(item_id).get("kind", "") == "Birim":
					icons2.add_child(UiTheme.icon_rect(item_id, 14))
			return _row_box(id, [_expand(UiTheme.make_label(_name_of(id) + ("  (sen)" if mine else ""), 11, name_col), 110),
				icons2, UiTheme.make_label("%d birim" % Game.unit_count(id), 11, UiTheme.DIM)])
	return UiTheme.make_label(str(r), 11)


func _show_overlay(title: String, lines: Array, next_text: String, seconds: float, winner := -1) -> void:
	if is_instance_valid(overlay):
		remove_child(overlay)
		overlay.queue_free()
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.theme = UiTheme.make_theme()
	add_child(overlay)
	overlay.add_child(UiTheme.make_backdrop())

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	overlay.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)  # 5v5'te 10 satır ekrana sığsın
	margin.add_child(box)

	if winner >= 0:  # maç sonu: büyük kazanan banner'ı
		var wb := UiTheme.team_banner(winner, "%s TAKIM KAZANDI!" % Net.TEAM_NAMES[winner].to_upper(), 22)
		wb.custom_minimum_size = Vector2(0, 34)
		box.add_child(wb)
		var mine_won := Net.my_team() == winner
		var verdict := UiTheme.make_label("MAÇ BİTTİ  -  " + ("ZAFER!" if mine_won else "Yenilgi"), 12, UiTheme.GREEN if mine_won else UiTheme.RED)
		verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(verdict)
	else:
		var tb := UiTheme.banner("banner_gold", title, 16)
		tb.custom_minimum_size = Vector2(0, 28)
		box.add_child(tb)

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 2)
	panel.add_child(content)
	for line in lines:
		if line is Dictionary:
			content.add_child(_make_row(line))
		else:
			content.add_child(UiTheme.make_label(str(line), 11))

	countdown_text = "Sıradaki: " + next_text + " -"
	countdown_left = seconds
	countdown_label = UiTheme.make_label("%s %d sn" % [countdown_text, ceili(seconds)], 11, UiTheme.GOLD_L)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(countdown_label)
