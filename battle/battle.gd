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

const VIEW := Vector2(640, 360)
const ARENA := Rect2(0, 0, 1280, 720)
const PSIZE := 12.0  # kahraman
const HALF := 6.0
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
const ARROW_SPEED := 220.0
const ARROW_LIFE := 0.9
const WALL_HP := {"wall_wood": 40, "wall_stone": 100}
const SHIELD := {"shield_wood": 0.15, "shield_iron": 0.30}

# Birim türleri (item id'leri ile aynı). UNIT_ORDER: anlık görüntüde kısa indeks.
const UNIT_ORDER := ["unit_swordsman", "unit_archer"]
const UNIT_TYPES := {
	"unit_swordsman": {"name": "Kılıççı", "hp": 50.0, "speed": 62.0, "dmg": 8.0, "range": 12.0, "cd": 0.6, "ranged": false},
	"unit_archer": {"name": "Okçu", "hp": 30.0, "speed": 56.0, "dmg": 7.0, "range": 90.0, "cd": 0.9, "ranged": true},
}
const CMD_NAMES := ["Takip", "Saldır", "Bayrak"]
const UNIT_AGGRO := [70.0, 100.0, 50.0]  # komuta göre düşman fark etme yarıçapı
const UNIT_LEASH := 130.0  # Takip modunda kahramandan en fazla bu kadar uzaklaşır

# Maç ayarları (GDD: ilk 3 bayrak / 5 dk / 5 sn yeniden doğma). "fast" test modunda hızlanır.
var time_limit := 300.0
var captures_to_win := 3
var respawn_time := 5.0
var countdown_time := 3.0
var speed_mul := 1.0

# --- Sunucu durumu ---
var hello: Dictionary = {}
var started := false
var over := false
var tick := 0
var pl: Dictionary = {}  # peer_id -> kahraman durumu
var units: Dictionary = {}  # uid -> birim durumu
var next_uid := 1
var losses: Dictionary = {}  # peer_id -> ölen birim item id'leri
var flags: Array = []
var projectiles: Array = []
var walls: Array = []
var inputs: Dictionary = {}
var scores: Array = [0, 0]
var time_left := 0.0
var countdown := 0.0
var sudden := false

# --- İstemci durumu ---
var snap: Dictionary = {}
var view_pos: Dictionary = {}
var view_u: Dictionary = {}
var feed: Array = []
var send_acc := 0.0
var my_id := 0
var camera: Camera2D
var hud: Control
var bot_kill_done := false
var bot_cmd_sent := false
var is_auto := false


func _ready() -> void:
	my_id = multiplayer.get_unique_id()
	var args := OS.get_cmdline_user_args()
	is_auto = "auto" in args
	if "fast" in args:
		captures_to_win = 1
		respawn_time = 1.0
		countdown_time = 1.0
		speed_mul = 3.0
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
	if not started and hello.size() >= Net.players.size():
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
	var armor := 0.0
	for s in SHIELD:
		if inv.has(s):
			armor = maxf(armor, SHIELD[s])
	var wall_list: Array = []
	for w in ["wall_stone", "wall_wood"]:
		for item in inv:
			if item == w:
				wall_list.append(w)
	var max_hp: int = BASE_HP + (40 if inv.has("heart") else 0)
	var spd: float = BASE_SPEED * (1.2 if inv.has("boots") else 1.0) * speed_mul
	var pos := _spawn_pos(team, idx)
	return {
		"team": team, "idx": idx, "pos": pos, "cur": pos,
		"hp": max_hp, "max_hp": max_hp, "alive": true, "respawn": 0.0, "carrying": -1,
		"aim": 0.0 if team == 0 else PI, "cd": 0.0, "atk_vis": 0.0,
		"weapons": weapons, "wsel": 0, "armor": armor, "speed": spd, "walls": wall_list,
		"cmd": 0,
	}


func _spawn_units(id: int, p: Dictionary) -> void:
	var slot := 0
	for item_id in Game.inventory.get(id, []):
		if not UNIT_TYPES.has(item_id):
			continue
		var t: Dictionary = UNIT_TYPES[item_id]
		var angle := float(slot) * TAU / 4.0 + 0.5
		units[next_uid] = {
			"owner": id, "team": p.team, "type": item_id, "slot": slot,
			"pos": p.pos + Vector2.from_angle(angle) * 22.0,
			"hp": t.hp, "max_hp": t.hp, "cd": 0.0, "retarget": randf() * 0.25,
			"tkind": 0, "tid": -1, "stuck": 0.0, "side": 0.0,
			"side_sign": 1.0 if randf() < 0.5 else -1.0,
		}
		next_uid += 1
		slot += 1


# ============================ SUNUCU SİMÜLASYONU ============================

func _physics_process(delta: float) -> void:
	if multiplayer.is_server() and started and not over:
		_sim(delta)
		tick += 1
		if tick % 2 == 0:
			snap = _make_snapshot()
			_snapshot.rpc(snap)
	send_acc += delta
	if send_acc >= SEND_INTERVAL and not snap.is_empty() and not over:
		send_acc = 0.0
		_send_input()


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
	for id in pl.keys():
		_update_player(id, pl[id], delta)
		if over:
			return
	for uid in units.keys():
		if units.has(uid):
			_update_unit(uid, units[uid], delta)
	_update_projectiles(delta)
	_update_flags(delta)


func _time_up() -> void:
	if scores[0] == scores[1]:
		sudden = true  # altın bayrak: ilk alan kazanır
		_feed.rpc("Süre doldu! Altın bayrak: ilk alan kazanır")
	else:
		_finish(0 if scores[0] > scores[1] else 1)


func _finish(winner: int) -> void:
	if over:
		return
	over = true
	_battle_over.rpc(winner, scores, losses)


func _update_player(id: int, p: Dictionary, dt: float) -> void:
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


func _unit_rect(c: Vector2) -> Rect2:
	return Rect2(c - Vector2(UHALF, UHALF), Vector2(USIZE, USIZE))


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
	p.atk_vis = 0.15
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
	t.hp -= amount * (1.0 - t.armor)
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
	u.hp -= amount
	if u.hp <= 0.0:
		if not losses.has(u.owner):
			losses[u.owner] = []
		losses[u.owner].append(u.type)  # kalıcı kayıp
		units.erase(uid)


func _damage_wall(wall: Dictionary, amount: float) -> void:
	wall.hp -= amount
	if wall.hp <= 0.0:
		walls.erase(wall)


func _update_projectiles(dt: float) -> void:
	for pr in projectiles.duplicate():
		pr.pos += pr.vel * dt
		pr.life -= dt
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
				if u.team != pr.team and _unit_rect(u.pos).grow(1.5).has_point(pr.pos):
					_damage_unit(uid, pr.dmg)
					hit = true
					break
		if hit:
			projectiles.erase(pr)


# --- Birim zekâsı ---

func _update_unit(uid: int, u: Dictionary, dt: float) -> void:
	if not pl.has(u.owner):
		units.erase(uid)
		return
	var owner_p: Dictionary = pl[u.owner]
	var cmd: int = owner_p.cmd
	var t: Dictionary = UNIT_TYPES[u.type]
	var spd: float = t.speed * speed_mul
	u.cd = maxf(0.0, u.cd - dt)
	u.retarget -= dt
	if u.tkind != 0 and not _target_valid(u):
		u.tkind = 0
	if u.retarget <= 0.0:
		u.retarget = 0.25
		_unit_retarget(u, owner_p, cmd)

	if u.tkind != 0:
		var tp: Vector2 = _target_pos(u)
		if cmd == 0 and tp.distance_to(owner_p.pos) > UNIT_LEASH * 1.4:
			u.tkind = 0  # Takip modunda çok uzağa kovalamaz
		elif u.pos.distance_to(tp) <= t.range:
			_unit_attack(u, t, tp)
			return
		else:
			_unit_step(u, tp, spd, dt, t.range * 0.8)
			return
	# Hedef yok: komuta göre git
	match cmd:
		0:  # Takip: kahramanın etrafında formasyon
			var slot_pos: Vector2 = owner_p.pos + Vector2.from_angle(float(u.slot) * TAU / 4.0 + 0.5) * 22.0
			_unit_step(u, slot_pos, spd, dt, 5.0)
		1:  # Saldır: imlece
			_unit_step(u, owner_p.cur, spd, dt, 10.0)
		2:  # Bayrak: düşman bayrağına (kendi bayrağı çalındıysa taşıyanı kovala)
			_unit_step(u, _flag_goal(u.team), spd, dt, 12.0)


func _flag_goal(team: int) -> Vector2:
	var own: Dictionary = flags[team]
	if own.state == 1 and pl.has(own.carrier):
		return pl[own.carrier].pos  # bayrağımızı taşıyanı durdur
	return flags[1 - team].pos


func _target_valid(u: Dictionary) -> bool:
	if u.tkind == 1:
		return pl.has(u.tid) and pl[u.tid].alive
	return units.has(u.tid)


func _target_pos(u: Dictionary) -> Vector2:
	if u.tkind == 1:
		return pl[u.tid].pos
	return units[u.tid].pos


func _unit_retarget(u: Dictionary, owner_p: Dictionary, cmd: int) -> void:
	var best := 1.0e9
	var kind := 0
	var tid := -1
	var radius: float = UNIT_AGGRO[cmd]
	for hid in pl.keys():
		var h: Dictionary = pl[hid]
		if h.team == u.team or not h.alive:
			continue
		var d: float = u.pos.distance_to(h.pos)
		if d < best and d <= radius and (cmd != 0 or h.pos.distance_to(owner_p.pos) <= UNIT_LEASH):
			best = d
			kind = 1
			tid = hid
	for eid in units.keys():
		var e: Dictionary = units[eid]
		if e.team == u.team:
			continue
		var d2: float = u.pos.distance_to(e.pos)
		if d2 < best and d2 <= radius and (cmd != 0 or e.pos.distance_to(owner_p.pos) <= UNIT_LEASH):
			best = d2
			kind = 2
			tid = eid
	u.tkind = kind
	u.tid = tid


func _unit_attack(u: Dictionary, t: Dictionary, tp: Vector2) -> void:
	if u.cd > 0.0:
		return
	u.cd = t.cd
	if t.ranged:
		var dir: Vector2 = (tp - u.pos).normalized()
		var speed := ARROW_SPEED * 0.8
		projectiles.append({"pos": u.pos, "vel": dir * speed, "team": u.team, "dmg": t.dmg,
			"life": t.range / speed + 0.15, "by": u.owner})
	elif u.tkind == 1:
		_damage(u.tid, t.dmg, u.owner)
	else:
		_damage_unit(u.tid, t.dmg)


## Hedefe doğru adım atar; engele takılırsa yan yürüyerek kurtulmaya çalışır.
func _unit_step(u: Dictionary, goal: Vector2, spd: float, dt: float, stop_dist: float) -> void:
	var d: Vector2 = goal - u.pos
	var dist := d.length()
	if dist <= stop_dist:
		u.stuck = 0.0
		return
	var dir := d / dist
	if u.side > 0.0:
		u.side -= dt
		dir = dir.rotated(u.side_sign * PI * 0.5)
	var step := minf(spd * dt, dist)
	var before: Vector2 = u.pos
	var nx: Vector2 = u.pos + Vector2(dir.x * step, 0.0)
	if not _rect_blocked(_unit_rect(nx)):
		u.pos = nx
	var ny: Vector2 = u.pos + Vector2(0.0, dir.y * step)
	if not _rect_blocked(_unit_rect(ny)):
		u.pos = ny
	if before.distance_to(u.pos) < step * 0.3:
		u.stuck += dt
		if u.stuck > 0.2 and u.side <= 0.0:
			u.side = 0.5
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


func _name_of(id: int) -> String:
	return Net.players.get(id, {}).get("name", "?")


# --- İstemciden gelen girdiler ---

@rpc("any_peer", "unreliable")
func _srv_input(mv: Vector2, aim: float, atk: bool, cur: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	inputs[id] = {"mv": mv.limit_length(1.0), "aim": aim, "atk": atk,
		"cur": cur.clamp(Vector2.ZERO, ARENA.size)}


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
		"team": p.team, "kind": kind})


# --- Herkese yayılanlar ---

func _make_snapshot() -> Dictionary:
	var unit_counts := {}
	var us := []
	for uid in units.keys():
		var u: Dictionary = units[uid]
		unit_counts[u.owner] = unit_counts.get(u.owner, 0) + 1
		us.append([uid, u.pos.x, u.pos.y, u.hp, u.max_hp, u.team, UNIT_ORDER.find(u.type), u.owner])
	var ps := {}
	for id in pl.keys():
		var p: Dictionary = pl[id]
		ps[id] = [p.pos.x, p.pos.y, p.hp, p.max_hp, p.team, p.alive, p.carrying, p.aim,
			p.weapons[p.wsel], p.atk_vis, p.respawn, p.walls.size(), p.cmd, unit_counts.get(id, 0)]
	var fl := []
	for f in flags:
		fl.append([f.pos.x, f.pos.y, f.state])
	var prs := []
	for pr in projectiles:
		prs.append([pr.pos.x, pr.pos.y, pr.team])
	var ws := []
	for w in walls:
		ws.append([w.rect.position.x, w.rect.position.y, w.hp, w.max, w.team])
	return {"p": ps, "u": us, "f": fl, "pr": prs, "w": ws, "t": time_left, "s": scores.duplicate(),
		"cd": countdown, "sd": sudden}


@rpc("authority", "unreliable")
func _snapshot(s: Dictionary) -> void:
	snap = s


@rpc("authority", "call_local", "reliable")
func _feed(text: String) -> void:
	feed.append([text, 5.0])
	if feed.size() > 5:
		feed.pop_front()


@rpc("authority", "call_local", "reliable")
func _battle_over(winner: int, final_scores: Array, lost: Dictionary) -> void:
	over = true
	camera.enabled = false  # sonuç ekranı kamerayla kaymasın
	for id in lost.keys():
		Game.remove_units(id, lost[id])  # ölen birimler kalıcı olarak gider
	if is_auto:
		var counts := {}
		for id in Net.players.keys():
			counts[id] = Game.unit_count(id)
		print("[battle] kayıplar=", lost, " kalan birim sayıları=", counts)
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
	if multiplayer.is_server():
		inputs[1] = {"mv": mv.limit_length(1.0), "aim": aim, "atk": atk,
			"cur": cur.clamp(Vector2.ZERO, ARENA.size)}
	else:
		_srv_input.rpc_id(1, mv, aim, atk, cur)


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
			res.atk = mypos.distance_to(target) < 30.0
	if bot_kill_done:
		if me[6] >= 0:
			target = FLAG_HOME[0]
		else:
			target = Vector2(snap.f[1][0], snap.f[1][1])
	var d := target - mypos
	res.aim = d.angle()
	res.cur = target
	if d.length() > 14.0 or bot_kill_done:
		res.mv = d.normalized() if d.length() > 2.0 else Vector2.ZERO
	return res


func _process(delta: float) -> void:
	if snap.is_empty():
		return
	var k := 1.0 - exp(-delta * 25.0)
	for id in snap.p.keys():
		var a: Array = snap.p[id]
		var target := Vector2(a[0], a[1])
		if not view_pos.has(id) or view_pos[id].distance_to(target) > 60.0:
			view_pos[id] = target
		else:
			view_pos[id] = view_pos[id].lerp(target, k)
	var new_u := {}
	for a in snap.u:
		var target := Vector2(a[1], a[2])
		var old: Vector2 = view_u.get(a[0], target)
		new_u[a[0]] = target if old.distance_to(target) > 40.0 else old.lerp(target, k)
	view_u = new_u
	if snap.p.has(my_id) and not over:
		camera.position = view_pos[my_id].round()
	for entry in feed:
		entry[1] -= delta
	feed = feed.filter(func(e): return e[1] > 0.0)
	queue_redraw()
	hud.queue_redraw()


# ============================ ÇİZİM ============================

func _tint(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


func _text(canvas: CanvasItem, pos: Vector2, text: String, size: int, color: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	canvas.draw_string(ThemeDB.fallback_font, pos, text, align, width, size, color)


func _draw() -> void:
	draw_rect(ARENA, Color(0.16, 0.2, 0.16))
	for t in 2:
		var bx := 0.0 if t == 0 else ARENA.size.x - BASE_W
		draw_rect(Rect2(bx, 0.0, BASE_W, ARENA.size.y), _tint(TEAM_COLORS[t], 0.14))
	for o in OBSTACLES:
		draw_rect(o, Color(0.38, 0.38, 0.42))
	if snap.is_empty():
		return

	for w in snap.w:
		var wr := Rect2(w[0], w[1], WALL_SIZE, WALL_SIZE)
		draw_rect(wr, Color(0.55, 0.4, 0.25) if w[3] <= 40.0 else Color(0.6, 0.6, 0.65))
		draw_rect(wr, _tint(TEAM_COLORS[w[4]], 0.9), false, 1.0)
		draw_rect(Rect2(w[0], w[1] - 3.0, WALL_SIZE * w[2] / w[3], 1.5), Color(0.3, 1.0, 0.3))

	for t in 2:
		var f: Array = snap.f[t]
		var fp := Vector2(f[0], f[1])
		if f[2] == 0:
			draw_arc(fp, 8.0, 0.0, TAU, 12, _tint(TEAM_COLORS[t], 0.5), 1.0)
		draw_rect(Rect2(fp.x - 1.0, fp.y - 14.0, 2.0, 16.0), Color(0.9, 0.9, 0.9))
		draw_rect(Rect2(fp.x + 1.0, fp.y - 14.0, 9.0, 7.0), TEAM_COLORS[t])

	# Birimler (küçük, soluk)
	for a in snap.u:
		var upos: Vector2 = view_u.get(a[0], Vector2(a[1], a[2]))
		var ucol: Color = TEAM_COLORS[a[5]].darkened(0.25)
		draw_rect(Rect2(upos.x - UHALF, upos.y - UHALF, USIZE, USIZE), ucol)
		if a[6] == 1:  # okçu: ortada açık nokta
			draw_rect(Rect2(upos.x - 1.0, upos.y - 1.0, 2.0, 2.0), Color(1, 1, 1, 0.85))
		if a[3] < a[4]:
			draw_rect(Rect2(upos.x - UHALF, upos.y - 6.0, USIZE * a[3] / a[4], 1.0), Color(0.3, 1.0, 0.3))

	for pr in snap.pr:
		draw_rect(Rect2(pr[0] - 1.5, pr[1] - 1.5, 3.0, 3.0), Color(1.0, 0.95, 0.5))

	# Kahramanlar (büyük, belirgin, isimli)
	for id in snap.p.keys():
		var a: Array = snap.p[id]
		var pos: Vector2 = view_pos.get(id, Vector2(a[0], a[1]))
		var col: Color = TEAM_COLORS[a[4]]
		if not a[5]:
			draw_line(pos - Vector2(5, 5), pos + Vector2(5, 5), _tint(col, 0.5), 1.0)
			draw_line(pos - Vector2(5, -5), pos + Vector2(5, -5), _tint(col, 0.5), 1.0)
			continue
		draw_rect(Rect2(pos.x - HALF, pos.y - HALF, PSIZE, PSIZE), col)
		var outline := Color.WHITE if id == my_id else Color(0.05, 0.05, 0.08)
		draw_rect(Rect2(pos.x - HALF - 1.0, pos.y - HALF - 1.0, PSIZE + 2.0, PSIZE + 2.0), outline, false, 1.0)
		var dir := Vector2.from_angle(a[7])
		draw_line(pos, pos + dir * 12.0, Color.WHITE, 1.0)
		if a[9] > 0.0:
			var reach: float = WEAPONS[a[8]].range
			if reach > 0.0:
				draw_arc(pos, reach, a[7] - deg_to_rad(60.0), a[7] + deg_to_rad(60.0), 8, Color(1, 1, 1, 0.8), 1.0)
		draw_rect(Rect2(pos.x - 8.0, pos.y - 13.0, 16.0, 2.0), Color(0.3, 0.05, 0.05))
		draw_rect(Rect2(pos.x - 8.0, pos.y - 13.0, 16.0 * clampf(a[2] / a[3], 0.0, 1.0), 2.0), Color(0.3, 1.0, 0.3))
		if a[6] >= 0:
			draw_rect(Rect2(pos.x - 1.0, pos.y - 24.0, 8.0, 6.0), TEAM_COLORS[a[6]])
		_text(self, pos + Vector2(-24, -16), _name_of(id), 8, _tint(Color.WHITE, 0.85), 48.0, HORIZONTAL_ALIGNMENT_CENTER)

	# Saldır komutundayken imleç işareti
	if snap.p.has(my_id) and snap.p[my_id][12] == 1:
		var c := get_global_mouse_position()
		draw_arc(c, 6.0, 0.0, TAU, 10, Color(1, 1, 1, 0.6), 1.0)


func _draw_hud() -> void:
	if snap.is_empty():
		_text(hud, Vector2(0, 180), "Savaş yükleniyor...", 14, Color.WHITE, VIEW.x, HORIZONTAL_ALIGNMENT_CENTER)
		return
	hud.draw_rect(Rect2(0, 0, VIEW.x, 16), Color(0, 0, 0, 0.45))
	var secs := ceili(snap.t)
	var clock := "ALTIN BAYRAK" if snap.sd else "%d:%02d" % [secs / 60, secs % 60]
	_text(hud, Vector2(0, 12), "%s %d  -  %d %s     %s" % [Net.TEAM_NAMES[0], snap.s[0], snap.s[1], Net.TEAM_NAMES[1], clock],
		11, Color.WHITE, VIEW.x, HORIZONTAL_ALIGNMENT_CENTER)
	if snap.cd > 0.0:
		_text(hud, Vector2(0, 150), "HAZIRLAN: %d" % ceili(snap.cd), 20, Color.WHITE, VIEW.x, HORIZONTAL_ALIGNMENT_CENTER)
		_text(hud, Vector2(0, 172), "WASD hareket · sol tık saldırı · Q silah · E duvar", 10, Color(1, 1, 1, 0.85), VIEW.x, HORIZONTAL_ALIGNMENT_CENTER)
		_text(hud, Vector2(0, 186), "1 Takip · 2 Saldır (imlece) · 3 Bayrak  (birliğin için)", 10, Color(1, 1, 1, 0.85), VIEW.x, HORIZONTAL_ALIGNMENT_CENTER)
	if snap.p.has(my_id):
		var me: Array = snap.p[my_id]
		hud.draw_rect(Rect2(0, 340, 400, 20), Color(0, 0, 0, 0.45))
		_text(hud, Vector2(6, 354), "%s   Can %d/%d   Duvar: %d   Birlik: %d (%s)" % [
			WEAPONS[me[8]].name, ceili(me[2]), me[3], me[11], me[13], CMD_NAMES[me[12]]], 10, Color.WHITE)
		if not me[5]:
			_text(hud, Vector2(0, 170), "Yeniden doğuyorsun: %d" % ceili(me[10]), 14, Color.WHITE, VIEW.x, HORIZONTAL_ALIGNMENT_CENTER)
	var y := 28.0
	for e in feed:
		_text(hud, Vector2(0, y), e[0], 10, Color(1, 1, 1, clampf(e[1], 0.0, 1.0)), 634.0, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 11.0
	_draw_minimap()


func _draw_minimap() -> void:
	var s := 0.1
	var origin := Vector2(VIEW.x - ARENA.size.x * s - 4.0, VIEW.y - ARENA.size.y * s - 4.0)
	hud.draw_rect(Rect2(origin, ARENA.size * s), Color(0, 0, 0, 0.55))
	for t in 2:
		var bx := 0.0 if t == 0 else ARENA.size.x - BASE_W
		hud.draw_rect(Rect2(origin + Vector2(bx, 0.0) * s, Vector2(BASE_W, ARENA.size.y) * s), _tint(TEAM_COLORS[t], 0.2))
	for o in OBSTACLES:
		hud.draw_rect(Rect2(origin + o.position * s, o.size * s), Color(0.5, 0.5, 0.55))
	for f in snap.f:
		hud.draw_rect(Rect2(origin + Vector2(f[0], f[1]) * s - Vector2(1, 1), Vector2(3, 3)), Color(1, 1, 0.4))
	for a in snap.u:
		hud.draw_rect(Rect2(origin + Vector2(a[1], a[2]) * s, Vector2(1, 1)), TEAM_COLORS[a[5]])
	for id in snap.p.keys():
		var a: Array = snap.p[id]
		if a[5]:
			hud.draw_rect(Rect2(origin + Vector2(a[0], a[1]) * s - Vector2(1, 1), Vector2(3, 3)),
				Color.WHITE if id == my_id else TEAM_COLORS[a[4]])
	var cc := camera.get_screen_center_position()
	hud.draw_rect(Rect2(origin + (cc - VIEW * 0.5) * s, VIEW * s), Color(1, 1, 1, 0.5), false, 1.0)
