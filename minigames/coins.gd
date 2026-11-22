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


# --- Çizim ---

func _draw_world() -> void:
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
