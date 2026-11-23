extends Control
## Hareketli (üstten görünüm) minigame'lerin ortak tabanı: koşu, coin toplama.
## Akış: el sıkışma -> geri sayım -> oyun -> sonuç. Sunucu otoriterdir:
## istemci sadece WASD girdisini yollar, hareketi/skoru sunucu hesaplar
## ve ~20 Hz anlık görüntüyü (snapshot) herkese yayar.
## Alt sınıflar `# --- Alt sınıf ---` bölümündeki kancaları doldurur.

signal finished(ranking: Array, labels: Dictionary)

const MgArt = preload("res://minigames/mg_art.gd")

enum Phase { LOADING, COUNTDOWN, PLAY, DONE }

const SCREEN := Vector2(640, 360)
const HANDSHAKE_TIMEOUT := 5.0  # gelmeyen oyuncuyu bu kadar bekle
const SNAP_EVERY := 3  # fizik karesi başına; 60 Hz / 3 = 20 Hz

var fast := "fast" in OS.get_cmdline_user_args()
var auto := "auto" in OS.get_cmdline_user_args()
var got_start := false
var snap: Dictionary = {}  # son anlık görüntü (herkeste)
var disp: Dictionary = {}  # çizim konumları (yumuşatılmış)
var setup: Dictionary = {}

# Sadece sunucuda
var phase: Phase = Phase.LOADING
var started := false
var finalized := false
var ready_peers: Dictionary = {}
var inputs: Dictionary = {}  # peer -> Vector2
var pos: Dictionary = {}  # peer -> Vector2
var cd_left := 0.0
var time_left := 0.0
var elapsed := 0.0
var tick := 0

# Sadece görünüm (herkeste, oyun mantığını etkilemez)
var fancy := false  # sprite'lı görünüm (MgArt.ok()); yoksa eski düz çizim
var moving: Dictionary = {}  # id -> koşuyor mu
var move_at: Dictionary = {}  # id -> son hareket anı (ms)
var face: Dictionary = {}  # id -> sola bakıyor mu
var last_target: Dictionary = {}
var dust: Array = []  # [konum, doğduğu an (ms)]
var dust_acc: Dictionary = {}
var shown_ph := -1
var ph_at := 0  # aşamanın değiştiği an (ms)
var shown_cd := -1
var cd_at := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fancy = MgArt.ok()
	if multiplayer.is_server():
		setup = _make_setup()
		Net.players_changed.connect(func(): _srv_hello_from(1))  # biri ayrılınca bekleyen el sıkışmayı yeniden kontrol et
		_srv_hello_from(1)
		get_tree().create_timer(HANDSHAKE_TIMEOUT).timeout.connect(_srv_begin)
	else:
		_hello_loop()


## Sunucunun sahnesi bizden önce yüklenmemiş olabilir ya da mesaj kaybolabilir:
## başlangıç mesajı gelene kadar "hazırım" bilgisini tekrar tekrar yolla.
func _hello_loop() -> void:
	while not got_start and is_inside_tree():
		_srv_hello.rpc_id(1)
		await get_tree().create_timer(0.3).timeout


@rpc("any_peer", "reliable")
func _srv_hello() -> void:
	if multiplayer.is_server():
		_srv_hello_from(multiplayer.get_remote_sender_id())


func _srv_hello_from(id: int) -> void:
	if started:
		if id != 1:
			_start.rpc_id(id, setup)  # geç kalan oyuncuya başlangıç bilgisini tekrar yolla
		return
	ready_peers[id] = true
	if Net.all_in(ready_peers):
		_srv_begin()


func _srv_begin() -> void:
	if started or not is_inside_tree():
		return
	started = true
	var ids: Array = Net.players.keys()
	for i in ids.size():
		pos[ids[i]] = _spawn_pos(i, ids.size())
		inputs[ids[i]] = Vector2.ZERO
	cd_left = 1.0 if fast else 3.0
	time_left = _play_time() * (0.5 if fast else 1.0)
	phase = Phase.COUNTDOWN
	_start.rpc(setup)


@rpc("authority", "call_local", "reliable")
func _start(s: Dictionary) -> void:
	if got_start:
		return
	got_start = true
	setup = s
	_apply_setup(s)


# --- Sunucu döngüsü ---

func _physics_process(delta: float) -> void:
	if got_start:
		_send_local_input()
	if not multiplayer.is_server() or not started or finalized:
		return
	match phase:
		Phase.COUNTDOWN:
			cd_left -= delta
			if cd_left <= 0.0:
				cd_left = 0.0
				phase = Phase.PLAY
		Phase.PLAY:
			elapsed += delta
			time_left -= delta
			for id in pos.keys():
				if not Net.players.has(id):
					continue
				var mv: Vector2 = inputs.get(id, Vector2.ZERO)
				pos[id] = _move_player(id, pos[id], mv.limit_length(1.0) * _speed() * delta)
			_sim(delta)
			if time_left <= 0.0 and not finalized:
				_end()
	tick += 1
	if tick % SNAP_EVERY == 0 and not finalized:
		_broadcast_snapshot()


func _broadcast_snapshot() -> void:
	var s: Dictionary = {"ph": phase, "cd": cd_left, "tl": maxf(time_left, 0.0), "p": pos.duplicate()}
	s.merge(_extra_snap())
	for id in Net.players:  # sadece kayıtlı oyunculara (araya giren yabancı bağlantıya değil)
		if id != 1 and multiplayer.get_peers().has(id):
			_snapshot.rpc_id(id, s)
	_take_snapshot(s)


@rpc("authority", "unreliable")
func _snapshot(s: Dictionary) -> void:
	_take_snapshot(s)


func _take_snapshot(s: Dictionary) -> void:
	snap = s
	var p: Dictionary = s.get("p", {})
	for id in p:
		if not disp.has(id):
			disp[id] = p[id]


## Sunucu: oyunu bitir, sonucu herkese yolla.
func _end() -> void:
	if finalized:
		return
	finalized = true
	phase = Phase.DONE
	var res: Array = _compute_result()
	_broadcast_snapshot()
	_finish.rpc(res[0], res[1])


@rpc("authority", "call_local", "reliable")
func _finish(ranking: Array, labels: Dictionary) -> void:
	finished.emit(ranking, labels)


# --- Girdi ---

func _send_local_input() -> void:
	if int(snap.get("ph", -1)) != Phase.PLAY:
		return
	var mv := _read_input()
	if multiplayer.is_server():
		inputs[1] = _clean(mv)
	else:
		_srv_input.rpc_id(1, mv)


func _read_input() -> Vector2:
	if auto:
		return _bot_input()
	var mv := Vector2.ZERO
	mv.x = float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) \
		- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	mv.y = float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) \
		- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	return mv


@rpc("any_peer", "unreliable")
func _srv_input(mv: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if inputs.has(id):
		inputs[id] = _clean(mv)  # hız sınırı hareket sırasında zorlanır (limit_length)


## İstemciye güvenme: sonlu mu, en fazla birim uzunlukta mı.
func _clean(mv: Vector2) -> Vector2:
	if not (is_finite(mv.x) and is_finite(mv.y)):
		return Vector2.ZERO
	return mv.limit_length(1.0)


# --- Çizim ---

func _process(delta: float) -> void:
	var p: Dictionary = snap.get("p", {})
	var now := Time.get_ticks_msec()
	for id in p:
		var target: Vector2 = p[id]
		var cur: Vector2 = disp.get(id, target)
		disp[id] = cur.lerp(target, minf(1.0, delta * 20.0))
		if fancy:  # koşu animasyonu, bakış yönü ve toz (yalnızca görünüm)
			var step: Vector2 = target - last_target.get(id, target)
			last_target[id] = target
			if (target - cur).length() > 0.6 or step.length() > 0.1:
				move_at[id] = now
			var mv: bool = now - int(move_at.get(id, -1000)) < 160  # anlık görüntü aralarında titremesin
			moving[id] = mv
			if absf(target.x - cur.x) > 0.4:
				face[id] = target.x < cur.x
			if mv:
				dust_acc[id] = float(dust_acc.get(id, 0.0)) + delta
				if dust_acc[id] > 0.09:
					dust_acc[id] = 0.0
					var back := 5.0 if not face.get(id, false) else -5.0
					dust.append([cur + Vector2(-back, 3.0), now])
	if fancy:
		while not dust.is_empty() and now - int(dust[0][1]) > 360:
			dust.pop_front()
		var ph: int = int(snap.get("ph", -1))
		if ph != shown_ph:
			shown_ph = ph
			ph_at = now
		var n := ceili(float(snap.get("cd", 0.0)))
		if n != shown_cd:
			shown_cd = n
			cd_at = now
	queue_redraw()


func _since(t: int) -> float:
	return float(Time.get_ticks_msec() - t) / 1000.0


func _draw() -> void:
	if fancy:
		_draw_fancy()
		return
	_draw_world()
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(6, 12), _title(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
	if snap.is_empty():
		_center_text("Hazırlanıyor...", 16)
		return
	var ph: int = int(snap.ph)
	if ph == Phase.COUNTDOWN:
		_center_text(str(ceili(float(snap.cd))), 40)
		_center_text(_hint(), 10, 40)
	elif ph == Phase.PLAY:
		draw_string(font, Vector2(SCREEN.x - 66, 12), "%d sn" % ceili(float(snap.tl)), HORIZONTAL_ALIGNMENT_RIGHT, 60, 10, Color.WHITE)
	elif ph == Phase.DONE:
		_center_text("BİTTİ!", 24)


func _center_text(text: String, font_size: int, y_off := 0) -> void:
	var font := ThemeDB.fallback_font
	var y: float = SCREEN.y * 0.5 + font_size * 0.35 + y_off
	draw_string(font, Vector2(1, y + 1), text, HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, font_size, Color.BLACK)
	draw_string(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, font_size, Color.WHITE)


## Oyuncuyu küçük bir pixel karakter olarak çizer (takım rengi, kendisi beyaz çerçeveli).
func _draw_player(id: int, p: Vector2) -> void:
	var team: int = Net.players.get(id, {}).get("team", 0)
	var col := Color(0.25, 0.5, 1.0) if team == 0 else Color(1.0, 0.35, 0.3)
	var r := Rect2((p - Vector2(5, 5)).round(), Vector2(10, 10))
	if id == multiplayer.get_unique_id():
		draw_rect(r.grow(1), Color.WHITE)
	draw_rect(r, col)
	draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(6, 2)), Color(1, 1, 1, 0.8))
	var font := ThemeDB.fallback_font
	var nm: String = Net.players.get(id, {}).get("name", "?")
	draw_string(font, Vector2(p.x - 30, p.y - 8).round(), nm, HORIZONTAL_ALIGNMENT_CENTER, 60, 8, Color(1, 1, 1, 0.9))


## Sprite'lı görünüm: dünya (alt sınıf) -> üst band ve HUD -> geri sayım / BAŞLA / BİTTİ.
func _draw_fancy() -> void:
	_draw_world()
	if snap.is_empty():
		MgArt.band(self, _title(), -1.0)
		MgArt.text(self, "HAZIRLANIYOR...", Vector2(320, 180), MgArt.PX * 2.0, Color(0.93, 0.92, 0.97))
		return
	var ph: int = int(snap.ph)
	var tl: float = float(snap.tl)
	if ph == Phase.PLAY:
		MgArt.urgent_vignette(self, tl)
	MgArt.band(self, _title(), tl if ph != Phase.LOADING else -1.0)
	_draw_hud()
	if ph == Phase.COUNTDOWN:
		MgArt.countdown(self, maxi(1, ceili(float(snap.cd))), _since(cd_at), _hint())
	elif ph == Phase.PLAY:
		MgArt.shout(self, "BAŞLA!", _since(ph_at) / 0.9, Color(0.55, 1.0, 0.45))
	elif ph == Phase.DONE:
		MgArt.shout(self, "BİTTİ!", minf(_since(ph_at) / 2.0, 0.6), Color(1.0, 0.9, 0.51))


## Oyuncuları ve `extra` nesneleri ([sıralama y'si, Callable]) ayak hizasına göre (önden arkaya) çizer.
## Önce koşu tozu (altta kalsın).
func _draw_actors(extra: Array = []) -> void:
	var now := Time.get_ticks_msec()
	var dt := MgArt.tex("dust")
	for d in dust:
		var k := float(now - int(d[1])) / 360.0
		MgArt.frame(self, dt, clampi(int(k * 4.0), 0, 3), 10, d[0] + Vector2(0, -k * 3.0), MgArt.PX, Color(1, 1, 1, 0.9))
	var items: Array = extra.duplicate()
	for id in disp:
		items.append([disp[id].y + 4.0, _draw_actor.bind(id, disp[id])])
	items.sort_custom(func(a, b): return a[0] < b[0])
	for it in items:
		(it[1] as Callable).call()


## Tek oyuncu: ayak halkası, Savaşçı sprite'ı (koşu/bekleme, yöne göre ayna), isim, taç/ok ve alt sınıfın başüstü eki.
func _draw_actor(id: int, p: Vector2) -> void:
	var team: int = Net.players.get(id, {}).get("team", 0)
	var mine := id == multiplayer.get_unique_id()
	MgArt.ring(self, p, team, mine)
	var anim := "run" if moving.get(id, false) else "idle"
	if not MgArt.hero(self, team, anim, p + Vector2(0, 4), face.get(id, false)):
		draw_rect(Rect2((p - Vector2(5, 5)).round(), Vector2(10, 10)), MgArt.team_col(team))
	var top := Art.hero_top() + 2.0
	var nm: String = Net.players.get(id, {}).get("name", "?")
	MgArt.small(self, nm, p + Vector2(0, -top + 3.0), 8, Color(1.0, 0.92, 0.6) if mine else Color(1, 1, 1, 0.92))
	MgArt.marker(self, p + Vector2(0, -top - 6.0), team, mine)
	_above_head(id, p, top)


func _my_pos() -> Vector2:
	var p: Dictionary = snap.get("p", {})
	return p.get(multiplayer.get_unique_id(), Vector2.ZERO)


# --- Alt sınıf: bunlar doldurulur ---

func _title() -> String:
	return ""

func _hint() -> String:
	return ""

func _play_time() -> float:
	return 30.0

func _speed() -> float:
	return 100.0

func _make_setup() -> Dictionary:  # sunucu, rastgele ayarlar (herkese yollanır)
	return {}

func _apply_setup(_s: Dictionary) -> void:  # herkes
	pass

func _spawn_pos(_index: int, _count: int) -> Vector2:
	return SCREEN * 0.5

func _move_player(_id: int, p: Vector2, step: Vector2) -> Vector2:  # sunucu
	return p + step

func _sim(_delta: float) -> void:  # sunucu, her oyun karesi
	pass

func _extra_snap() -> Dictionary:  # sunucu, anlık görüntüye eklenecekler
	return {}

func _compute_result() -> Array:  # sunucu: [sıralama, etiketler]
	return [[], {}]

func _draw_world() -> void:  # `fancy` ise sprite'lı dünya + _draw_actors(), değilse eski düz çizim
	pass

func _draw_hud() -> void:  # sprite'lı görünüm: bandın ortası / skor tablosu
	pass

func _above_head(_id: int, _p: Vector2, _top: float) -> void:  # sprite'lı görünüm: oyuncunun başı üstü eki
	pass

func _bot_input() -> Vector2:  # test botu
	return Vector2.ZERO
