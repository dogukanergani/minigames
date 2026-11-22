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


# --- Çizim ---

func _draw_world() -> void:
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
