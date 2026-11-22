#!/usr/bin/env python3
"""Özgün arayüz görselleri üreticisi (bağımlılıksız: yalnızca zlib + struct).

Kullanım:  python tools/make_ui.py
Çıktı:     assets/custom/ui/ altında 9-patch paneller, butonlar, bannerlar, madalyalar,
           coin, market ikonları (16x16) ve preview_ikonlar.png önizleme sayfası.

Stil: koyu doygun palet, taş-metal çerçeve, altın vurgu, takım renkleri Mavi / Kırmızı
(make_sprites.py paletiyle aynı). İkonlar piksel kümelerinden çizilir, dış çerçeve otomatik eklenir.
"""
import os
import struct
import zlib

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "custom", "ui")

# ---------------------------------------------------------------- palet
OL = (14, 10, 22, 255)
INK = (28, 26, 42, 255)        # panel dolgusu
INK_L = (42, 40, 62, 255)
STEEL = (178, 188, 206, 255)
STEEL_M = (126, 136, 160, 255)
STEEL_D = (86, 96, 122, 255)
STEEL_DD = (58, 64, 88, 255)
GOLD = (240, 190, 56, 255)
GOLD_D = (200, 138, 40, 255)
GOLD_L = (255, 230, 130, 255)
WOOD = (150, 96, 52, 255)
WOOD_D = (98, 62, 38, 255)
WOOD_L = (190, 132, 76, 255)
WHITE = (250, 250, 255, 255)
SKIN = (236, 190, 152, 255)
SKIN_D = (192, 136, 104, 255)
LEAF = (88, 170, 74, 255)
LEAF_D = (50, 110, 52, 255)
RED = (220, 44, 56, 255)
RED_D = (130, 20, 34, 255)
CYAN = (90, 210, 255, 255)
CYAN_D = (40, 120, 190, 255)
GREY = (132, 136, 152, 255)
GREY_D = (84, 88, 106, 255)
GREY_L = (172, 176, 190, 255)
IRON = (60, 64, 82, 255)
T = (0, 0, 0, 0)
TEAMS = {
	"blue": {"m": (40, 84, 204, 255), "l": (92, 146, 244, 255), "d": (18, 34, 108, 255)},
	"red": {"m": (204, 36, 38, 255), "l": (244, 98, 78, 255), "d": (104, 16, 28, 255)},
}


class Img:
	def __init__(self, w, h, fill=T):
		self.w, self.h = w, h
		self.p = [fill] * (w * h)

	def set(self, x, y, c):
		if 0 <= x < self.w and 0 <= y < self.h:
			self.p[y * self.w + x] = c

	def get(self, x, y):
		if 0 <= x < self.w and 0 <= y < self.h:
			return self.p[y * self.w + x]
		return T

	def fill(self, pts, c):
		for x, y in pts:
			self.set(x, y, c)

	def blit(self, o, ox, oy):
		for y in range(o.h):
			for x in range(o.w):
				c = o.p[y * o.w + x]
				if c[3] > 0:
					self.set(ox + x, oy + y, c)

	def save(self, path):
		_CACHE.append((os.path.basename(path), self))
		os.makedirs(os.path.dirname(path), exist_ok=True)
		raw = b"".join(b"\x00" + b"".join(bytes(c) for c in self.p[y * self.w:(y + 1) * self.w]) for y in range(self.h))

		def chunk(t, d):
			c = struct.pack(">I", len(d)) + t + d
			return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
		png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", self.w, self.h, 8, 6, 0, 0, 0)) \
			+ chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
		with open(path, "wb") as f:
			f.write(png)

	def scaled(self, k):
		o = Img(self.w * k, self.h * k)
		for y in range(self.h):
			for x in range(self.w):
				c = self.p[y * self.w + x]
				if c[3]:
					for j in range(k):
						for i in range(k):
							o.p[(y * k + j) * o.w + x * k + i] = c
		return o


# ---------------------------------------------------------------- şekiller
def rect(x0, y0, x1, y1):
	return {(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)}


def circ(cx, cy, r):
	return {(x, y) for y in range(int(cy - r - 1), int(cy + r + 2)) for x in range(int(cx - r - 1), int(cx + r + 2))
		if (x - cx) ** 2 + (y - cy) ** 2 <= r * r}


def ell(cx, cy, rx, ry):
	return {(x, y) for y in range(int(cy - ry - 1), int(cy + ry + 2)) for x in range(int(cx - rx - 1), int(cx + rx + 2))
		if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0}


def line(x0, y0, x1, y1, th=1):
	pts = set()
	n = int(max(abs(x1 - x0), abs(y1 - y0))) * 2 + 1
	for i in range(n + 1):
		x = x0 + (x1 - x0) * i / n
		y = y0 + (y1 - y0) * i / n
		for j in range(th):
			for k in range(th):
				pts.add((int(round(x)) + j, int(round(y)) + k))
	return pts


def rows(spec):
	"""spec: [(y, x0, x1), ...] -> piksel kümesi."""
	pts = set()
	for y, x0, x1 in spec:
		for x in range(x0, x1 + 1):
			pts.add((x, y))
	return pts


def icon(parts, size=16):
	"""parts: [(küme, renk), ...] alttan üste. Birleşimin etrafına 1 piksel koyu çerçeve ekler."""
	im = Img(size, size)
	union = set()
	for pts, _ in parts:
		union |= pts
	edge = set()
	for x, y in union:
		for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
			q = (x + dx, y + dy)
			if q not in union:
				edge.add(q)
	im.fill(edge, OL)
	for pts, c in parts:
		im.fill(pts, c)
	return im


# ---------------------------------------------------------------- 9-patch çerçeveler
def frame(w, h, fill, hi, lo, rim=OL, rivets=None):
	"""Taş-metal çerçeve: dış koyu kenar, bevel (üst/sol açık, alt/sağ koyu), iç koyu halka, dolgu."""
	im = Img(w, h, fill)
	for x in range(w):
		for y in range(h):
			d = min(x, y, w - 1 - x, h - 1 - y)
			if d == 0:
				im.set(x, y, rim)
			elif d == 1:
				im.set(x, y, hi if (y == 1 or x == 1) and not (x == w - 2 or y == h - 2) else lo)
			elif d == 2:
				im.set(x, y, STEEL_D if (x > 1 and y > 1) else STEEL_D)
			elif d == 3:
				im.set(x, y, rim)
	for cx, cy in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):  # köşeleri yuvarla
		im.set(cx, cy, T)
	if rivets:
		for (rx, ry) in rivets:
			im.set(rx, ry, GOLD)
			im.set(rx + 1, ry, GOLD_D)
			im.set(rx, ry + 1, GOLD_D)
			im.set(rx + 1, ry + 1, GOLD_D)
	return im


def make_panel():
	im = frame(24, 24, INK, STEEL, STEEL_DD, rivets=[(4, 4), (18, 4), (4, 18), (18, 18)])
	return im


def make_row(tone):
	"""İç satır paneli (11x11 ->9-patch m3): ince çerçeveli koyu şerit."""
	im = Img(12, 12, tone)
	for i in range(12):
		for (x, y) in ((i, 0), (i, 11), (0, i), (11, i)):
			im.set(x, y, OL)
	for i in range(1, 11):
		im.set(i, 1, STEEL_DD)
		im.set(1, i, STEEL_DD)
	for c in ((0, 0), (11, 0), (0, 11), (11, 11)):
		im.set(c[0], c[1], T)
	return im


def make_button(kind):
	w, h = 24, 20
	pal = {
		"normal": ((74, 70, 104, 255), STEEL, STEEL_DD, OL),
		"hover": ((98, 92, 134, 255), GOLD_L, GOLD_D, OL),
		"pressed": ((44, 42, 68, 255), STEEL_DD, STEEL_D, OL),
		"disabled": ((38, 36, 52, 255), STEEL_DD, STEEL_DD, OL),
	}[kind]
	fill, hi, lo, rim = pal
	im = Img(w, h, fill)
	for x in range(w):
		for y in range(h):
			d = min(x, y, w - 1 - x, h - 1 - y)
			if d == 0:
				im.set(x, y, rim)
			elif d == 1:
				if kind == "pressed":
					im.set(x, y, lo if (y == 1 or x == 1) else hi)
				else:
					im.set(x, y, hi if (y == 1 or x == 1) else lo)
			elif kind != "pressed" and kind != "disabled" and y == 2:
				im.set(x, y, tuple(min(255, c + 22) for c in fill[:3]) + (255,))
	for cx, cy in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
		im.set(cx, cy, T)
	if kind == "hover":  # altın köşe noktaları
		for cx, cy in ((3, 3), (w - 4, 3), (3, h - 4), (w - 4, h - 4)):
			im.set(cx, cy, GOLD)
	return im


def make_banner(col):
	"""Takım/başlık bandı (16x16, m5): doygun renk, üstte açık parlama, altın şerit."""
	w, h = 16, 16
	im = Img(w, h, col["m"])
	for x in range(w):
		for y in range(h):
			d = min(x, y, w - 1 - x, h - 1 - y)
			if d == 0:
				im.set(x, y, OL)
			elif d == 1:
				im.set(x, y, col["l"] if (y == 1 or x == 1) else col["d"])
			elif y == 2:
				im.set(x, y, col["l"])
			elif y >= h - 4 and y < h - 2:
				im.set(x, y, col["d"])
	for cx, cy in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
		im.set(cx, cy, T)
	for x in range(2, w - 2):  # altın alt şerit
		im.set(x, h - 2, GOLD_D)
	return im


def make_slot(active):
	"""HUD kutusu (20x20, m4): koyu çukur; active = altın çerçeve."""
	w = h = 20
	im = Img(w, h, (22, 20, 34, 255))
	rim = GOLD if active else STEEL_D
	inner = GOLD_D if active else STEEL_DD
	for x in range(w):
		for y in range(h):
			d = min(x, y, w - 1 - x, h - 1 - y)
			if d == 0:
				im.set(x, y, OL)
			elif d == 1:
				im.set(x, y, rim)
			elif d == 2:
				im.set(x, y, inner)
	for cx, cy in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
		im.set(cx, cy, T)
	return im


# ---------------------------------------------------------------- ikonlar
def digit(d):
	f = {
		"1": ["010", "110", "010", "010", "111"],
		"2": ["111", "001", "111", "100", "111"],
		"3": ["111", "001", "011", "001", "111"],
	}[d]
	return {(x, y) for y, r in enumerate(f) for x, ch in enumerate(r) if ch == "1"}


def medal(n):
	col = {1: (GOLD, GOLD_D, GOLD_L), 2: (STEEL, STEEL_D, WHITE), 3: ((205, 127, 70, 255), (130, 74, 40, 255), (240, 170, 110, 255))}[n]
	body, dark, light = col
	rib_l = line(4, 0, 8, 6, 3)
	rib_r = line(11, 0, 7, 6, 3)
	parts = [(rib_l, TEAMS["blue"]["m"]), (rib_r, TEAMS["red"]["m"]),
		(circ(7.5, 10, 5.4), dark), (circ(7.5, 10, 4.5), body),
		({(5, 8), (6, 7), (7, 7)}, light)]
	im = icon(parts)
	for x, y in digit(str(n)):
		im.set(6 + x, 8 + y, dark if n != 2 else STEEL_D)
	return im


def coin():
	return icon([
		(circ(7.5, 7.5, 6.2), GOLD_D), (circ(7.5, 7.5, 5.2), GOLD), (circ(7.5, 7.5, 3.4), GOLD_D),
		(circ(7.5, 7.5, 2.6), (252, 214, 90, 255)),
		({(4, 4), (5, 3), (4, 5)}, GOLD_L), ({(7, 6), (8, 6), (7, 7), (8, 7), (7, 8), (8, 8), (7, 9), (8, 9)}, GOLD_D)])


def star():
	pts = {(7, 1), (8, 1), (7, 2), (8, 2), (7, 3), (8, 3)} | rows([(4, 1, 14), (5, 2, 13), (6, 3, 12), (7, 4, 11), (8, 5, 10), (9, 5, 10),
		(10, 4, 5), (10, 10, 11), (11, 3, 5), (11, 10, 12), (12, 2, 4), (12, 11, 13)])
	return icon([(pts, GOLD), ({(7, 3), (8, 3), (7, 4), (8, 4)}, GOLD_L)])


def check():
	return icon([(line(2, 8, 6, 12, 2) | line(6, 12, 13, 3, 2), LEAF), (line(3, 8, 6, 11, 1), (150, 230, 120, 255))])


def dots():
	return icon([({(3, 8), (4, 8), (3, 9), (4, 9)}, STEEL_M), ({(7, 8), (8, 8), (7, 9), (8, 9)}, STEEL_M), ({(11, 8), (12, 8), (11, 9), (12, 9)}, STEEL_M)])


def skull():
	return icon([(circ(7.5, 6.5, 5), WHITE), (rect(5, 9, 10, 13), WHITE),
		({(5, 6), (6, 6), (5, 7), (6, 7), (9, 6), (10, 6), (9, 7), (10, 7)}, OL), ({(7, 9), (8, 9)}, OL),
		({(6, 12), (8, 12), (10, 12)}, GREY)])


def sword():
	return icon([
		(line(13, 2, 5, 10, 2), STEEL), (line(14, 2, 7, 9, 1), WHITE),
		(line(3, 8, 7, 12, 2), GOLD), (line(4, 11, 2, 13, 2), WOOD_D), ({(1, 14), (2, 14), (1, 13)}, GOLD)])


def spear():
	return icon([
		(line(2, 14, 11, 5, 2), WOOD), (line(2, 14, 10, 6, 1), WOOD_L),
		(rows([(1, 13, 14), (2, 12, 14), (3, 11, 14), (4, 11, 13), (5, 11, 12)]), STEEL), ({(14, 1), (14, 2), (13, 2), (13, 3)}, WHITE),
		(line(9, 7, 11, 9, 1), GOLD)])


def bow():
	arc = set()
	for y in range(1, 15):
		x = 4 + int(round(((y - 7.5) / 6.5) ** 2 * 6))
		arc.add((x, y))
		arc.add((x + 1, y))
	return icon([(arc, WOOD), (line(11, 1, 11, 14, 1), WHITE),
		(line(3, 8, 14, 8, 1), WOOD_L), (rows([(7, 13, 15), (8, 13, 15), (9, 13, 15)]), STEEL), ({(1, 7), (1, 9), (2, 8)}, RED)])


SHIELD = rows([(2, 3, 12), (3, 3, 12), (4, 3, 12), (5, 3, 12), (6, 3, 12), (7, 3, 12), (8, 4, 11), (9, 4, 11),
	(10, 5, 10), (11, 5, 10), (12, 6, 9), (13, 7, 8)])


def shield(wood):
	if wood:
		return icon([(SHIELD, WOOD_D), (SHIELD - rows([(2, 3, 12)]) - {(3, 3), (3, 12)}, WOOD),
			(rect(7, 3, 8, 12), WOOD_D), ({(4, 3), (4, 4), (4, 5), (11, 3), (11, 4)}, WOOD_L), (circ(7.5, 7, 2), GOLD), ({(7, 6), (6, 6)}, GOLD_L)])
	return icon([(SHIELD, STEEL_D), (SHIELD - rows([(2, 3, 12)]) - {(3, 3), (3, 12)}, STEEL),
		(rect(7, 3, 8, 12), STEEL_M), (rect(4, 6, 11, 7), STEEL_M), ({(4, 3), (4, 4), (4, 5)}, WHITE),
		(circ(7.5, 6.5, 1.8), GOLD), ({(7, 6)}, GOLD_L)])


def wall(wood):
	if wood:
		parts = []
		for i, x in enumerate((1, 5, 9)):
			top = 3 + (i % 2)
			parts.append((rect(x, top + 1, x + 3, 14) | {(x + 1, top), (x + 2, top)}, WOOD))
			parts.append((rect(x + 2, top + 1, x + 3, 14), WOOD_D))
			parts.append(({(x, top + 3), (x, top + 4), (x, top + 5)}, WOOD_L))
		return icon(parts + [(rect(1, 9, 12, 10), (110, 70, 40, 255)), (rect(1, 9, 12, 9), WOOD_L)])
	base = rect(1, 5, 14, 14)
	cren = rect(1, 2, 3, 4) | rect(6, 2, 9, 4) | rect(12, 2, 14, 4)
	mortar = {(x, y) for x in range(1, 15) for y in (8, 11)} | {(x, y) for y in (5, 6, 7) for x in (5, 10)} | \
		{(x, y) for y in (9, 10) for x in (3, 8, 12)} | {(x, y) for y in (12, 13, 14) for x in (6, 11)}
	return icon([(base | cren, GREY), (mortar & (base | cren), GREY_D), (rect(1, 5, 14, 5), GREY_L), (rect(1, 2, 3, 2) | rect(6, 2, 9, 2) | rect(12, 2, 14, 2), GREY_L)])


def boots():
	return icon([
		(line(0, 4, 3, 4, 1), WHITE), (line(0, 7, 3, 7, 1), WHITE), (line(1, 10, 3, 10, 1), WHITE),
		(rect(5, 2, 9, 10) | rect(5, 9, 14, 13), WOOD), (rect(5, 12, 14, 13), WOOD_D), (rect(5, 2, 6, 9), WOOD_L),
		(rect(5, 3, 9, 4), STEEL), ({(7, 3)}, GOLD), (rect(10, 9, 14, 10), WOOD_D)])


def heart():
	pts = circ(4.8, 5.6, 3.3) | circ(10.2, 5.6, 3.3) | rows([(7, 2, 13), (8, 2, 13), (9, 3, 12), (10, 4, 11), (11, 5, 10), (12, 6, 9), (13, 7, 8)])
	return icon([(pts, RED), (rows([(10, 5, 11), (11, 6, 10), (12, 7, 9), (9, 9, 12), (8, 11, 13)]), RED_D),
		({(3, 4), (4, 3), (3, 5), (5, 3)}, (255, 190, 190, 255))])


def fist():
	return icon([(rect(4, 5, 12, 12), SKIN), (rect(4, 11, 12, 12), SKIN_D),
		({(7, 5), (7, 6), (7, 7), (10, 5), (10, 6), (10, 7)}, SKIN_D), (rect(3, 8, 4, 11), SKIN), (rect(5, 13, 11, 14), STEEL_D)])


def _bust(face_extra, body, body_d):
	return [(rect(3, 10, 12, 14), body_d), (rect(4, 10, 11, 13), body), (circ(7.5, 6.5, 3.6), SKIN)] + face_extra


def unit_swordsman():
	helm = rows([(2, 5, 10), (3, 4, 11), (4, 4, 11), (5, 4, 5), (5, 10, 11)])
	parts = _bust([(helm, STEEL), (rows([(2, 5, 6)]), WHITE), (rect(7, 0, 8, 3), RED), ({(7, 4), (8, 4)}, STEEL_D),
		({(6, 7), (9, 7), (6, 6), (9, 6)}, OL), (line(7, 9, 8, 9, 1), SKIN_D)], STEEL_D, STEEL_DD)
	parts += [(line(14, 4, 14, 11, 1), WHITE), ({(13, 11), (15, 11)}, GOLD)]
	return icon(parts)


def unit_archer():
	hood = ell(7.5, 5.5, 4.8, 4.4)
	parts = _bust([(hood, LEAF), (rect(5, 6, 10, 9), SKIN), ({(5, 4), (6, 3), (7, 3)}, (140, 220, 110, 255)),
		({(6, 7), (9, 7)}, OL), ({(6, 6), (9, 6)}, OL)], LEAF_D, (30, 70, 40, 255))
	arc = set()
	for y in range(2, 14):
		arc.add((13 + int(round(((y - 7.5) / 5.5) ** 2 * -2)) + 1, y))
	parts += [(arc, WOOD_L), (line(13, 2, 13, 13, 1), WHITE)]
	return icon(parts)


def unit_artillery():
	return icon([
		(circ(5.5, 11.5, 3.4), WOOD_D), (circ(5.5, 11.5, 2.4), WOOD), ({(5, 11), (6, 11), (5, 12), (6, 12)}, GOLD),
		(line(2, 10, 11, 5, 4), IRON), (line(2, 8, 11, 3, 1), STEEL_D), (line(3, 9, 10, 5, 1), STEEL_M),
		(rect(11, 3, 13, 8), STEEL_D), (rect(11, 3, 12, 4), STEEL_M), ({(14, 5), (14, 6), (15, 5), (14, 4)}, (255, 140, 40, 255)), ({(14, 5)}, GOLD_L)])


def unit_shieldbearer():
	helm = rows([(1, 5, 10), (2, 4, 11), (3, 4, 11)])
	big = rect(2, 7, 13, 14)
	return icon([(circ(7.5, 4.5, 2.8), SKIN), (helm, STEEL), ({(6, 4), (9, 4)}, OL), (rect(7, 0, 8, 2), GOLD),
		(big, STEEL_D), (rect(3, 8, 12, 13), STEEL), (rect(3, 8, 12, 8), WHITE),
		(rect(7, 8, 8, 13), GOLD), (rect(3, 10, 12, 11), GOLD), ({(7, 10), (8, 10), (7, 11), (8, 11)}, GOLD_L)])


def ability_dash():
	return icon([(line(1, 2, 6, 8, 2) | line(6, 8, 1, 14, 2), CYAN), (line(8, 2, 13, 8, 2) | line(13, 8, 8, 14, 2), CYAN),
		(line(2, 3, 6, 8, 1) | line(9, 3, 13, 8, 1), WHITE)])


def ability_burst():
	spikes = set()
	for dx, dy in ((0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)):
		spikes |= line(7.5 + dx * 3, 7.5 + dy * 3, 7.5 + dx * 7, 7.5 + dy * 7, 2) if dx == 0 or dy == 0 else line(7.5 + dx * 3, 7.5 + dy * 3, 7.5 + dx * 5.5, 7.5 + dy * 5.5, 2)
	return icon([(spikes, CYAN_D), (circ(7.5, 7.5, 4.4), CYAN), (circ(7.5, 7.5, 2.4), WHITE)], 16)


def ability_rally():
	return icon([(line(3, 1, 3, 15, 2), WOOD),
		(rows([(2, 5, 14), (3, 5, 14), (4, 5, 14), (5, 5, 14), (6, 5, 14), (7, 5, 14), (8, 5, 10), (9, 5, 9)]), RED),
		(rows([(2, 5, 14), (3, 5, 14)]), (255, 120, 100, 255)), (rows([(5, 5, 14), (6, 5, 14)]), GOLD),
		({(5, 9), (6, 9)}, RED_D), (rows([(8, 11, 14), (7, 12, 14)]), RED_D)])


ICONS = {
	"sword": sword, "spear": spear, "bow": bow,
	"shield_wood": lambda: shield(True), "shield_iron": lambda: shield(False),
	"wall_wood": lambda: wall(True), "wall_stone": lambda: wall(False),
	"boots": boots, "heart": heart, "fist": fist,
	"unit_swordsman": unit_swordsman, "unit_archer": unit_archer, "unit_artillery": unit_artillery,
	"unit_shieldbearer": unit_shieldbearer,
	"ability_dash": ability_dash, "ability_burst": ability_burst, "ability_rally": ability_rally,
	"coin": coin, "star": star, "check": check, "dots": dots, "skull": skull,
	"medal_1": lambda: medal(1), "medal_2": lambda: medal(2), "medal_3": lambda: medal(3),
}


def nine(path, w, h):
	"""Önizleme için PNG'yi okuyup (kenar boyutu = yarısı) 9-patch gibi w x h'ye gerer."""
	import binascii  # noqa: F401
	src = None
	for im in _CACHE:
		if im[0] == os.path.basename(path):
			src = im[1]
	m = src.w // 2 - 1 if src.w > 16 else src.w // 3
	m = {"panel.png": 6, "slot.png": 4, "slot_active.png": 4}.get(os.path.basename(path), 5)
	out = Img(w, h)
	for y in range(h):
		sy = y if y < m else (src.h - (h - y) if y >= h - m else m)
		for x in range(w):
			sx = x if x < m else (src.w - (w - x) if x >= w - m else m)
			out.p[y * w + x] = src.get(sx, sy)
	return out


_CACHE = []


def main():
	os.makedirs(OUT, exist_ok=True)
	make_panel().save(os.path.join(OUT, "panel.png"))
	make_row((20, 18, 32, 255)).save(os.path.join(OUT, "row.png"))
	make_row((46, 42, 70, 255)).save(os.path.join(OUT, "row_hi.png"))
	for k in ("normal", "hover", "pressed", "disabled"):
		make_button(k).save(os.path.join(OUT, "button_%s.png" % k))
	for k, col in TEAMS.items():
		make_banner(col).save(os.path.join(OUT, "banner_%s.png" % k))
	make_banner({"m": (190, 140, 40, 255), "l": GOLD_L, "d": GOLD_D}).save(os.path.join(OUT, "banner_gold.png"))
	make_banner({"m": (58, 54, 84, 255), "l": STEEL_M, "d": STEEL_DD}).save(os.path.join(OUT, "banner_steel.png"))
	make_slot(False).save(os.path.join(OUT, "slot.png"))
	make_slot(True).save(os.path.join(OUT, "slot_active.png"))
	imgs = {}
	for name, fn in ICONS.items():
		im = fn()
		im.save(os.path.join(OUT, "icon_%s.png" % name))
		imgs[name] = im
	# Önizleme: koyu zeminde 4x
	names = list(imgs.keys())
	cols = 8
	k = 4
	cell = 16 * k + 8
	nrows = (len(names) + cols - 1) // cols
	sheet = Img(cols * cell + 8, nrows * cell + 60, (44, 40, 62, 255))
	for i, n in enumerate(names):
		sheet.blit(imgs[n].scaled(k), 4 + (i % cols) * cell, 4 + (i // cols) * cell)
	y0 = nrows * cell + 12
	x = 4
	for fn, w, h in (("panel.png", 24, 24), ("button_normal.png", 40, 20), ("button_hover.png", 40, 20), ("button_pressed.png", 40, 20),
			("button_disabled.png", 40, 20), ("banner_blue.png", 40, 16), ("banner_red.png", 40, 16), ("banner_gold.png", 40, 16),
			("slot.png", 20, 20), ("slot_active.png", 20, 20)):
		sheet.blit(nine(os.path.join(OUT, fn), w, h), x, y0)
		x += w + 4
	sheet.save(os.path.join(OUT, "preview_ikonlar.png"))
	print("UI görselleri yazıldı:", os.path.abspath(OUT), len(names), "ikon")


if __name__ == "__main__":
	main()
