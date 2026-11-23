extends Control
## Refleks minigame'i: ekran yeşile dönünce herkes mümkün olduğunca hızlı basar.
## Süreyi istemci ölçer (gecikmeden etkilenmesin), sunucu sıralar.
## Erken basan ya da basmayan en sona düşer.

signal finished(ranking: Array, labels: Dictionary)

const MgArt = preload("res://minigames/mg_art.gd")

enum State { WAIT, GO, DONE }

const FALSE_START := -1
const NO_ANSWER := -2
const TIMEOUT := 3.0  # GO'dan sonra en fazla bu kadar beklenir
const LATENCY_ALLOWANCE := 200  # ms: istemci süresi, sunucunun gördüğünden en fazla bu kadar kısa olabilir

var state := State.WAIT
var go_msec := 0
var bg: ColorRect
var label: Label

# Sadece sunucuda kullanılır
var go_sent_msec := 0  # GO sinyalinin gönderildiği an (sunucu saati)
var results: Dictionary = {}
var finalized := false

# Sadece görünüm (oyun mantığını etkilemez)
var fancy := false  # sprite'lı düello sahnesi; yoksa eski düz renk + yazı
var my_ms := 0  # kendi sonucum (ms) ya da FALSE_START
var pressed := false
var press_at := 0  # basış anı (ms, yerel)
var go_at := 0  # GO'nun geldiği an (ms, yerel)
var result_rank: Array = []
var result_labels: Dictionary = {}


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

	fancy = MgArt.ok()
	if fancy:
		bg.visible = false
		label.visible = false

	if multiplayer.is_server():
		Net.players_changed.connect(_on_roster_changed)
		_server_run()
	elif "cheat" in OS.get_cmdline_user_args():
		# Test: hilekâr istemci GO gelmeden "0 ms" sonucu yollar. Sunucu bunu erken basış saymalı.
		get_tree().create_timer(1.5).timeout.connect(func(): _srv_result.rpc_id(1, 0))


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
	pressed = true
	press_at = Time.get_ticks_msec()
	if state == State.GO:
		ms = Time.get_ticks_msec() - go_msec
		label.text = "%d ms\nDiğerleri bekleniyor..." % ms
	else:
		bg.color = Color(0.3, 0.3, 0.3)
		label.text = "Erken bastın!"
	state = State.DONE
	my_ms = ms
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
	go_sent_msec = Time.get_ticks_msec()
	_go.rpc()
	await get_tree().create_timer(TIMEOUT).timeout
	_finalize()


## Biri ayrıldı: kalan herkes cevap verdiyse beklemeden bitir.
func _on_roster_changed() -> void:
	if not finalized and Net.all_in(results):
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
	results[id] = _checked_ms(ms)
	if Net.all_in(results):
		_finalize()


## Süreyi istemci ölçer (ağ gecikmesinden etkilenmesin) ama sunucu sınırlar:
## GO gönderilmeden gelen sonuç erken basıştır; sonuç, GO'dan bu yana geçen sunucu süresinden
## uzun olamaz ve (gecikme payı kadar) fazla kısa da olamaz, "0 ms" yollayıp kazanmak olmaz.
func _checked_ms(ms: int) -> int:
	if ms < 0 or go_sent_msec == 0:
		return FALSE_START
	var elapsed := Time.get_ticks_msec() - go_sent_msec
	return clampi(maxi(ms, elapsed - LATENCY_ALLOWANCE), 0, elapsed)


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
	go_at = go_msec
	bg.color = Color(0.1, 0.6, 0.2)
	label.text = "ŞİMDİ!"
	if "auto" in OS.get_cmdline_user_args():  # test için otomatik basış
		get_tree().create_timer(randf_range(0.15, 0.4)).timeout.connect(_press)


@rpc("authority", "call_local", "reliable")
func _finish(ranking: Array, labels: Dictionary) -> void:
	state = State.DONE
	result_rank = ranking
	result_labels = labels
	finished.emit(ranking, labels)


# --- Çizim (sprite'lı düello sahnesi; sprite paketi yoksa eski ColorRect + Label kalır) ---

func _process(_delta: float) -> void:
	if not fancy:
		return
	# ekran sarsıntısı: VUR! anında ve erken basışta
	var now := Time.get_ticks_msec()
	var k := 0.0
	if go_at > 0 and now - go_at < 300:
		k = 1.0 - float(now - go_at) / 300.0
	if pressed and my_ms == FALSE_START and now - press_at < 400:
		k = maxf(k, 1.0 - float(now - press_at) / 400.0)
	position = Vector2(roundf(sin(now * 0.09) * 3.0 * k), roundf(cos(now * 0.13) * 2.0 * k))
	queue_redraw()


func _draw() -> void:
	if not fancy:
		return
	var now := Time.get_ticks_msec()
	var early := pressed and my_ms == FALSE_START
	var hit := pressed and my_ms >= 0
	draw_rect(Rect2(-8, -8, 656, 376), Color(0.05, 0.03, 0.08))
	MgArt.background(self, "reaction_bg")
	if state == State.WAIT or early:  # gerilim: yavaşça nabız atan kızıl ton
		var pulse := 0.5 + 0.5 * sin(float(now) / 1000.0 * 3.0)
		draw_rect(Rect2(0, 0, 640, 360), Color(0.35, 0.02, 0.08, 0.10 + 0.08 * pulse))
	elif go_at > 0:  # GO: yeşil flaş, sonra hafif yeşil ton
		var g := clampf(1.0 - float(now - go_at) / 260.0, 0.0, 1.0)
		draw_rect(Rect2(0, 0, 640, 360), Color(0.3, 1.0, 0.4, 0.12 + 0.55 * g))
	_draw_duelists(now, early, hit)
	# sinema bantları
	draw_rect(Rect2(-8, -8, 656, 30), Color(0.02, 0.01, 0.04, 0.85))
	draw_rect(Rect2(-8, 334, 656, 34), Color(0.02, 0.01, 0.04, 0.85))
	MgArt.band(self, "REFLEKS", -1.0)
	_draw_message(now, early, hit)
	_draw_roster()


## Sol: kendi karakterim (sağa bakar); sağ: rakipler silüet halinde (sola bakar). Bekleme: nefes alma.
func _draw_duelists(now: int, early: bool, hit: bool) -> void:
	var my_id := multiplayer.get_unique_id()
	var others: Array = Net.players.keys()
	others.erase(my_id)
	var foot_y := 255.0
	var sc := 3.0 if others.size() <= 1 else (2.0 if others.size() <= 3 else 1.5)
	var lit := go_at > 0 and not early
	var items: Array = []
	for i in others.size():
		var col := i / 3
		var row := i % 3
		var n_in_col := mini(3, others.size() - col * 3)
		var off := float(row) - float(n_in_col - 1) * 0.5
		var y := foot_y + off * 30.0
		var x := 455.0 + col * 62.0 + absf(off) * 16.0
		items.append([y, others[i], Vector2(x, y)])
	items.sort_custom(func(a, b): return a[0] < b[0])
	for it in items:
		var id: int = it[1]
		var p: Vector2 = it[2]
		var team: int = Net.players.get(id, {}).get("team", 0)
		draw_colored_polygon(MgArt.ellipse(p + Vector2(0, 1), 9.0 * sc, 3.0 * sc), Color(0.05, 0.02, 0.06, 0.5))
		var tint := Color(0.42, 0.36, 0.5) if lit else Color(0.13, 0.07, 0.16)
		MgArt.hero(self, team, "idle", p, true, sc, tint, -1, 520.0 + float(id % 7) * 40.0)
	for it in items:  # isimler gövdelerin üstünde kalsın
		var nm: String = Net.players.get(it[1], {}).get("name", "?")
		MgArt.small(self, nm, it[2] + Vector2(0, 11.0), 8, Color(1, 1, 1, 0.8))
	# kendim
	var me := Vector2(170, foot_y)
	var my_team: int = Net.players.get(my_id, {}).get("team", 0)
	var since := float(now - press_at)
	if hit:  # atılma: öne doğru hamle
		me.x += 90.0 * clampf(since / 120.0, 0.0, 1.0)
	elif early:  # sendeleme: geri seker, sallanır
		var k := clampf(since / 700.0, 0.0, 1.0)
		me.x -= 14.0 * sin(k * PI * 0.5) + sin(since / 45.0) * 3.0 * (1.0 - k)
	draw_colored_polygon(MgArt.ellipse(me + Vector2(0, 1), 26.0, 8.0), Color(0.05, 0.02, 0.06, 0.5))
	var drawn := false
	if hit:
		var at := Art.unit_tex(my_team, "warrior", "attack")
		if at != null:
			var fr := Art.attack_frame(at, "sword", since * 0.6)  # biraz yavaş: düello hissi
			if fr >= 0:
				var foot: float = Art.foot_for(at, 32.0, Art.get_meta_value("foot")) if Art.custom else -1.0
				Art.draw_frame(self, at, fr, me, Art.hero_scale() * 3.0, false, Color.WHITE, foot)
				drawn = true
	if not drawn:
		var tint := Color(1.0, 0.45, 0.45) if early and since < 500.0 and (int(since) / 80) % 2 == 0 else Color.WHITE
		MgArt.hero(self, my_team, "idle", me, false, 3.0, tint, -1, 520.0)
	MgArt.small(self, Net.players.get(my_id, {}).get("name", "?"), me + Vector2(0, 15.0), 9, Color(1.0, 0.92, 0.6))
	MgArt.marker(self, me + Vector2(0, -62.0), my_team, true)


## Ortadaki büyük yazı: HAZIR OL / VUR! / süre (ms) / ÇOK ERKEN!
func _draw_message(now: int, early: bool, hit: bool) -> void:
	var c := Vector2(320, 92)
	if early:
		var k := float(now - press_at)
		var ct := MgArt.tex("crack")
		if ct != null:
			var a := clampf(1.2 - k / 2500.0, 0.55, 1.0)
			var sz := Vector2(ct.get_width(), ct.get_height()) * MgArt.PX * 2.0
			draw_texture_rect(ct, Rect2(Vector2(320, 175) - sz * 0.5, sz), false, Color(1.0, 0.3, 0.3, a))
		if k < 250.0:
			draw_rect(Rect2(0, 0, 640, 360), Color(1.0, 0.1, 0.1, 0.45 * (1.0 - k / 250.0)))
		MgArt.shout(self, "ÇOK ERKEN!", minf(k / 1000.0, 0.5), Color(1.0, 0.3, 0.3), c, 8.0 / 3.0)
		_hint_plate("Yeşili beklemeden bastın: en sona düştün.", 128.0)
		return
	if hit:
		var k := float(now - press_at)
		var big := 8.0 / 3.0
		var sc := big if k > 120.0 else lerpf(big * 1.5, big, k / 120.0)
		var s := "%d MS" % my_ms
		var w := MgArt.text_w(s, big) + 20.0
		MgArt.plate(self, Rect2(320 - w * 0.5, c.y - 25.0, w, 50), Color(0.09, 0.08, 0.15, 0.9), Color(1.0, 0.85, 0.3))
		MgArt.text(self, s, c + Vector2(3, 3), sc, Color(0, 0, 0, 0.4))
		MgArt.text(self, s, c, sc, Color(1.0, 0.9, 0.51))
		var word := "ŞİMŞEK!" if my_ms < 220 else ("HIZLI!" if my_ms < 320 else ("İYİ" if my_ms < 450 else "YAVAŞ..."))
		MgArt.text(self, word, c + Vector2(0, 42), MgArt.PX * 2.0, Color(0.55, 1.0, 0.45) if my_ms < 320 else Color(0.93, 0.92, 0.97))
		var dots := ".".repeat(1 + (now / 300) % 3)
		MgArt.text(self, "DİĞERLERİ BEKLENİYOR" + dots, Vector2(320, 318), MgArt.PX, Color(0.8, 0.78, 0.9))
		return
	if state == State.GO:
		var k := float(now - go_at)
		MgArt.shout(self, "VUR!", minf(k / 900.0, 0.5), Color(0.55, 1.0, 0.45), c)
		return
	# WAIT: HAZIR OL (nabız), ipucu
	var pulse := 0.5 + 0.5 * sin(float(now) / 1000.0 * 4.0)
	MgArt.text(self, "HAZIR OL", c + Vector2(3, 3), 8.0 / 3.0, Color(0, 0, 0, 0.4))
	MgArt.text(self, "HAZIR OL", c, 8.0 / 3.0, Color(1.0, 0.55 + 0.35 * pulse, 0.35 + 0.2 * pulse))
	_hint_plate("Ekran yeşil olunca bas!  (Boşluk / tıkla)", 124.0)


func _hint_plate(s: String, y: float) -> void:
	var r := Rect2(320 - 130, y, 260, 15)
	MgArt.plate(self, r, Color(0.09, 0.08, 0.15, 0.9))
	MgArt.small(self, s, Vector2(320, y + 11.0), 9, Color(0.93, 0.92, 0.97), 256.0)


## Alt bant: katılımcılar (takım rengi + ad). Sonuç gelince sıra ve süre.
func _draw_roster() -> void:
	var ids: Array = result_rank if not result_rank.is_empty() else Net.players.keys()
	var n := ids.size()
	if n == 0:
		return
	var w := minf(120.0, 620.0 / float(n))
	var x0 := 320.0 - w * n * 0.5
	var my_id := multiplayer.get_unique_id()
	for i in n:
		var id: int = ids[i]
		var team: int = Net.players.get(id, {}).get("team", 0)
		var r := Rect2(x0 + i * w + 2.0, 339, w - 4.0, 15)
		MgArt.plate(self, r, Color(0.62, 0.45, 0.1, 0.9) if id == my_id else Color(0.09, 0.08, 0.15, 0.9),
			Color(1.0, 0.85, 0.3) if id == my_id else Color(0.5, 0.55, 0.7))
		draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(3, r.size.y - 2.0)), MgArt.team_col(team))
		var nm: String = Net.players.get(id, {}).get("name", "?")
		if not result_rank.is_empty():
			nm = "%d. %s  %s" % [i + 1, nm, result_labels.get(id, "")]
		MgArt.small(self, nm, r.position + Vector2(6, 11), 8, Color.WHITE, r.size.x - 8.0, HORIZONTAL_ALIGNMENT_LEFT)
