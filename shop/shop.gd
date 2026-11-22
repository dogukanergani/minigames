extends Control
## Market: oyuncular minigame sıralamasına göre sırayla alışveriş yapar.
## Sıra geldiğinde 1 eşya alır ya da pas geçer. Pas geçen (ya da süresi dolan)
## bir daha oynamaz. Alacak parası/stoğu kalmayan otomatik pas sayılır.
## Sunucu doğrular; durum RPC ile herkese yansır.

signal finished

const Items = preload("res://scripts/items.gd")
const UiTheme = preload("res://scripts/ui_theme.gd")
const TURN_TIME := 15.0

# Herkeste aynı tutulan durum
var stock: Dictionary = {}  # item_id -> kalan
var turn_id := 0  # sırası gelen peer (0 = yok)
var done: Dictionary = {}  # peer_id -> true
var time_left := 0.0
var log_lines: Array = []

# Sadece sunucuda
var order: Array = []
var idx := -1
var turn_timer: Timer

var turn_label: Label
var turn_panel: PanelContainer
var turn_was_mine := false
var time_bar: ProgressBar
var coins_box: HBoxContainer
var order_box: VBoxContainer
var inv_title: Label
var log_label: Label
var pass_btn: Button
var sell_box: GridContainer
var item_buttons: Dictionary = {}
var item_rows: Dictionary = {}  # item_id -> {"stock": Label}
var ended := false
var auto_calls := 0
var hello: Dictionary = {}
var turns_started := false
var got_sync := false  # istemci: sunucudan ilk sıra/bitiş bilgisi geldi mi
var auto_test := "auto" in OS.get_cmdline_user_args()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for it in Items.ITEMS:
		stock[it.id] = Items.stock_for(it, Net.players.size())
	_build_ui()
	_refresh()
	if multiplayer.is_server():
		turn_timer = Timer.new()
		turn_timer.one_shot = true
		turn_timer.timeout.connect(_on_turn_timeout)
		add_child(turn_timer)
		order = Game.last_ranking.duplicate()
		for id in Net.players.keys():
			if not order.has(id):
				order.append(id)
		Net.players_changed.connect(_on_roster_changed)
		_mark_hello(1)
	else:
		_announce_hello()


## Sunucu: biri ayrıldı. Sırası gelen oyuncu gittiyse 15 sn beklemeden sırayı geçir;
## bekleyen el sıkışma varsa yeniden kontrol et.
func _on_roster_changed() -> void:
	if ended:
		return
	if not turns_started:
		_mark_hello(1)
		return
	if turn_id != 0 and not Net.players.has(turn_id):
		turn_timer.stop()
		done[turn_id] = true
		_next_turn()


## Sunucu, tüm oyuncular market sahnesini yükleyene kadar sırayı başlatmaz.
## Mesaj kaybolabileceği için istemci, ilk sıra bilgisi gelene kadar tekrar yollar.
func _announce_hello() -> void:
	while not got_sync and is_inside_tree():
		_srv_hello.rpc_id(1)
		await get_tree().create_timer(0.5).timeout


@rpc("any_peer", "reliable")
func _srv_hello() -> void:
	if multiplayer.is_server():
		_mark_hello(multiplayer.get_remote_sender_id())


func _mark_hello(id: int) -> void:
	hello[id] = true
	if not turns_started and Net.all_in(hello):
		turns_started = true
		_next_turn()


func _build_ui() -> void:
	theme = UiTheme.make_theme()
	add_child(UiTheme.make_backdrop())

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	margin.add_child(root)

	# Üst şerit: sıra bandı + coin
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	root.add_child(header)
	turn_panel = UiTheme.banner("banner_steel", "")
	turn_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	turn_panel.custom_minimum_size = Vector2(0, 24)
	turn_label = turn_panel.get_child(0)
	turn_label.add_theme_font_size_override("font_size", 14)
	header.add_child(turn_panel)
	var coin_panel := PanelContainer.new()
	coin_panel.add_theme_stylebox_override("panel", UiTheme.row_box(true))
	header.add_child(coin_panel)
	pass_btn = Button.new()
	pass_btn.text = "Pas Geç"
	pass_btn.custom_minimum_size = Vector2(84, 24)
	pass_btn.pressed.connect(_request_pass)
	header.add_child(pass_btn)
	coins_box = HBoxContainer.new()
	coin_panel.add_child(coins_box)
	time_bar = ProgressBar.new()
	time_bar.show_percentage = false
	time_bar.min_value = 0.0
	time_bar.max_value = TURN_TIME
	time_bar.custom_minimum_size = Vector2(0, 6)
	root.add_child(time_bar)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	# Sol: eşya listesi (kaydırılabilir) + son olay
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 3)
	body.add_child(left)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var items_col := VBoxContainer.new()
	items_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items_col.add_theme_constant_override("separation", 0)
	scroll.add_child(items_col)
	for it in Items.ITEMS:
		items_col.add_child(_make_item_row(it))

	# Sağ: sıra listesi, envanter (tıkla = sat), pas geç
	var side_col := VBoxContainer.new()
	side_col.custom_minimum_size = Vector2(244, 0)
	side_col.add_theme_constant_override("separation", 4)
	body.add_child(side_col)
	var order_panel := PanelContainer.new()
	var op_box := VBoxContainer.new()
	op_box.add_theme_constant_override("separation", 1)
	order_panel.add_child(op_box)
	op_box.add_child(UiTheme.make_label("SIRA", 10, UiTheme.GOLD))
	order_box = VBoxContainer.new()
	order_box.add_theme_constant_override("separation", 1)
	op_box.add_child(order_box)
	side_col.add_child(order_panel)
	var inv_panel := PanelContainer.new()
	inv_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var ip_box := VBoxContainer.new()
	ip_box.add_theme_constant_override("separation", 2)
	inv_panel.add_child(ip_box)
	inv_title = UiTheme.make_label("ENVANTER  (tıkla = sat)", 10, UiTheme.GOLD)
	ip_box.add_child(inv_title)
	sell_box = GridContainer.new()
	sell_box.columns = 3
	sell_box.add_theme_constant_override("h_separation", 2)
	sell_box.add_theme_constant_override("v_separation", 2)
	ip_box.add_child(sell_box)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ip_box.add_child(spacer)
	log_label = UiTheme.make_label("", 10, UiTheme.DIM)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ip_box.add_child(log_label)
	side_col.add_child(inv_panel)


## Eşya satırı: renk şeridi, ikon, ad + tür, kalan stok, fiyat (coin ikonlu). Tıklama = satın al.
func _make_item_row(it: Dictionary) -> Button:
	var b := Button.new()
	b.theme_type_variation = "RowButton"
	b.custom_minimum_size = Vector2(0, 17)
	b.pressed.connect(_request_buy.bind(it.id))
	item_buttons[it.id] = b
	var stripe := ColorRect.new()  # kategoriye göre renk şeridi
	stripe.color = UiTheme.kind_color(it.kind)
	stripe.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	stripe.offset_left = 3
	stripe.offset_right = 6
	stripe.offset_top = 3
	stripe.offset_bottom = -3
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(stripe)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10
	h.offset_right = -6
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	h.add_child(UiTheme.icon_rect(it.id, 16))
	var nm := UiTheme.make_label(it.name, 11)
	nm.custom_minimum_size = Vector2(110, 0)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(nm)
	var kind := UiTheme.make_label(it.kind, 9, UiTheme.kind_color(it.kind))
	kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(kind)
	var stock_l := UiTheme.make_label("", 10, UiTheme.DIM)
	stock_l.custom_minimum_size = Vector2(52, 0)
	stock_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stock_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(stock_l)
	var price := UiTheme.coin_amount(str(it.cost), UiTheme.GOLD_L, 11)
	price.custom_minimum_size = Vector2(38, 0)
	h.add_child(price)
	item_rows[it.id] = {"stock": stock_l}
	return b


func _process(delta: float) -> void:
	if turn_id != 0:
		time_left = maxf(0.0, time_left - delta)
	_update_turn_label()


func _update_turn_label() -> void:
	var mine := turn_id == multiplayer.get_unique_id()
	if turn_id == 0:
		turn_label.text = "Market hazırlanıyor..."
	elif mine:
		turn_label.text = "SIRA SENDE!   %d sn" % ceili(time_left)
	else:
		var n: String = Net.players.get(turn_id, {}).get("name", "?")
		turn_label.text = "Sıra: %s   %d sn" % [n, ceili(time_left)]
	if mine != turn_was_mine:  # bant rengi sadece değişince güncellenir
		turn_was_mine = mine
		turn_panel.add_theme_stylebox_override("panel", UiTheme.banner_box("banner_gold" if mine else "banner_steel"))
	time_bar.value = time_left if turn_id != 0 else 0.0
	var low := mine and time_left <= 5.0
	time_bar.add_theme_stylebox_override("fill", _flat_box(UiTheme.RED if low else (UiTheme.GOLD if mine else Color(0.5, 0.55, 0.7))))


func _flat_box(c: Color) -> StyleBoxFlat:
	var f := StyleBoxFlat.new()
	f.bg_color = c
	return f


func _refresh() -> void:
	var my := multiplayer.get_unique_id()
	var my_turn := turn_id == my
	var coins: int = Game.coins.get(my, 0)
	for c in coins_box.get_children():
		coins_box.remove_child(c)
		c.queue_free()
	coins_box.add_child(UiTheme.coin_amount(str(coins), UiTheme.GOLD_L, 14))
	for it in Items.ITEMS:
		var b: Button = item_buttons[it.id]
		var left: int = stock.get(it.id, 0)
		var can: bool = left > 0 and Game.can_buy(my, it)
		var stock_l: Label = item_rows[it.id].stock
		stock_l.text = "tükendi" if left <= 0 else "kalan %d" % left
		stock_l.add_theme_color_override("font_color", UiTheme.RED if left <= 0 else UiTheme.DIM)
		b.disabled = not my_turn or not can
		b.modulate = Color.WHITE if can else Color(1, 1, 1, 0.45)  # alınamayanlar soluk
	pass_btn.disabled = not my_turn

	for c in order_box.get_children():
		order_box.remove_child(c)
		c.queue_free()
	for i in Game.last_ranking.size():
		order_box.add_child(_order_row(i, Game.last_ranking[i], my))
	_refresh_sell_buttons(my)
	log_label.text = "\n".join(log_lines.slice(maxi(0, log_lines.size() - 2)))


## Sıra satırı: takım renkli şerit, sıra no, ad, coin; sırası gelen vurgulu, bitenler soluk.
func _order_row(i: int, id: int, my: int) -> Control:
	var team: int = Net.players.get(id, {}).get("team", 0)
	var pc := PanelContainer.new()
	var f := StyleBoxFlat.new()
	f.bg_color = Color(0.34, 0.28, 0.1) if id == turn_id else Color(0.08, 0.07, 0.125)
	f.border_color = UiTheme.GOLD if id == turn_id else Color(0, 0, 0, 0)
	f.set_border_width_all(1)
	f.content_margin_left = 1
	f.content_margin_right = 3
	f.content_margin_top = 1
	f.content_margin_bottom = 1
	pc.add_theme_stylebox_override("panel", f)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	pc.add_child(h)
	var stripe := ColorRect.new()
	stripe.color = UiTheme.TEAM[team]
	stripe.custom_minimum_size = Vector2(3, 0)
	h.add_child(stripe)
	var n: String = Net.players.get(id, {}).get("name", "?")
	var nm := UiTheme.make_label("%d. %s%s" % [i + 1, n, " (sen)" if id == my else ""], 10,
		UiTheme.GOLD_L if id == turn_id else (UiTheme.TEXT if id == my else UiTheme.DIM))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	h.add_child(nm)
	if done.has(id):
		h.add_child(UiTheme.make_label("bitti", 9, UiTheme.DIM))
	h.add_child(UiTheme.coin_amount(str(Game.coins.get(id, 0)), UiTheme.GOLD_L, 10))
	if done.has(id):
		pc.modulate = Color(1, 1, 1, 0.55)
	return pc


## Envanterdeki her eşya türü için bir "Sat" butonu: ikon + adet + iade (alışın %70'i).
func _refresh_sell_buttons(my: int) -> void:
	for c in sell_box.get_children():
		sell_box.remove_child(c)
		c.queue_free()
	var counts := {}
	for item_id in Game.inventory.get(my, []):
		counts[item_id] = counts.get(item_id, 0) + 1
	for item_id in counts.keys():
		var item := Items.get_item(item_id)
		var b := Button.new()
		b.theme_type_variation = "RowButton"
		b.custom_minimum_size = Vector2(78, 20)
		b.tooltip_text = "Sat: %s (+%d coin)" % [item.name, Game.sell_price(item)]
		b.disabled = ended
		b.pressed.connect(_request_sell.bind(item_id))
		var h := HBoxContainer.new()
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 4
		h.offset_right = -3
		h.add_theme_constant_override("separation", 2)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(h)
		h.add_child(UiTheme.icon_rect(item_id, 14))
		var cnt := UiTheme.make_label("x%d" % counts[item_id], 10)
		cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cnt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(cnt)
		h.add_child(UiTheme.coin_amount("+%d" % Game.sell_price(item), UiTheme.GREEN, 10))
		sell_box.add_child(b)


# --- İstekler (oyuncu → sunucu) ---

func _request_sell(item_id: String) -> void:
	if multiplayer.is_server():
		_srv_sell(item_id)
	else:
		_srv_sell.rpc_id(1, item_id)


## Satma sıra hakkını harcamaz; market açıkken her zaman yapılabilir.
@rpc("any_peer", "reliable")
func _srv_sell(item_id: String) -> void:
	if not multiplayer.is_server() or ended:
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	if not Game.inventory.get(id, []).has(item_id):
		return
	_apply_sell.rpc(id, item_id)

func _request_buy(item_id: String) -> void:
	if multiplayer.is_server():
		_srv_buy(item_id)
	else:
		_srv_buy.rpc_id(1, item_id)


func _request_pass() -> void:
	if multiplayer.is_server():
		_srv_pass()
	else:
		_srv_pass.rpc_id(1)


@rpc("any_peer", "reliable")
func _srv_buy(item_id: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	if id != turn_id:
		return
	var item := Items.get_item(item_id)
	if item.is_empty() or stock.get(item_id, 0) <= 0 or not Game.can_buy(id, item):
		return
	turn_timer.stop()
	_apply_buy.rpc(id, item_id)
	_next_turn()


@rpc("any_peer", "reliable")
func _srv_pass() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	if id != turn_id:
		return
	turn_timer.stop()
	done[id] = true
	_next_turn()


func _on_turn_timeout() -> void:
	if turn_id != 0:
		done[turn_id] = true
		_next_turn()


# --- Sıra yönetimi (sunucu) ---

func _can_buy_any(id: int) -> bool:
	for it in Items.ITEMS:
		if stock.get(it.id, 0) > 0 and Game.can_buy(id, it):
			return true
	return false


func _next_turn() -> void:
	for step in order.size():
		idx = (idx + 1) % order.size()
		var id: int = order[idx]
		if done.has(id) or not Net.players.has(id):
			continue
		if not _can_buy_any(id):
			done[id] = true
			continue
		turn_timer.start(TURN_TIME)
		_sync.rpc(stock, id, done)
		return
	_end.rpc()  # herkes bitti


# --- Herkese yansıyanlar ---

@rpc("authority", "call_local", "reliable")
func _apply_buy(id: int, item_id: String) -> void:
	Game.buy(id, item_id)
	stock[item_id] = stock.get(item_id, 0) - 1
	var n: String = Net.players.get(id, {}).get("name", "?")
	log_lines.append("%s aldı: %s" % [n, Items.display_name(item_id)])
	_refresh()


@rpc("authority", "call_local", "reliable")
func _apply_sell(id: int, item_id: String) -> void:
	if Game.sell(id, item_id):
		stock[item_id] = stock.get(item_id, 0) + 1  # satılan stoğa döner
		var n: String = Net.players.get(id, {}).get("name", "?")
		log_lines.append("%s sattı: %s" % [n, Items.display_name(item_id)])
		if auto_test:
			print("[shop] SATIŞ: ", n, " ", item_id, " coin=", Game.coins.get(id, 0), " stok=", stock[item_id])
		_refresh()


@rpc("authority", "call_local", "reliable")
func _sync(s: Dictionary, t: int, d: Dictionary) -> void:
	got_sync = true
	stock = s
	turn_id = t
	done = d
	time_left = TURN_TIME
	_refresh()
	if auto_test and t == multiplayer.get_unique_id():
		get_tree().create_timer(0.3).timeout.connect(_auto_play)


@rpc("authority", "call_local", "reliable")
func _end() -> void:
	got_sync = true
	ended = true
	turn_id = 0
	_refresh()
	finished.emit()


func _auto_play() -> void:  # test için otomatik oyuncu
	var my := multiplayer.get_unique_id()
	if turn_id != my:
		return
	auto_calls += 1
	var owned: Array = Game.inventory.get(my, [])
	# Test: `ab=dash|burst|rally` verilen yeteneği tercih et (savaşta yetenek yolunu sınamak için)
	var pref := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("ab="):
			pref = "ability_" + a.get_slice("=", 1)
	if auto_calls == 2 and pref == "" and not owned.is_empty():
		_request_sell(owned[owned.size() - 1])  # satma testi: sonra aynı tur alışverişe devam
	if pref != "" and stock.get(pref, 0) > 0 and not owned.has(pref) and Game.can_buy(my, Items.get_item(pref)):
		_request_buy(pref)
		return
	for it in Items.ITEMS:
		if stock.get(it.id, 0) > 0 and Game.can_buy(my, it):
			_request_buy(it.id)
			return
	_request_pass()
