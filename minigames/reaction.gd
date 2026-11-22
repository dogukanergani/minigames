extends Control
## Refleks minigame'i: ekran yeşile dönünce herkes mümkün olduğunca hızlı basar.
## Süreyi istemci ölçer (gecikmeden etkilenmesin), sunucu sıralar.
## Erken basan ya da basmayan en sona düşer.

signal finished(ranking: Array, labels: Dictionary)

enum State { WAIT, GO, DONE }

const FALSE_START := -1
const NO_ANSWER := -2
const TIMEOUT := 3.0  # GO'dan sonra en fazla bu kadar beklenir

var state := State.WAIT
var go_msec := 0
var bg: ColorRect
var label: Label

# Sadece sunucuda kullanılır
var results: Dictionary = {}
var finalized := false


func _ready() -> void:
	var ui_theme := Theme.new()
	ui_theme.default_font_size = 16
	theme = ui_theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	bg = ColorRect.new()
	bg.color = Color(0.6, 0.15, 0.15)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	label = Label.new()
	label.text = "Hazır ol...\nEkran yeşil olunca bas!\n(Boşluk / tıkla)"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(label)

	if multiplayer.is_server():
		_server_run()


func _input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventMouseButton and event.pressed:
		pressed = true
	elif event is InputEventKey and event.pressed and not event.echo:
		pressed = event.keycode in [KEY_SPACE, KEY_ENTER]
	if pressed:
		_press()


func _press() -> void:
	if state == State.DONE:
		return
	var ms := FALSE_START
	if state == State.GO:
		ms = Time.get_ticks_msec() - go_msec
		label.text = "%d ms\nDiğerleri bekleniyor..." % ms
	else:
		bg.color = Color(0.3, 0.3, 0.3)
		label.text = "Erken bastın!"
	state = State.DONE
	if multiplayer.is_server():
		_srv_result(ms)
	else:
		_srv_result.rpc_id(1, ms)


# --- Sunucu ---

func _server_run() -> void:
	# İstemcilerin sahneyi yüklemesi için 1 sn + rastgele bekleme
	await get_tree().create_timer(1.0 + randf_range(2.0, 5.0)).timeout
	if finalized:
		return  # herkes erken bastı
	_go.rpc()
	await get_tree().create_timer(TIMEOUT).timeout
	_finalize()


@rpc("any_peer", "reliable")
func _srv_result(ms: int) -> void:
	if not multiplayer.is_server() or finalized:
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1  # host kendi çağırdı
	if results.has(id) or not Net.players.has(id):
		return
	results[id] = ms
	if results.size() >= Net.players.size():
		_finalize()


func _finalize() -> void:
	if finalized:
		return
	finalized = true
	var ids: Array = Net.players.keys()
	for id in ids:
		if not results.has(id):
			results[id] = NO_ANSWER
	ids.sort_custom(func(a, b): return _sort_key(results[a]) < _sort_key(results[b]))
	var labels := {}
	for id in ids:
		labels[id] = _label_for(results[id])
	_finish.rpc(ids, labels)


func _sort_key(ms: int) -> int:
	if ms >= 0:
		return ms
	return 1000000000 if ms == FALSE_START else 1000000001


func _label_for(ms: int) -> String:
	if ms >= 0:
		return "%d ms" % ms
	return "erken bastı" if ms == FALSE_START else "cevap yok"


# --- Herkes ---

@rpc("authority", "call_local", "reliable")
func _go() -> void:
	if state != State.WAIT:
		return
	state = State.GO
	go_msec = Time.get_ticks_msec()
	bg.color = Color(0.1, 0.6, 0.2)
	label.text = "ŞİMDİ!"
	if "auto" in OS.get_cmdline_user_args():  # test için otomatik basış
		get_tree().create_timer(randf_range(0.15, 0.4)).timeout.connect(_press)


@rpc("authority", "call_local", "reliable")
func _finish(ranking: Array, labels: Dictionary) -> void:
	state = State.DONE
	finished.emit(ranking, labels)
