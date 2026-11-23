extends "res://minigames/arena_base.gd"
## Koşu minigame'i: üstten görünüm pist, engeller, soldan sağa bitiş çizgisi.
## İlk bitiren 1. olur. Süre dolarsa bitirmeyenler bitişe yakınlığa göre sıralanır.

const TRACK_TOP := 28.0
const TRACK_BOTTOM := 348.0
const START_X := 22.0
const FINISH_X := 600.0
const HALF := 5.0  # oyuncu yarı boyutu

var obstacles: Array = []  # Rect2 listesi (herkeste aynı)

# Sunucu
var finish_time: Dictionary = {}  # peer -> süre (sn)
var finish_order: Array = []

# Bot
var bot_dir := 0


func _title() -> String:
	return "KOŞU"

func _hint() -> String:
	return "WASD ile koş, engellere çarpma. İlk bitiren kazanır!"

func _play_time() -> float:
	return 30.0

func _speed() -> float:
	return 100.0


func _make_setup() -> Dictionary:
	# 12 sütun, her birinde tek bir engel. Pist kenarından 30 px boşluk bırakılır,
	# böylece her engelin hem altından hem üstünden geçilebilir.
	var rects: Array = []
	for i in 12:
		var x := 80.0 + i * 41.0
		var h := randf_range(60.0, 110.0)
		var y := randf_range(TRACK_TOP + 30.0, TRACK_BOTTOM - 30.0 - h)
		rects.append(Rect2(x, y, 14.0, h))
	return {"obstacles": rects}


func _apply_setup(s: Dictionary) -> void:
	obstacles = s.get("obstacles", [])


func _spawn_pos(index: int, count: int) -> Vector2:
	var span := TRACK_BOTTOM - TRACK_TOP - 24.0
	var y := TRACK_TOP + 12.0 + span * (float(index) + 0.5) / float(maxi(count, 1))
	return Vector2(START_X, y)


func _body(p: Vector2) -> Rect2:
	return Rect2(p - Vector2(HALF, HALF), Vector2(HALF * 2.0, HALF * 2.0))


func _blocked(p: Vector2) -> bool:
	var b := _body(p)
	for r in obstacles:
		if b.intersects(r):
			return true
	return false


## Eksen eksen hareket: çarpınca o eksende dur (engele sürtünerek kay).
func _move_player(id: int, p: Vector2, step: Vector2) -> Vector2:
	if finish_time.has(id):
		return p  # bitiren durur
	var np := p
	var tx := Vector2(clampf(p.x + step.x, HALF, SCREEN.x - HALF), p.y)
	if not _blocked(tx):
		np = tx
	var ty := Vector2(np.x, clampf(np.y + step.y, TRACK_TOP + HALF, TRACK_BOTTOM - HALF))
	if not _blocked(ty):
		np = ty
	return np


func _sim(_delta: float) -> void:
	for id in pos:
		if not finish_time.has(id) and Net.players.has(id) and pos[id].x >= FINISH_X:
			finish_time[id] = elapsed
			finish_order.append(id)
	var all_done := true
	for id in Net.players:
		if not finish_time.has(id):
			all_done = false
	if all_done:
		_end()


func _extra_snap() -> Dictionary:
	return {"fin": finish_order.duplicate()}


func _compute_result() -> Array:
	var ids: Array = Net.players.keys()
	ids.sort_custom(func(a, b):
		var fa: bool = finish_time.has(a)
		var fb: bool = finish_time.has(b)
		if fa and fb:
			return finish_time[a] < finish_time[b]
		if fa != fb:
			return fa
		return pos.get(a, Vector2.ZERO).x > pos.get(b, Vector2.ZERO).x)
	var labels := {}
	for id in ids:
		if finish_time.has(id):
			labels[id] = "%.1f sn" % finish_time[id]
		else:
			var frac: float = clampf((pos.get(id, Vector2.ZERO).x - START_X) / (FINISH_X - START_X), 0.0, 1.0)
			labels[id] = "bitiremedi (%%%d)" % int(frac * 100.0)
	return [ids, labels]


# --- Çizim (sprite'lı) ---

const OB_KINDS := ["ob_stone", "ob_log", "ob_fence"]
const OB_TOP := 10  # engel dokusu: üst kapak / orta (yinelenen) / alt yüz satırları (sanat pikseli)
const OB_MID := 16
const OB_BOT := 8
const POST_X := FINISH_X + 6.0


func _draw_world() -> void:
	if not fancy:
		_draw_world_plain()
		return
	if not MgArt.background(self, "run_bg"):
		_draw_world_plain()
		return
	_draw_crowd()
	var extra: Array = []
	for i in obstacles.size():
		var r: Rect2 = obstacles[i]
		extra.append([r.end.y, _draw_obstacle.bind(i, r)])
	for y in [TRACK_TOP + 1.0, TRACK_BOTTOM + 9.0]:  # başlangıç direkleri
		extra.append([y, _draw_post.bind("start_post", 9, Vector2(START_X - 11.0, y))])
	# bitiş kemeri: alt direk + bayraklar (üst direk ekranın dışında, ip oradan iner)
	extra.append([TRACK_BOTTOM + 9.0, _draw_post.bind("finish_post", 16, Vector2(POST_X, TRACK_BOTTOM + 9.0))])
	_draw_actors(extra)
	_draw_bunting()


## Engel: alt sınıfa göre taş duvar / kütük / tahta barikat; üst kapak + yinelenen orta + alt yüz, gölgeli.
func _draw_obstacle(i: int, r: Rect2) -> void:
	var t := MgArt.tex(OB_KINDS[(i * 5 + int(r.size.y)) % OB_KINDS.size()])
	if t == null:
		Art.draw_obstacle(self, r)
		return
	draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0.05, 0.03, 0.08, 0.28))
	var s := MgArt.PX
	var w := float(t.get_width())
	var h := roundf(r.size.y / s)
	draw_set_transform((r.position * 3.0).round() / 3.0, 0.0, Vector2(s, s))
	draw_texture_rect_region(t, Rect2(0, 0, w, OB_TOP), Rect2(0, 0, w, OB_TOP))
	var y := float(OB_TOP)
	var mid_end := h - 4.0
	while y < mid_end:
		var part := minf(OB_MID, mid_end - y)
		draw_texture_rect_region(t, Rect2(0, y, w, part), Rect2(0, OB_TOP, w, part))
		y += part
	draw_texture_rect_region(t, Rect2(0, mid_end, w, OB_BOT), Rect2(0, OB_TOP + OB_MID, w, OB_BOT))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Direk: ayak noktası `foot` (doku altı).
func _draw_post(name_: String, fw: int, foot: Vector2) -> void:
	var t := MgArt.tex(name_)
	if t == null:
		return
	MgArt.frame(self, t, 0, fw, foot - Vector2(0, t.get_height() * MgArt.PX * 0.5), MgArt.PX)
	if name_ == "finish_post":  # direğin iki yanında takım bayrakları
		Art.draw_flag(self, 0, foot + Vector2(-13, -1))
		Art.draw_flag(self, 1, foot + Vector2(9, -1))


## Bitiş kemeri: iki direğin tepesi arasında flamalı ip (her şeyin üstünde).
func _draw_bunting() -> void:
	var top := Vector2(POST_X, -2.0)
	var bot := Vector2(POST_X, TRACK_BOTTOM + 9.0 - 28.0)
	var sway := sin(float(Time.get_ticks_msec()) / 1000.0 * 2.0) * 1.5
	var pts := PackedVector2Array()
	for k in 25:
		var u := float(k) / 24.0
		pts.append(top.lerp(bot, u) + Vector2(sin(u * PI) * (6.0 + sway), 0))
	draw_polyline(pts, Color(0.08, 0.05, 0.05), 1.0)
	var pt := MgArt.tex("pennant")
	for k in range(1, 24):
		MgArt.frame(self, pt, k % 3, 8, pts[k] + Vector2(3.0, 2.0), MgArt.PX)


## Üst kenarda tezahürat eden seyirciler (çarpışmasız), önünde tahta korkuluk.
func _draw_crowd() -> void:
	var sp := MgArt.tex("spectators")
	var rail := MgArt.tex("rail")
	if sp == null or rail == null:
		return
	var cheer := int(snap.get("ph", -1)) == Phase.PLAY or int(snap.get("ph", -1)) == Phase.DONE
	var now := Time.get_ticks_msec()
	var x := 30.0
	var i := 0
	while x < 585.0:
		var kind := (i * 7 + 3) % 6
		var up := cheer and ((now / 220 + i * 3) % 4) < 2
		var y := 22.0 + float((i * 5) % 3)
		MgArt.frame(self, sp, kind * 2 + (1 if up else 0), 12, Vector2(x, y), MgArt.PX)
		x += 9.0 + float((i * 13) % 5)
		i += 1
	var rw := rail.get_width() * MgArt.PX
	var rx := 0.0
	while rx < 640.0:
		draw_texture_rect(rail, Rect2(rx, 24.0, rw, rail.get_height() * MgArt.PX), false)
		draw_texture_rect(rail, Rect2(rx, 351.0, rw, rail.get_height() * MgArt.PX), false)
		rx += rw


## Bandın ortası: tüm oyuncuların bitişe göre konumu (ilerleme çubuğu).
func _draw_hud() -> void:
	var r := Rect2(232, 3, 176, 12)
	MgArt.plate(self, r, Color(0.09, 0.08, 0.15, 0.94))
	var x0 := r.position.x + 8.0
	var x1 := r.end.x - 12.0
	var yc := r.position.y + 6.0
	draw_rect(Rect2(x0, yc - 1.0, x1 - x0, 2.0), Color(0.36, 0.3, 0.26))
	draw_rect(Rect2(x0, yc - 1.0, x1 - x0, 1.0), Color(0.55, 0.45, 0.36))
	for k in 4:  # bitiş damaları
		draw_rect(Rect2(x1 + 1.0 + (k % 2) * 2.0, yc - 4.0 + k * 2.0, 2.0, 2.0), Color.WHITE)
		draw_rect(Rect2(x1 + 1.0 + ((k + 1) % 2) * 2.0, yc - 4.0 + k * 2.0, 2.0, 2.0), Color(0.08, 0.06, 0.1))
	var my := multiplayer.get_unique_id()
	var ids: Array = disp.keys()
	ids.sort_custom(func(a, b): return int(a == my) < int(b == my))  # kendi işaretim en üstte
	for id in ids:
		var team: int = Net.players.get(id, {}).get("team", 0)
		var u := clampf((disp[id].x - START_X) / (FINISH_X - START_X), 0.0, 1.0)
		var c := Vector2(roundf(lerpf(x0, x1, u)), yc)
		if id == my:
			draw_rect(Rect2(c - Vector2(3, 3), Vector2(6, 6)), Color(1.0, 0.85, 0.25))
		draw_rect(Rect2(c - Vector2(2, 2), Vector2(4, 4)), Color(0.05, 0.04, 0.09))
		draw_rect(Rect2(c - Vector2(1.5, 1.5), Vector2(3, 3)), MgArt.team_col(team))


## Başüstü: anlık sıra rozeti (lider altın), kendi karakterin geride ise öne doğru ok.
func _above_head(id: int, p: Vector2, top: float) -> void:
	var fin: Array = snap.get("fin", [])
	var rank := fin.find(id)
	if rank < 0:
		rank = fin.size()
		for o in disp:
			if o != id and not fin.has(o) and disp[o].x > p.x:
				rank += 1
	var nm: String = Net.players.get(id, {}).get("name", "?")
	var nw := ThemeDB.fallback_font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	var b := Rect2(roundf(p.x - nw * 0.5 - 10.0), roundf(p.y - top - 4.0), 8, 8)
	MgArt.plate(self, b, Color(0.62, 0.42, 0.08) if rank == 0 else Color(0.18, 0.17, 0.26), Color(1.0, 0.85, 0.3) if rank == 0 else Color(0.5, 0.55, 0.7))
	MgArt.small(self, str(rank + 1), b.position + Vector2(4, 7), 8, Color.WHITE, 8.0)
	if id == multiplayer.get_unique_id() and rank > 0 and not fin.has(id) and int(snap.get("ph", -1)) == Phase.PLAY:
		var k := float(Time.get_ticks_msec() % 600) / 600.0
		var a := Vector2(p.x + 11.0 + k * 3.0, p.y - 8.0)
		var tri := PackedVector2Array([a + Vector2(0, -3), a + Vector2(4, 0), a + Vector2(0, 3)])
		draw_colored_polygon(tri, Color(1.0, 0.85, 0.25, 1.0 - k * 0.6))


# --- Çizim (düz yedek: sprite paketi yoksa) ---

func _draw_world_plain() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0.16, 0.3, 0.17))  # çimen
	var track := Rect2(0, TRACK_TOP, SCREEN.x, TRACK_BOTTOM - TRACK_TOP)
	draw_rect(track, Color(0.55, 0.38, 0.25))
	# Pist şeritleri (sadece görsel)
	for i in range(1, 8):
		var y := TRACK_TOP + (TRACK_BOTTOM - TRACK_TOP) * i / 8.0
		for x in range(0, 640, 24):
			draw_rect(Rect2(x, y, 12, 1), Color(0.62, 0.45, 0.3))
	# Başlangıç çizgisi
	draw_rect(Rect2(START_X - 12, TRACK_TOP, 2, TRACK_BOTTOM - TRACK_TOP), Color(0.9, 0.9, 0.9))
	# Bitiş çizgisi (damalı)
	var cell := 6.0
	var rows := int((TRACK_BOTTOM - TRACK_TOP) / cell)
	for ry in rows:
		for cx in 2:
			var c := Color.WHITE if (ry + cx) % 2 == 0 else Color.BLACK
			draw_rect(Rect2(FINISH_X + cx * cell, TRACK_TOP + ry * cell, cell, cell), c)
	# Engeller
	for r in obstacles:
		draw_rect(r, Color(0.35, 0.35, 0.4))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color(0.55, 0.55, 0.6))
		draw_rect(Rect2(r.position.x, r.end.y - 2, r.size.x, 2), Color(0.2, 0.2, 0.25))
	for id in disp:
		_draw_player(id, disp[id])
	# Bitirenlerin sırası
	var fin: Array = snap.get("fin", [])
	var font := ThemeDB.fallback_font
	for i in fin.size():
		var nm: String = Net.players.get(fin[i], {}).get("name", "?")
		draw_string(font, Vector2(SCREEN.x - 150, 24 + i * 10), "%d. %s" % [i + 1, nm],
			HORIZONTAL_ALIGNMENT_RIGHT, 144, 8, Color(1, 1, 0.6))


# --- Test botu ---

func _bot_input() -> Vector2:
	var me := _my_pos()
	var ahead := Rect2(me - Vector2(HALF, HALF), Vector2(HALF * 2.0 + 14.0, HALF * 2.0))
	for r in obstacles:
		if ahead.intersects(r):
			if bot_dir == 0:
				# Engelin yakın kenarına göre yukarı ya da aşağı kaç
				bot_dir = -1 if me.y - r.position.y < r.end.y - me.y else 1
			return Vector2(0, bot_dir)
	bot_dir = 0
	return Vector2(1, 0)
