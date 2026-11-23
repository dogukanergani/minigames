#!/usr/bin/env python3
"""Minigame görselleri üreticisi (bağımlılıksız; tools/make_sprites.py çizim araçlarını kullanır).

Kullanım:  python tools/make_minigame_art.py   (önce make_sprites.py çalışmış olmalı: kahraman/zemin dokuları)
Çıktı:     assets/custom/minigame/*.png + assets/custom/preview_minigame_*.png

Ölçek: 1 sanat pikseli = 2/3 dünya birimi (1080p'de 2 ekran pikseli). Arka planlar 960x540 sanat pikseli
(= 640x360 dünya). Refleks düellosundaki karakterler 2 kat (4/3 dünya birimi / piksel).
Oyundaki çizim kodu: minigames/mg_art.gd (yazı tipi düzeni FONT_CHARS ile AYNI olmalı).
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_sprites as ms  # noqa: E402
from make_sprites import (Img, part, fill, fill_a, rect, circ, ell, line, poly, shift, grow, strip, over, text,  # noqa: E402
	OL, GOLD, GOLD_D, WHITE, STEEL, STEEL_D, WOOD, WOOD_D, LEAF, TEAMS, SKIN, SKIN_D, shadow, spark_star)

OUT = os.path.join(ms.OUT, "minigame")
W, H = 960, 540          # arka plan (sanat pikseli)
K = 1.5                  # dünya birimi -> sanat pikseli
GOLD_L = (255, 230, 130, 255)
INK = (28, 26, 42, 255)
STONE = (100, 106, 126, 255)
STONE_L = (132, 138, 158, 255)
STONE_D = (70, 76, 98, 255)
MORTAR = (44, 46, 62, 255)
GRASS = (72, 130, 66, 255)
GRASS_D = (58, 110, 56, 255)
GRASS_L = (92, 150, 76, 255)
DIRT = (158, 122, 84, 255)
DIRT_D = (132, 98, 68, 255)
DIRT_L = (182, 146, 104, 255)
CHALK = (236, 228, 208, 255)


def rgba(c, a):
	return (c[0], c[1], c[2], a)


def mix(a, b, t):
	return tuple(int(a[k] + (b[k] - a[k]) * t) for k in range(3)) + (255,)


def tile_from(strip_img, i, w=16):
	t = Img(w, strip_img.h)
	for y in range(strip_img.h):
		for x in range(w):
			t.p[y * w + x] = strip_img.p[y * strip_img.w + i * w + x]
	return t


def frame_of(strip_img, i, fw):
	return tile_from(strip_img, i, fw)


def blit_a(dst, src, ox, oy):
	"""Saydamlığı karıştırarak yapıştır."""
	for y in range(src.h):
		for x in range(src.w):
			c = src.p[y * src.w + x]
			if c[3] > 0:
				dst.blend(ox + x, oy + y, c)


def flip_h(im):
	o = Img(im.w, im.h)
	for y in range(im.h):
		for x in range(im.w):
			o.p[y * im.w + x] = im.p[y * im.w + im.w - 1 - x]
	return o


def tinted(im, col, keep=0.0):
	"""Silüet: her opak pikseli `col` yap (keep: orijinal rengin oranı)."""
	o = Img(im.w, im.h)
	for i, c in enumerate(im.p):
		if c[3]:
			o.p[i] = tuple(int(c[k] * keep + col[k] * (1 - keep)) for k in range(3)) + (c[3],)
	return o


# ================================================================ büyük pixel yazı tipi
# 5x7 gövde, her yazı pikseli 2x2 sanat pikseli. Hücre: 5 sütun x 10 satır (0-1 şapka/nokta, 2-8 gövde, 9 çengel).
# Beyaz -> açık gri tonlu: oyunda renkle çarpılır (tint). 1 piksel koyu çerçeve + sağ-alt gölge.
FONT_CHARS = " 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZÇĞİÖŞÜ!?.:-+/%"
CELL_W, CELL_H = 13, 23
G = {
	"0": ".###.|#...#|#..##|#.#.#|##..#|#...#|.###.", "1": "..#..|.##..|..#..|..#..|..#..|..#..|.###.",
	"2": ".###.|#...#|....#|...#.|..#..|.#...|#####", "3": "####.|....#|....#|.###.|....#|....#|####.",
	"4": "...#.|..##.|.#.#.|#..#.|#####|...#.|...#.", "5": "#####|#....|####.|....#|....#|#...#|.###.",
	"6": ".###.|#....|#....|####.|#...#|#...#|.###.", "7": "#####|....#|...#.|..#..|.#...|.#...|.#...",
	"8": ".###.|#...#|#...#|.###.|#...#|#...#|.###.", "9": ".###.|#...#|#...#|.####|....#|....#|.###.",
	"A": ".###.|#...#|#...#|#####|#...#|#...#|#...#", "B": "####.|#...#|#...#|####.|#...#|#...#|####.",
	"C": ".###.|#...#|#....|#....|#....|#...#|.###.", "D": "####.|#...#|#...#|#...#|#...#|#...#|####.",
	"E": "#####|#....|#....|####.|#....|#....|#####", "F": "#####|#....|#....|####.|#....|#....|#....",
	"G": ".###.|#...#|#....|#.###|#...#|#...#|.####", "H": "#...#|#...#|#...#|#####|#...#|#...#|#...#",
	"I": ".###.|..#..|..#..|..#..|..#..|..#..|.###.", "J": "..###|...#.|...#.|...#.|#..#.|#..#.|.##..",
	"K": "#...#|#..#.|#.#..|##...|#.#..|#..#.|#...#", "L": "#....|#....|#....|#....|#....|#....|#####",
	"M": "#...#|##.##|#.#.#|#.#.#|#...#|#...#|#...#", "N": "#...#|##..#|#.#.#|#..##|#...#|#...#|#...#",
	"O": ".###.|#...#|#...#|#...#|#...#|#...#|.###.", "P": "####.|#...#|#...#|####.|#....|#....|#....",
	"Q": ".###.|#...#|#...#|#...#|#.#.#|#..#.|.##.#", "R": "####.|#...#|#...#|####.|#.#..|#..#.|#...#",
	"S": ".####|#....|#....|.###.|....#|....#|####.", "T": "#####|..#..|..#..|..#..|..#..|..#..|..#..",
	"U": "#...#|#...#|#...#|#...#|#...#|#...#|.###.", "V": "#...#|#...#|#...#|#...#|#...#|.#.#.|..#..",
	"W": "#...#|#...#|#...#|#.#.#|#.#.#|##.##|#...#", "X": "#...#|#...#|.#.#.|..#..|.#.#.|#...#|#...#",
	"Y": "#...#|#...#|.#.#.|..#..|..#..|..#..|..#..", "Z": "#####|....#|...#.|..#..|.#...|#....|#####",
	"!": "..#..|..#..|..#..|..#..|..#..|.....|..#..", "?": ".###.|#...#|....#|...#.|..#..|.....|..#..",
	".": ".....|.....|.....|.....|.....|.....|..#..", ":": ".....|..#..|.....|.....|.....|..#..|.....",
	"-": ".....|.....|.....|.###.|.....|.....|.....", "+": ".....|..#..|..#..|#####|..#..|..#..|.....",
	"/": "....#|....#|...#.|..#..|.#...|#....|#....", "%": "##..#|##..#|...#.|..#..|.#...|#..##|#..##",
	" ": ".....|.....|.....|.....|.....|.....|.....",
}
# Türkçe harfler: gövde + şapka (satır 0) / çengel (satır 9)
ACCENT = {"Ç": ("C", None, "..#.."), "Ş": ("S", None, "..#.."), "İ": ("I", "..#..", None),
	"Ö": ("O", ".#.#.", None), "Ü": ("U", ".#.#.", None), "Ğ": ("G", ".###.", None)}


def glyph_grid(ch):
	"""10 satırlık 5 sütun ızgara (set of (x, y))."""
	top, bot = None, None
	if ch in ACCENT:
		base, top, bot = ACCENT[ch]
	else:
		base = ch
	rows = G[base].split("|")
	pts = set()
	for y, r in enumerate(rows):
		for x, v in enumerate(r):
			if v == "#":
				pts.add((x, y + 2))
	if top:
		for x, v in enumerate(top):
			if v == "#":
				pts.add((x, 0))
	if bot:
		for x, v in enumerate(bot):
			if v == "#":
				pts.add((x, 9))
	return pts


def font_sheet():
	im = Img(CELL_W * len(FONT_CHARS), CELL_H)
	for i, ch in enumerate(FONT_CHARS):
		g = glyph_grid(ch)
		px = set()
		for gx, gy in g:
			for a in range(2):
				for b in range(2):
					px.add((i * CELL_W + 1 + gx * 2 + a, 1 + gy * 2 + b))
		# gölge (sağ-alt), çerçeve, gövde (üstten alta açık -> gri ton: tint ile renklenir)
		for x, y in grow(shift(px, 1, 1)):
			im.set(x, y, OL)
		for x, y in grow(px):
			im.set(x, y, OL)
		for x, y in px:
			gy = (y - 1) // 2
			c = WHITE if gy <= 4 else ((222, 222, 232, 255) if gy <= 6 else (176, 176, 194, 255))
			im.set(x, y, c)
		for x, y in px:  # her vuruşun üst kenarında parlak çizgi
			if (x, y - 1) not in px and (y - 1) // 2 >= 2:
				im.set(x, y, (255, 255, 255, 255))
	return im


def big_text(img, x, y, s, col, k=1):
	"""Önizleme için: yazı tipi sayfasından renkli yazı (k: büyütme). Sol üst köşe (x, y)."""
	sheet = FONT
	for ch in s:
		i = FONT_CHARS.find(ch)
		if i < 0:
			i = 0
		for yy in range(CELL_H):
			for xx in range(CELL_W):
				c = sheet.p[yy * sheet.w + i * CELL_W + xx]
				if c[3]:
					cc = tuple(c[j] * col[j] // 255 for j in range(3)) + (255,)
					for a in range(k):
						for b in range(k):
							img.set(x + xx * k + a, y + yy * k + b, cc)
		x += (CELL_W - 1) * k
	return x


def big_w(s, k=1):
	return (len(s) * (CELL_W - 1) + 1) * k


# ================================================================ ortak küçük parçalar
def clock_icon():
	im = Img(12, 12)
	part(im, circ(5.5, 6.5, 4.6), (236, 232, 244, 255))
	fill(im, {(x, y) for x, y in circ(5.5, 6.5, 4.6) if y >= 9}, (190, 190, 210, 255))
	fill(im, line(5.5, 6.5, 5.5, 3.5, 1), OL)
	fill(im, line(5.5, 6.5, 7.5, 6.5, 1), OL)
	part(im, rect(4, 0, 7, 1), GOLD)
	fill(im, {(5, 6), (6, 6)}, (220, 40, 50, 255))
	return im


def burst_strip():
	"""Geri sayım / BAŞLA patlaması: altın ışınlar, 4 kare 48x48 (sönerek büyür)."""
	frames = []
	for f in range(4):
		im = Img(48, 48)
		k = f / 3.0
		n = 12
		for j in range(n):
			a = j * math.tau / n + (0.13 if j % 2 else 0.0)
			r0 = 5 + k * 9
			r1 = (16 if j % 2 else 22) + k * 2
			col = GOLD_L if j % 2 == 0 else GOLD
			if f == 3 and j % 2:
				continue
			pts = line(24 + math.cos(a) * r0, 24 + math.sin(a) * r0, 24 + math.cos(a) * r1, 24 + math.sin(a) * r1, 2 if f < 2 else 1)
			fill_a(im, pts, rgba(col, 255 if f < 2 else 170))
		if f < 2:
			for x, y in circ(24, 24, 8 + f * 6) - circ(24, 24, 6 + f * 6):
				im.blend(x, y, (255, 250, 220, 220 - f * 60))
		if f == 0:
			fill(im, circ(24, 24, 4), WHITE)
		frames.append(im)
	return strip(frames)


def dust_strip():
	"""Koşu tozu, 4 kare 10x10."""
	frames = []
	for f in range(4):
		im = Img(10, 10)
		r = 1.6 + f * 0.8
		a = 230 - f * 50
		blob = circ(5, 6 - f * 0.4, r) | circ(3.5, 6.5 - f * 0.3, r * 0.7) | circ(6.8, 6.6 - f * 0.3, r * 0.6)
		if f == 3:
			blob = {p for p in blob if (p[0] + p[1]) % 2 == 0}
		for x, y in grow(blob):
			im.blend(x, y, (96, 70, 52, a // 2))
		for x, y in blob:
			im.blend(x, y, (214, 190, 150, a))
		for x, y in blob:
			if (x, y - 1) not in blob:
				im.blend(x, y, (240, 224, 190, a))
		frames.append(im)
	return strip(frames)


def sparkle_strip():
	"""Coin toplama parıltısı, 5 kare 20x20: beyaz çekirdek, altın yıldız, halka, dağılan kıvılcımlar."""
	frames = []
	for f in range(5):
		im = Img(20, 20)
		if f == 0:
			fill(im, circ(10, 10, 3.5), WHITE)
			spark_star(im, 10, 10, 6, GOLD_L)
		elif f == 1:
			spark_star(im, 10, 10, 8, GOLD)
			for x, y in circ(10, 10, 6) - circ(10, 10, 5):
				im.blend(x, y, (255, 250, 220, 230))
		elif f == 2:
			for x, y in circ(10, 10, 8.5) - circ(10, 10, 7.3):
				im.blend(x, y, (255, 236, 150, 200))
			for a in range(4):
				r = math.radians(a * 90 + 45)
				spark_star(im, int(10 + math.cos(r) * 6), int(10 + math.sin(r) * 6), 1, GOLD_L)
		elif f == 3:
			for a in range(6):
				r = math.radians(a * 60 + 15)
				fill(im, {(int(10 + math.cos(r) * 8), int(10 + math.sin(r) * 8))}, GOLD_L)
				fill(im, {(int(10 + math.cos(r) * 7), int(10 + math.sin(r) * 7))}, GOLD)
		else:
			for a in range(6):
				r = math.radians(a * 60 + 30)
				fill(im, {(int(10 + math.cos(r) * 9), int(10 + math.sin(r) * 9))}, GOLD_D)
		frames.append(im)
	return strip(frames)


def coin_big_strip():
	"""Arena coini (16x16, 6 kare dönüş): kalın altın kenar, kabartma yıldız, beyaz parlama."""
	frames = []
	for f, rx in enumerate((6.5, 5.5, 3.5, 1.2, 3.5, 5.5)):
		im = Img(16, 16)
		e = ell(8, 8, max(rx, 0.8), 6.5)
		part(im, e, GOLD_D)
		if rx > 2:
			inner = ell(8, 8, rx - 1.2, 5.3)
			fill(im, inner, GOLD)
			fill(im, {(x, y) for x, y in inner if y <= 5}, GOLD_L)
			if rx > 4:  # kabartma: elmas
				st = {(8, 5), (7, 6), (8, 6), (9, 6), (6, 7), (7, 7), (9, 7), (10, 7), (6, 8), (7, 8), (9, 8), (10, 8), (7, 9), (8, 9), (9, 9), (8, 10)}
				st = {(int(round(8 + (x - 8) * rx / 6.5)), y) for x, y in st}
				fill(im, st, GOLD_D)
				fill(im, {(8, 7), (8, 8)}, GOLD_L)
			fill(im, {(int(8 - rx * 0.5), 4), (int(8 - rx * 0.5), 5)}, WHITE)
		else:
			fill(im, rect(8, 2, 8, 13), GOLD)
		frames.append(im)
	return strip(frames)


def pennant_strip():
	"""Flama: Mavi, Kırmızı, Altın (8x9)."""
	frames = []
	for col, lt in ((TEAMS["blue"]["m"], TEAMS["blue"]["l"]), (TEAMS["red"]["m"], TEAMS["red"]["l"]), (GOLD_D, GOLD_L)):
		im = Img(8, 9)
		tri = poly([(1, 1), (7, 1), (4, 8)])
		part(im, tri, col)
		fill(im, {(x, y) for x, y in tri if y <= 2}, lt)
		frames.append(im)
	return strip(frames)


SPECTATOR_SHIRTS = [TEAMS["blue"]["m"], TEAMS["red"]["m"], (70, 150, 70, 255), GOLD_D, (140, 80, 170, 255), (60, 140, 160, 255)]
SPECTATOR_HAIR = [(70, 44, 30, 255), (30, 24, 30, 255), (220, 170, 70, 255), (160, 60, 40, 255)]


def spectator(kind, cheer):
	"""Seyirci (12x14): baş + omuz; cheer: kollar havada, ağız açık."""
	im = Img(12, 14)
	shirt = SPECTATOR_SHIRTS[kind % len(SPECTATOR_SHIRTS)]
	hair = SPECTATOR_HAIR[kind % len(SPECTATOR_HAIR)]
	dy = -1 if cheer else 0
	body = ell(6, 12 + dy, 4.5, 3.2)
	part(im, body, shirt)
	fill(im, {(x, y) for x, y in body if y <= 10 + dy}, mix(shirt, WHITE, 0.25))
	head = circ(6, 6 + dy, 3.2)
	part(im, head, SKIN)
	fill(im, {(x, y) for x, y in head if y <= 4 + dy}, hair)
	if kind % 3 == 1:  # şapka
		part(im, rect(3, 2 + dy, 9, 3 + dy), shirt)
	fill(im, {(5, 6 + dy), (7, 6 + dy)}, OL)
	if cheer:  # kollar havada, ağız açık
		fill(im, {(6, 8 + dy)}, (150, 30, 40, 255))
		for ax in (1, 10):
			part(im, rect(ax, 4 + dy, ax, 9 + dy), shirt)
			part(im, rect(ax, 2 + dy, ax, 3 + dy), SKIN)
	return im


def spectators_strip():
	frames = []
	for k in range(6):
		frames.append(spectator(k, False))
		frames.append(spectator(k, True))
	return strip(frames)


def crack_img():
	"""Erken basış: ekranın ortasında çatlak (beyaz, oyunda kırmızıyla çarpılır). 240x150."""
	im = Img(240, 150)
	cx, cy = 120, 75
	r = random.Random(9)
	segs = []
	for j in range(9):
		a = j * math.tau / 9 + r.uniform(-0.2, 0.2)
		x, y = cx, cy
		L = r.uniform(55, 110)
		n = 5
		for s in range(n):
			step = L / n
			a2 = a + r.uniform(-0.45, 0.45)
			nx, ny = x + math.cos(a2) * step, y + math.sin(a2) * step * 0.62
			segs.append((x, y, nx, ny, 2 if s < 2 else 1))
			if s == 2 and r.random() < 0.7:  # dal
				ba = a2 + r.choice((-0.8, 0.8))
				segs.append((nx, ny, nx + math.cos(ba) * 18, ny + math.sin(ba) * 11, 1))
			x, y = nx, ny
	# halka çatlaklar
	for rad in (16, 34):
		pts = []
		for j in range(14):
			a = j * math.tau / 14
			pts.append((cx + math.cos(a) * rad * r.uniform(0.85, 1.15), cy + math.sin(a) * rad * 0.62 * r.uniform(0.85, 1.15)))
		for j in range(14):
			if r.random() < 0.75:
				segs.append((pts[j][0], pts[j][1], pts[(j + 1) % 14][0], pts[(j + 1) % 14][1], 1))
	px = set()
	for x0, y0, x1, y1, th in segs:
		px |= line(x0, y0, x1, y1, th)
	for x, y in grow(px):
		im.set(x, y, (40, 10, 16, 200))
	for x, y in px:
		im.set(x, y, WHITE)
	fill(im, circ(cx, cy, 5), WHITE)
	return im


# ================================================================ KOŞU: engeller ve süsler
# Engel dokuları 21 piksel genişliğinde (14 dünya birimi): üst kapak 10, orta (yinelenen) 16, alt yüz 8 satır.
OB_W, OB_TOP, OB_MID, OB_BOT = 21, 10, 16, 8


def ob_stone():
	im = Img(OB_W, OB_TOP + OB_MID + OB_BOT)
	# üst kapak: yuvarlatılmış üst taş
	cap = rect(1, 2, OB_W - 2, OB_TOP - 1) - {(1, 2), (OB_W - 2, 2)}
	part(im, cap, STONE_L)
	fill(im, rect(2, 3, OB_W - 3, 4), (160, 166, 186, 255))
	fill(im, {(5, 6), (6, 6), (14, 7)}, STONE)
	# orta: iki sıra taş blok (harçlı), yan kenarlar koyu çerçeve
	y0 = OB_TOP
	for y in range(y0, y0 + OB_MID):
		for x in range(OB_W):
			c = STONE
			if x in (0, OB_W - 1):
				c = OL
			elif x == 1:
				c = STONE_L
			elif x == OB_W - 2:
				c = STONE_D
			im.set(x, y, c)
	for yy in (y0 + 7, y0 + 15):
		fill(im, rect(1, yy, OB_W - 2, yy), MORTAR)
	fill(im, rect(10, y0, 10, y0 + 6), MORTAR)
	fill(im, rect(5, y0 + 8, 5, y0 + 14), MORTAR)
	fill(im, rect(15, y0 + 8, 15, y0 + 14), MORTAR)
	for x, y in ((3, y0 + 2), (13, y0 + 3), (7, y0 + 10), (17, y0 + 11), (12, y0 + 12)):
		im.set(x, y, STONE_D)
	for x, y in ((2, y0 + 1), (12, y0 + 1), (7, y0 + 9)):
		im.set(x, y, STONE_L)
	# alt: ön yüz (koyu) + yosun
	yb = OB_TOP + OB_MID
	part(im, rect(1, yb, OB_W - 2, yb + OB_BOT - 2), STONE_D)
	fill(im, rect(1, yb, OB_W - 2, yb), MORTAR)
	fill(im, {(3, yb + 3), (9, yb + 2), (16, yb + 4)}, MORTAR)
	fill(im, {(2, yb + 5), (3, yb + 5), (4, yb + 4), (17, yb + 5), (18, yb + 5)}, (70, 130, 66, 255))
	return im


def ob_log():
	im = Img(OB_W, OB_TOP + OB_MID + OB_BOT)
	bark, bark_l, bark_d = (120, 76, 44, 255), (156, 104, 60, 255), (78, 48, 32, 255)
	ring, ring_d = (214, 170, 110, 255), (170, 124, 76, 255)
	# üst: kesik uç (yıllık halkalar)
	end = ell(10, 6, 9, 4.5)
	part(im, end, ring)
	for x, y in ell(10, 6, 6, 3) - ell(10, 6, 5, 2):
		im.set(x, y, ring_d)
	fill(im, {(10, 6), (9, 6)}, ring_d)
	# orta: kabuk, boyuna çizgiler
	y0 = OB_TOP
	for y in range(y0, y0 + OB_MID):
		for x in range(OB_W):
			c = bark
			if x in (0, OB_W - 1):
				c = OL
			elif x in (1, 2):
				c = bark_d
			elif x in (5, 6):
				c = bark_l
			elif x == OB_W - 2:
				c = bark_d
			im.set(x, y, c)
	for x, ys in ((9, (0, 1, 2, 3, 4, 5, 9, 10, 11)), (14, (3, 4, 5, 6, 7, 12, 13, 14)), (4, (8, 9, 10, 11))):
		for yy in ys:
			im.set(x, y0 + yy, bark_d)
	fill(im, {(12, y0 + 9), (12, y0 + 10), (13, y0 + 9)}, (90, 150, 70, 255))  # yosun
	# alt: yuvarlak uç (gölgede)
	yb = OB_TOP + OB_MID
	bot = ell(10, yb, 9.5, 5) - {(x, y) for x in range(OB_W) for y in range(yb - 6, yb)}
	part(im, bot, bark_d)
	fill(im, {(x, y) for x, y in bot if y == yb}, bark)
	return im


def ob_fence():
	"""Tahta barikat: boyuna kalaslar, çapraz destek, çiviler."""
	im = Img(OB_W, OB_TOP + OB_MID + OB_BOT)
	wl = (190, 134, 80, 255)
	# üst: kalas uçları (sivri)
	for i, x0 in enumerate((1, 8, 14)):
		w = 6 if i < 2 else 6
		tip = poly([(x0, 10), (x0, 4 + (i % 2)), (x0 + w / 2, 1 + (i % 2)), (x0 + w, 4 + (i % 2)), (x0 + w, 10)])
		part(im, tip, WOOD)
		fill(im, {(x, y) for x, y in tip if x < x0 + 2}, wl)
	y0 = OB_TOP
	for y in range(y0, y0 + OB_MID):
		for x in range(OB_W):
			c = WOOD
			if x in (0, OB_W - 1):
				c = OL
			elif x in (7, 13):
				c = WOOD_D
			elif x in (1, 8, 14):
				c = wl
			im.set(x, y, c)
	# çapraz destek
	fill(im, line(2, y0 + 1, OB_W - 3, y0 + 13, 2), WOOD_D)
	fill(im, line(2, y0 + 2, OB_W - 3, y0 + 14, 1), (120, 80, 46, 255))
	for x, y in ((4, y0 + 3), (17, y0 + 3), (4, y0 + 12), (17, y0 + 12)):
		im.set(x, y, STEEL)
		im.set(x, y + 1, STEEL_D)
	yb = OB_TOP + OB_MID
	part(im, rect(1, yb, OB_W - 2, yb + OB_BOT - 3), WOOD_D)
	fill(im, rect(1, yb, OB_W - 2, yb), (70, 44, 28, 255))
	for x in (7, 13):
		fill(im, rect(x, yb + 1, x, yb + 4), (70, 44, 28, 255))
	return im


def finish_post():
	"""Bitiş kemeri direği: taş kaide + altın tepelik + dama şerit (16x46). Bayrak (buildings/*_flag) üstüne konur."""
	im = Img(16, 46)
	shadow(im, 8, 43, 7, 2.2)
	part(im, rect(2, 36, 13, 43), STONE_D)
	fill(im, rect(2, 36, 13, 37), STONE_L)
	part(im, rect(4, 6, 11, 36), STONE)
	fill(im, rect(4, 6, 5, 36), STONE_L)
	fill(im, rect(10, 6, 11, 36), STONE_D)
	for y in range(12, 32, 4):  # dama şerit
		for x in range(6, 10, 2):
			fill(im, rect(x + (y // 4) % 2 * 2 - 0, y, x + 1, y + 1), OL if (x // 2 + y // 4) % 2 else WHITE)
	part(im, rect(3, 3, 12, 5), GOLD)
	fill(im, rect(3, 3, 12, 3), GOLD_L)
	part(im, circ(7.5, 1.5, 1.6), GOLD)
	return im


def start_post():
	"""Başlangıç direği: tahta direk + fener (9x24)."""
	im = Img(9, 24)
	shadow(im, 4, 22, 4, 1.5)
	part(im, rect(3, 6, 5, 21), WOOD)
	fill(im, rect(3, 6, 3, 21), (190, 134, 80, 255))
	part(im, rect(1, 1, 7, 6), STEEL_D)
	fill(im, rect(2, 2, 6, 5), (255, 190, 70, 255))
	fill(im, rect(3, 3, 5, 4), (255, 240, 170, 255))
	fill(im, rect(1, 0, 7, 0), OL)
	return im


def rail_tile():
	"""Seyirci önündeki çit korkuluğu (16x7, yatay yinelenir)."""
	im = Img(16, 7)
	part(im, rect(0, 1, 15, 2), WOOD)
	fill(im, rect(0, 1, 15, 1), (190, 134, 80, 255))
	part(im, rect(2, 0, 3, 6), WOOD_D)
	part(im, rect(0, 4, 15, 4), WOOD_D)
	return im


def grass_base(img, seed, x0=0, y0=0, x1=None, y1=None):
	g = [ms.grass_tile(s) for s in (1, 2, 3)]
	r = random.Random(seed)
	x1 = x1 or img.w
	y1 = y1 or img.h
	for ty in range(y0 - y0 % 16, y1, 16):
		for tx in range(x0 - x0 % 16, x1, 16):
			t = g[r.randrange(3)]
			for yy in range(16):
				for xx in range(16):
					X, Y = tx + xx, ty + yy
					if x0 <= X < x1 and y0 <= Y < y1:
						img.set(X, Y, t.p[yy * 16 + xx])


def run_bg():
	"""Koşu pisti arka planı (960x540): çimen kenarlar, toprak pist, şerit çizgileri, başlangıç ve dama bitiş."""
	im = Img(W, H)
	grass_base(im, 3)
	TT, TB = int(28 * K), int(348 * K)  # 42, 522
	d = [ms.dirt_tile(s) for s in (11, 12)]
	r = random.Random(5)
	for ty in range(TT - TT % 16, TB, 16):
		for tx in range(0, W, 16):
			t = d[r.randrange(2)]
			for yy in range(16):
				for xx in range(16):
					Y = ty + yy
					if TT <= Y < TB:
						im.set(tx + xx, Y, t.p[yy * 16 + xx])
	# zemin dokusu: koyu/açık lekeler, ayak izleri, su birikintisi (tekdüzeliği kırar)
	for _ in range(46):
		cx, cy = r.randrange(40, W - 60), r.randrange(TT + 10, TB - 10)
		col = (120, 90, 62, 70) if r.random() < 0.6 else (196, 162, 118, 70)
		for x, y in ell(cx, cy, r.randrange(14, 40), r.randrange(6, 14)):
			if TT + 3 <= y < TB - 3 and (x + y) % 3:
				im.blend(x, y, col)
	for _ in range(30):  # ayak izi çiftleri
		x, y = r.randrange(40, W - 80), r.randrange(TT + 8, TB - 8)
		for k in range(4):
			fx_, fy_ = x + k * 9, y + (2 if k % 2 else -2)
			for xx, yy in ((fx_, fy_), (fx_ + 1, fy_), (fx_ + 2, fy_)):
				im.blend(xx, yy, (100, 72, 50, 120))
	for _ in range(3):  # su birikintisi
		cx, cy = r.randrange(120, W - 160), r.randrange(TT + 40, TB - 40)
		pud = ell(cx, cy, 16, 6)
		for x, y in grow(pud):
			im.set(x, y, DIRT_D)
		for x, y in pud:
			im.set(x, y, (92, 120, 150, 255))
		fill(im, {(x, y) for x, y in pud if y < cy - 3}, (140, 170, 200, 255))
		fill(im, {(cx - 6, cy - 2), (cx - 5, cy - 2), (cx + 3, cy + 1)}, (220, 236, 250, 255))
	# pist kenarı: koyu toprak bordür + üstüne taşan çim tutamları
	for x in range(W):
		for y in (TT, TT + 1, TB - 1, TB - 2):
			im.set(x, y, DIRT_D)
		im.set(x, TT + 2, mix(DIRT_D, DIRT, 0.5))
		im.set(x, TB - 3, mix(DIRT_D, DIRT, 0.5))
	for x in range(0, W, 3):
		h = r.choice((1, 2, 2, 3))
		for k in range(h):
			im.set(x, TT + k, GRASS_D if k else GRASS)
			im.set(x + 1, TB - 1 - k, GRASS_D)
	# şerit çizgileri (kesik tebeşir)
	for i in range(1, 8):
		y = int(TT + (TB - TT) * i / 8.0)
		for x in range(0, W, 24):
			for xx in range(12):
				im.blend(x + xx + (6 if i % 2 else 0), y, (236, 220, 190, 120))
	# başlangıç çizgisi (dünya x 10) ve bitiş damaları (dünya x 600..612)
	sx = int(10 * K)
	for y in range(TT + 3, TB - 3):
		for xx in range(3):
			im.set(sx + xx, y, CHALK if (y // 2) % 6 else (200, 190, 170, 255))
	# şerit numaraları (başlangıçta tebeşirle)
	for i in range(8):
		y = int(TT + (TB - TT) * (i + 0.5) / 8.0)
		ch = str(i + 1)
		gp = glyph_grid(ch)
		for gx, gy in gp:
			for a_ in range(2):
				for b_ in range(2):
					im.blend(sx + 10 + gx * 2 + a_, y - 9 + gy * 2 + b_, (240, 232, 214, 150))
	fx = int(600 * K)
	cell = 9
	for ry in range(int((TB - TT) / cell) + 1):
		for cx in range(2):
			c = (240, 240, 246, 255) if (ry + cx) % 2 == 0 else (30, 28, 40, 255)
			for yy in range(cell):
				for xx in range(cell):
					Y = TT + ry * cell + yy
					if TT <= Y < TB:
						im.set(fx + cx * cell + xx, Y, c)
	# bitişten sonraki alan: hafif altın ton (kazanma bölgesi)
	for y in range(TT, TB):
		for x in range(fx + 2 * cell, W):
			im.blend(x, y, (255, 220, 120, 40))
	# alt/üst çimende küçük süsler
	dec = ms.decor_strip()
	for i in range(26):
		x = r.randrange(10, W - 20)
		y = r.choice((r.randrange(27, 32), r.randrange(526, 530)))
		blit_a(im, frame_of(dec, r.randrange(5), 12), x, y)
	return im


# ================================================================ COIN: arena zemini
def coins_bg():
	im = Img(W, H)
	grass_base(im, 7)
	ax0, ay0, ax1, ay1 = int(6 * K), int(20 * K), int(634 * K), int(354 * K)  # 9, 30, 951, 531
	r = random.Random(11)
	# arena dışı: koyu çit gölgesi bandı
	for y in range(H):
		for x in range(W):
			if not (ax0 <= x < ax1 and ay0 <= y < ay1):
				im.blend(x, y, (20, 30, 24, 120))
	# toprak yamalar (yuvarlak, kenarı tırtıklı)
	d = ms.dirt_tile(12)
	for _ in range(0):  # toprak yamalar kaldırıldı (orta meydan yeterli)
		cx, cy = r.randrange(80, W - 80), r.randrange(80, H - 60)
		rx, ry = r.randrange(26, 54), r.randrange(14, 26)
		for x, y in ell(cx, cy, rx, ry):
			if r.random() < 0.97:
				im.set(x, y, d.p[(y % 16) * 16 + x % 16])
		for x, y in ell(cx, cy, rx + 1.5, ry + 1.2) - ell(cx, cy, rx, ry):
			if r.random() < 0.6:
				im.set(x, y, GRASS_D)
	# süsler: çiçek, mantar, çalı, taş + büyük kaya ve çalılar
	dec = ms.decor_strip()
	for _ in range(170):
		x, y = r.randrange(ax0 + 6, ax1 - 14), r.randrange(ay0 + 6, ay1 - 14)
		blit_a(im, frame_of(dec, r.randrange(5), 12), x, y)
	# orta meydan: taş döşeli halka + altın coin amblemi (oyunun odağı)
	cx, cy = 480, 284
	for px, py in ell(cx, cy + 4, 104, 50):
		im.blend(px, py, (10, 20, 14, 70))
	stone_pts = ell(cx, cy, 100, 46) - ell(cx, cy, 84, 38)
	part(im, stone_pts, STONE)
	for px, py in stone_pts:  # parke taşı deseni
		if (px // 7 + py // 4) % 2 == 0 and (px % 7 == 0 or py % 4 == 0):
			im.set(px, py, MORTAR)
		elif (px * 3 + py * 7) % 11 == 0:
			im.set(px, py, STONE_L)
	for px, py in ell(cx, cy, 84, 38):
		im.set(px, py, d.p[(py % 16) * 16 + px % 16])
	part(im, ell(cx, cy, 22, 13), GOLD_D)
	fill(im, ell(cx, cy, 18, 10), GOLD)
	fill(im, {(px, py) for px, py in ell(cx, cy, 18, 10) if py < cy - 5}, GOLD_L)
	for a in range(5):  # yıldız
		ang = -math.pi / 2 + a * math.tau / 5
		fill(im, line(cx, cy, cx + math.cos(ang) * 12, cy + math.sin(ang) * 7, 2), GOLD_D)
	for a in range(8):  # meydanı çevreleyen küçük taşlar
		ang = a * math.tau / 8
		sx, sy = cx + math.cos(ang) * 112, cy + math.sin(ang) * 54
		part(im, ell(sx, sy, 4, 3), STONE)
		fill(im, {(int(sx) - 1, int(sy) - 1), (int(sx), int(sy) - 1)}, STONE_L)
	for _ in range(10):  # büyük çalı (dört loblu, alt gölgeli)
		while True:
			x, y = r.randrange(ax0 + 24, ax1 - 30), r.randrange(ay0 + 24, ay1 - 20)
			if ((x - cx) / 130) ** 2 + ((y - cy) / 70) ** 2 > 1:
				break
		for px, py in ell(x, y + 6, 15, 3.5):
			im.blend(px, py, (10, 20, 14, 110))
		b = ell(x, y, 8, 6) | ell(x - 7, y + 2, 6, 4.5) | ell(x + 7, y + 2, 6, 4.5) | ell(x - 2, y - 4, 5, 4)
		part(im, b, (46, 104, 52, 255))
		fill(im, {(px, py) for px, py in b if py <= y + 1}, (70, 146, 64, 255))
		fill(im, {(px, py) for px, py in b if py <= y - 3}, (104, 180, 82, 255))
		fill(im, {(x - 4, y - 3), (x + 3, y - 1), (x - 8, y + 1), (x + 6, y + 2)}, (220, 70, 80, 255))
		fill(im, {(x - 4, y - 4), (x + 3, y - 2)}, (255, 160, 160, 255))
	for _ in range(7):  # kaya
		x, y = r.randrange(ax0 + 20, ax1 - 30), r.randrange(ay0 + 20, ay1 - 20)
		for px, py in ell(x + 1, y + 4, 9, 2.5):
			im.blend(px, py, (10, 20, 14, 90))
		rock = ell(x, y, 7, 5)
		part(im, rock, STONE)
		fill(im, {(px, py) for px, py in rock if py < y - 1}, STONE_L)
		fill(im, {(x + 2, y + 1), (x + 3, y + 2), (x - 3, y + 2)}, STONE_D)
	# arena çiti (tahta direk + iki kalas), köşelerde taş direk
	def post(x, y):
		part(im, rect(x, y - 6, x + 3, y + 3), WOOD)
		fill(im, rect(x, y - 6, x + 3, y - 6), (190, 134, 80, 255))
	for x in range(ax0, ax1, 3):  # yatay kalaslar (üst ve alt)
		for y in (ay0 - 4, ay0 - 1):
			im.set(x, y, WOOD if y == ay0 - 4 else WOOD_D)
			im.set(x, y - 1, OL if y == ay0 - 4 else WOOD)
		for y in (ay1 - 3, ay1):
			im.set(x, y, WOOD if y == ay1 - 3 else WOOD_D)
			im.set(x, y - 1, OL if y == ay1 - 3 else WOOD)
			im.set(x + 1, y, WOOD if y == ay1 - 3 else WOOD_D)
			im.set(x + 2, y, WOOD if y == ay1 - 3 else WOOD_D)
	for x in range(ax0, ax1):
		for y in (ay0 - 4, ay0 - 1, ay1 - 3, ay1):
			im.set(x, y, WOOD if y in (ay0 - 4, ay1 - 3) else WOOD_D)
		im.set(x, ay0 - 5, OL)
		im.set(x, ay1 - 4, OL)
		im.set(x, ay1 + 1, OL)
	for y in range(ay0 - 4, ay1 + 1):
		for x in (ax0 - 3, ax0 - 2, ax1 + 1, ax1 + 2):
			im.set(x, y, WOOD if x in (ax0 - 3, ax1 + 1) else WOOD_D)
		im.set(ax0 - 4, y, OL)
		im.set(ax1 + 3, y, OL)
	for x in range(ax0, ax1, 48):
		post(x - 1, ay0 - 2)
		post(x - 1, ay1 - 1)
	for y in range(ay0 + 40, ay1, 48):
		post(ax0 - 4, y)
		post(ax1, y)
	for x, y in ((ax0 - 5, ay0 - 9), (ax1 - 2, ay0 - 9), (ax0 - 5, ay1 - 6), (ax1 - 2, ay1 - 6)):
		part(im, rect(x, y, x + 6, y + 8), STONE)
		fill(im, rect(x, y, x + 6, y + 1), STONE_L)
	return im


# ================================================================ REFLEKS: alacakaranlık düello sahnesi
REACT_GROUND = 382   # karakterlerin ayak çizgisi (sanat pikseli; dünya ~255)


def reaction_bg():
	im = Img(W, H)
	hor = 300
	stops = [(0, (22, 14, 40)), (110, (52, 22, 66)), (210, (128, 40, 66)), (hor, (232, 108, 58))]
	for y in range(H):
		for i in range(len(stops) - 1):
			if stops[i][0] <= y <= stops[i + 1][0]:
				t = (y - stops[i][0]) / max(1, stops[i + 1][0] - stops[i][0])
				# 4 tonlu bant + sınırda dama (dither)
				tb = int(t * 4) / 4.0
				tn = min(1.0, tb + 0.25)
				frac = t * 4 - int(t * 4)
				c0 = mix(stops[i][1] + (255,), stops[i + 1][1] + (255,), tb)
				c1 = mix(stops[i][1] + (255,), stops[i + 1][1] + (255,), tn)
				for x in range(W):
					use = c1 if (frac > 0.75 and (x + y) % 2 == 0) else c0
					im.set(x, y, use)
				break
		else:
			for x in range(W):
				im.set(x, y, (232, 108, 58, 255))
	r = random.Random(13)
	for _ in range(90):  # yıldızlar (üstte)
		x, y = r.randrange(W), r.randrange(0, 150)
		im.set(x, y, (255, 240, 220, 255) if r.random() < 0.3 else (200, 170, 220, 255))
	# güneş: yatay şeritli retro disk
	sx, sy, sr = 480, hor - 6, 74
	for x, y in circ(sx, sy, sr):
		if y > hor + 20:
			continue
		band = (y - (sy - sr))
		if y > sy - 30 and (y - sy) % 9 in (0, 1) and y < hor:
			continue
		im.set(x, y, mix((255, 236, 150, 255), (250, 120, 70, 255), max(0, band) / (2 * sr)))
	# uzak dağlar, yakın tepeler
	def ridge(base, amp, freq, seed, col, rough=0.0):
		rr = random.Random(seed)
		ph = rr.uniform(0, 6)
		for x in range(W):
			h = base - amp * (0.55 * math.sin(x * freq + ph) + 0.3 * math.sin(x * freq * 2.7 + ph * 2) + 0.15 * math.sin(x * freq * 6.1))
			h += rr.uniform(-rough, rough)
			for y in range(int(h), H):
				im.set(x, y, col)
			im.set(x, int(h), mix(col, (232, 108, 58, 255), 0.35))
	ridge(285, 46, 0.011, 1, (98, 36, 74, 255), 0.6)
	ridge(318, 28, 0.017, 2, (62, 24, 56, 255), 0.4)
	ridge(345, 10, 0.03, 3, (40, 20, 42, 255), 0.2)
	# zemin: toprak düzlük (yukarıdan aşağı koyulaşan bantlar), ortada açık düello alanı
	gy = 350
	for y in range(gy, H):
		t = (y - gy) / (H - gy)
		base = mix((116, 66, 58, 255), (44, 24, 34, 255), t)
		for x in range(W):
			c = base
			dx = abs(x - 480) / 480.0
			if dx < 0.75 and y < gy + 90:  # düello alanı: daha açık toprak
				c = mix(base, (170, 104, 74, 255), (1 - dx / 0.75) * 0.45 * (1 - (y - gy) / 90))
			if (x * 7 + y * 13) % 29 == 0:
				c = mix(c, (30, 16, 24, 255), 0.4)
			im.set(x, y, c)
	for y in range(gy, gy + 2):
		for x in range(W):
			im.set(x, y, (150, 80, 62, 255))
	# ön plan kuru ot tutamları (silüet)
	for _ in range(70):
		x = r.randrange(W)
		y = r.randrange(gy + 20, H)
		h = r.randrange(3, 9)
		col = (30, 16, 26, 255)
		for k in range(h):
			im.set(x, y - k, col)
			if k > h // 2:
				im.set(x - 1 if k % 2 else x + 1, y - k, col)
	# ölü ağaçlar (sol ve sağ, silüet)
	def tree(x, y, s, flip):
		col = (24, 12, 26, 255)
		fill(im, line(x, y, x, y - 70 * s, 4), col)
		for a, L, t in ((-0.9, 34, 3), (-2.3, 30, 3), (-1.3, 44, 2), (-2.0, 24, 2)):
			aa = math.pi - a if flip else a
			bx, by = x, y - (44 + L * 0.3) * s
			ex, ey = bx + math.cos(aa) * L * s, by + math.sin(aa) * L * s
			fill(im, line(bx, by, ex, ey, t), col)
			fill(im, line(ex, ey, ex + math.cos(aa - 0.6) * 10 * s, ey + math.sin(aa - 0.6) * 10 * s, 1), col)
		fill(im, ell(x, y, 10 * s, 2.5), col)
	tree(70, 410, 1.6, False)
	tree(905, 420, 1.4, True)
	# uçan kuşlar
	for bx, by in ((300, 120), (318, 112), (690, 150), (706, 158), (560, 90)):
		fill(im, {(bx - 2, by - 1), (bx - 1, by), (bx, by + 1), (bx + 1, by), (bx + 2, by - 1)}, (30, 14, 30, 255))
	# toprağa saplı kılıç ve kayalar (süs)
	for kx, ky in ((150, 470), (800, 486)):
		part(im, ell(kx, ky, 16, 7), (70, 44, 56, 255))
		fill(im, {(x, y) for x, y in ell(kx, ky, 16, 7) if y < ky - 2}, (104, 66, 74, 255))
	part(im, line(860, 470, 866, 438, 1), STEEL)
	part(im, line(856, 446, 872, 449, 1), WOOD_D)
	return im


# ================================================================ üretim
def build():
	global FONT
	files = {}
	FONT = font_sheet()
	files["font.png"] = FONT
	files["clock.png"] = clock_icon()
	files["burst.png"] = burst_strip()
	files["dust.png"] = dust_strip()
	files["sparkle.png"] = sparkle_strip()
	files["pennant.png"] = pennant_strip()
	files["coin.png"] = coin_big_strip()
	files["spectators.png"] = spectators_strip()
	files["crack.png"] = crack_img()
	files["ob_stone.png"] = ob_stone()
	files["ob_log.png"] = ob_log()
	files["ob_fence.png"] = ob_fence()
	files["finish_post.png"] = finish_post()
	files["start_post.png"] = start_post()
	files["rail.png"] = rail_tile()
	files["run_bg.png"] = run_bg()
	files["coins_bg.png"] = coins_bg()
	files["reaction_bg.png"] = reaction_bg()
	return files


FONT = None

if __name__ == "__main__":
	import preview_minigame as pv  # noqa: E402  (önizleme sayfaları ayrı dosyada)
	files = build()
	for path, im in files.items():
		im.save(os.path.join(OUT, path))
	pv.make_previews(files, sys.modules[__name__])
	print("tamam: %d PNG -> %s" % (len(files), os.path.normpath(OUT)))
