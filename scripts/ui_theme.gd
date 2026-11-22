extends RefCounted
## Ortak arayüz teması ve yardımcıları. Kullanım: const UiTheme = preload("res://scripts/ui_theme.gd")
## Görseller assets/custom/ui/ altından çalışma anında okunur (tools/make_ui.py üretir).
## Dosyalar yoksa her şey düz StyleBoxFlat'e düşer; oyun çökmez.

const DIR := "res://assets/custom/ui/"

# Palet (sanat paletiyle uyumlu)
const INK := Color(0.11, 0.10, 0.165)
const TEXT := Color(0.93, 0.92, 0.97)
const DIM := Color(0.62, 0.63, 0.74)
const GOLD := Color(0.94, 0.745, 0.22)
const GOLD_L := Color(1.0, 0.9, 0.51)
const GREEN := Color(0.4, 0.85, 0.35)
const RED := Color(0.86, 0.17, 0.22)
const TEAM := [Color(0.36, 0.58, 0.96), Color(0.96, 0.42, 0.34)]  # Mavi, Kırmızı (açık tonlar: yazı için)
const TEAM_D := [Color(0.07, 0.13, 0.42), Color(0.41, 0.06, 0.11)]
const TEAM_BANNER := ["banner_blue", "banner_red"]
## Eşya türü -> renk şeridi
const KIND_COLORS := {
	"Silah": Color(0.9, 0.35, 0.3), "Kalkan": Color(0.45, 0.6, 0.9), "Duvar": Color(0.7, 0.5, 0.3),
	"Ekstra": Color(0.4, 0.8, 0.4), "Birim": Color(0.75, 0.5, 0.9), "Yetenek": Color(0.35, 0.85, 0.95),
}

static var _cache: Dictionary = {}


## PNG'yi diskten okur (içe aktarma gerekmez). Yoksa null.
static func tex(name: String) -> Texture2D:
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


static func icon_tex(id: String) -> Texture2D:
	return tex("icon_" + id)


static func kind_color(kind: String) -> Color:
	return KIND_COLORS.get(kind, DIM)


## 9-patch kutu. Doku yoksa düz renkli yedek.
static func box(name: String, margin: int, content: int, fb_fill: Color, fb_border: Color) -> StyleBox:
	var t := tex(name)
	if t != null:
		var s := StyleBoxTexture.new()
		s.texture = t
		for side in ["left", "right", "top", "bottom"]:
			s.set("texture_margin_" + side, margin)
			s.set("content_margin_" + side, content)
		return s
	var f := StyleBoxFlat.new()
	f.bg_color = fb_fill
	f.set_border_width_all(2)
	f.border_color = fb_border
	f.set_content_margin_all(content)
	return f


static func panel_box() -> StyleBox:
	return box("panel", 6, 7, INK, Color(0.5, 0.55, 0.7))


static func row_box(hi := false) -> StyleBox:
	return box("row_hi" if hi else "row", 3, 3, Color(0.3, 0.28, 0.45) if hi else Color(0.08, 0.07, 0.125), Color(0.2, 0.2, 0.3))


static func banner_box(kind: String) -> StyleBox:  # banner_blue / banner_red / banner_gold / banner_steel
	var fills := {"banner_blue": Color(0.16, 0.33, 0.8), "banner_red": Color(0.8, 0.14, 0.15),
		"banner_gold": Color(0.75, 0.55, 0.16), "banner_steel": Color(0.23, 0.21, 0.33)}
	return box(kind, 5, 4, fills.get(kind, Color.GRAY), Color(0.05, 0.04, 0.09))


static func slot_box(active := false) -> StyleBox:
	return box("slot_active" if active else "slot", 4, 2, Color(0.09, 0.08, 0.13), GOLD if active else Color(0.34, 0.38, 0.48))


static func _button_box(state: String) -> StyleBox:
	var fills := {"normal": Color(0.29, 0.27, 0.41), "hover": Color(0.38, 0.36, 0.52),
		"pressed": Color(0.17, 0.16, 0.27), "disabled": Color(0.15, 0.14, 0.2)}
	var borders := {"normal": Color(0.5, 0.55, 0.7), "hover": GOLD, "pressed": Color(0.35, 0.38, 0.5), "disabled": Color(0.22, 0.24, 0.32)}
	var s := box("button_" + state, 5, 4, fills[state], borders[state])
	if s is StyleBoxTexture:
		s.content_margin_left = 6
		s.content_margin_right = 6
	return s


static func _flat(fill: Color, border: Color = Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var f := StyleBoxFlat.new()
	f.bg_color = fill
	f.set_border_width_all(bw)
	f.border_color = border
	return f


## Ana tema: Button, Label, Panel(Container), LineEdit, ScrollBar, ProgressBar.
static func make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 12

	th.set_color("font_color", "Label", TEXT)
	th.set_color("font_outline_color", "Label", Color(0.05, 0.04, 0.09))
	th.set_constant("outline_size", "Label", 0)

	for state in ["normal", "hover", "pressed", "disabled"]:
		th.set_stylebox(state, "Button", _button_box(state))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", GOLD_L)
	th.set_color("font_pressed_color", "Button", GOLD)
	th.set_color("font_hover_pressed_color", "Button", GOLD_L)
	th.set_color("font_focus_color", "Button", TEXT)
	th.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.6))
	# Aktif (basılı kalan) düğme: toggle için altın
	th.set_stylebox("hover_pressed", "Button", _button_box("hover"))

	# Eşya satırı düğmesi: içine kendi çocuklarını koyarız, kenar payı küçük
	th.add_type("RowButton")
	th.set_type_variation("RowButton", "Button")
	for state in ["normal", "hover", "pressed", "disabled"]:
		var rb := _button_box("normal" if state == "disabled" else state)
		if rb is StyleBoxTexture:
			rb.content_margin_top = 0
			rb.content_margin_bottom = 0
			rb.content_margin_left = 9
			rb.content_margin_right = 4
		th.set_stylebox(state, "RowButton", rb)

	th.set_stylebox("panel", "PanelContainer", panel_box())
	th.set_stylebox("panel", "Panel", panel_box())

	var le_n := _flat(Color(0.07, 0.06, 0.11), Color(0.5, 0.55, 0.7), 1)
	le_n.set_content_margin_all(4)
	var le_f := le_n.duplicate()
	le_f.border_color = GOLD
	th.set_stylebox("normal", "LineEdit", le_n)
	th.set_stylebox("focus", "LineEdit", le_f)
	th.set_stylebox("read_only", "LineEdit", le_n)
	th.set_color("font_color", "LineEdit", TEXT)
	th.set_color("font_placeholder_color", "LineEdit", DIM)
	th.set_color("caret_color", "LineEdit", GOLD)
	th.set_color("selection_color", "LineEdit", Color(0.94, 0.745, 0.22, 0.4))

	# Kaydırma çubuğu: ince, koyu yuva + metal kulp
	var grab := _flat(Color(0.5, 0.55, 0.7), Color(0.05, 0.04, 0.09), 1)
	var grab_h := _flat(GOLD, Color(0.05, 0.04, 0.09), 1)
	var track := _flat(Color(0.08, 0.07, 0.125), Color(0.2, 0.2, 0.3), 1)
	for ty in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("scroll", ty, track)
		th.set_stylebox("grabber", ty, grab)
		th.set_stylebox("grabber_highlight", ty, grab_h)
		th.set_stylebox("grabber_pressed", ty, grab_h)

	th.set_stylebox("background", "ProgressBar", _flat(Color(0.07, 0.06, 0.11), Color(0.5, 0.55, 0.7), 1))
	th.set_stylebox("fill", "ProgressBar", _flat(GOLD))
	th.set_constant("separation", "VBoxContainer", 4)
	return th


# --- Hazır parçalar ---

static func make_label(text: String, size := 12, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Sabit boyutlu ikon (piksel net, filtre yok). Doku yoksa boş yer tutar (düzen bozulmaz).
static func icon_rect(id: String, size := 16) -> TextureRect:
	var r := TextureRect.new()
	r.texture = icon_tex(id)
	r.custom_minimum_size = Vector2(size, size)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## "[coin ikonu] 60" gibi fiyat/miktar parçası.
static func coin_amount(amount: String, color: Color = GOLD_L, size := 11) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex("icon_coin") != null:
		h.add_child(icon_rect("coin", 12))
	var l := make_label(amount if tex("icon_coin") != null else amount + "c", size, color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	return h


## Panel kapsayıcı (çerçeveli).
static func make_panel() -> PanelContainer:
	var p := PanelContainer.new()
	return p


## Takım renkli başlık bandı (içinde ortalı yazı).
static func team_banner(team: int, text: String, size := 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", banner_box(TEAM_BANNER[team]))
	var l := make_label(text, size, Color.WHITE)
	l.add_theme_color_override("font_outline_color", TEAM_D[team])
	l.add_theme_constant_override("outline_size", 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


static func banner(kind: String, text: String, size := 12, color: Color = Color.WHITE) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", banner_box(kind))
	var l := make_label(text, size, color)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.09))
	l.add_theme_constant_override("outline_size", 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## Zemin: koyu mor-lacivert düz renk + hafif üst/alt ton (ColorRect'ler).
static func make_backdrop() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.08, 0.15)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	for i in 6:  # basit bant gradyanı (alt koyulaşır)
		var band := ColorRect.new()
		band.color = Color(0.17, 0.14, 0.27, 0.35 - i * 0.055)
		band.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		band.offset_top = i * 14.0
		band.offset_bottom = (i + 1) * 14.0 + 1.0
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(band)
	return root


## HUD / _draw için: kutuyu ve ikonu CanvasItem'a çizer.
static func draw_box(ci: CanvasItem, box_style: StyleBox, rect: Rect2) -> void:
	ci.draw_style_box(box_style, rect)


static func draw_icon(ci: CanvasItem, id: String, pos: Vector2, size := 16.0, tint := Color.WHITE) -> bool:
	var t := icon_tex(id)
	if t == null:
		return false
	ci.draw_texture_rect(t, Rect2(pos, Vector2(size, size)), false, tint)
	return true
