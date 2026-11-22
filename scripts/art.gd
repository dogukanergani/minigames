extends Node
## Sprite yükleyici (autoload: Art).
## Tiny Swords (Pixel Frog) sprite'ları assets/tinyswords/ altında durur; lisansı yeniden
## dağıtımı yasakladığı için GitHub'a konmaz (assets/README.md). Dosyalar yoksa `available`
## false olur ve oyun eski kutu çizimine döner. Sprite'lar çalışma anında diskten okunur
## (editörde içe aktarma gerekmez).

const ROOT := "res://assets/tinyswords/"

## Birim item id'si -> sprite birimi
const UNIT_SPRITE := {
	"unit_swordsman": "warrior",
	"unit_archer": "archer",
	"unit_artillery": "pawn",
	"unit_shieldbearer": "lancer",
}
## Silah -> kahramanın görünümü (yay = okçu, mızrak = mızrakçı, diğerleri = savaşçı)
const WEAPON_SPRITE := {"fist": "warrior", "sword": "warrior", "spear": "lancer", "bow": "archer"}
## Saldırı animasyonu dosya adı eki
const ATTACK_ANIM := {"warrior": "attack1", "archer": "shoot", "lancer": "right_attack", "pawn": "idle", "monk": "heal"}
const TEAM_DIR := ["blue", "red"]

var available := false
var _cache: Dictionary = {}
var _grass: Texture2D


func _ready() -> void:
	available = FileAccess.file_exists(ROOT + "units/blue/warrior_idle.png")


func tex(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var t: Texture2D = null
	if FileAccess.file_exists(ROOT + path):
		var img := Image.load_from_file(ROOT + path)
		if img != null:
			t = ImageTexture.create_from_image(img)
	_cache[path] = t
	return t


func unit_tex(team: int, unit: String, anim: String) -> Texture2D:
	return tex("units/%s/%s_%s.png" % [TEAM_DIR[team], unit, anim])


## Çimen döşemesi: büyük çimen bloğunun ortasından 64x64'lük saf çimen kesiti (yan yana döşenir).
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
func draw_frame(canvas: CanvasItem, t: Texture2D, frame: int, foot: Vector2, scale: float, flip: bool, tint := Color.WHITE) -> void:
	var fs := t.get_height()
	var size := Vector2(fs, fs) * scale
	canvas.draw_set_transform(foot, 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
	canvas.draw_texture_rect_region(t, Rect2(Vector2(-size.x * 0.5, -size.y * 0.66), size),
		Rect2(frame * fs, 0, fs, fs), tint)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
