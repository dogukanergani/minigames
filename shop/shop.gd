extends Control
## Market: oyuncular minigame sıralamasına göre sırayla alışveriş yapar.
## Sıra geldiğinde 1 eşya alır ya da pas geçer. Pas geçen (ya da süresi dolan)
## bir daha oynamaz. Alacak parası/stoğu kalmayan otomatik pas sayılır.
## Sunucu doğrular; durum RPC ile herkese yansır.

signal finished

const Items = preload("res://scripts/items.gd")
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
var coins_label: Label
var inv_label: Label
var order_label: Label
var log_label: Label
var pass_btn: Button
var sell_box: VBoxContainer
var item_buttons: Dictionary = {}
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
		_mark_hello(1)
	else:
		_announce_hello()


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
	if not turns_started and hello.size() >= Net.players.size():
		turns_started = true
		_next_turn()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.13, 0.1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	turn_label = Label.new()
	turn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(turn_label)
	coins_label = Label.new()
	header.add_child(coins_label)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)

	var items_col := VBoxContainer.new()
	items_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items_col.add_theme_constant_override("separation", 1)
	body.add_child(items_col)
	for it in Items.ITEMS:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(_request_buy.bind(it.id))
		items_col.add_child(b)
		item_buttons[it.id] = b

	var side_col := VBoxContainer.new()
	side_col.custom_minimum_size = Vector2(220, 0)
	body.add_child(side_col)
	order_label = Label.new()
	side_col.add_child(order_label)
	inv_label = Label.new()
	inv_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side_col.add_child(inv_label)
	sell_box = VBoxContainer.new()
	side_col.add_child(sell_box)
	log_label = Label.new()
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side_col.add_child(log_label)
	pass_btn = Button.new()
	pass_btn.text = "Pas Geç"
	pass_btn.pressed.connect(_request_pass)
	side_col.add_child(pass_btn)


func _process(delta: float) -> void:
	if turn_id != 0:
		time_left = maxf(0.0, time_left - delta)
	_update_turn_label()


func _update_turn_label() -> void:
	if turn_id == 0:
		turn_label.text = "Market hazırlanıyor..."
	elif turn_id == multiplayer.get_unique_id():
		turn_label.text = "SIRA SENDE! (%d sn)" % ceili(time_left)
	else:
		var n: String = Net.players.get(turn_id, {}).get("name", "?")
		turn_label.text = "Sıra: %s (%d sn)" % [n, ceili(time_left)]


func _refresh() -> void:
	var my := multiplayer.get_unique_id()
	var my_turn := turn_id == my
	var coins: int = Game.coins.get(my, 0)
	coins_label.text = "Coin: %d" % coins
	for it in Items.ITEMS:
		var b: Button = item_buttons[it.id]
		var left: int = stock.get(it.id, 0)
		b.text = "%s [%s]  %dc  (kalan %d)" % [it.name, it.kind, it.cost, left]
		b.disabled = not my_turn or left <= 0 or not Game.can_buy(my, it)
	pass_btn.disabled = not my_turn

	var lines: Array = ["Sıra:"]
	for i in Game.last_ranking.size():
		var id: int = Game.last_ranking[i]
		var n: String = Net.players.get(id, {}).get("name", "?")
		lines.append("%s%d. %s  %dc%s" % [
			">" if id == turn_id else " ", i + 1, n, Game.coins.get(id, 0),
			" (bitti)" if done.has(id) else ""])
	order_label.text = "\n".join(lines)
	inv_label.text = "Envanterin: " + Game.inventory_text(my)
	_refresh_sell_buttons(my)
	log_label.text = "\n".join(log_lines.slice(maxi(0, log_lines.size() - 5)))


## Envanterdeki her eşya türü için bir "Sat" butonu (iade: alışın %70'i).
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
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "Sat: %s x%d (+%dc)" % [item.name, counts[item_id], Game.sell_price(item)]
		b.disabled = ended
		b.pressed.connect(_request_sell.bind(item_id))
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
	if auto_calls == 2 and not owned.is_empty():
		_request_sell(owned[owned.size() - 1])  # satma testi: sonra aynı tur alışverişe devam
	for it in Items.ITEMS:
		if stock.get(it.id, 0) > 0 and Game.can_buy(my, it):
			_request_buy(it.id)
			return
	_request_pass()
