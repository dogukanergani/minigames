extends RefCounted
## Minigame'lerin ortak görsel yardımcıları (yalnızca çizim, oyun mantığı yok).
## Kullanım: const MgArt = preload("res://minigames/mg_art.gd")
## Dokular assets/custom/minigame/ altından çalışma anında okunur (tools/make_minigame_art.py üretir).
## Sprite paketi yoksa (`Art.available` false, ör. `pack=none`) ya da dosya eksikse `ok()` false döner
## ve minigame'ler eski düz çizime düşer.

const UiTheme = preload("res://scripts/ui_theme.gd")

const DIR := "res://assets/custom/minigame/"
## Büyük pixel yazı tipi: tools/make_minigame_art.py FONT_CHARS / CELL_W / CELL_H ile AYNI.
const FONT_CHARS := " 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZÇĞİÖŞÜ!?.:-+/%"
const CELL := Vector2(13, 23)
const ADV := 12.0          # karakter ilerlemesi (sanat pikseli)
const BODY_MID := 11.0     # gövdenin dikey ortası (hücre içinde, sanat pikseli)
const PX := 2.0 / 3.0      # 1 sanat pikseli = 2/3 dünya birimi (1080p'de 2 ekran pikseli)
const BAND_H := 18.0       # üst başlık bandı yüksekliği (dünya birimi)

static var _cache: Dictionary = {}


static func tex(name: String) -> Texture2D:
	if not Art.available:
		return null
	if _cache.has(name):
		return _cache[name]
	var t: Texture2D = null
	var path := DIR + name + ".png"
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null:
			t = ImageTexture.create_from_image(img)
	_cache[name] = t
	return t


## Yeni görünüm kullanılabilir mi (paket var ve minigame dokuları üretilmiş).
static func ok() -> bool:
	return tex("font") != null and Art.unit_tex(0, "warrior", "idle") != null


# ---------------------------------------------------------------- büyük pixel yazı

## Büyük yazının dünya birimi cinsinden genişliği (`sc`: dünya birimi / sanat pikseli).
static func text_w(s: String, sc: float) -> float:
	return (s.length() * ADV + 1.0) * sc


## Büyük pixel yazı. `pos`: hizalama noktası (yatayda `align`a göre sol/orta/sağ, dikeyde gövdenin ortası).
## Yalnızca büyük harf / rakam / FONT_CHARS içindeki işaretler. Yazı tipi yoksa yedek font.
static func text(ci: CanvasItem, s: String, pos: Vector2, sc: float, tint := Color.WHITE,
		align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var f := tex("font")
	var w := text_w(s, sc)
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	if f == null:
		var fs := int(maxf(8.0, 14.0 * sc))
		ci.draw_string_outline(ThemeDB.fallback_font, Vector2(x, pos.y + fs * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0.05, 0.04, 0.09))
		ci.draw_string(ThemeDB.fallback_font, Vector2(x, pos.y + fs * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tint)
		return
	var y := pos.y - BODY_MID * sc
	# piksel ızgarasına oturt (1 dünya birimi = 3 ekran pikseli)
	x = roundf(x * 3.0) / 3.0
	y = roundf(y * 3.0) / 3.0
	for ch in s:
		var i := FONT_CHARS.find(ch)
		if i > 0:
			ci.draw_texture_rect_region(f, Rect2(Vector2(x, y), CELL * sc), Rect2(Vector2(i * CELL.x, 0), CELL), tint)
		x += ADV * sc


## Küçük isim yazısı (yedek font, koyu dış çizgili).
static func small(ci: CanvasItem, s: String, pos: Vector2, size: int, col: Color, width := 80.0,
		align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var x := pos.x - (width * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else (width if align == HORIZONTAL_ALIGNMENT_RIGHT else 0.0))
	var font := ThemeDB.fallback_font
	ci.draw_string_outline(font, Vector2(x, pos.y), s, align, width, size, 3, Color(0.05, 0.04, 0.09, col.a))
	ci.draw_string(font, Vector2(x, pos.y), s, align, width, size, col)


# ---------------------------------------------------------------- şerit ve doku

## Şeridin `frame`. karesini ortası `center`da olacak şekilde çizer (`sc`: dünya birimi / sanat pikseli).
static func frame(ci: CanvasItem, t: Texture2D, frame_i: int, fw: int, center: Vector2, sc := PX, tint := Color.WHITE, flip := false) -> void:
	if t == null:
		return
	var size := Vector2(fw, t.get_height()) * sc
	var c := (center * 3.0).round() / 3.0
	ci.draw_set_transform(c, 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
	ci.draw_texture_rect_region(t, Rect2(-size * 0.5, size), Rect2(frame_i * fw, 0, fw, t.get_height()), tint)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Tam ekran arka plan (960x540 sanat pikseli = 640x360 dünya). Yoksa false.
static func background(ci: CanvasItem, name: String) -> bool:
	var t := tex(name)
	if t == null:
		return false
	ci.draw_texture_rect(t, Rect2(0, 0, 640, 360), false)
	return true


# ---------------------------------------------------------------- oyuncu

static func team_col(team: int) -> Color:
	return UiTheme.TEAM[clampi(team, 0, 1)]


static func ellipse(c: Vector2, rx: float, ry: float, n := 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in n + 1:
		var a := TAU * float(k) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


## Ayak halkası (savaştaki gibi): takım renginde; kendi karakterin altın çizgili, nabız atar.
static func ring(ci: CanvasItem, pos: Vector2, team: int, mine: bool, k := 1.0) -> void:
	var col := team_col(team)
	var c := pos + Vector2(0, 4.0)
	if mine:
		var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 1000.0 * 5.0)
		var rx := 11.0 + pulse * 1.5
		ci.draw_colored_polygon(ellipse(c, rx, rx * 0.5), Color(col.lightened(0.15), (0.35 + 0.15 * pulse) * k))
		ci.draw_polyline(ellipse(c, rx, rx * 0.5), Color(col.lightened(0.45), 0.95 * k), 2.0)
		ci.draw_polyline(ellipse(c, rx + 2.5, (rx + 2.5) * 0.5), Color(1.0, 0.85, 0.25, (0.55 + 0.4 * pulse) * k), 1.0)
	else:
		ci.draw_colored_polygon(ellipse(c, 9.0, 4.5), Color(col, 0.35 * k))
		ci.draw_polyline(ellipse(c, 9.0, 4.5), Color(col.lightened(0.3), k), 1.5)


## Başın üstünde: kendi karakterin altın taç, diğerleri takım renginde ok.
static func marker(ci: CanvasItem, p: Vector2, team: int, mine: bool) -> void:
	p.y += roundf(sin(float(Time.get_ticks_msec()) / 1000.0 * 4.0))
	var edge := Color(0.08, 0.05, 0.05)
	var pts: PackedVector2Array
	if mine:
		pts = PackedVector2Array([p + Vector2(-5, 0), p + Vector2(-5, -6), p + Vector2(-2.5, -3), p + Vector2(0, -7),
			p + Vector2(2.5, -3), p + Vector2(5, -6), p + Vector2(5, 0)])
		ci.draw_colored_polygon(pts, Color(1.0, 0.82, 0.2))
	else:
		pts = PackedVector2Array([p + Vector2(-4, -5), p + Vector2(4, -5), p + Vector2(0, 0)])
		ci.draw_colored_polygon(pts, team_col(team).lightened(0.2))
	pts.append(pts[0])
	ci.draw_polyline(pts, edge, 1.0)


## Kahraman (Savaşçı) sprite'ı: koşuyorsa koşu, değilse bekleme kareleri. `pos`: ayak noktası.
## `sc_mul`: boyut çarpanı (Refleks düellosunda 2). Doku yoksa false.
static func hero(ci: CanvasItem, team: int, anim: String, pos: Vector2, flip: bool, sc_mul := 1.0,
		tint := Color.WHITE, frame_i := -1, step_ms := 0.0) -> bool:
	var t := Art.unit_tex(clampi(team, 0, 1), "warrior", anim)
	if t == null:
		return false
	var n := Art.frame_count(t)
	if frame_i < 0:
		var ms := step_ms if step_ms > 0.0 else (90.0 if anim == "run" else 260.0)
		frame_i = int(float(Time.get_ticks_msec()) / ms) % n
	var foot: float = Art.foot_for(t, 32.0, Art.get_meta_value("foot")) if Art.custom else -1.0
	Art.draw_frame(ci, t, mini(frame_i, n - 1), pos, Art.hero_scale() * sc_mul, flip, tint, foot)
	return true


# ---------------------------------------------------------------- arayüz parçaları

## Koyu çerçeveli düz kutu (savaş HUD'u ile aynı palet).
static func plate(ci: CanvasItem, r: Rect2, fill: Color, rim := Color(0.5, 0.55, 0.7)) -> void:
	ci.draw_rect(r.grow(1.0), Color(0.05, 0.04, 0.09))
	ci.draw_rect(r, rim)
	ci.draw_rect(r.grow(-1.0), fill)
	ci.draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(r.size.x - 2.0, 1.0)), Color(fill.lightened(0.25), fill.a))


## Üst şerit: solda minigame adı (kırmızı-altın levha), sağda saat + kalan süre (son 5 sn kırmızı nabız).
## Levhalar dünyanın üstünde yüzer; arkada okunurluk için hafif karartma. `time_left` < 0 ise süre yok.
## Ortası alt sınıfa kalır (_draw_hud).
static func band(ci: CanvasItem, title: String, time_left: float) -> void:
	for i in 6:
		ci.draw_rect(Rect2(0, i * 3.0, 640, 3.0), Color(0.05, 0.03, 0.09, 0.42 - i * 0.07))
	var tw := text_w(title, PX)
	var r := Rect2(4, 2, tw + 10.0, 15)
	plate(ci, r, Color(0.62, 0.16, 0.18), UiTheme.GOLD)
	text(ci, title, Vector2(r.position.x + 5.0, 9.5), PX, Color(1.0, 0.95, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
	if time_left < 0.0:
		return
	var secs := ceili(time_left)
	var urgent := secs <= 5 and time_left > 0.0
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 1000.0 * TAU * 2.0)
	var col := UiTheme.GOLD_L
	var sc := PX
	if urgent:
		col = Color(1.0, 0.25, 0.25).lerp(Color(1.0, 0.8, 0.8), pulse * 0.6)
		sc = PX * 1.5 if pulse > 0.5 else PX
	var s := str(secs)
	var pr := Rect2(640 - 48, 2, 44, 15)
	plate(ci, pr, Color(0.45, 0.07, 0.1) if urgent else Color(0.11, 0.1, 0.17), Color(1.0, 0.35, 0.35) if urgent else Color(0.5, 0.55, 0.7))
	frame(ci, tex("clock"), 0, 12, Vector2(pr.position.x + 8.0, 9.5), PX)
	text(ci, s, Vector2(pr.end.x - 4.0, 9.5), sc, col, HORIZONTAL_ALIGNMENT_RIGHT)


## Son 5 saniye: ekran kenarında kırmızı nabız.
static func urgent_vignette(ci: CanvasItem, time_left: float) -> void:
	if time_left <= 0.0 or time_left > 5.0:
		return
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 1000.0 * TAU * 2.0)
	var a := 0.12 + 0.18 * pulse
	for i in 4:
		var w := 6.0 - i * 1.5
		var c := Color(0.9, 0.1, 0.12, a * (1.0 - i * 0.22))
		ci.draw_rect(Rect2(0, BAND_H + 2.0 + i * 2.0, 640, 2.0), c)
		ci.draw_rect(Rect2(0, 358 - i * 2.0, 640, 2.0), c)
		ci.draw_rect(Rect2(i * 2.0, BAND_H, 2.0, 360 - BAND_H), c)
		ci.draw_rect(Rect2(638 - i * 2.0, BAND_H, 2.0, 360 - BAND_H), c)
		if w < 0.0:
			break


## Büyük geri sayım: rakam büyüyüp yerine oturur, arkasında altın patlama. `since`: rakamın değiştiği andan bu yana (sn).
static func countdown(ci: CanvasItem, n: int, since: float, hint: String) -> void:
	var c := Vector2(320, 165)
	ci.draw_rect(Rect2(0, 0, 640, 360), Color(0.03, 0.02, 0.06, 0.35))
	var bf := clampi(int(since / 0.07), 0, 4)
	if bf < 4:
		frame(ci, tex("burst"), bf, 48, c, 3.0, Color(1, 1, 1, 0.9))
	var k := clampf(since / 0.18, 0.0, 1.0)
	var sc := lerpf(6.0, 4.0, k)
	text(ci, str(n), c + Vector2(4, 4), sc, Color(0, 0, 0, 0.35))
	text(ci, str(n), c, sc, UiTheme.GOLD_L if n > 1 else Color(1.0, 0.55, 0.3))
	if hint != "":
		var hr := Rect2(320 - 150, 222, 300, 16)
		plate(ci, hr, Color(0.09, 0.08, 0.15, 0.92))
		small(ci, hint, Vector2(320, 233), 9, Color(0.93, 0.92, 0.97), 296.0)


## "BAŞLA!" / "BİTTİ!" gibi büyük duyuru. `k`: 0 (yeni) -> 1 (sönmüş).
static func shout(ci: CanvasItem, s: String, k: float, col: Color, pos := Vector2(320, 165), size := 4.0) -> void:
	if k >= 1.0:
		return
	var a := 1.0 if k < 0.7 else 1.0 - (k - 0.7) / 0.3
	var bf := clampi(int(k * 8.0), 0, 4)
	if bf < 4:
		frame(ci, tex("burst"), bf, 48, pos, 4.0, Color(col.lightened(0.4), 0.8 * a))  # patlama yazının renginde
	var sc := size if k > 0.12 else lerpf(size * 1.5, size, k / 0.12)
	text(ci, s, pos + Vector2(3, 3), sc, Color(0, 0, 0, 0.35 * a))
	text(ci, s, pos, sc, Color(col, a))
