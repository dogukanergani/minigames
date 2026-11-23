extends Node2D
## Savaş: takımlı bayrak savaşı. Her oyuncunun bir KAHRAMANI (doğrudan yönetilir)
## ve marketten aldığı bir BİRLİĞİ (komutla yönetilir) vardır.
##
## Mimari: sunucu otoriter simülasyon çalıştırır (hareket, saldırı, birim zekâsı,
## bayrak, ölüm). İstemciler girdi (yön, nişan, saldırı, imleç) yollar, ~30 Hz anlık
## görüntü (snapshot) alıp çizer. Tüm çizim kodla yapılır (harici görsel yok).
##
## Kontroller: WASD hareket, fare nişan, sol tık saldırı, Q silah değiştir,
##   E / sağ tık duvar koy, 1 = birlik Takip, 2 = birlik Saldır (imlece), 3 = birlik Bayrak.

signal finished(winner_team: int, scores: Array)

const Items = preload("res://scripts/items.gd")
const UiTheme = preload("res://scripts/ui_theme.gd")

const VIEW := Vector2(640, 360)
const ARENA := Rect2(0, 0, 1280, 720)
const PSIZE := 16.0  # kahraman çarpışma kutusu (sprite'a uysun diye büyütüldü)
const HALF := 8.0
## Sprite ölçekleri (dünya birimi / sprite pikseli). Pencere 1920x1080 = dünya x3, bu yüzden
## kahraman 1/3 ile 1080p'de birebir piksel boyutunda görünür; birimler yarı boyutta (1/6).
const SPR_HERO := 1.0 / 3.0
const SPR_UNIT := 1.0 / 6.0
const SPR_TILE := 1.0 / 3.0
const USIZE := 6.0  # birim
const UHALF := 3.0
const BASE_SPEED := 80.0
const BASE_HP := 100
const CARRY_SLOW := 0.85
const FLAG_RETURN_TIME := 10.0
const PICKUP_R := 12.0
const CAPTURE_R := 16.0
const WALL_SIZE := 14.0
const SEND_INTERVAL := 1.0 / 30.0
const BASE_W := 120.0

const FLAG_HOME := [Vector2(60, 360), Vector2(1220, 360)]  # 0 = Mavi (sol), 1 = Kırmızı (sağ)
const TEAM_COLORS := [Color(0.3, 0.55, 1.0), Color(1.0, 0.4, 0.35)]

# Sabit engeller (sol-sağ simetrik, orta şerit y=360 açık)
const OBSTACLES := [
	Rect2(300, 140, 24, 110), Rect2(956, 140, 24, 110),
	Rect2(300, 470, 24, 110), Rect2(956, 470, 24, 110),
	Rect2(520, 250, 60, 16), Rect2(700, 250, 60, 16),
	Rect2(520, 454, 60, 16), Rect2(700, 454, 60, 16),
	Rect2(600, 40, 80, 20), Rect2(600, 660, 80, 20),
	Rect2(180, 200, 30, 14), Rect2(1070, 200, 30, 14),
	Rect2(180, 506, 30, 14), Rect2(1070, 506, 30, 14),
]

const WEAPONS := {
	"fist": {"name": "Yumruk", "dmg": 10.0, "range": 18.0, "cd": 0.5, "ranged": false},
	"sword": {"name": "Kılıç", "dmg": 20.0, "range": 24.0, "cd": 0.45, "ranged": false},
	"spear": {"name": "Mızrak", "dmg": 16.0, "range": 36.0, "cd": 0.6, "ranged": false},
	"bow": {"name": "Yay", "dmg": 12.0, "range": 0.0, "cd": 0.7, "ranged": true},
}
# Yetenekler (markette "Yetenek" olarak satılır, en fazla 2 tane: Boşluk = 1., F = 2.)
const ABILITIES := {
	"ability_dash": {"name": "Atılma", "cd": 6.0},
	"ability_burst": {"name": "Kalkan Patlaması", "cd": 10.0},
	"ability_rally": {"name": "Savaş Narası", "cd": 20.0},
}
const ABILITY_ORDER := ["ability_dash", "ability_burst", "ability_rally"]  # anlık görüntüde kısa indeks
const DASH_DIST := 70.0  # Atılma: bakılan yöne anında bu kadar ilerler (engelde durur)
const BURST_R := 40.0  # Kalkan Patlaması: yarıçap, hasar, geri itme, kısa süreli %50 hasar azaltma
const BURST_DMG := 15.0
const BURST_PUSH := 24.0
const SHIELD_TIME := 2.0
const RALLY_TIME := 5.0  # Savaş Narası: birliğin bu süre hızlı (x1.4) ve güçlü (x1.5) olur
const RALLY_SPEED := 1.4
const RALLY_DMG := 1.5
const SUDDEN_MAX := 120.0  # altın bayrak en fazla bu kadar sürer (sn)
const ARROW_SPEED := 220.0
# Yalnızca GÖRSEL zamanlayıcılar (oyun mantığına etkisi yok): anlık görüntüde "az önce saldırdı / vuruldu" biti
const ATK_VIS := 0.15
const HIT_VIS := 0.12
const HIT_FLASH_MS := 80  # vurulan beyaz yanıp söner
const SPARK_MS := 200  # vuruş kıvılcımı (4 kare)
const PUFF_MS := 350  # ölüm bulutu (5 kare)
const ARROW_LIFE := 0.9
const WALL_HP := {"wall_wood": 40, "wall_stone": 100}
const SHIELD := {"shield_wood": 0.15, "shield_iron": 0.30}

# Birim türleri (item id'leri ile aynı). UNIT_ORDER: anlık görüntüde kısa indeks.
const UNIT_ORDER := ["unit_swordsman", "unit_archer", "unit_artillery", "unit_shieldbearer"]
# Ek alanlar: half = çarpışma/çizim yarı boyutu, aoe = alan hasarı yarıçapı, wmul = duvar hasar çarpanı,
# armor = hasar azaltma, taunt = düşman birimleri önce buna saldırır.
const UNIT_TYPES := {
	"unit_swordsman": {"name": "Kılıççı", "hp": 50.0, "speed": 62.0, "dmg": 8.0, "range": 12.0, "cd": 0.6, "ranged": false, "half": 3.0},
	"unit_archer": {"name": "Okçu", "hp": 30.0, "speed": 56.0, "dmg": 7.0, "range": 90.0, "cd": 0.9, "ranged": true, "half": 3.0},
	"unit_artillery": {"name": "Topçu", "hp": 28.0, "speed": 40.0, "dmg": 16.0, "range": 160.0, "cd": 2.2, "ranged": true,
		"half": 4.0, "aoe": 24.0, "wmul": 3.0},
	"unit_shieldbearer": {"name": "Kalkancı", "hp": 140.0, "speed": 50.0, "dmg": 5.0, "range": 12.0, "cd": 0.8, "ranged": false,
		"half": 4.0, "armor": 0.4, "taunt": true},
}
# Ölen birim kalıcı gitmez: sahibinin üssünde bu kadar sn sonra tam canla yeniden doğar (🧪 taslak).
const UNIT_RESPAWN := {"unit_swordsman": 12.0, "unit_archer": 14.0, "unit_shieldbearer": 20.0,
	"unit_artillery": 28.0, "unit_healer": 16.0}
const SHELL_SPEED := 120.0
const SEP_R := 9.0  # dost birimler bundan yakınsa birbirini iter
const CMD_NAMES := ["Takip", "Saldır", "Bayrak"]
const UNIT_AGGRO := [70.0, 100.0, 50.0]  # komuta göre düşman fark etme yarıçapı
const UNIT_LEASH := 130.0  # Takip modunda kahramandan en fazla bu kadar uzaklaşır

# Maç ayarları (GDD: ilk 3 bayrak / 5 dk / 5 sn yeniden doğma). "fast" test modunda hızlanır.
var time_limit := 300.0
var captures_to_win := 3
var respawn_time := 5.0
var countdown_time := 3.0
var speed_mul := 1.0
var respawn_mul := 1.0  # birim yeniden doğma süresi çarpanı ("fast" testte kısalır)

# --- Sunucu durumu ---
var hello: Dictionary = {}
var started := false
var over := false
var tick := 0
var pl: Dictionary = {}  # peer_id -> kahraman durumu
var units: Dictionary = {}  # uid -> birim durumu
var next_uid := 1
var next_wid := 1
var booms_vis: Array = []  # istemci: patlama efektleri
var booms: Array = []  # bu anlık görüntüde patlayanlar (çizim için)
var stress := false
var st_sum := 0.0
var st_max := 0.0
var st_n := 0
var losses: Dictionary = {}  # eski kalıcı kayıp listesi: artık hep boş (ağ imzası için duruyor)
var respawning: Array = []  # ölen birimler: {owner, type, slot, t} (sunucu)
var flags: Array = []
var projectiles: Array = []
var walls: Array = []
var inputs: Dictionary = {}
var scores: Array = [0, 0]
var time_left := 0.0
var countdown := 0.0
var sudden := false
var sudden_t := 0.0  # altın bayrakta geçen süre

# --- İstemci durumu ---
var snap: Dictionary = {}
var snap_u: Array = []  # birimler: [uid, x, y, hp, max_hp, takım, tür, sahip (istemcide -1), saldırdı, vuruldu, sola bakış]
var view_pos: Dictionary = {}
var view_u: Dictionary = {}
# Sprite animasyonu için hareket / bakış yönü (istemci, sadece çizim)
var unit_move: Dictionary = {}  # uid -> hareket ediyor mu
var unit_flip: Dictionary = {}  # uid -> sola mı bakıyor
var hero_move: Dictionary = {}
var atk_anim: Dictionary = {}  # peer_id -> {t: başlangıç ms, w: silah, aim: açı, pred: yerel tahmin mi}
var atk_prev: Dictionary = {}  # peer_id -> önceki anlık görüntüde saldırı işareti (yükselen kenar = yeni saldırı)
var hit_prev: Dictionary = {}
var hit_t: Dictionary = {}  # peer_id -> vurulma anı (ms): beyaz parlama
var alive_prev: Dictionary = {}
var u_atk: Dictionary = {}  # uid -> saldırı animasyonu başlangıcı (ms)
var u_atk_prev: Dictionary = {}
var u_hit_prev: Dictionary = {}
var u_hit_t: Dictionary = {}
var fx_sparks: Array = []  # [konum, başlangıç ms]: vuruş kıvılcımları
var fx_puffs: Array = []  # [konum, başlangıç ms]: ölüm bulutları
var pred_atk_next := 0  # kendi saldırı animasyonu tahmini: bir sonraki izinli an (ms)
var shake_t := -1000  # kamera sarsıntısı başlangıcı (ms)
var feed: Array = []
var send_acc := 0.0
var my_id := 0
var camera: Camera2D
var hud: Control
var bot_kill_done := false
var bot_cmd_sent := false
var bot_ab_last := [0, 0]  # botun yetenekleri son kullandığı an (ms)
var is_auto := false

# Kendi kahramanın için istemci tarafı tahmin (prediction): girdi hemen uygulanır,
# sunucu cevabı gelince "onaylanmamış" girdiler yeniden oynatılarak düzeltilir.
var in_seq := 0  # gönderilen girdi paketi sayacı (sunucu son aldığını geri bildirir)
var held_mv := Vector2.ZERO  # son gönderilen yön (sunucu da bunu uygular)
var pred_pos := Vector2.ZERO
var pred_valid := false
var pending: Array = []  # [seq, mv, dt] onaylanmamış kareler
var snap_ack: Dictionary = {}  # peer_id -> sunucunun aldığı son seq (8 bit)
var pred_err_sum := 0.0
var pred_err_max := 0.0
var pred_n := 0

# Ağ ölçümü (istemcide, test modunda savaş sonunda yazdırılır)
var net_n := 0
var net_last_ms := 0
var net_gap_sum := 0
var net_gap_max := 0
var shots_dir := ""
var shot_n := 0
var shot_last := 0
var net_late := 0  # 100 ms'den uzun aralıkların sayısı (takılma göstergesi)


func _ready() -> void:
	my_id = multiplayer.get_unique_id()
	var args := OS.get_cmdline_user_args()
	is_auto = "auto" in args
	stress = "stress" in args
	for a in args:
		if a.begins_with("shots="):
			shots_dir = a.substr(6)
	if "fast" in args:
		captures_to_win = 1
		respawn_time = 1.0
		countdown_time = 1.0
		speed_mul = 3.0
		respawn_mul = 0.15
	time_left = time_limit

	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(ARENA.size.x)
	camera.limit_bottom = int(ARENA.size.y)
	camera.position = Vector2(60, 360)
	add_child(camera)
	var layer := CanvasLayer.new()  # HUD kamerayla kaymasın
	add_child(layer)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud)
	layer.add_child(hud)

	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_left)
		Net.players_changed.connect(func(): _mark_hello(1))  # biri ayrılınca bekleyen el sıkışmayı yeniden kontrol et
		_mark_hello(1)
	else:
		_announce_hello()


## Sunucunun savaş sahnesi henüz yüklenmemişse mesaj kaybolur: ilk anlık görüntü
## gelene kadar "hazırım" bilgisini tekrar tekrar yollarız.
func _announce_hello() -> void:
	while snap.is_empty() and is_inside_tree():
		_srv_hello.rpc_id(1)
		await get_tree().create_timer(0.5).timeout


@rpc("any_peer", "reliable")
func _srv_hello() -> void:
	if multiplayer.is_server():
		_mark_hello(multiplayer.get_remote_sender_id())


func _mark_hello(id: int) -> void:
	hello[id] = true
	if not started and Net.all_in(hello):
		_start()


func _start() -> void:
	var counts := [0, 0]
	var ids: Array = Net.players.keys()
	ids.sort()
	for id in ids:
		var t: int = Net.players[id].team
		pl[id] = _make_player(id, t, counts[t])
		counts[t] += 1
		_spawn_units(id, pl[id])
		if stress:
			_spawn_stress(id, pl[id])
	flags = [_new_flag(0), _new_flag(1)]
	countdown = countdown_time
	time_left = time_limit
	started = true


func _new_flag(team: int) -> Dictionary:
	return {"pos": FLAG_HOME[team], "state": 0, "carrier": -1, "timer": 0.0}  # 0 evde, 1 taşınıyor, 2 yerde


func _spawn_pos(team: int, idx: int) -> Vector2:
	var off := float((idx + 2) % 5 - 2) * 36.0
	return FLAG_HOME[team] + Vector2(40.0 if team == 0 else -40.0, off)


## Envanterden kahraman istatistiklerini üretir (eşyalar kalıcı).
func _make_player(id: int, team: int, idx: int) -> Dictionary:
	var inv: Array = Game.inventory.get(id, [])
	var weapons: Array = []
	for w in ["sword", "spear", "bow"]:
		if inv.has(w):
			weapons.append(w)
	if weapons.is_empty():
		weapons.append("fist")
	var wsel_i := 0
	for a in OS.get_cmdline_user_args():  # test: `wp=bow` verilen silahla başla
		if a.begins_with("wp=") and WEAPONS.has(a.substr(3)):
			if not weapons.has(a.substr(3)):
				weapons.append(a.substr(3))
			wsel_i = weapons.find(a.substr(3))
	var armor := 0.0
	for s in SHIELD:
		if inv.has(s):
			armor = maxf(armor, SHIELD[s])
	var wall_list: Array = []
	for w in ["wall_stone", "wall_wood"]:
		for item in inv:
			if item == w:
				wall_list.append(w)
	var abil: Array = []
	for item in inv:
		if ABILITIES.has(item) and abil.size() < 2:
			abil.append(item)
	var max_hp: int = BASE_HP + (40 if inv.has("heart") else 0)
	var spd: float = BASE_SPEED * (1.2 if inv.has("boots") else 1.0) * speed_mul
	var pos := _spawn_pos(team, idx)
	return {
		"team": team, "idx": idx, "pos": pos, "cur": pos,
		"hp": max_hp, "max_hp": max_hp, "alive": true, "respawn": 0.0, "carrying": -1,
		"aim": 0.0 if team == 0 else PI, "cd": 0.0, "atk_vis": 0.0, "hit_vis": 0.0,
		"weapons": weapons, "wsel": wsel_i, "armor": armor, "speed": spd, "walls": wall_list,
		"cmd": 0,
		"abil": abil, "ab_cd": [0.0, 0.0], "shield_t": 0.0, "rally_t": 0.0,
	}


func _spawn_units(id: int, p: Dictionary) -> void:
	var slot := 0
	for item_id in Game.inventory.get(id, []):
		if not UNIT_TYPES.has(item_id):
			continue
		_add_unit(id, p, item_id, slot, false)
		slot += 1


func _add_unit(id: int, p: Dictionary, item_id: String, slot: int, fake: bool, at := Vector2.INF) -> void:
	var t: Dictionary = UNIT_TYPES[item_id]
	var angle := float(slot % 4) * TAU / 4.0 + 0.5
	var ring := 22.0 + float(slot / 4) * 10.0
	units[next_uid] = {
		"owner": id, "team": p.team, "type": item_id, "slot": slot, "fake": fake,
		"pos": p.pos + Vector2.from_angle(angle) * ring if at == Vector2.INF else at,
		"hp": t.hp, "max_hp": t.hp, "cd": 0.0, "retarget": randf() * 0.25,
		"tkind": 0, "tid": -1, "stuck": 0.0, "side": 0.0,
		"side_sign": 1.0 if randf() < 0.5 else -1.0,
		"half": t.half, "sep": Vector2.ZERO, "sep_t": randf() * 0.12,
		"atk_vis": 0.0, "hit_vis": 0.0, "face_l": p.team == 1,  # yalnızca görsel
	}
	next_uid += 1


## Test amaçlı (stress argümanı): takım başına ~25 birime çıkarır. Sahte birimler kayıp sayılmaz.
func _spawn_stress(id: int, p: Dictionary) -> void:
	var have := 0
	for u in units.values():
		if u.owner == id:
			have += 1
	var team_players := 0
	for q in pl.values():
		if q.team == p.team:
			team_players += 1
	var want: int = 25 / maxi(1, team_players)
	for i in range(have, want):
		_add_unit(id, p, UNIT_ORDER[i % UNIT_ORDER.size()], i, true)


# ============================ SUNUCU SİMÜLASYONU ============================

func _physics_process(delta: float) -> void:
	if multiplayer.is_server() and started and not over:
		var t0 := Time.get_ticks_usec()
		_sim(delta)
		tick += 1
		if tick % 2 == 0:
			snap = _make_snapshot()
			_snapshot.rpc(_pack_snapshot(snap))
			_snapshot_units.rpc(_pack_units())
		if stress:
			var ms := float(Time.get_ticks_usec() - t0) / 1000.0
			st_sum += ms
			st_max = maxf(st_max, ms)
			st_n += 1
			if st_n >= 300:
				print("[stress] birim=%d  fizik adımı ort=%.2f ms  maks=%.2f ms (bütçe 16.6 ms)" % [units.size(), st_sum / st_n, st_max])
				st_sum = 0.0
				st_max = 0.0
				st_n = 0
	send_acc += delta
	if send_acc >= SEND_INTERVAL and not snap.is_empty() and not over:
		send_acc = 0.0
		_send_input()
	_predict_step(delta)


func _sim(delta: float) -> void:
	if countdown > 0.0:
		countdown -= delta
		return
	if not sudden:
		time_left -= delta
		if time_left <= 0.0:
			time_left = 0.0
			_time_up()
			if over:
				return
	else:
		sudden_t += delta
		if sudden_t >= SUDDEN_MAX:  # altın bayrak sonsuza uzamasın
			_feed.rpc("Altın bayrak süresi doldu: kalan güce göre karar verildi")
			_finish(_sudden_winner())
			return
	for id in pl.keys():
		_update_player(id, pl[id], delta)
		if over:
			return
	for uid in units.keys():
		if units.has(uid):
			_update_unit(uid, units[uid], delta)
	_update_respawns(delta)
	_update_projectiles(delta)
	_update_flags(delta)


## Ölen birimler: süre dolunca sahibinin üssünde (kahraman doğma bölgesi) tam canla geri gelir.
func _update_respawns(dt: float) -> void:
	for e in respawning.duplicate():
		e.t -= dt
		if e.t > 0.0:
			continue
		respawning.erase(e)
		if not pl.has(e.owner):
			continue
		var p: Dictionary = pl[e.owner]
		var base := _spawn_pos(p.team, p.idx)
		var at := base
		for k in 8:  # üs çevresinde boş bir yer bul
			var c := base + Vector2.from_angle(randf() * TAU) * (10.0 + randf() * 18.0)
			if not _rect_blocked(_unit_rect(c, 4.0)):
				at = c
				break
		_add_unit(e.owner, p, e.type, e.slot, false, at)
		booms.append([at.x, at.y, 10.0])
		if is_auto:
			print("[birim] doğdu: ", _name_of(e.owner), " ", e.type)


func _time_up() -> void:
	if scores[0] == scores[1]:
		sudden = true  # altın bayrak: ilk alan kazanır
		_feed.rpc("Süre doldu! Altın bayrak: ilk alan kazanır")
	else:
		_finish(0 if scores[0] > scores[1] else 1)


## Altın bayrak süre sınırı dolunca: kalan kahraman + birim canı fazla olan kazanır (eşitlikte Mavi).
func _sudden_winner() -> int:
	var power := [0.0, 0.0]
	for p in pl.values():
		if p.alive:
			power[p.team] += p.hp
	for u in units.values():
		power[u.team] += u.hp
	return 1 if power[1] > power[0] else 0


func _finish(winner: int) -> void:
	if over:
		return
	over = true
	_battle_over.rpc(winner, scores, losses)


func _update_player(id: int, p: Dictionary, dt: float) -> void:
	for i in 2:
		p.ab_cd[i] = maxf(0.0, p.ab_cd[i] - dt)
	p.shield_t = maxf(0.0, p.shield_t - dt)
	p.rally_t = maxf(0.0, p.rally_t - dt)
	p.hit_vis = maxf(0.0, p.hit_vis - dt)
	if not p.alive:
		p.respawn -= dt
		if p.respawn <= 0.0:
			p.alive = true
			p.hp = p.max_hp
			p.pos = _spawn_pos(p.team, p.idx)
			p.cd = 0.5
		return
	p.cd = maxf(0.0, p.cd - dt)
	p.atk_vis = maxf(0.0, p.atk_vis - dt)
	var inp: Dictionary = inputs.get(id, {})
	var mv: Vector2 = inp.get("mv", Vector2.ZERO)
	if mv.length() > 1.0:
		mv = mv.normalized()
	var spd: float = p.speed * (CARRY_SLOW if p.carrying >= 0 else 1.0)
	_move(p, mv * spd * dt)
	p.aim = inp.get("aim", p.aim)
	p.cur = inp.get("cur", p.cur)
	if inp.get("atk", false) and p.cd <= 0.0:
		_attack(id, p)
	# Bayrak teslimi: kendi bayrağı evdeyse
	if p.carrying >= 0 and flags[p.team].state == 0 \
			and p.pos.distance_to(FLAG_HOME[p.team]) <= CAPTURE_R:
		_capture(id, p)


func _player_rect(c: Vector2) -> Rect2:
	return Rect2(c - Vector2(HALF, HALF), Vector2(PSIZE, PSIZE))


func _unit_rect(c: Vector2, half := UHALF) -> Rect2:
	return Rect2(c - Vector2(half, half), Vector2(half * 2.0, half * 2.0))


func _rect_blocked(r: Rect2) -> bool:
	if not ARENA.encloses(r):
		return true
	for o in OBSTACLES:
		if o.intersects(r):
			return true
	for w in walls:
		if w.rect.intersects(r):
			return true
	return false


func _move(p: Dictionary, d: Vector2) -> void:
	var nx: Vector2 = p.pos + Vector2(d.x, 0.0)
	if not _rect_blocked(_player_rect(nx)):
		p.pos = nx
	var ny: Vector2 = p.pos + Vector2(0.0, d.y)
	if not _rect_blocked(_player_rect(ny)):
		p.pos = ny


func _attack(id: int, p: Dictionary) -> void:
	var w: Dictionary = WEAPONS[p.weapons[p.wsel]]
	p.cd = w.cd
	p.atk_vis = ATK_VIS
	var dir := Vector2.from_angle(p.aim)
	if w.ranged:
		projectiles.append({"pos": p.pos + dir * 8.0, "vel": dir * ARROW_SPEED, "team": p.team,
			"dmg": w.dmg, "life": ARROW_LIFE, "by": id})
		return
	var reach: float = w.range
	for eid in pl.keys():
		var e: Dictionary = pl[eid]
		if e.team == p.team or not e.alive:
			continue
		var delta: Vector2 = e.pos - p.pos
		if delta.length() <= reach + HALF and _in_arc(delta, p.aim):
			_damage(eid, w.dmg, id)
	for uid in units.keys():
		var u: Dictionary = units[uid]
		if u.team == p.team:
			continue
		var ud: Vector2 = u.pos - p.pos
		if ud.length() <= reach + UHALF and _in_arc(ud, p.aim):
			_damage_unit(uid, w.dmg)
	for wall in walls.duplicate():
		if wall.team == p.team:
			continue
		var wd: Vector2 = wall.rect.get_center() - p.pos
		if wd.length() <= reach + WALL_SIZE * 0.5 and _in_arc(wd, p.aim):
			_damage_wall(wall, w.dmg)


func _in_arc(delta: Vector2, aim: float) -> bool:
	if delta.length() < 8.0:
		return true
	return absf(angle_difference(delta.angle(), aim)) <= deg_to_rad(60.0)


func _damage(target_id: int, amount: float, by: int) -> void:
	var t: Dictionary = pl[target_id]
	var shield: float = 0.5 if t.shield_t > 0.0 else 1.0  # Kalkan Patlaması'nın kısa koruması
	t.hp -= amount * (1.0 - t.armor) * shield
	t.hit_vis = HIT_VIS
	if t.hp <= 0.0 and t.alive:
		t.alive = false
		t.respawn = respawn_time
		if t.carrying >= 0:
			_drop_flag(t)
		_feed.rpc("%s → %s" % [_name_of(by), _name_of(target_id)])


func _damage_unit(uid: int, amount: float) -> void:
	if not units.has(uid):
		return
	var u: Dictionary = units[uid]
	u.hp -= amount * (1.0 - UNIT_TYPES[u.type].get("armor", 0.0))
	u.hit_vis = HIT_VIS
	if u.hp <= 0.0:
		if not u.fake:
			respawning.append({"owner": u.owner, "type": u.type, "slot": u.slot,
				"t": UNIT_RESPAWN.get(u.type, 15.0) * respawn_mul})
			if is_auto:
				print("[birim] öldü: ", _name_of(u.owner), " ", u.type, " ", UNIT_RESPAWN.get(u.type, 15.0) * respawn_mul, " sn sonra doğar")
		units.erase(uid)


func _damage_wall(wall: Dictionary, amount: float) -> void:
	wall.hp -= amount
	if wall.hp <= 0.0:
		walls.erase(wall)


func _update_projectiles(dt: float) -> void:
	for pr in projectiles.duplicate():
		pr.pos += pr.vel * dt
		pr.life -= dt
		if pr.has("aoe"):  # top mermisi: engelleri aşar, hedef noktada patlar
			if pr.life <= 0.0:
				_explode(pr)
				projectiles.erase(pr)
			continue
		var hit: bool = pr.life <= 0.0 or not ARENA.has_point(pr.pos)
		if not hit:
			for o in OBSTACLES:
				if o.has_point(pr.pos):
					hit = true
					break
		if not hit:
			for wall in walls.duplicate():
				if wall.rect.has_point(pr.pos):
					if wall.team != pr.team:
						_damage_wall(wall, pr.dmg)
					hit = true
					break
		if not hit:
			for eid in pl.keys():
				var e: Dictionary = pl[eid]
				if e.team != pr.team and e.alive and _player_rect(e.pos).grow(1.5).has_point(pr.pos):
					_damage(eid, pr.dmg, pr.by)
					hit = true
					break
		if not hit:
			for uid in units.keys():
				var u: Dictionary = units[uid]
				if u.team != pr.team and _unit_rect(u.pos, u.half).grow(1.5).has_point(pr.pos):
					_damage_unit(uid, pr.dmg)
					hit = true
					break
		if hit:
			projectiles.erase(pr)


## Alan hasarı: düşman kahraman/birim tam, duvarlar wmul katı hasar alır.
func _explode(pr: Dictionary) -> void:
	var r: float = pr.aoe
	for eid in pl.keys():
		var e: Dictionary = pl[eid]
		if e.team != pr.team and e.alive and e.pos.distance_to(pr.pos) <= r + HALF:
			_damage(eid, pr.dmg, pr.by)
	for uid in units.keys():
		var u: Dictionary = units[uid]
		if u.team != pr.team and u.pos.distance_to(pr.pos) <= r + u.half:
			_damage_unit(uid, pr.dmg)
	for wall in walls.duplicate():
		if wall.team != pr.team and wall.rect.get_center().distance_to(pr.pos) <= r + WALL_SIZE * 0.5:
			_damage_wall(wall, pr.dmg * pr.wmul)
	booms.append([pr.pos.x, pr.pos.y, r])


# --- Birim zekâsı ---

func _update_unit(uid: int, u: Dictionary, dt: float) -> void:
	if not pl.has(u.owner):
		units.erase(uid)
		return
	var owner_p: Dictionary = pl[u.owner]
	var cmd: int = owner_p.cmd
	var t: Dictionary = UNIT_TYPES[u.type]
	var spd: float = t.speed * speed_mul * (RALLY_SPEED if owner_p.rally_t > 0.0 else 1.0)
	u.cd = maxf(0.0, u.cd - dt)
	u.atk_vis = maxf(0.0, u.atk_vis - dt)
	u.hit_vis = maxf(0.0, u.hit_vis - dt)
	u.retarget -= dt
	u.sep_t -= dt
	if u.sep_t <= 0.0:
		u.sep_t = 0.12
		_unit_separation(uid, u)
	if u.tkind != 0 and not _target_valid(u):
		u.tkind = 0
	if u.retarget <= 0.0:
		u.retarget = 0.25
		_unit_retarget(u, t, owner_p, cmd)

	if u.tkind != 0:
		var tp: Vector2 = _target_pos(u)
		if cmd == 0 and tp.distance_to(owner_p.pos) > UNIT_LEASH * 1.4 + t.range * 0.5:
			u.tkind = 0  # Takip modunda çok uzağa kovalamaz
		elif u.pos.distance_to(tp) <= t.range:
			_unit_attack(u, t, tp)
			_unit_move(u, u.sep * spd * 0.3 * dt)  # dururken de üst üste yığılma
			return
		else:
			_unit_step(u, tp, spd, dt, t.range * 0.8)
			return
	# Hedef yok: komuta göre git
	match cmd:
		0:  # Takip: kahramanın etrafında formasyon
			var ring := 22.0 + float(u.slot / 4) * 10.0
			var slot_pos: Vector2 = owner_p.pos + Vector2.from_angle(float(u.slot % 4) * TAU / 4.0 + 0.5) * ring
			_unit_step(u, slot_pos, spd, dt, 5.0)
		1:  # Saldır: imlece
			_unit_step(u, owner_p.cur, spd, dt, 10.0)
		2:  # Bayrak: düşman bayrağına (kendi bayrağı çalındıysa taşıyanı kovala)
			_unit_step(u, _flag_goal(u.team), spd, dt, 12.0)


## Yakındaki dost birimlerden uzaklaşma vektörü (sep). Her 0.12 sn'de bir hesaplanır, ucuzdur.
func _unit_separation(uid: int, u: Dictionary) -> void:
	var push := Vector2.ZERO
	for oid in units.keys():
		if oid == uid:
			continue
		var o: Dictionary = units[oid]
		var d: Vector2 = u.pos - o.pos
		var dd := d.length_squared()
		if dd >= SEP_R * SEP_R:
			continue
		if dd < 0.01:
			push += Vector2.from_angle(randf() * TAU)
		else:
			var l := sqrt(dd)
			push += d / l * (1.0 - l / SEP_R)
	u.sep = push.limit_length(1.0)


func _flag_goal(team: int) -> Vector2:
	var own: Dictionary = flags[team]
	if own.state == 1 and pl.has(own.carrier):
		return pl[own.carrier].pos  # bayrağımızı taşıyanı durdur
	return flags[1 - team].pos


func _find_wall(wid: int) -> Dictionary:
	for w in walls:
		if w.id == wid:
			return w
	return {}


func _target_valid(u: Dictionary) -> bool:
	if u.tkind == 1:
		return pl.has(u.tid) and pl[u.tid].alive
	if u.tkind == 3:
		return not _find_wall(u.tid).is_empty()
	return units.has(u.tid)


func _target_pos(u: Dictionary) -> Vector2:
	if u.tkind == 1:
		return pl[u.tid].pos
	if u.tkind == 3:
		return _find_wall(u.tid).rect.get_center()
	return units[u.tid].pos


func _unit_retarget(u: Dictionary, t: Dictionary, owner_p: Dictionary, cmd: int) -> void:
	var best := 1.0e9
	var kind := 0
	var tid := -1
	var radius: float = UNIT_AGGRO[cmd]
	if t.has("aoe"):
		radius = maxf(radius, t.range)  # topçu menzili kadar uzağı görür
	var leash := cmd == 0
	var tbest := 1.0e9  # kalkancı (taunt) varsa onlar önce gelir
	var tid_t := -1
	for hid in pl.keys():
		var h: Dictionary = pl[hid]
		if h.team == u.team or not h.alive:
			continue
		var d: float = u.pos.distance_to(h.pos)
		if d < best and d <= radius and (not leash or h.pos.distance_to(owner_p.pos) <= UNIT_LEASH):
			best = d
			kind = 1
			tid = hid
	for eid in units.keys():
		var e: Dictionary = units[eid]
		if e.team == u.team:
			continue
		var d2: float = u.pos.distance_to(e.pos)
		if d2 > radius or (leash and e.pos.distance_to(owner_p.pos) > UNIT_LEASH):
			continue
		if d2 < best:
			best = d2
			kind = 2
			tid = eid
		if d2 < tbest and UNIT_TYPES[e.type].get("taunt", false):
			tbest = d2
			tid_t = eid
	if tid_t >= 0:  # taunt: menzildeki Kalkancı'ya öncelik
		kind = 2
		tid = tid_t
	if kind == 0 and t.has("wmul"):  # topçu: başka hedef yoksa duvarları döver
		for w in walls:
			if w.team == u.team:
				continue
			var d3: float = u.pos.distance_to(w.rect.get_center())
			if d3 < best and d3 <= radius:
				best = d3
				kind = 3
				tid = w.id
	u.tkind = kind
	u.tid = tid


func _unit_attack(u: Dictionary, t: Dictionary, tp: Vector2) -> void:
	if u.cd > 0.0:
		return
	u.cd = t.cd
	u.atk_vis = ATK_VIS  # görsel: saldırı animasyonu + hedefe dönük bakış
	u.face_l = tp.x < u.pos.x
	# Savaş Narası etkisindeyse sahibinin birlikleri %50 daha çok hasar verir
	var dmg: float = t.dmg * (RALLY_DMG if pl.has(u.owner) and pl[u.owner].rally_t > 0.0 else 1.0)
	if t.has("aoe"):  # top mermisi: hedef noktaya uçar ve orada patlar
		var dist: float = u.pos.distance_to(tp)
		var dirs: Vector2 = (tp - u.pos).normalized()
		projectiles.append({"pos": u.pos, "vel": dirs * SHELL_SPEED, "team": u.team, "dmg": dmg,
			"life": dist / SHELL_SPEED, "by": u.owner, "aoe": t.aoe, "wmul": t.wmul})
	elif t.ranged:
		var dir: Vector2 = (tp - u.pos).normalized()
		var speed := ARROW_SPEED * 0.8
		projectiles.append({"pos": u.pos, "vel": dir * speed, "team": u.team, "dmg": dmg,
			"life": t.range / speed + 0.15, "by": u.owner})
	elif u.tkind == 1:
		_damage(u.tid, dmg, u.owner)
	else:
		_damage_unit(u.tid, dmg)


## Birimi engellere takılmadan kaydırır (eksen eksen).
func _unit_move(u: Dictionary, d: Vector2) -> void:
	if d.is_zero_approx():
		return
	var nx: Vector2 = u.pos + Vector2(d.x, 0.0)
	if not _rect_blocked(_unit_rect(nx, u.half)):
		u.pos = nx
	var ny: Vector2 = u.pos + Vector2(0.0, d.y)
	if not _rect_blocked(_unit_rect(ny, u.half)):
		u.pos = ny


## Hedefe doğru adım atar (dostlardan hafifçe kaçınarak); engele takılırsa yan yürüyerek kurtulur.
func _unit_step(u: Dictionary, goal: Vector2, spd: float, dt: float, stop_dist: float) -> void:
	var d: Vector2 = goal - u.pos
	var dist := d.length()
	if dist <= stop_dist:
		u.stuck = 0.0
		_unit_move(u, u.sep * spd * 0.3 * dt)
		return
	var dir := d / dist
	if u.side > 0.0:
		u.side -= dt
		dir = dir.rotated(u.side_sign * PI * 0.5)
	elif not u.sep.is_zero_approx():
		dir = (dir + u.sep * 0.7).normalized()
	var step := minf(spd * dt, dist)
	var before: Vector2 = u.pos
	_unit_move(u, dir * step)
	if before.distance_to(u.pos) < step * 0.3:
		u.stuck += dt
		if u.stuck > 0.2 and u.side <= 0.0:
			u.side = 0.5
			u.side_sign = -u.side_sign  # takılınca yön değiştir: iki yönü de dener
			u.stuck = 0.0
	else:
		u.stuck = 0.0


# --- Bayrak ---

func _take_flag(team: int, id: int, p: Dictionary) -> void:
	var f: Dictionary = flags[team]
	f.state = 1
	f.carrier = id
	p.carrying = team
	_feed.rpc("%s %s bayrağı aldı!" % [_name_of(id), Net.TEAM_NAMES[team]])


func _drop_flag(p: Dictionary) -> void:
	var f: Dictionary = flags[p.carrying]
	f.state = 2
	f.carrier = -1
	f.pos = p.pos
	f.timer = FLAG_RETURN_TIME
	p.carrying = -1


func _return_flag(team: int) -> void:
	flags[team] = _new_flag(team)


func _capture(id: int, p: Dictionary) -> void:
	var captured_team: int = p.carrying
	p.carrying = -1
	_return_flag(captured_team)
	scores[p.team] += 1
	_feed.rpc("%s bayrak getirdi! (%d - %d)" % [_name_of(id), scores[0], scores[1]])
	if sudden or scores[p.team] >= captures_to_win:
		_finish(p.team)


func _update_flags(dt: float) -> void:
	for t in 2:
		var f: Dictionary = flags[t]
		if f.state == 1:
			if pl.has(f.carrier) and pl[f.carrier].alive:
				f.pos = pl[f.carrier].pos
			else:
				f.state = 2
				f.timer = FLAG_RETURN_TIME
			continue
		if f.state == 2:
			f.timer -= dt
			if f.timer <= 0.0:
				_return_flag(t)
				continue
		for id in pl.keys():
			var p: Dictionary = pl[id]
			if not p.alive or p.pos.distance_to(f.pos) > PICKUP_R:
				continue
			if p.team != t:
				_take_flag(t, id, p)
				break
			if f.state == 2:  # kendi bayrağına dokunan geri gönderir
				_return_flag(t)
				_feed.rpc("%s bayrağı geri getirdi" % _name_of(id))
				break


func _on_peer_left(id: int) -> void:
	if pl.has(id):
		if pl[id].carrying >= 0:
			_drop_flag(pl[id])
		pl.erase(id)
		inputs.erase(id)
		for uid in units.keys():
			if units[uid].owner == id:
				units.erase(uid)
		respawning = respawning.filter(func(e): return e.owner != id)


func _name_of(id: int) -> String:
	return Net.players.get(id, {}).get("name", "?")


# --- İstemciden gelen girdiler ---

@rpc("any_peer", "unreliable")
func _srv_input(mv: Vector2, aim: float, atk: bool, cur: Vector2, seq: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	if not is_finite(aim) or not mv.is_finite() or not cur.is_finite():
		return  # bozuk (NaN/Inf) girdi kahramanın nişanını kalıcı bozmasın
	# Sunucu geç gelen / sırası bozuk paketi eskisinin üstüne yazmasın (8 bit sayaç, mod 256)
	var old: Dictionary = inputs.get(id, {})
	if old.has("seq") and ((seq - int(old.seq)) & 255) >= 128:
		return
	inputs[id] = {"mv": mv.limit_length(1.0), "aim": aim, "atk": atk,
		"cur": cur.clamp(Vector2.ZERO, ARENA.size), "seq": seq & 255}


@rpc("any_peer", "reliable")
func _srv_action(kind: int) -> void:
	if not multiplayer.is_server() or over or countdown > 0.0:
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	if not pl.has(id):
		return
	var p: Dictionary = pl[id]
	if kind >= 2 and kind <= 4:  # birlik komutu (kahraman ölüyken de verilebilir)
		p.cmd = kind - 2
		return
	if not p.alive:
		return
	if kind == 1:  # silah değiştir
		p.wsel = (p.wsel + 1) % p.weapons.size()
	elif kind == 0:  # duvar koy
		_place_wall(p)
	elif kind == 5 or kind == 6:  # yetenek: 5 = Boşluk (1. yetenek), 6 = F (2. yetenek)
		_use_ability(id, p, kind - 5)


func _use_ability(id: int, p: Dictionary, slot: int) -> void:
	if slot >= p.abil.size() or p.ab_cd[slot] > 0.0:
		return
	var ab: String = p.abil[slot]
	p.ab_cd[slot] = ABILITIES[ab].cd
	if is_auto:
		print("[yetenek] ", _name_of(id), " ", ab)
	match ab:
		"ability_dash":
			booms.append([p.pos.x, p.pos.y, 8.0])
			var dir := Vector2.from_angle(p.aim)
			var moved := 0.0
			while moved < DASH_DIST:  # 2 piksellik adımlarla, engele çarpana dek
				var next: Vector2 = p.pos + dir * 2.0
				if _rect_blocked(_player_rect(next)):
					break
				p.pos = next
				moved += 2.0
		"ability_burst":
			p.shield_t = SHIELD_TIME
			booms.append([p.pos.x, p.pos.y, BURST_R])
			for eid in pl.keys():
				var e: Dictionary = pl[eid]
				if e.team == p.team or not e.alive:
					continue
				var d: Vector2 = e.pos - p.pos
				if d.length() <= BURST_R + HALF:
					_damage(eid, BURST_DMG, id)
					_move(e, d.normalized() * BURST_PUSH)
			for uid in units.keys():
				if not units.has(uid) or units[uid].team == p.team:
					continue
				var d2: Vector2 = units[uid].pos - p.pos
				if d2.length() <= BURST_R + UHALF:
					var push: Vector2 = d2.normalized() * BURST_PUSH
					_damage_unit(uid, BURST_DMG)
					if units.has(uid):
						_unit_move(units[uid], push)
		"ability_rally":
			p.rally_t = RALLY_TIME
			booms.append([p.pos.x, p.pos.y, 18.0])


func _place_wall(p: Dictionary) -> void:
	if p.walls.is_empty():
		return
	var c: Vector2 = p.pos + Vector2.from_angle(p.aim) * (HALF + WALL_SIZE * 0.5 + 2.0)
	var r := Rect2(c - Vector2(WALL_SIZE, WALL_SIZE) * 0.5, Vector2(WALL_SIZE, WALL_SIZE))
	if _rect_blocked(r):
		return
	for t in 2:
		if c.distance_to(FLAG_HOME[t]) < 24.0:
			return
	for q in pl.values():
		if q.alive and _player_rect(q.pos).intersects(r):
			return
	var kind: String = p.walls.pop_front()
	walls.append({"rect": r, "hp": float(WALL_HP[kind]), "max": float(WALL_HP[kind]),
		"team": p.team, "kind": kind, "id": next_wid})
	next_wid += 1


# --- Herkese yayılanlar ---

func _make_snapshot() -> Dictionary:
	var unit_counts := {}
	var spawn_counts := {}
	for e in respawning:
		spawn_counts[e.owner] = spawn_counts.get(e.owner, 0) + 1
	var us := []
	for uid in units.keys():
		var u: Dictionary = units[uid]
		unit_counts[u.owner] = unit_counts.get(u.owner, 0) + 1
		us.append([uid, u.pos.x, u.pos.y, u.hp, u.max_hp, u.team, UNIT_ORDER.find(u.type), u.owner,
			u.atk_vis > 0.0, u.hit_vis > 0.0, u.face_l])
	var ps := {}
	for id in pl.keys():
		var p: Dictionary = pl[id]
		var a1: int = ABILITY_ORDER.find(p.abil[0]) + 1 if p.abil.size() > 0 else 0  # 0 = yok
		var a2: int = ABILITY_ORDER.find(p.abil[1]) + 1 if p.abil.size() > 1 else 0
		ps[id] = [p.pos.x, p.pos.y, p.hp, p.max_hp, p.team, p.alive, p.carrying, p.aim,
			p.weapons[p.wsel], p.atk_vis, p.respawn, p.walls.size(), p.cmd, unit_counts.get(id, 0),
			a1, a2, ceili(p.ab_cd[0]), ceili(p.ab_cd[1]), p.shield_t > 0.0, p.rally_t > 0.0, p.hit_vis > 0.0, spawn_counts.get(id, 0)]
	var fl := []
	for f in flags:
		fl.append([f.pos.x, f.pos.y, f.state])
	var prs := []
	for pr in projectiles:
		prs.append([pr.pos.x, pr.pos.y, pr.team, pr.has("aoe"), roundi((pr.vel.angle() + PI) / TAU * 256.0) & 255])
	var ws := []
	for w in walls:
		ws.append([w.rect.position.x, w.rect.position.y, w.hp, w.max, w.team])
	snap_u = us
	var res := {"p": ps, "f": fl, "pr": prs, "w": ws, "t": time_left, "s": scores.duplicate(),
		"cd": countdown, "sd": sudden, "bm": booms.duplicate()}
	booms.clear()
	return res


@rpc("authority", "unreliable")
func _snapshot(packed: PackedInt32Array) -> void:
	var now := Time.get_ticks_msec()
	if net_last_ms > 0:
		var gap := now - net_last_ms
		net_gap_sum += gap
		net_gap_max = maxi(net_gap_max, gap)
		if gap > 100:
			net_late += 1
	net_last_ms = now
	net_n += 1
	snap = _unpack_snapshot(packed)
	_reconcile()


# --- Anlık görüntü paketleme ---
# Tek PackedInt32Array (5v5'te ~300 bayt). Eskiden Dictionary olarak gidiyordu, 10 oyuncuda 1639 bayt
# ile MTU'yu (1392) aşıyordu: paket parçalanır, bir parça kaybolunca tüm görüntü düşerdi.
# Konum 1/8 piksel (16 bit), açı 8 bit. İstemcide açılınca eski Dictionary biçimi aynen geri gelir.

func _q(v: float) -> int:
	return clampi(roundi(v * 8.0), 0, 65535)


func _pack_snapshot(s: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	var weapon_order: Array = WEAPONS.keys()
	out.append(roundi(s.t * 10.0))
	out.append(int(s.s[0]) | (int(s.s[1]) << 8))
	out.append(clampi(roundi(s.cd * 10.0), 0, 65535) | (int(s.sd) << 16))
	out.append(s.p.size())
	out.append(s.pr.size())
	out.append(s.w.size())
	out.append(s.bm.size())
	for f in s.f:
		out.append(_q(f[0]) | (_q(f[1]) << 16))
		out.append(int(f[2]))
	for id in s.p.keys():
		var a: Array = s.p[id]
		out.append(int(id))
		out.append(_q(a[0]) | (_q(a[1]) << 16))
		out.append(clampi(ceili(a[2]), 0, 511) | (clampi(int(a[3]), 0, 511) << 9) | (int(a[4]) << 18)
			| (int(a[5]) << 19) | ((int(a[6]) + 1) << 20) | (maxi(weapon_order.find(a[8]), 0) << 22)
			| (int(a[12]) << 25) | (int(a[9] > 0.0) << 27) | (int(a[20]) << 28))
		var aim8 := roundi((float(a[7]) + PI) / TAU * 256.0) & 255
		var ack := int(inputs.get(id, {}).get("seq", 0)) & 255
		out.append(aim8 | (clampi(ceili(a[10]), 0, 15) << 8) | (clampi(int(a[11]), 0, 15) << 12)
			| (clampi(int(a[13]), 0, 63) << 16) | (ack << 22))
		# Yetenekler: indeks (0 = yok), bekleme (sn), kalkan ve narayla güçlenme göstergeleri
		out.append(clampi(int(a[14]), 0, 7) | (clampi(int(a[15]), 0, 7) << 3)
			| (clampi(int(a[16]), 0, 31) << 6) | (clampi(int(a[17]), 0, 31) << 11)
			| (int(a[18]) << 16) | (int(a[19]) << 17) | (clampi(int(a[21]), 0, 7) << 18))
	for pr in s.pr:
		out.append(_q(pr[0]) | (_q(pr[1]) << 16))
		out.append(int(pr[2]) | (int(pr[3]) << 1) | (int(pr[4]) << 2))  # bit 2-9: yön (8 bit)
	for w in s.w:
		out.append(_q(w[0]) | (_q(w[1]) << 16))
		out.append(clampi(ceili(w[2]), 0, 511) | (clampi(int(w[3]), 0, 511) << 9) | (int(w[4]) << 18))
	for bm in s.bm:
		out.append(_q(bm[0]) | (_q(bm[1]) << 16))
		out.append(clampi(roundi(bm[2] * 8.0), 0, 65535))
	return out


func _unpack_snapshot(a: PackedInt32Array) -> Dictionary:
	var weapon_order: Array = WEAPONS.keys()
	var n_p := a[3]
	var n_pr := a[4]
	var n_w := a[5]
	var n_bm := a[6]
	var i := 7
	var fl := []
	for k in 2:
		fl.append([float(a[i] & 0xFFFF) / 8.0, float((a[i] >> 16) & 0xFFFF) / 8.0, a[i + 1]])
		i += 2
	var ps := {}
	var acks := {}
	for k in n_p:
		var id := a[i]
		var pos := a[i + 1]
		var w2 := a[i + 2]
		var w3 := a[i + 3]
		var w4 := a[i + 4]
		i += 5
		var wi := (w2 >> 22) & 7
		ps[id] = [
			float(pos & 0xFFFF) / 8.0, float((pos >> 16) & 0xFFFF) / 8.0,
			float(w2 & 511), float((w2 >> 9) & 511), (w2 >> 18) & 1, ((w2 >> 19) & 1) == 1, ((w2 >> 20) & 3) - 1,
			float(w3 & 255) / 256.0 * TAU - PI,
			weapon_order[wi] if wi < weapon_order.size() else "fist",
			0.15 if ((w2 >> 27) & 1) == 1 else 0.0,
			float((w3 >> 8) & 15), (w3 >> 12) & 15, (w2 >> 25) & 3, (w3 >> 16) & 63,
			w4 & 7, (w4 >> 3) & 7, (w4 >> 6) & 31, (w4 >> 11) & 31, ((w4 >> 16) & 1) == 1, ((w4 >> 17) & 1) == 1,
			((w2 >> 28) & 1) == 1, (w4 >> 18) & 7]
		acks[id] = (w3 >> 22) & 255
	snap_ack = acks
	var prs := []
	for k in n_pr:
		prs.append([float(a[i] & 0xFFFF) / 8.0, float((a[i] >> 16) & 0xFFFF) / 8.0, a[i + 1] & 1, ((a[i + 1] >> 1) & 1) == 1,
			float((a[i + 1] >> 2) & 255) / 256.0 * TAU - PI])
		i += 2
	var ws := []
	for k in n_w:
		var v := a[i + 1]
		ws.append([float(a[i] & 0xFFFF) / 8.0, float((a[i] >> 16) & 0xFFFF) / 8.0, float(v & 511), float((v >> 9) & 511), (v >> 18) & 1])
		i += 2
	var bms := []
	for k in n_bm:
		bms.append([float(a[i] & 0xFFFF) / 8.0, float((a[i] >> 16) & 0xFFFF) / 8.0, float(a[i + 1]) / 8.0])
		i += 2
	return {"p": ps, "f": fl, "pr": prs, "w": ws, "t": float(a[0]) / 10.0,
		"s": [a[1] & 255, (a[1] >> 8) & 255], "cd": float(a[2] & 0xFFFF) / 10.0,
		"sd": ((a[2] >> 16) & 1) == 1, "bm": bms}


# --- Kendi kahramanın için tahmin (prediction) ---

func _my_speed() -> float:
	var inv: Array = Game.inventory.get(my_id, [])
	var carrying: bool = snap.p[my_id][6] >= 0
	return BASE_SPEED * (1.2 if inv.has("boots") else 1.0) * speed_mul * (CARRY_SLOW if carrying else 1.0)


func _pred_blocked(r: Rect2) -> bool:
	if not ARENA.encloses(r):
		return true
	for o in OBSTACLES:
		if o.intersects(r):
			return true
	for w in snap.w:
		if Rect2(w[0], w[1], WALL_SIZE, WALL_SIZE).intersects(r):
			return true
	return false


func _pred_move(pos: Vector2, mv: Vector2, dt: float) -> Vector2:
	var d := mv.limit_length(1.0) * _my_speed() * dt
	var nx := pos + Vector2(d.x, 0.0)
	if not _pred_blocked(_player_rect(nx)):
		pos = nx
	var ny := pos + Vector2(0.0, d.y)
	if not _pred_blocked(_player_rect(ny)):
		pos = ny
	return pos


## Her fizik karesinde: girdiyi sunucuyu beklemeden uygula ve kareyi kaydet.
func _predict_step(dt: float) -> void:
	if multiplayer.is_server() or snap.is_empty() or over or not snap.p.has(my_id):
		return
	var me: Array = snap.p[my_id]
	if not me[5] or snap.cd > 0.0:  # ölü ya da geri sayım: sunucunun konumuna güven
		pred_valid = false
		return
	if not pred_valid:
		pred_pos = Vector2(me[0], me[1])
		pred_valid = true
		pending.clear()
	pred_pos = _pred_move(pred_pos, held_mv, dt)
	pending.append([in_seq, held_mv, dt])
	if pending.size() > 150:
		pending.pop_front()


## Sunucu cevabı gelince: onaylanan kareleri at, kalanları sunucu konumundan yeniden oynat.
func _reconcile() -> void:
	if multiplayer.is_server() or not pred_valid or not snap.p.has(my_id):
		return
	var me: Array = snap.p[my_id]
	if not me[5] or snap.cd > 0.0:
		pred_valid = false
		return
	var ack: int = snap_ack.get(my_id, 0)
	var kept: Array = []
	for f in pending:
		if (f[0] & 255) != ack and ((f[0] - ack) & 255) < 128:  # ack'ten sonraki kareler
			kept.append(f)
	pending = kept
	var target := Vector2(me[0], me[1])
	for f in pending:
		target = _pred_move(target, f[1], f[2])
	var err := pred_pos.distance_to(target)
	pred_err_sum += err
	pred_err_max = maxf(pred_err_max, err)
	pred_n += 1
	if err > 30.0:
		pred_pos = target  # ışınlanma / büyük sapma: doğrudan düzelt
	else:
		pred_pos = pred_pos.lerp(target, 0.3)  # küçük sapma: yumuşak düzelt


## Birimler ayrı ve sıkıştırılmış gider (50 birim tek pakette MTU'yu aşıyordu): birim başına 4 tamsayı.
## Tür kelimesi: bit 0-3 takım, 4-7 tür, 8 saldırdı, 9 vuruldu, 10 sola bakıyor (son üçü yalnızca görsel).
func _pack_units() -> PackedInt32Array:
	var out := PackedInt32Array()
	for a in snap_u:
		out.append(a[0])
		out.append(roundi(a[1] * 8.0) | (roundi(a[2] * 8.0) << 16))
		out.append(ceili(a[3]) | (ceili(a[4]) << 12))
		out.append(a[5] | (maxi(a[6], 0) << 4) | (int(a[8]) << 8) | (int(a[9]) << 9) | (int(a[10]) << 10))
	return out


@rpc("authority", "unreliable")
func _snapshot_units(packed: PackedInt32Array) -> void:
	var us := []
	for i in range(0, packed.size(), 4):
		var pos := packed[i + 1]
		var hp := packed[i + 2]
		var ty := packed[i + 3]
		us.append([packed[i], float(pos & 0xFFFF) / 8.0, float(pos >> 16) / 8.0, float(hp & 0xFFF), float(hp >> 12),
			ty & 15, (ty >> 4) & 15, -1, ((ty >> 8) & 1) == 1, ((ty >> 9) & 1) == 1, ((ty >> 10) & 1) == 1])
	snap_u = us


@rpc("authority", "call_local", "reliable")
func _feed(text: String) -> void:
	feed.append([text, 5.0])
	if feed.size() > 5:
		feed.pop_front()


@rpc("authority", "call_local", "reliable")
func _battle_over(winner: int, final_scores: Array, lost: Dictionary) -> void:
	over = true
	camera.enabled = false  # sonuç ekranı kamerayla kaymasın
	# Ölen birimler artık kalıcı gitmez (yeniden doğarlar): envanterden silme yok. `lost` eski imza için duruyor.
	if is_auto and net_n > 1:
		print("[net %d] anlık görüntü=%d  ort aralık=%.1f ms  maks=%d ms  100ms'den uzun=%d  tahmin hatası ort=%.2f maks=%.1f px (%d düzeltme)" % [
			my_id, net_n, float(net_gap_sum) / float(net_n - 1), net_gap_max, net_late,
			pred_err_sum / maxf(float(pred_n), 1.0), pred_err_max, pred_n])
	if is_auto:
		var counts := {}
		for id in Net.players.keys():
			counts[id] = Game.unit_count(id)
		print("[battle] birim sayıları=", counts)
	finished.emit(winner, final_scores)


# ============================ İSTEMCİ ============================

func _send_action(kind: int) -> void:
	if multiplayer.is_server():
		_srv_action(kind)
	else:
		_srv_action.rpc_id(1, kind)


func _unhandled_input(event: InputEvent) -> void:
	if over or snap.is_empty():
		return
	var kind := -1
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q: kind = 1
			KEY_E: kind = 0
			KEY_1: kind = 2
			KEY_2: kind = 3
			KEY_3: kind = 4
			KEY_SPACE: kind = 5  # 1. yetenek
			KEY_F: kind = 6  # 2. yetenek
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		kind = 0
	if kind >= 0:
		_send_action(kind)


func _send_input() -> void:
	var mv := Vector2.ZERO
	mv.x = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	mv.y = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	var my_pos: Vector2 = view_pos.get(my_id, Vector2(320, 180))
	var cur := get_global_mouse_position()
	var aim := (cur - my_pos).angle()
	var atk := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if is_auto:
		var bot := _bot_input()
		mv = bot.mv
		aim = bot.aim
		atk = bot.atk
		cur = bot.cur
	if atk:
		_predict_attack(aim)
	in_seq += 1
	held_mv = mv.limit_length(1.0)
	if multiplayer.is_server():
		inputs[1] = {"mv": held_mv, "aim": aim, "atk": atk,
			"cur": cur.clamp(Vector2.ZERO, ARENA.size), "seq": in_seq & 255}
	else:
		_srv_input.rpc_id(1, mv, aim, atk, cur, in_seq & 255)


## Test botu: Mavi takım önce rakibi öldürür, sonra bayrağı alıp getirir. Kırmızı durur.
func _bot_input() -> Dictionary:
	var res := {"mv": Vector2.ZERO, "aim": 0.0, "atk": false, "cur": Vector2.ZERO}
	if not snap.p.has(my_id):
		return res
	var me: Array = snap.p[my_id]
	var mypos := Vector2(me[0], me[1])
	res.aim = me[7]
	res.cur = mypos
	if me[4] != 0:
		return res
	if not bot_cmd_sent:
		bot_cmd_sent = true
		_send_action(3)  # birliği "Saldır" komutuna al (komut yolunu test eder)
	if not me[5]:
		return res
	# Yetenekleri hazır oldukça kullan (yetenek yolunu test eder)
	var now_ms := Time.get_ticks_msec()
	for s in 2:
		if me[14 + s] > 0 and me[16 + s] <= 0 and now_ms - bot_ab_last[s] > 1500:
			bot_ab_last[s] = now_ms
			_send_action(5 + s)
	var target := mypos
	if not bot_kill_done:
		var enemy: Array = []
		for id in snap.p.keys():
			if snap.p[id][4] == 1:
				enemy = snap.p[id]
		if enemy.is_empty() or not enemy[5]:
			bot_kill_done = true
			print("[bot] düşman kahraman öldü")
		else:
			target = Vector2(enemy[0], enemy[1])
			res.atk = mypos.distance_to(target) < (110.0 if me[8] == "bow" else 30.0)
	if bot_kill_done:
		if me[6] >= 0:
			target = FLAG_HOME[0]
		else:
			target = Vector2(snap.f[1][0], snap.f[1][1])
	var d := target - mypos
	res.aim = d.angle()
	res.cur = target
	var stop_d := 80.0 if (me[8] == "bow" and not bot_kill_done) else 14.0  # yaylı bot uzaktan ateş eder
	if d.length() > stop_d or bot_kill_done:
		res.mv = d.normalized() if d.length() > 2.0 else Vector2.ZERO
	return res


func _process(delta: float) -> void:
	if snap.is_empty():
		return
	var k := 1.0 - exp(-delta * 25.0)
	for id in snap.p.keys():
		var a: Array = snap.p[id]
		var target := Vector2(a[0], a[1])
		var before: Vector2 = view_pos.get(id, target)
		if id == my_id and pred_valid and not multiplayer.is_server():
			view_pos[id] = pred_pos  # kendi kahramanım: tahmin edilen konum (gecikmesiz)
		elif not view_pos.has(id) or view_pos[id].distance_to(target) > 60.0:
			view_pos[id] = target
		else:
			view_pos[id] = view_pos[id].lerp(target, k)
		hero_move[id] = before.distance_to(view_pos[id]) > 0.25
	var new_u := {}
	for a in snap_u:
		var target := Vector2(a[1], a[2])
		var old: Vector2 = view_u.get(a[0], target)
		var now_pos: Vector2 = target if old.distance_to(target) > 40.0 else old.lerp(target, k)
		new_u[a[0]] = now_pos
		var d := now_pos - old
		unit_move[a[0]] = d.length() > 0.2
		if absf(d.x) > 0.06:
			unit_flip[a[0]] = d.x < 0.0
	var now_ms := Time.get_ticks_msec()
	for uid in view_u.keys():  # bu karede kaybolan birim: öldü -> puf bulutu
		if not new_u.has(uid):
			fx_puffs.append([view_u[uid], now_ms])
			u_atk.erase(uid)
	view_u = new_u
	_vis_events(now_ms)
	if snap.p.has(my_id) and not over:
		camera.position = view_pos[my_id].round()
		var shaking := now_ms - shake_t < 90
		camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).round() if shaking else Vector2.ZERO
	fx_sparks = fx_sparks.filter(func(e): return now_ms - int(e[1]) < SPARK_MS)
	fx_puffs = fx_puffs.filter(func(e): return now_ms - int(e[1]) < PUFF_MS)
	for bv in booms_vis:
		bv[2] -= delta
	booms_vis = booms_vis.filter(func(e): return e[2] > 0.0)
	for entry in feed:
		entry[1] -= delta
	feed = feed.filter(func(e): return e[1] > 0.0)
	queue_redraw()
	hud.queue_redraw()
	if shots_dir != "" and (not snap.pr.is_empty() or _attack_active(now_ms)) and shot_n < 90 and now_ms - shot_last > 45:
		shot_last = now_ms  # test: mermi havadayken / saldırı sırasında ekran görüntüsü (shots=<klasör>)
		var shot := get_viewport().get_texture().get_image()
		if snap.p.has(my_id):  # kendi kahramanın çevresi (200x130 dünya birimi)
			var k_px := float(shot.get_width()) / VIEW.x
			var c: Vector2 = get_viewport().get_canvas_transform() * (view_pos[my_id] as Vector2) * k_px
			var sz := Vector2(200.0, 130.0) * k_px
			var r := Rect2i(Vector2i((c - sz * 0.5).clamp(Vector2.ZERO, Vector2(shot.get_size()) - sz)), Vector2i(sz))
			shot = shot.get_region(r)
		shot.save_png("%s/b%d_%03d.png" % [shots_dir, my_id, shot_n])
		shot_n += 1


# ============================ ÇİZİM ============================

func _tint(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


func _text(canvas: CanvasItem, pos: Vector2, text: String, size: int, color: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	canvas.draw_string(ThemeDB.fallback_font, pos, text, align, width, size, color)


func _draw() -> void:
	var grass: Texture2D = Art.grass() if Art.available and not Art.custom else null
	if Art.custom:  # özgün paket: pişirilmiş zemin (çimen + yol + süs)
		Art.draw_ground(self, ARENA, OBSTACLES)
	elif grass != null:  # sprite'lı zemin: çimen döşemesi (dünya x3 ölçeğinde birebir piksel)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(SPR_TILE, SPR_TILE))
		draw_texture_rect(grass, Rect2(Vector2.ZERO, ARENA.size / SPR_TILE), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_rect(ARENA, Color(0.16, 0.2, 0.16))
	for t in 2:
		var bx := 0.0 if t == 0 else ARENA.size.x - BASE_W
		draw_rect(Rect2(bx, 0.0, BASE_W, ARENA.size.y), _tint(TEAM_COLORS[t], 0.14))
		var castle: Texture2D = Art.tex("buildings/%s_castle.png" % Art.TEAM_DIR[t]) if Art.available else null
		if Art.custom:
			Art.draw_castle(self, t, FLAG_HOME[t])
		elif castle != null:  # üs: kale, bayrağın arkasında
			var csize := Vector2(castle.get_width(), castle.get_height()) * SPR_TILE
			draw_texture_rect(castle, Rect2(FLAG_HOME[t] - Vector2(csize.x * 0.5, csize.y * 0.72), csize), false)
	for o in OBSTACLES:
		if Art.custom:
			Art.draw_obstacle(self, o)
		elif Art.available:
			draw_rect(o, Color(0.33, 0.41, 0.42))
			draw_rect(Rect2(o.position, Vector2(o.size.x, 3.0)), Color(0.5, 0.6, 0.58))
			draw_rect(o, Color(0.12, 0.18, 0.2), false, 1.5)
		else:
			draw_rect(o, Color(0.38, 0.38, 0.42))
	if snap.is_empty():
		return

	for w in snap.w:
		var wr := Rect2(w[0], w[1], WALL_SIZE, WALL_SIZE)
		if Art.custom and Art.draw_wall(self, wr, w[3] > 40.0):
			draw_rect(wr, _tint(TEAM_COLORS[w[4]], 0.9), false, 1.0)
		else:
			draw_rect(wr, Color(0.55, 0.4, 0.25) if w[3] <= 40.0 else Color(0.6, 0.6, 0.65))
			draw_rect(wr, _tint(TEAM_COLORS[w[4]], 0.9), false, 1.0)
		draw_rect(Rect2(w[0], w[1] - 3.0, WALL_SIZE * w[2] / w[3], 1.5), Color(0.3, 1.0, 0.3))

	for t in 2:
		var f: Array = snap.f[t]
		var fp := Vector2(f[0], f[1])
		if f[2] == 0:
			draw_arc(fp, 8.0, 0.0, TAU, 12, _tint(TEAM_COLORS[t], 0.5), 1.0)
		if Art.custom and Art.draw_flag(self, t, fp):
			pass  # özgün bayrak çizildi
		elif Art.available:  # sprite'lı görünümde: tahta direk + üçgen flama (kalenin önünde okunur)
			draw_rect(Rect2(fp.x - 1.5, fp.y - 24.0, 3.0, 26.0), Color(0.3, 0.2, 0.12))
			var flag_pts := PackedVector2Array([Vector2(fp.x + 1.5, fp.y - 24.0), Vector2(fp.x + 17.0, fp.y - 18.0), Vector2(fp.x + 1.5, fp.y - 12.0)])
			draw_colored_polygon(flag_pts, TEAM_COLORS[t])
			flag_pts.append(flag_pts[0])
			draw_polyline(flag_pts, Color(0.1, 0.08, 0.08), 1.0)
		else:
			draw_rect(Rect2(fp.x - 1.0, fp.y - 14.0, 2.0, 16.0), Color(0.9, 0.9, 0.9))
			draw_rect(Rect2(fp.x + 1.0, fp.y - 14.0, 9.0, 7.0), TEAM_COLORS[t])

	# Birimler (küçük, soluk)
	var ordered: Array = snap_u.duplicate()
	ordered.sort_custom(func(p, q):  # derinlik: aşağıdaki birim yukarıdakinin üstüne çizilir
		return view_u.get(p[0], Vector2(p[1], p[2])).y < view_u.get(q[0], Vector2(q[1], q[2])).y)
	for a in ordered:
		var upos: Vector2 = view_u.get(a[0], Vector2(a[1], a[2]))
		var ucol: Color = TEAM_COLORS[a[5]].darkened(0.25)
		var uh: float = UNIT_TYPES[UNIT_ORDER[a[6]]].half
		var ur := Rect2(upos.x - uh, upos.y - uh, uh * 2.0, uh * 2.0)
		var sprite_drawn := Art.available and _draw_unit_sprite(a, upos)
		if not sprite_drawn:
			draw_rect(ur, ucol)
			match a[6]:
				1:  # okçu: ortada açık nokta
					draw_rect(Rect2(upos.x - 1.0, upos.y - 1.0, 2.0, 2.0), Color(1, 1, 1, 0.85))
				2:  # topçu: büyük, ortasında koyu namlu + sarı uç
					draw_rect(Rect2(upos.x - 1.0, upos.y - 5.0, 2.0, 6.0), Color(0.1, 0.1, 0.12))
					draw_rect(Rect2(upos.x - 1.0, upos.y - 6.0, 2.0, 1.5), Color(1.0, 0.8, 0.3))
				3:  # kalkancı: kalın beyaz çerçeve + ortada kalkan çizgisi
					draw_rect(ur.grow(1.0), Color(0.92, 0.92, 0.95), false, 2.0)
					draw_rect(Rect2(upos.x - 0.5, upos.y - 3.0, 1.0, 6.0), Color(0.92, 0.92, 0.95))
			var now_u := Time.get_ticks_msec()
			if now_u - int(u_atk.get(a[0], -1000)) < 150:  # kutu yedeği: saldırı anında beyaz çerçeve
				draw_rect(ur.grow(1.5), Color(1, 1, 0.8, 0.9), false, 1.0)
			if now_u - int(u_hit_t.get(a[0], -1000)) < HIT_FLASH_MS:
				draw_rect(ur, Color(1, 1, 1, 0.85))
		if a[3] < a[4]:
			var bar_y := upos.y - uh - 3.0 - (8.0 if sprite_drawn else 0.0)
			draw_rect(Rect2(upos.x - uh, bar_y, uh * 2.0 * a[3] / a[4], 1.0), Color(0.3, 1.0, 0.3))

	for pr in snap.pr:
		if Art.available and Art.draw_projectile(self, Vector2(pr[0], pr[1]), pr[2], pr[3], pr[4]):
			pass
		elif pr[3]:  # top mermisi
			draw_circle(Vector2(pr[0], pr[1]), 2.5, Color(0.2, 0.2, 0.22))
		else:  # kutu yedeği: yöne dönük ok çizgisi + uç
			var pd := Vector2.from_angle(pr[4])
			var pp := Vector2(pr[0], pr[1])
			draw_line(pp - pd * 4.0, pp + pd * 3.0, Color(1.0, 0.95, 0.5), 1.5)
			draw_circle(pp + pd * 3.0, 1.5, Color.WHITE)
	for bm in snap.bm:  # patlama (kısa süre görünür)
		booms_vis.append([Vector2(bm[0], bm[1]), bm[2], 0.3])
	snap.bm = []
	for bv in booms_vis:
		var k: float = bv[2] / 0.3
		if Art.custom and Art.draw_boom(self, bv[0], bv[1], k):
			continue
		draw_circle(bv[0], bv[1] * (1.3 - k * 0.3), Color(1.0, 0.6, 0.2, 0.45 * k))

	# Kahramanlar (büyük, belirgin, isimli)
	for id in snap.p.keys():
		var a: Array = snap.p[id]
		var pos: Vector2 = view_pos.get(id, Vector2(a[0], a[1]))
		var col: Color = TEAM_COLORS[a[4]]
		var mine: bool = id == my_id
		if not a[5]:  # ölü: sönük halka, çarpı ve yeniden doğma sayacı
			_draw_hero_ring(pos, col, mine, false)
			draw_line(pos - Vector2(5, 5), pos + Vector2(5, 5), _tint(col, 0.6), 1.0)
			draw_line(pos - Vector2(5, -5), pos + Vector2(5, -5), _tint(col, 0.6), 1.0)
			_text(self, pos + Vector2(-12, -9), "%d" % int(a[10]), 9, Color(1, 1, 1, 0.85), 24.0, HORIZONTAL_ALIGNMENT_CENTER)
			continue
		_draw_hero_ring(pos, col, mine, true)  # sprite'ın altında: takım halkası
		var top := 13.0  # can çubuğu ve isim için kahramanın üstündeki boşluk
		if Art.available and _draw_hero_sprite(id, a, pos):
			top = Art.hero_top()
		else:
			draw_rect(Rect2(pos.x - HALF, pos.y - HALF, PSIZE, PSIZE), col)
			var outline := Color.WHITE if mine else Color(0.05, 0.05, 0.08)
			draw_rect(Rect2(pos.x - HALF - 1.0, pos.y - HALF - 1.0, PSIZE + 2.0, PSIZE + 2.0), outline, false, 1.0)
			if Time.get_ticks_msec() - int(hit_t.get(id, -1000)) < HIT_FLASH_MS:  # vurulma: beyaz parlama
				draw_rect(Rect2(pos.x - HALF, pos.y - HALF, PSIZE, PSIZE), Color(1, 1, 1, 0.85))
		if a[18]:  # Kalkan Patlaması koruması
			draw_arc(pos, 11.0, 0.0, TAU, 20, Color(0.4, 0.8, 1.0, 0.9), 1.5)
		if a[19]:  # Savaş Narası: birlik güçlü
			draw_arc(pos, 14.0, 0.0, TAU, 20, Color(1.0, 0.85, 0.3, 0.9), 1.5)
		var aim_a: float = a[7]
		if id == my_id and not is_auto:
			aim_a = (get_global_mouse_position() - pos).angle()  # kendi nişanım gecikmesiz
		var dir := Vector2.from_angle(aim_a)
		draw_line(pos, pos + dir * 12.0, Color.WHITE, 1.0)
		_draw_attack_fx(id, pos, a[4])
		draw_rect(Rect2(pos.x - 8.0, pos.y - top, 16.0, 2.0), Color(0.3, 0.05, 0.05))
		draw_rect(Rect2(pos.x - 8.0, pos.y - top, 16.0 * clampf(a[2] / a[3], 0.0, 1.0), 2.0), Color(0.3, 1.0, 0.3))
		if a[6] >= 0:
			draw_rect(Rect2(pos.x + 16.0, pos.y - top - 9.0, 7.0, 5.0), TEAM_COLORS[a[6]])
		_text(self, pos + Vector2(-24, -top - 3.0), _name_of(id), 8, _tint(Color.WHITE, 0.85), 48.0, HORIZONTAL_ALIGNMENT_CENTER)
		_draw_hero_marker(pos + Vector2(0, -top - 12.0), col, mine)

	_draw_hit_fx()

	# Saldır komutundayken imleç işareti
	if snap.p.has(my_id) and snap.p[my_id][12] == 1:
		var c := get_global_mouse_position()
		draw_arc(c, 6.0, 0.0, TAU, 10, Color(1, 1, 1, 0.6), 1.0)


## Elips noktaları (ayak halkası için).
func _ellipse_pts(c: Vector2, rx: float, ry: float, n := 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in n + 1:
		var ang := TAU * float(k) / float(n)
		pts.append(c + Vector2(cos(ang) * rx, sin(ang) * ry))
	return pts


## Kahramanın ayağının altında takım renginde halka. Kendi kahramanım: altın dış halka, daha kalın, nabız atar.
func _draw_hero_ring(pos: Vector2, col: Color, mine: bool, alive: bool) -> void:
	var c := pos + Vector2(0, 4.0)
	var k := 1.0 if alive else 0.3
	if mine:
		var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 1000.0 * 5.0)
		var rx := 12.0 + pulse * 1.5
		draw_colored_polygon(_ellipse_pts(c, rx, rx * 0.5), _tint(col.lightened(0.15), (0.35 + 0.15 * pulse) * k))
		draw_polyline(_ellipse_pts(c, rx, rx * 0.5), _tint(col.lightened(0.45), 0.95 * k), 2.0)
		draw_polyline(_ellipse_pts(c, rx + 2.5, (rx + 2.5) * 0.5), Color(1.0, 0.85, 0.25, (0.55 + 0.4 * pulse) * k), 1.0)
	else:
		draw_colored_polygon(_ellipse_pts(c, 10.0, 5.0), _tint(col, 0.35 * k))
		draw_polyline(_ellipse_pts(c, 10.0, 5.0), _tint(col.lightened(0.3), 1.0 * k), 1.5)


## Başın üstünde işaret: kendi kahramanım = altın taç, diğerleri = takım renginde ok. Birimlerde yok.
func _draw_hero_marker(p: Vector2, col: Color, mine: bool) -> void:
	p.y += roundf(sin(float(Time.get_ticks_msec()) / 1000.0 * 4.0))
	var edge := Color(0.08, 0.05, 0.05)
	if mine:
		var pts := PackedVector2Array([p + Vector2(-5, 0), p + Vector2(-5, -6), p + Vector2(-2.5, -3), p + Vector2(0, -7),
			p + Vector2(2.5, -3), p + Vector2(5, -6), p + Vector2(5, 0)])
		draw_colored_polygon(pts, Color(1.0, 0.82, 0.2))
		pts.append(pts[0])
		draw_polyline(pts, edge, 1.0)
	else:
		var tri := PackedVector2Array([p + Vector2(-4, -6), p + Vector2(4, -6), p + Vector2(0, 0)])
		draw_colored_polygon(tri, col.lightened(0.2))
		tri.append(tri[0])
		draw_polyline(tri, edge, 1.0)


## Animasyon karesi: zamanla ilerler, `phase` birimlerin aynı anda adım atmasını bozar.
func _anim_frame(t: Texture2D, step_ms: float, phase: int) -> int:
	return (int(float(Time.get_ticks_msec()) / step_ms) + phase) % Art.frame_count(t)


## Birimi sprite ile çizer (saldırıyorsa saldırı şeridi, hareket ediyorsa koşu, değilse bekleme; yöne göre ayna).
## Vurulunca kısa beyaz parlama. Dosya yoksa false.
func _draw_unit_sprite(a: Array, upos: Vector2) -> bool:
	var sprite: String = Art.unit_sprite(UNIT_ORDER[a[6]])
	if sprite == "":
		return false
	var uid: int = a[0]
	var now := Time.get_ticks_msec()
	var t: Texture2D = null
	var frame := 0
	if u_atk.has(uid) and Art.has_attack(sprite):
		var at := Art.unit_tex(a[5], sprite, Art.attack_anim(sprite))
		if at != null:
			var fr := Art.attack_frame(at, sprite, float(now - int(u_atk[uid])))
			if fr >= 0:
				t = at
				frame = fr
	if t == null:
		t = Art.unit_tex(a[5], sprite, "run" if unit_move.get(uid, false) else "idle")
		if t == null:
			return false
		frame = _anim_frame(t, 110.0, uid * 3)
	var flip: bool = unit_flip.get(uid, a[5] == 1)  # Mavi sağa, Kırmızı sola bakarak başlar
	var foot := Art.foot_for(t, 24.0, Art.get_meta_value("unit_foot"))
	Art.draw_frame(self, t, frame, upos + Vector2(0, 2), Art.unit_scale(), flip, Color.WHITE, foot)
	var hk := 1.0 - float(now - int(u_hit_t.get(uid, -1000))) / float(HIT_FLASH_MS)
	if hk > 0.0:
		Art.draw_frame(self, Art.white(t), frame, upos + Vector2(0, 2), Art.unit_scale(), flip, Color(1, 1, 1, 0.5 + 0.5 * hk), foot)
	return true


## Kahramanı sprite ile çizer. Silaha göre görünüm: yay = okçu, mızrak = mızrakçı, diğerleri = savaşçı.
## Saldırı sırasında silaha özel saldırı şeridi (yön saldırı başındaki nişandan), vurulunca beyaz parlama.
func _draw_hero_sprite(id: int, a: Array, pos: Vector2) -> bool:
	var team: int = a[4]
	var now := Time.get_ticks_msec()
	var sprite: String = Art.WEAPON_SPRITE.get(a[8], "warrior")
	var face_a: float = a[7]
	if id == my_id and not is_auto:
		face_a = (get_global_mouse_position() - pos).angle()
	var t: Texture2D = null
	var frame := 0
	var st: Dictionary = atk_anim.get(id, {})
	if not st.is_empty():
		var w: String = st.w
		var s2: String = Art.WEAPON_SPRITE.get(w, "warrior")
		var at := Art.unit_tex(team, s2, Art.hero_attack_anim(s2, w))
		if at != null:
			var fr := Art.attack_frame(at, w, float(now - int(st.t)))
			if fr >= 0:
				t = at
				frame = fr
				face_a = st.aim
	if t == null:
		var moving: bool = hero_move.get(id, false)
		t = Art.unit_tex(team, sprite, "run" if moving else "idle")
		if t == null:
			return false
		frame = _anim_frame(t, 90.0 if moving else 130.0, 0)
	var foot: float = Art.foot_for(t, 32.0, Art.get_meta_value("foot")) if Art.custom else -1.0
	var flip := cos(face_a) < 0.0
	Art.draw_frame(self, t, frame, pos + Vector2(0, 4), Art.hero_scale(), flip, Color.WHITE, foot)
	var hk := 1.0 - float(now - int(hit_t.get(id, -1000))) / float(HIT_FLASH_MS)
	if hk > 0.0:
		Art.draw_frame(self, Art.white(t), frame, pos + Vector2(0, 4), Art.hero_scale(), flip, Color(1, 1, 1, 0.5 + 0.5 * hk), foot)
	return true


# ============================ SALDIRI GÖRSELLERİ (yalnızca istemci çizimi) ============================

## Saldırı animasyonunu başlatır. `pred`: kendi kahramanım için sunucuyu beklemeden (görsel tahmin).
func _start_atk(id: int, weapon: String, aim: float, pred: bool) -> void:
	atk_anim[id] = {"t": Time.get_ticks_msec(), "w": weapon, "aim": aim, "pred": pred}


## Fareye basınca kendi saldırı animasyonumu hemen başlat (yüksek pingde de tepkisel). Bekleme süresi
## yerelde izlenir; sunucunun "saldırdı" işareti gelince bu saldırı ikinci kez başlatılmaz.
func _predict_attack(aim: float) -> void:
	if snap.is_empty() or not snap.p.has(my_id) or snap.cd > 0.0 or over:
		return
	var me: Array = snap.p[my_id]
	if not me[5]:
		return
	var now := Time.get_ticks_msec()
	if now < pred_atk_next:
		return
	pred_atk_next = now + int(WEAPONS[me[8]].cd * 1000.0)
	_start_atk(my_id, me[8], aim, true)


## Herhangi bir saldırı animasyonu oynuyor mu (test ekran görüntüsü için).
func _attack_active(now: int) -> bool:
	for st in atk_anim.values():
		if now - int(st.t) < 400:
			return true
	for t0 in u_atk.values():
		if now - int(t0) < 400:
			return true
	return false


## Anlık görüntüdeki görsel bitlerden olay üretir: yeni saldırı (yükselen kenar), vurulma, ölüm.
func _vis_events(now: int) -> void:
	var my_pos: Vector2 = view_pos.get(my_id, Vector2(-1000, -1000))
	var my_swing := atk_anim.has(my_id) and now - int(atk_anim[my_id].t) < 400
	for id in snap.p.keys():
		var a: Array = snap.p[id]
		var pos: Vector2 = view_pos.get(id, Vector2(a[0], a[1]))
		var atk: bool = a[9] > 0.0
		if atk and not atk_prev.get(id, false):
			var st: Dictionary = atk_anim.get(id, {})
			var cd_ms: float = WEAPONS[a[8]].cd * 1000.0
			if not (st.get("pred", false) and float(now - int(st.t)) < cd_ms):  # tahminle zaten başladıysa tekrar başlatma
				_start_atk(id, a[8], a[7], false)
		atk_prev[id] = atk
		var hit: bool = a[20]
		if hit and not hit_prev.get(id, false):
			hit_t[id] = now
			fx_sparks.append([pos + Vector2(randf_range(-3, 3), randf_range(-7, -2)), now])
			if id == my_id or (my_swing and pos.distance_to(my_pos) < 50.0):
				shake_t = now  # vurdum / vuruldum: kısa kamera sarsıntısı
		hit_prev[id] = hit
		var alive: bool = a[5]
		if alive_prev.get(id, false) and not alive:
			fx_puffs.append([pos, now])
			atk_anim.erase(id)
		alive_prev[id] = alive
	for a in snap_u:
		var uid: int = a[0]
		var upos: Vector2 = view_u.get(uid, Vector2(a[1], a[2]))
		var atk: bool = a[8]
		if atk and not u_atk_prev.get(uid, false):
			u_atk[uid] = now
			unit_flip[uid] = a[10]  # hedefe dön
		u_atk_prev[uid] = atk
		var hit: bool = a[9]
		if hit and not u_hit_prev.get(uid, false):
			u_hit_t[uid] = now
			fx_sparks.append([upos + Vector2(randf_range(-2, 2), randf_range(-5, -1)), now])
			if my_swing and upos.distance_to(my_pos) < 50.0:
				shake_t = now
		u_hit_prev[uid] = hit


## Kahraman saldırı efekti: kılıç kesme izi, mızrak katmanı + saplama, yumruk/kılıç vuruş kıvılcımı.
## Hepsi saldırı başındaki nişan açısına döner. Doku yoksa (Tiny Swords / kutu) basit çizgi yedeği.
func _draw_attack_fx(id: int, pos: Vector2, team: int) -> void:
	var st: Dictionary = atk_anim.get(id, {})
	if st.is_empty():
		return
	var w: String = st.w
	var since := float(Time.get_ticks_msec() - int(st.t))
	var f := Art.atk_phase(w, since)
	if f < 0:
		return
	var ang: float = st.aim
	var dir := Vector2.from_angle(ang)
	var flip := cos(ang) < 0.0
	var chest := pos + Vector2(0, -2)
	match w:
		"sword":
			if f >= 2 and not Art.draw_fx(self, "slash", f - 2, chest, ang, flip):
				var sweep: float = [0.5, 1.0, 1.0, 1.0][f - 2]  # yedek: savrulan yay
				var fade: float = [1.0, 1.0, 0.6, 0.3][f - 2]
				var s0 := -60.0 if not flip else 60.0
				var s1 := s0 + (120.0 if not flip else -120.0) * sweep
				draw_arc(chest, 24.0, ang + deg_to_rad(minf(s0, s1)), ang + deg_to_rad(maxf(s0, s1)), 12, Color(1, 1, 1, 0.9 * fade), 2.0)
				draw_arc(chest, 21.0, ang + deg_to_rad(minf(s0, s1)), ang + deg_to_rad(maxf(s0, s1)), 12, Color(0.7, 0.8, 1.0, 0.6 * fade), 1.0)
			if f >= 3:
				_draw_spark(chest + dir * 22.0, f - 3)
		"spear":
			var grip := pos + Vector2(0, -1) + dir * float(Art.SPEAR_GRIP[f])
			var drawn := Art.draw_fx(self, "spear", 0, grip, ang, flip, Color.WHITE, "fx/spear_%s.png" % Art.TEAM_DIR[team])
			if f >= 2 and f <= 4 and drawn:
				Art.draw_fx(self, "thrust", f - 2, grip, ang, flip)
			if not drawn and f >= 1 and f <= 4:  # yedek: ileri saplama çizgisi
				draw_line(grip, grip + dir * 26.0, Color(1, 1, 1, 0.9), 1.5)
				draw_circle(grip + dir * 27.0, 1.5 if f != 3 else 2.5, Color(1, 0.95, 0.6))
		"fist":
			if f >= 2:
				_draw_spark(chest + dir * 12.0, f - 2)
			elif not Art.custom and f == 1:
				draw_line(chest, chest + dir * 12.0, Color(1, 1, 1, 0.8), 1.5)
		"bow":
			if f == 1 and not Art.custom:  # yedek: bırakma parlaması
				draw_circle(chest + dir * 9.0, 2.0, Color(1, 0.95, 0.6, 0.9))


## Vuruş kıvılcımı (4 kare). Doku yoksa sarı yıldız çizgileri.
func _draw_spark(p: Vector2, frame: int) -> void:
	if frame > 3 or Art.draw_fx(self, "spark", frame, p, 0.0, false):
		return
	var r := 2.0 + frame * 1.5
	var c := Color(1.0, 0.9, 0.4, 1.0 - frame * 0.25)
	for k in 4:
		var d := Vector2.from_angle(k * PI / 2.0 + PI / 4.0 * float(frame % 2))
		draw_line(p + d * r * 0.4, p + d * r, c, 1.0)


## İsabet kıvılcımları ve ölüm bulutları (kahramanların üstüne).
func _draw_hit_fx() -> void:
	var now := Time.get_ticks_msec()
	for e in fx_sparks:
		_draw_spark(e[0], int(float(now - int(e[1])) / float(SPARK_MS) * 4.0))
	for e in fx_puffs:
		var k := float(now - int(e[1])) / float(PUFF_MS)
		if not Art.draw_fx(self, "puff", mini(4, int(k * 5.0)), e[0] + Vector2(0, -3), 0.0, false):
			draw_circle(e[0], 3.0 + k * 6.0, Color(0.8, 0.8, 0.8, 0.6 * (1.0 - k)))


## HUD yazısı: okunurluk için 1 piksel koyu gölge.
func _hud_text(pos: Vector2, text: String, size: int, color: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	_text(hud, pos + Vector2(1, 1), text, size, Color(0.04, 0.03, 0.08, color.a), width, align)
	_text(hud, pos, text, size, color, width, align)


func _text_w(text: String, size: int) -> float:
	return ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func _draw_hud() -> void:
	if over:
		return  # sonuç ekranı HUD'un üstüne gelir, altta HUD görünmesin
	if snap.is_empty():
		_hud_text(Vector2(0, 180), "Savaş yükleniyor...", 14, Color.WHITE, VIEW.x, HORIZONTAL_ALIGNMENT_CENTER)
		return
	_draw_scorebar()
	if snap.cd > 0.0:
		var bx := Rect2(130, 126, 380, 92)
		hud.draw_style_box(UiTheme.panel_box(), bx)
		_hud_text(Vector2(130, 154), "HAZIRLAN: %d" % ceili(snap.cd), 20, UiTheme.GOLD_L, 380.0, HORIZONTAL_ALIGNMENT_CENTER)
		var tips := ["WASD hareket · sol tık saldırı · Q silah · E duvar",
			"1 Takip · 2 Saldır (imlece) · 3 Bayrak  (birliğin için)",
			"Boşluk / F: yeteneklerin (markette aldıysan)"]
		for i in tips.size():
			_hud_text(Vector2(130, 176 + i * 14), tips[i], 10, Color(1, 1, 1, 0.9), 380.0, HORIZONTAL_ALIGNMENT_CENTER)
	if snap.p.has(my_id):
		var me: Array = snap.p[my_id]
		_draw_player_bar(me)
		if not me[5]:
			hud.draw_style_box(UiTheme.panel_box(), Rect2(220, 156, 200, 34))
			_hud_text(Vector2(220, 178), "Yeniden doğuyorsun: %d" % ceili(me[10]), 14, Color.WHITE, 200.0, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_feed()
	_draw_minimap()


## Üst bant: [Mavi skor] [süre] [Kırmızı skor], takım renkli, ortada metal saat kutusu.
func _draw_scorebar() -> void:
	var secs := ceili(snap.t)
	var clock := "ALTIN BAYRAK" if snap.sd else "%d:%02d" % [secs / 60, secs % 60]
	hud.draw_style_box(UiTheme.banner_box("banner_blue"), Rect2(150, 1, 150, 20))
	hud.draw_style_box(UiTheme.banner_box("banner_red"), Rect2(340, 1, 150, 20))
	hud.draw_style_box(UiTheme.banner_box("banner_steel"), Rect2(284, 0, 72, 22))
	_hud_text(Vector2(156, 16), Net.TEAM_NAMES[0].to_upper(), 10, Color(1, 1, 1, 0.9))
	_hud_text(Vector2(150, 17), str(snap.s[0]), 16, Color.WHITE, 142.0, HORIZONTAL_ALIGNMENT_RIGHT)
	_hud_text(Vector2(484, 16), Net.TEAM_NAMES[1].to_upper(), 10, Color(1, 1, 1, 0.9), -1.0)
	_hud_text(Vector2(346, 17), str(snap.s[1]), 16, Color.WHITE, 142.0, HORIZONTAL_ALIGNMENT_LEFT)
	_hud_text(Vector2(284, 16), clock, 12 if snap.sd else 13, UiTheme.GOLD_L if snap.sd else Color.WHITE, 72.0, HORIZONTAL_ALIGNMENT_CENTER)


## Alt panel: can çubuğu, silah, yetenekler (bekleme = karartma), duvar, birlik + birlik komutu göstergesi.
func _draw_player_bar(me: Array) -> void:
	# Birlik komutu: 1 / 2 / 3, aktif olan altın çerçeveli
	for c in 3:
		var r := Rect2(6 + c * 56, 290, 54, 20)
		hud.draw_style_box(UiTheme.slot_box(me[12] == c), r)
		_hud_text(r.position + Vector2(5, 14), str(c + 1), 11, UiTheme.GOLD_L if me[12] == c else UiTheme.DIM)
		_hud_text(r.position + Vector2(14, 14), CMD_NAMES[c], 10, Color.WHITE if me[12] == c else UiTheme.DIM)
	hud.draw_style_box(UiTheme.panel_box(), Rect2(4, 314, 346, 44))
	# Can
	var hp: float = clampf(me[2] / me[3], 0.0, 1.0)
	UiTheme.draw_icon(hud, "heart", Vector2(11, 335), 14.0)
	var bar := Rect2(28, 337, 92, 10)
	hud.draw_rect(bar.grow(1.0), Color(0.05, 0.04, 0.09))
	hud.draw_rect(bar, Color(0.28, 0.06, 0.08))
	hud.draw_rect(Rect2(bar.position, Vector2(bar.size.x * hp, bar.size.y)), Color(0.3, 0.85, 0.3).lerp(Color(0.9, 0.2, 0.2), 1.0 - hp))
	hud.draw_rect(Rect2(bar.position, Vector2(bar.size.x * hp, 2.0)), Color(1, 1, 1, 0.25))
	_hud_text(bar.position + Vector2(0, 9), "%d/%d" % [ceili(me[2]), me[3]], 9, Color.WHITE, bar.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	# Silah
	_draw_slot(Rect2(128, 329, 26, 26), me[8], false, WEAPONS[me[8]].name, 0.0, 0)
	# Yetenekler: Boşluk, F
	var key_names := ["Boşluk", "F"]
	for s in 2:
		var ai: int = me[14 + s]
		var r := Rect2(162 + s * 32, 329, 26, 26)
		if ai > 0:
			var aid: String = ABILITY_ORDER[ai - 1]
			var cd_left: int = me[16 + s]
			_draw_slot(r, aid, cd_left <= 0, key_names[s], clampf(cd_left / float(ABILITIES[aid].cd), 0.0, 1.0), cd_left)
		else:
			_draw_slot(r, "", false, key_names[s], 0.0, 0)
	# Duvar ve birlik
	_draw_slot(Rect2(232, 329, 26, 26), "wall_wood", false, "Duvar", 0.0, 0)
	_hud_text(Vector2(262, 347), "x%d" % me[11], 12, Color.WHITE)
	_draw_slot(Rect2(292, 329, 26, 26), "unit_swordsman", false, "Birlik", 0.0, 0)
	_hud_text(Vector2(322, 347 if me[21] == 0 else 343), "x%d" % me[13], 12, Color.WHITE)
	if me[21] > 0:
		_hud_text(Vector2(322, 353), "(%d doğuyor)" % me[21], 8, UiTheme.GOLD_L)


## Kutu: ikon + (varsa) tuş adı; bekleme varsa üstten karartma ve kalan saniye. Hazırsa altın çerçeve.
func _draw_slot(r: Rect2, icon_id: String, ready: bool, key: String, cd_ratio: float, cd_left: int) -> void:
	hud.draw_style_box(UiTheme.slot_box(ready), r)
	if icon_id != "":
		UiTheme.draw_icon(hud, icon_id, r.position + Vector2(5, 5), 16.0)
	if cd_ratio > 0.0:
		var inner := r.grow(-2.0)
		hud.draw_rect(Rect2(inner.position, Vector2(inner.size.x, inner.size.y * cd_ratio)), Color(0.02, 0.02, 0.06, 0.72))
		_hud_text(r.position + Vector2(0, 17), str(cd_left), 12, Color.WHITE, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	if key != "":
		_hud_text(r.position + Vector2(-8, -2), key, 8, UiTheme.GOLD_L if ready else UiTheme.DIM, r.size.x + 16.0, HORIZONTAL_ALIGNMENT_CENTER)


## Kill feed: sağ üstte, arkaplanlı satırlar. "A → B" satırı: takım renkli adlar + kılıç ikonu.
func _draw_feed() -> void:
	var y := 26.0
	for e in feed:
		var al: float = clampf(e[1], 0.0, 1.0)
		var text: String = e[0]
		var parts := text.split(" → ")
		var w := _text_w(text, 10) + 10.0
		if parts.size() == 2:
			w = _text_w(parts[0], 10) + _text_w(parts[1], 10) + 28.0
		var x := 636.0 - w
		hud.draw_rect(Rect2(x, y - 1.0, w, 13.0), Color(0.05, 0.04, 0.1, 0.6 * al))
		hud.draw_rect(Rect2(x, y - 1.0, 2.0, 13.0), Color(UiTheme.GOLD.r, UiTheme.GOLD.g, UiTheme.GOLD.b, al))
		if parts.size() == 2:
			var c0 := _team_color_of_name(parts[0])
			var c1 := _team_color_of_name(parts[1])
			_hud_text(Vector2(x + 5, y + 9), parts[0], 10, Color(c0.r, c0.g, c0.b, al))
			var ix := x + 5 + _text_w(parts[0], 10) + 2
			UiTheme.draw_icon(hud, "sword", Vector2(ix, y - 1), 12.0, Color(1, 1, 1, al))
			_hud_text(Vector2(ix + 14, y + 9), parts[1], 10, Color(c1.r, c1.g, c1.b, al))
		else:
			_hud_text(Vector2(x + 5, y + 9), text, 10, Color(1, 1, 1, al))
		y += 14.0


func _team_color_of_name(n: String) -> Color:
	for p in Net.players.values():
		if p.name == n:
			return UiTheme.TEAM[p.team]
	return Color.WHITE


func _draw_minimap() -> void:
	var s := 0.1
	var origin := Vector2(VIEW.x - ARENA.size.x * s - 8.0, VIEW.y - ARENA.size.y * s - 8.0)
	hud.draw_style_box(UiTheme.slot_box(false), Rect2(origin - Vector2(4, 4), ARENA.size * s + Vector2(8, 8)))
	hud.draw_rect(Rect2(origin, ARENA.size * s), Color(0.04, 0.05, 0.1, 0.85))
	for t in 2:
		var bx := 0.0 if t == 0 else ARENA.size.x - BASE_W
		hud.draw_rect(Rect2(origin + Vector2(bx, 0.0) * s, Vector2(BASE_W, ARENA.size.y) * s), _tint(TEAM_COLORS[t], 0.25))
	for o in OBSTACLES:
		hud.draw_rect(Rect2(origin + o.position * s, o.size * s), Color(0.5, 0.5, 0.55))
	for f in snap.f:
		hud.draw_rect(Rect2(origin + Vector2(f[0], f[1]) * s - Vector2(1, 1), Vector2(3, 3)), Color(1, 1, 0.4))
	for a in snap_u:
		hud.draw_rect(Rect2(origin + Vector2(a[1], a[2]) * s, Vector2(1, 1)), TEAM_COLORS[a[5]])
	for id in snap.p.keys():
		var a: Array = snap.p[id]
		if a[5]:
			hud.draw_rect(Rect2(origin + Vector2(a[0], a[1]) * s - Vector2(1, 1), Vector2(3, 3)),
				Color.WHITE if id == my_id else TEAM_COLORS[a[4]])
	var cc := camera.get_screen_center_position()
	hud.draw_rect(Rect2(origin + (cc - VIEW * 0.5) * s, VIEW * s), Color(1, 1, 1, 0.5), false, 1.0)
