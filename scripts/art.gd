extends Node
## Sprite yükleyici (autoload: Art). Sprite "paketleri":
##   1. "custom"     -> assets/custom/ (özgün, repoda, tools/make_sprites.py üretir)
##   2. "tinyswords" -> assets/tinyswords/ (Pixel Frog; lisansı yüzünden repoda YOK, assets/README.md)
##   3. "none"       -> hiçbiri yoksa `available` false: oyun eski kutu çizimine döner.
## Sprite'lar çalışma anında diskten okunur (editörde içe aktarma gerekmez).
## Test için paket zorlanabilir: komut satırı kullanıcı argümanı `pack=none|custom|tinyswords`.

const PACKS := {
	"custom": {
		"root": "res://assets/custom/",
		"check": "units/blue/warrior_idle.png",
		"scale": 2.0 / 3.0,       # sanat pikseli -> dünya birimi (1080p'de tam 2 ekran pikseli)
		"hero_scale": 2.0 / 3.0,
		"unit_scale": 2.0 / 3.0,
		"foot": 0.88,             # karakter ayağının kare yüksekliğine oranı (sprite çizim hizası)
		"unit_foot": 0.84,
		"hero_top": 21.0,         # kahramanın üstündeki can çubuğu boşluğu (dünya birimi)
		"unit_sprite": {"unit_swordsman": "u_swordsman", "unit_archer": "u_archer",
			"unit_artillery": "u_cannon", "unit_shieldbearer": "u_shield", "unit_healer": "u_healer"},
		"attack": {"warrior": "attack", "archer": "attack", "lancer": "attack"},
	},
	"tinyswords": {
		"root": "res://assets/tinyswords/",
		"check": "units/blue/warrior_idle.png",
		"scale": 1.0 / 3.0,
		"hero_scale": 1.0 / 3.0,
		"unit_scale": 1.0 / 6.0,
		"foot": 0.66,
		"unit_foot": 0.66,
		"hero_top": 27.0,
		"unit_sprite": {"unit_swordsman": "warrior", "unit_archer": "archer",
			"unit_artillery": "pawn", "unit_shieldbearer": "lancer"},
		"attack": {"warrior": "attack1", "archer": "shoot", "lancer": "right_attack", "pawn": "idle", "monk": "heal"},
	},
}
const PACK_ORDER := ["custom", "tinyswords"]
## Silah -> kahramanın görünümü (yay = okçu, mızrak = mızrakçı, diğerleri = savaşçı)
const WEAPON_SPRITE := {"fist": "warrior", "sword": "warrior", "spear": "lancer", "bow": "archer"}
const TEAM_DIR := ["blue", "red"]

var available := false        # herhangi bir sprite paketi var mı
var custom := false           # özgün paket mi
var pack := "none"
var root := ""
var _meta: Dictionary = {}
var _cache: Dictionary = {}
var _grass: Texture2D
var _ground: Texture2D
var _ground_key := ""


func _ready() -> void:
	var want := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("pack="):
			want = a.substr(5)
	for p in PACK_ORDER:
		if want != "" and want != p:
			continue
		if FileAccess.file_exists(PACKS[p].root + PACKS[p].check):
			set_pack(p)
			return
	set_pack("none")


func set_pack(p: String) -> void:
	pack = p
	_cache.clear()
	_grass = null
	_ground = null
	_ground_key = ""
	available = p != "none"
	custom = p == "custom"
	_meta = PACKS.get(p, {})
	root = _meta.get("root", "")


func tex(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var t: Texture2D = null
	if root != "" and FileAccess.file_exists(root + path):
		var img := Image.load_from_file(root + path)
		if img != null:
			t = ImageTexture.create_from_image(img)
	_cache[path] = t
	return t


func unit_tex(team: int, unit: String, anim: String) -> Texture2D:
	return tex("units/%s/%s_%s.png" % [TEAM_DIR[team], unit, anim])


## Birim eşya id'sinden sprite adı ("" = bu pakette yok, kutu çizimine dönülür).
func unit_sprite(item_id: String) -> String:
	return _meta.get("unit_sprite", {}).get(item_id, "")


func attack_anim(sprite: String) -> String:
	return _meta.get("attack", {}).get(sprite, "idle")


func hero_scale() -> float:
	return _meta.get("hero_scale", 1.0 / 3.0)


func unit_scale() -> float:
	return _meta.get("unit_scale", 1.0 / 6.0)


func world_scale() -> float:
	return _meta.get("scale", 1.0 / 3.0)


func hero_top() -> float:
	return _meta.get("hero_top", 27.0)


## Çimen döşemesi (Tiny Swords): büyük çimen bloğunun ortasından 64x64'lük saf çimen kesiti.
func grass() -> Texture2D:
	if _grass != null:
		return _grass
	var atlas := tex("terrain/tilemap_color1.png")
	if atlas == null:
		return null
	_grass = ImageTexture.create_from_image(atlas.get_image().get_region(Rect2i(64, 64, 64, 64)))
	return _grass


## Kare sayısı: kareler kare şeklindedir (genişlik / yükseklik).
func frame_count(t: Texture2D) -> int:
	return maxi(1, t.get_width() / t.get_height())


## Animasyon karesini çizer. `foot`: karakterin ayak noktası (kare, buna göre hizalanır).
## `scale`: dünya birimi / sprite pikseli. `flip`: sola bakış.
func draw_frame(canvas: CanvasItem, t: Texture2D, frame: int, foot: Vector2, scale: float, flip: bool, tint := Color.WHITE, foot_frac := -1.0) -> void:
	var fs := t.get_height()
	var size := Vector2(fs, fs) * scale
	if foot_frac < 0.0:
		foot_frac = _meta.get("foot", 0.66)
	if custom:  # piksel kalınlığı tutarlı kalsın: ayak noktası ekran pikseline oturur (1 dünya birimi = 3 piksel)
		foot = (foot * 3.0).round() / 3.0
	canvas.draw_set_transform(foot, 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
	canvas.draw_texture_rect_region(t, Rect2(Vector2(-size.x * 0.5, -size.y * foot_frac), size),
		Rect2(frame * fs, 0, fs, fs), tint)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- özgün paket: dünya nesneleri

## Bir şeridin tek karesini ayrı doku olarak keser (önbellekli). Kare genişliği = `w`.
func _cell(path: String, i: int, w: int) -> Texture2D:
	var key := "%s#%d" % [path, i]
	if _cache.has(key):
		return _cache[key]
	var t: Texture2D = null
	var strip := tex(path)
	if strip != null:
		t = ImageTexture.create_from_image(strip.get_image().get_region(Rect2i(i * w, 0, w, strip.get_height())))
	_cache[key] = t
	return t


## Arena zemini: çimen (3 çeşit) + toprak yol + çarpışmasız süsler, bir kez tek dokuya pişirilir.
func ground(arena: Rect2, obstacles: Array) -> Texture2D:
	var key := "%s|%d" % [str(arena), obstacles.size()]
	if _ground != null and _ground_key == key:
		return _ground
	var g_strip := tex("terrain/grass.png")
	var d_strip := tex("terrain/dirt.png")
	if g_strip == null or d_strip == null:
		return null
	var s := world_scale()
	var cols := ceili(arena.size.x / s / 16.0)
	var rows := ceili(arena.size.y / s / 16.0)
	var img := Image.create(cols * 16, rows * 16, false, Image.FORMAT_RGBA8)
	var gi := g_strip.get_image()
	var di := d_strip.get_image()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260101
	var mid := rows / 2
	for cy in rows:
		for cx in cols:
			var wob := int(round(sin(float(cx) * 0.22) * 1.6 + sin(float(cx) * 0.07) * 1.0))
			var on_path := absi(cy - mid - wob) <= 1
			var v := rng.randi() % 3
			if on_path:
				img.blit_rect(di, Rect2i((rng.randi() % 2) * 16, 0, 16, 16), Vector2i(cx * 16, cy * 16))
			else:
				img.blit_rect(gi, Rect2i(v * 16, 0, 16, 16), Vector2i(cx * 16, cy * 16))
	# süsler: engellerden ve yoldan uzak, alçak/küçük, hepsi aynı çarpışmasız görünüm
	var dec_strip := tex("terrain/decor.png")
	if dec_strip != null:
		var dec := dec_strip.get_image()
		for _i in 110:
			var p := Vector2(rng.randf_range(8.0, arena.size.x - 8.0), rng.randf_range(8.0, arena.size.y - 8.0))
			var ok := true
			for o in obstacles:
				if (o as Rect2).grow(14.0).has_point(p):
					ok = false
					break
			var ccx := int(p.x / s / 16.0)
			var wob2 := int(round(sin(float(ccx) * 0.22) * 1.6 + sin(float(ccx) * 0.07) * 1.0))
			if absi(int(p.y / s / 16.0) - mid - wob2) <= 2:
				ok = false
			if ok:
				var f := rng.randi() % 5
				img.blend_rect(dec, Rect2i(f * 12, 0, 12, 12), Vector2i(int(p.x / s) - 6, int(p.y / s) - 10))
	_ground = ImageTexture.create_from_image(img)
	_ground_key = key
	return _ground


func draw_ground(canvas: CanvasItem, arena: Rect2, obstacles: Array) -> void:
	var t := ground(arena, obstacles)
	var s := world_scale()
	if t == null:
		canvas.draw_rect(arena, Color(0.16, 0.2, 0.16))
		return
	canvas.draw_texture_rect_region(t, arena, Rect2(Vector2.ZERO, arena.size / s))


func draw_castle(canvas: CanvasItem, team: int, home: Vector2) -> void:
	var t := tex("buildings/%s_castle.png" % TEAM_DIR[team])
	if t == null:
		return
	var size := Vector2(t.get_width(), t.get_height()) * world_scale()
	canvas.draw_texture_rect(t, Rect2(home - Vector2(size.x * 0.5, size.y * 1.1), size), false)


## Taş engel: yinelenen taş döşemesi + koyu çerçeve.
func draw_obstacle(canvas: CanvasItem, o: Rect2) -> void:
	var t := _cell("terrain/stone.png", 0, 16)
	var s := world_scale()
	if t == null:
		canvas.draw_rect(o, Color(0.38, 0.38, 0.42))
		return
	canvas.draw_set_transform(o.position, 0.0, Vector2(s, s))
	canvas.draw_texture_rect(t, Rect2(Vector2.ZERO, o.size / s), true)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	canvas.draw_rect(o, Color(0.1, 0.08, 0.14), false, 1.0)


func draw_wall(canvas: CanvasItem, r: Rect2, stone: bool) -> bool:
	var t := tex("fx/wall_stone.png" if stone else "fx/wall_wood.png")
	if t == null:
		return false
	canvas.draw_texture_rect(t, r, false)
	return true


## Direkli bayrak (dalgalanma 4 kare). `fp`: direğin dibi.
func draw_flag(canvas: CanvasItem, team: int, fp: Vector2) -> bool:
	var t := tex("buildings/%s_flag.png" % TEAM_DIR[team])
	if t == null:
		return false
	var s := world_scale()
	var frame := int(Time.get_ticks_msec() / 140) % 4
	var origin := ((fp + Vector2(0.0, 2.0)) * 3.0).round() / 3.0 - Vector2(3.5, 38.0) * s
	canvas.draw_texture_rect_region(t, Rect2(origin, Vector2(24.0, 40.0) * s), Rect2(frame * 24, 0, 24, 40))
	return true


## Mermi: `angle` hareket yönü (radyan). Ok yöne göre döner, top dönmez. Özgün pakette fx/arrow.png,
## Tiny Swords'ta units/<takım>/archer_arrow.png (ikisi de sağa bakar). Doku yoksa false (kutu yedeği çizer).
func draw_projectile(canvas: CanvasItem, pos: Vector2, team: int, ball: bool, angle := 0.0) -> bool:
	var t: Texture2D
	var sc := world_scale()
	if ball:
		t = tex("fx/ball.png")
	elif custom:
		t = tex("fx/arrow.png")
	else:
		t = tex("units/%s/archer_arrow.png" % TEAM_DIR[team])
		sc = 1.0 / 5.0
	if t == null:
		return false
	var size := Vector2(t.get_width(), t.get_height()) * sc
	canvas.draw_set_transform(pos, 0.0 if ball else angle, Vector2.ONE)
	canvas.draw_texture_rect(t, Rect2(-size * 0.5, size), false)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


## Patlama: `k` 1 (yeni) -> 0 (bitti); 4 kare.
func draw_boom(canvas: CanvasItem, pos: Vector2, radius: float, k: float) -> bool:
	var t := tex("fx/boom.png")
	if t == null:
		return false
	var frame := clampi(int((1.0 - k) * 4.0), 0, 3)
	var side := maxf(radius * 2.4, 16.0)
	canvas.draw_texture_rect_region(t, Rect2(pos - Vector2(side, side) * 0.5, Vector2(side, side)),
		Rect2(frame * 32, 0, 32, 32))
	return true


func get_meta_value(key: String) -> float:
	return _meta.get(key, -1.0)
