extends "res://minigames/arena_base.gd"
## Coin toplama minigame'i: arenada sunucunun rastgele yarattığı coinleri en çok toplayan kazanır.
## Eşitlikte o sayıya önce ulaşan öne geçer.

const MARGIN := 14.0
const TOP := 20.0
const MAX_COINS := 10
const SPAWN_EVERY := 0.5
const PICKUP_R := 9.0  # oyuncu-coin mesafesi

# Sunucu
var coins: Dictionary = {}  # coin id -> Vector2
var next_coin := 1
var spawn_acc := 0.0
var score: Dictionary = {}  # peer -> toplanan
var reached_at: Dictionary = {}  # peer -> son coini aldığı zaman


func _title() -> String:
	return "COİN TOPLAMA"

func _hint() -> String:
	return "WASD ile hareket et, en çok coini topla!"

func _play_time() -> float:
	return 30.0

func _speed() -> float:
	return 110.0


func _spawn_pos(index: int, count: int) -> Vector2:
	var a := TAU * float(index) / float(maxi(count, 1))
	return SCREEN * 0.5 + Vector2(cos(a), sin(a)) * 60.0


func _move_player(_id: int, p: Vector2, step: Vector2) -> Vector2:
	var np := p + step
	return Vector2(clampf(np.x, MARGIN, SCREEN.x - MARGIN), clampf(np.y, TOP + MARGIN, SCREEN.y - MARGIN))


func _sim(delta: float) -> void:
	spawn_acc += delta
	while spawn_acc >= SPAWN_EVERY:
		spawn_acc -= SPAWN_EVERY
		if coins.size() < MAX_COINS:
			coins[next_coin] = Vector2(
				randf_range(MARGIN, SCREEN.x - MARGIN), randf_range(TOP + MARGIN, SCREEN.y - MARGIN))
			next_coin += 1
	for id in pos:
		if not Net.players.has(id):
			continue
		for cid in coins.keys():
			if pos[id].distance_to(coins[cid]) <= PICKUP_R:
				coins.erase(cid)
				score[id] = score.get(id, 0) + 1
				reached_at[id] = elapsed


func _extra_snap() -> Dictionary:
	return {"coins": coins.duplicate(), "score": score.duplicate()}


func _compute_result() -> Array:
	var ids: Array = Net.players.keys()
	ids.sort_custom(func(a, b):
		var sa: int = score.get(a, 0)
		var sb: int = score.get(b, 0)
		if sa != sb:
			return sa > sb
		return reached_at.get(a, 0.0) < reached_at.get(b, 0.0))
	var labels := {}
	for id in ids:
		labels[id] = "%d coin" % score.get(id, 0)
	return [ids, labels]


# --- Çizim (sprite'lı) ---

var pickups: Array = []  # [konum, an (ms)]: toplanan coin parıltısı
var floaters: Array = []  # [oyuncu id, an (ms), artış]: "+1" yüzen yazı


## Yalnızca görünüm: önceki anlık görüntüyle karşılaştırıp kaybolan coinlerde parıltı, artan skorda "+1" üretir.
func _take_snapshot(s: Dictionary) -> void:
	if fancy and not snap.is_empty():
		var now := Time.get_ticks_msec()
		var old_c: Dictionary = snap.get("coins", {})
		var new_c: Dictionary = s.get("coins", {})
		for cid in old_c:
			if not new_c.has(cid):
				pickups.append([old_c[cid], now])
		var old_s: Dictionary = snap.get("score", {})
		var new_s: Dictionary = s.get("score", {})
		for id in new_s:
			var d: int = int(new_s[id]) - int(old_s.get(id, 0))
			if d > 0:
				floaters.append([id, now, d])
	super._take_snapshot(s)


func _draw_world() -> void:
	if not fancy or not MgArt.background(self, "coins_bg"):
		_draw_world_plain()
		return
	var now := Time.get_ticks_msec()
	var t := float(now) / 1000.0
	var ct := MgArt.tex("coin")
	var cs: Dictionary = snap.get("coins", {})
	for cid in cs:
		var c: Vector2 = cs[cid]
		var bob := roundf(sin(t * 4.0 + float(cid)) * 1.5)
		draw_colored_polygon(MgArt.ellipse(c + Vector2(0, 5), 4.5, 1.8, 10), Color(0.04, 0.08, 0.04, 0.4))
		if ct != null:
			MgArt.frame(self, ct, int(t * 10.0 + float(cid)) % 6, 16, c + Vector2(0, bob - 1.0), MgArt.PX)
		else:
			var w := 3.0 + absf(sin(t * 5.0 + cid)) * 3.0
			draw_rect(Rect2((c - Vector2(w, 5)).round(), Vector2(w * 2.0, 10)), Color(1.0, 0.85, 0.2))
		if (int(t * 1.3 + float(cid) * 0.37) % 3) == 0 and fmod(t * 1.3 + float(cid) * 0.37, 1.0) < 0.25:  # ara sıra parlama
			MgArt.frame(self, MgArt.tex("sparkle"), 3, 20, c + Vector2(3, bob - 4.0), MgArt.PX * 0.75)
	_draw_actors()
	# toplanan coin: parıltı + genişleyen "pling" halkası
	while not pickups.is_empty() and now - int(pickups[0][1]) > 420:
		pickups.pop_front()
	var sp := MgArt.tex("sparkle")
	for pk in pickups:
		var k := float(now - int(pk[1])) / 420.0
		MgArt.frame(self, sp, clampi(int(k * 5.0), 0, 4), 20, pk[0], MgArt.PX)
		draw_arc(pk[0], 4.0 + k * 10.0, 0.0, TAU, 16, Color(1.0, 0.95, 0.6, 1.0 - k), 1.0)
	# "+1": oyuncunun başı üstünden yükselir
	while not floaters.is_empty() and now - int(floaters[0][1]) > 800:
		floaters.pop_front()
	for fl in floaters:
		var k := float(now - int(fl[1])) / 800.0
		if not disp.has(fl[0]):
			continue
		var p: Vector2 = disp[fl[0]] + Vector2(0, -42.0 - k * 14.0)
		MgArt.text(self, "+%d" % int(fl[2]), p, MgArt.PX, Color(1.0, 0.9, 0.4, 1.0 - maxf(0.0, k - 0.6) / 0.4))


## Başüstü: toplanan coin sayısı (ikon + sayı), taç/okun sağında.
func _above_head(id: int, p: Vector2, top: float) -> void:
	var n: int = int(snap.get("score", {}).get(id, 0))
	var pos := (p + Vector2(7, -top - 9.0)).round()
	_coin_icon(pos + Vector2(3, 3))
	MgArt.small(self, str(n), pos + Vector2(8, 6.5), 8, Color(1.0, 0.9, 0.45), 20.0, HORIZONTAL_ALIGNMENT_LEFT)


## Sağ üstte canlı skor tablosu: sıra, takım şeridi, ad, coin ikonu, sayı (kendi satırın altın).
func _draw_hud() -> void:
	var sc: Dictionary = snap.get("score", {})
	var ids: Array = Net.players.keys()
	ids.sort_custom(func(a, b): return sc.get(a, 0) > sc.get(b, 0))
	var n := mini(ids.size(), 5)
	var my := multiplayer.get_unique_id()
	if n == 0:
		return
	var r := Rect2(512, 21, 124, 6 + n * 11)
	MgArt.plate(self, r, Color(0.09, 0.08, 0.15, 0.88))
	for i in n:
		var id: int = ids[i]
		var team: int = Net.players.get(id, {}).get("team", 0)
		var row := Rect2(r.position.x + 3.0, r.position.y + 3.0 + i * 11.0, r.size.x - 6.0, 10.0)
		if id == my:
			draw_rect(row, Color(0.62, 0.45, 0.1, 0.55))
			draw_rect(row, Color(1.0, 0.85, 0.3), false, 1.0)
		draw_rect(Rect2(row.position, Vector2(2, row.size.y)), MgArt.team_col(team))
		var col := Color(1.0, 0.85, 0.3) if i == 0 else Color(0.93, 0.92, 0.97)
		MgArt.small(self, "%d" % (i + 1), row.position + Vector2(4, 8), 8, col, 10.0, HORIZONTAL_ALIGNMENT_LEFT)
		var nm: String = Net.players.get(id, {}).get("name", "?")
		MgArt.small(self, nm, row.position + Vector2(13, 8), 8, Color.WHITE, 70.0, HORIZONTAL_ALIGNMENT_LEFT)
		_coin_icon(row.position + Vector2(row.size.x - 18.0, 5.0))
		MgArt.small(self, str(sc.get(id, 0)), row.position + Vector2(row.size.x - 1.0, 8), 8, Color(1.0, 0.9, 0.45), 14.0, HORIZONTAL_ALIGNMENT_RIGHT)


## Küçük coin ikonu (coin şeridinin ilk karesi, 8x8 birim), ortası `c`.
func _coin_icon(c: Vector2) -> void:
	var ct: Texture2D = Art.tex("fx/coin.png") if Art.custom else null
	if ct != null:
		MgArt.frame(self, ct, 0, 12, c, MgArt.PX)
	else:
		draw_rect(Rect2(c - Vector2(3, 3), Vector2(6, 6)), Color(1.0, 0.85, 0.2))


# --- Çizim (düz yedek: sprite paketi yoksa) ---

func _draw_world_plain() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0.2, 0.22, 0.3))
	var arena := Rect2(6, TOP, SCREEN.x - 12, SCREEN.y - TOP - 6)
	draw_rect(arena, Color(0.27, 0.3, 0.4))
	# Zemin karoları (sadece görsel)
	for gx in range(6, 634, 32):
		for gy in range(int(TOP), 354, 32):
			if ((gx / 32) + (gy / 32)) % 2 == 0:
				draw_rect(Rect2(gx, gy, 32, 32).intersection(arena), Color(0.3, 0.33, 0.44))
	var t := Time.get_ticks_msec() / 1000.0
	var cs: Dictionary = snap.get("coins", {})
	for cid in cs:
		var c: Vector2 = cs[cid]
		var w := 3.0 + absf(sin(t * 5.0 + cid)) * 3.0  # dönen coin hissi
		draw_rect(Rect2((c - Vector2(w, 5)).round(), Vector2(w * 2.0, 10)), Color(0.75, 0.55, 0.1))
		draw_rect(Rect2((c - Vector2(maxf(w - 1.0, 1.0), 4)).round(), Vector2(maxf(w - 1.0, 1.0) * 2.0, 8)), Color(1.0, 0.85, 0.2))
	for id in disp:
		_draw_player(id, disp[id])
	# Skor tablosu
	var sc: Dictionary = snap.get("score", {})
	var ids: Array = Net.players.keys()
	ids.sort_custom(func(a, b): return sc.get(a, 0) > sc.get(b, 0))
	var font := ThemeDB.fallback_font
	for i in mini(ids.size(), 5):
		var nm: String = Net.players.get(ids[i], {}).get("name", "?")
		draw_string(font, Vector2(SCREEN.x - 150, 24 + i * 10), "%s: %d" % [nm, sc.get(ids[i], 0)],
			HORIZONTAL_ALIGNMENT_RIGHT, 144, 8, Color(1, 1, 0.6))


# --- Test botu ---

func _bot_input() -> Vector2:
	var me := _my_pos()
	var cs: Dictionary = snap.get("coins", {})
	var best := Vector2.ZERO
	var best_d := INF
	for cid in cs:
		var d := me.distance_to(cs[cid])
		if d < best_d:
			best_d = d
			best = cs[cid]
	if best_d == INF:
		return Vector2.ZERO
	return (best - me).normalized()
