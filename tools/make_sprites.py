#!/usr/bin/env python3
"""Özgün pixel art sprite üreticisi (bağımlılıksız: yalnızca zlib + struct).

Kullanım:  python tools/make_sprites.py
Çıktı:     assets/custom/ altında PNG şeritleri + preview_*.png önizleme sayfaları.

Her şekil piksel kümesidir; `part()` önce koyu çerçeveyi (kümenin 1 piksel genişletilmişi),
sonra rengi çizer. Takım rengi (Mavi/Kırmızı) paletten gelir; aynı çizim iki kez üretilir.
"""
import math
import os
import random
import struct
import sys
import zlib

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "custom")

# ---------------------------------------------------------------- palet (~24 renk)
OL = (26, 20, 36, 255)            # koyu çerçeve
SKIN = (255, 217, 176, 255)
SKIN_D = (226, 164, 124, 255)
STEEL = (206, 214, 228, 255)
STEEL_D = (132, 144, 168, 255)
GOLD = (255, 208, 72, 255)
GOLD_D = (200, 138, 40, 255)
WOOD = (150, 96, 52, 255)
WOOD_D = (98, 62, 38, 255)
WHITE = (250, 250, 255, 255)
LEAF = (88, 170, 74, 255)
SHADOW = (10, 10, 30, 80)
TEAMS = {
	"blue": {"m": (60, 112, 226, 255), "l": (118, 168, 255, 255), "d": (32, 56, 142, 255)},
	"red": {"m": (224, 70, 60, 255), "l": (255, 128, 106, 255), "d": (142, 32, 40, 255)},
}


# ---------------------------------------------------------------- tuval
class Img:
	def __init__(self, w, h):
		self.w, self.h = w, h
		self.p = [(0, 0, 0, 0)] * (w * h)

	def set(self, x, y, c):
		if 0 <= x < self.w and 0 <= y < self.h:
			self.p[y * self.w + x] = c

	def get(self, x, y):
		if 0 <= x < self.w and 0 <= y < self.h:
			return self.p[y * self.w + x]
		return (0, 0, 0, 0)

	def blit(self, o, ox, oy):
		for y in range(o.h):
			for x in range(o.w):
				c = o.p[y * o.w + x]
				if c[3] > 0:
					self.set(ox + x, oy + y, c)

	def save(self, path):
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


def over(img, bg):
	"""Yarı saydam pikselleri bg üzerine kar (önizleme için)."""
	o = Img(img.w, img.h)
	for i, c in enumerate(img.p):
		a = c[3] / 255.0
		o.p[i] = tuple(int(c[k] * a + bg[k] * (1 - a)) for k in range(3)) + (255,)
	return o


# ---------------------------------------------------------------- şekiller (piksel kümeleri)
def circ(cx, cy, r):
	return {(x, y) for y in range(int(cy - r - 1), int(cy + r + 2)) for x in range(int(cx - r - 1), int(cx + r + 2))
		if (x - cx) ** 2 + (y - cy) ** 2 <= r * r}


def ell(cx, cy, rx, ry):
	return {(x, y) for y in range(int(cy - ry - 1), int(cy + ry + 2)) for x in range(int(cx - rx - 1), int(cx + rx + 2))
		if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0}


def rect(x0, y0, x1, y1):
	return {(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)}


def line(x0, y0, x1, y1, th=1):
	pts = set()
	n = int(max(abs(x1 - x0), abs(y1 - y0))) * 2 + 1
	for i in range(n + 1):
		t = i / n
		x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
		for j in range(th):
			for k in range(th):
				pts.add((int(round(x)) + j - (th - 1) // 2, int(round(y)) + k - (th - 1) // 2))
	return pts


def poly(points):
	"""Dolu çokgen (ışın taraması)."""
	ys = [p[1] for p in points]
	out = set()
	for y in range(int(min(ys)), int(max(ys)) + 1):
		xs = []
		for i in range(len(points)):
			(ax, ay), (bx, by) = points[i], points[(i + 1) % len(points)]
			if (ay <= y + 0.5 < by) or (by <= y + 0.5 < ay):
				xs.append(ax + (y + 0.5 - ay) / (by - ay) * (bx - ax))
		xs.sort()
		for i in range(0, len(xs) - 1, 2):
			for x in range(int(round(xs[i])), int(round(xs[i + 1]))):
				out.add((x, y))
	return out


def shift(s, dx, dy):
	return {(x + dx, y + dy) for x, y in s}


def grow(s):
	o = set(s)
	for x, y in s:
		o.update(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
	return o


def part(img, s, col, ol=OL):
	if ol is not None:
		for x, y in grow(s):
			img.set(x, y, ol)
	for x, y in s:
		img.set(x, y, col)


def fill(img, s, col):
	for x, y in s:
		img.set(x, y, col)


def shadow(img, cx, cy, rx, ry):
	for x, y in ell(cx, cy, rx, ry):
		img.set(x, y, SHADOW)


# ---------------------------------------------------------------- kahramanlar (32x32)
HS = 32


def hero_frame(kind, team, anim, f):
	T = TEAMS[team]
	im = Img(HS, HS)
	bob = 0
	lean = 0
	legs = ((0, 0), (0, 0))
	if anim == "idle":
		bob = (0, -1)[f]
	elif anim == "run":
		bob = (0, -1, 0, -1)[f]
		legs = (((-2, 0), (2, 1)), ((0, 1), (0, 0)), ((2, 0), (-2, 1)), ((0, 0), (0, 1)))[f]
		lean = 1
	elif anim == "attack":
		lean = (-1, 1, 2)[f]
		bob = (0, 0, 1)[f]
	cx = 15 + lean
	shadow(im, 16, 29, 9, 2.5)
	# pelerin (arkada, uçuşan)
	flap = (0, 1, 2, 1)[f % 4] + (2 if anim == "run" else 0)
	cape = poly([(cx - 7, 13 + bob), (cx + 6, 13 + bob), (cx + 7, 26 + bob), (cx - 9 - flap, 28 + bob + (flap // 2))])
	part(im, cape, T["d"])
	fill(im, {(x, y) for x, y in cape if y > 20 + bob and x < cx - 3}, T["m"])
	# bacaklar
	for i, bx in enumerate((cx - 3, cx + 2)):
		dx, dy = legs[i]
		part(im, rect(bx + dx // 2, 24 + bob // 2, bx + 1 + dx // 2, 27 - dy), WOOD_D)
		part(im, rect(bx + dx - 1, 27 - dy, bx + 2 + dx, 28 - dy), WOOD)
	# gövde (tunik)
	body = ell(cx, 19 + bob, 6, 5.5)
	part(im, body, T["m"])
	fill(im, {(x, y) for x, y in body if x < cx - 1 and y < 19 + bob}, T["l"])
	fill(im, rect(cx - 5, 22 + bob, cx + 5, 22 + bob), GOLD_D)  # kemer
	fill(im, {(cx, 22 + bob), (cx + 1, 22 + bob)}, GOLD)
	fill(im, {(cx, 17 + bob), (cx + 1, 17 + bob), (cx, 18 + bob), (cx + 1, 18 + bob)}, GOLD)  # göğüs rozeti
	# silah (kafanın altına, elden çıkar) - gövdeden sonra çizilir
	hx, hy = cx + 7, 20 + bob  # sağ el
	if kind == "warrior":
		# sol kolda kalkan
		sh = circ(cx - 7, 20 + bob, 4)
		part(im, sh, T["l"])
		fill(im, circ(cx - 7, 20 + bob, 1.5), GOLD)
		if anim == "attack":
			sw = ((hx - 3, hy - 2, hx - 6, hy - 14), (hx, hy - 3, hx + 9, hy - 8), (hx, hy, hx + 8, hy + 7))[f]
		elif anim == "run":
			sw = (hx, hy - 1, hx + 6, hy - 10)
		else:
			sw = (hx, hy - 1, hx + 2, hy - 12)
		if anim == "attack" and f >= 1:  # savuruş izi
			a0, a1 = ((-1.9, -0.6), (-0.3, 0.9))[f - 1]
			for t in range(7):
				a = a0 + (a1 - a0) * t / 6.0
				fill(im, {(int(cx + 5 + math.cos(a) * 14), int(19 + bob + math.sin(a) * 14))}, WHITE)
		part(im, line(sw[0], sw[1], sw[2], sw[3], 2), STEEL)
		fill(im, line(sw[0], sw[1], sw[2], sw[3], 1), WHITE)
		gx, gy = sw[0], sw[1]
		part(im, line(gx - 2, gy + 1, gx + 2, gy - 1, 1), GOLD)
	elif kind == "lancer":
		if anim == "attack":
			dx = (-3, 2, 0)[f]
			sp = (hx - 13 + dx, hy + 1, hx + 1 + dx, hy - 1)
		elif anim == "run":
			sp = (hx - 7, hy + 6, hx + 8, hy - 7)
		else:
			sp = (hx + 1, hy + 8, hx + 2, hy - 13)
		part(im, line(sp[0], sp[1], sp[2], sp[3], 1), WOOD)
		ux, uy = sp[2] - sp[0], sp[3] - sp[1]
		ln = math.hypot(ux, uy)
		ux, uy = ux / ln, uy / ln
		tip = poly([(sp[2] - ux * 1 - uy * 2.5, sp[3] - uy * 1 + ux * 2.5), (sp[2] + ux * 5, sp[3] + uy * 5),
			(sp[2] - ux * 1 + uy * 2.5, sp[3] - uy * 1 - ux * 2.5)])
		part(im, tip, STEEL)
		fill(im, {(int(sp[2] - ux * 2), int(sp[3] - uy * 2))}, T["l"])
		# flama
		fx, fy = int(sp[2] - ux * 4), int(sp[3] - uy * 4)
		fill(im, {(fx, fy), (fx - 1, fy), (fx - 2, fy + 1), (fx - 1, fy + 1)}, T["m"])
	elif kind == "archer":
		# sadak (sırtta)
		part(im, line(cx - 5, 13 + bob, cx - 7, 22 + bob, 2), WOOD_D)
		fill(im, {(cx - 5, 12 + bob), (cx - 4, 11 + bob), (cx - 6, 11 + bob)}, WHITE)
		pull = 0
		if anim == "attack":
			pull = (3, 5, 0)[f]
		bow_x = hx + 3
		bow = {(int(bow_x + math.cos(a) * 9 * 0.55), int(hy + math.sin(a) * 9)) for a in [i * 0.05 for i in range(-30, 31)]}
		part(im, bow, WOOD)
		top, bot = (int(bow_x + math.cos(-1.5) * 5), hy - 9), (int(bow_x + math.cos(1.5) * 5), hy + 9)
		sx = hx - pull + 1
		fill(im, line(top[0], top[1], sx, hy, 1), WHITE)
		fill(im, line(sx, hy, bot[0], bot[1], 1), WHITE)
		if anim == "attack" and f < 2:
			part(im, line(sx, hy, bow_x + 6, hy, 1), WOOD_D, ol=None)
			fill(im, {(bow_x + 7, hy), (bow_x + 6, hy - 1), (bow_x + 6, hy + 1)}, STEEL)
		elif anim == "attack":  # bırakıldı: ok uçuyor
			part(im, line(bow_x + 4, hy, bow_x + 11, hy, 1), WOOD_D, ol=None)
			fill(im, {(bow_x + 12, hy), (bow_x + 11, hy - 1), (bow_x + 11, hy + 1)}, STEEL)
	# sağ el
	part(im, circ(hx, hy, 1.6), SKIN)
	# kafa
	hdx = lean
	head = circ(16 + hdx, 10 + bob, 6.6)
	part(im, head, SKIN)
	fill(im, {(x, y) for x, y in head if x < 12 + hdx and y > 10 + bob}, SKIN_D)
	# yüz (sağa bakıyor)
	ey = 11 + bob
	fill(im, {(17 + hdx, ey), (17 + hdx, ey + 1), (21 + hdx, ey), (21 + hdx, ey + 1)}, OL)
	fill(im, {(18 + hdx, ey), (22 + hdx, ey)}, WHITE)
	fill(im, {(16 + hdx, ey + 3), (22 + hdx, ey + 3)}, (255, 150, 150, 255))
	fill(im, {(19 + hdx, ey + 4), (20 + hdx, ey + 4)}, SKIN_D)
	# başlık
	capmask = {(x, y) for x, y in head if y < 9 + bob}
	if kind == "warrior":
		fill(im, capmask, STEEL)
		fill(im, {(x, y) for x, y in capmask if y < 6 + bob and x < 17 + hdx}, WHITE)
		fill(im, rect(10 + hdx, 9 + bob, 22 + hdx, 9 + bob) & head, STEEL_D)
		fill(im, line(19 + hdx, 6 + bob, 19 + hdx, 10 + bob, 1), STEEL_D)  # burun siperi
		crest = poly([(11 + hdx, 5 + bob), (15 + hdx, 1 + bob), (21 + hdx, 3 + bob), (17 + hdx, 6 + bob)])
		part(im, shift(crest, 0, 0) | {(10 + hdx - flap // 2, 6 + bob), (9 + hdx - flap // 2, 7 + bob)}, T["l"])
		fill(im, {(15 + hdx, 3 + bob), (16 + hdx, 3 + bob)}, T["m"])
	elif kind == "archer":
		hood = capmask | {(x, y) for x, y in head if x < 11 + hdx}
		fill(im, hood, T["m"])
		fill(im, {(x, y) for x, y in hood if y < 6 + bob}, T["l"])
		fill(im, rect(10 + hdx, 9 + bob, 22 + hdx, 9 + bob) & head, T["d"])
		part(im, line(14 + hdx, 4 + bob, 20 + hdx, -1 + bob, 2), LEAF)  # tüy
		fill(im, {(19 + hdx, 0 + bob), (20 + hdx, -1 + bob)}, WHITE)
	elif kind == "lancer":
		fill(im, capmask, GOLD)
		fill(im, {(x, y) for x, y in capmask if y < 6 + bob and x < 16 + hdx}, WHITE)
		fill(im, rect(10 + hdx, 9 + bob, 22 + hdx, 9 + bob) & head, GOLD_D)
		wing = poly([(10 + hdx, 8 + bob), (4 + hdx, 3 + bob), (5 + hdx, 8 + bob)]) | poly([(22 + hdx, 8 + bob), (28 + hdx, 3 + bob), (27 + hdx, 8 + bob)])
		part(im, wing, WHITE)
		part(im, line(16 + hdx, 4 + bob, 16 + hdx, 1 + bob, 3), T["m"])
		fill(im, line(15 + hdx, 3 + bob, 15 + hdx, 0 + bob, 1), T["l"])
	return im


# ---------------------------------------------------------------- birimler (24x24)
US = 24


def unit_frame(kind, team, anim, f):
	T = TEAMS[team]
	im = Img(US, US)
	bob = 0 if anim == "idle" and f == 0 else (-1 if anim == "idle" else (0, -1, 0, -1)[f])
	legs = (((-1, 0), (1, 0)), ((0, 1), (0, 0)), ((1, 0), (-1, 0)), ((0, 0), (0, 1)))[f] if anim == "run" else ((0, 0), (0, 0))
	cx = 11
	if kind == "cannon":
		return cannon_frame(team, anim, f)
	shadow(im, 12, 21, 6, 2)
	for i, bx in enumerate((cx - 2, cx + 1)):
		dx, dy = legs[i]
		part(im, rect(bx + dx, 17, bx + dx, 19 - dy), WOOD_D)
	robe = kind == "healer"
	body = ell(cx + 0.5, 14 + bob, 4.2, 4.2) if not robe else poly([(cx - 4, 11 + bob), (cx + 5, 11 + bob), (cx + 6, 19), (cx - 5, 19)])
	part(im, body, WHITE if robe else T["m"])
	fill(im, {(x, y) for x, y in body if x < cx and y < 14 + bob}, (225, 230, 245, 255) if robe else T["l"])
	if robe:
		fill(im, rect(cx - 1, 14 + bob, cx + 2, 18), T["m"])
	else:
		fill(im, rect(cx - 3, 16 + bob, cx + 4, 16 + bob), GOLD_D)
	hx, hy = cx + 5, 14 + bob
	if kind == "swordsman":
		atk = 0
		part(im, line(hx, hy, hx + 2, hy - 8, 2), STEEL)
		fill(im, {(hx + 1, hy - 7)}, WHITE)
		fill(im, line(hx - 1, hy - 1, hx + 2, hy - 2, 1), GOLD)
	elif kind == "archer":
		bow = {(int(hx + 1 + math.cos(a) * 3), int(hy + math.sin(a) * 6)) for a in [i * 0.06 for i in range(-26, 27)]}
		part(im, bow, WOOD)
		fill(im, line(hx + 1, hy - 6, hx + 1, hy + 6, 1), WHITE)
	elif kind == "shield":
		part(im, line(hx - 2, hy - 1, hx + 1, hy - 8, 1), STEEL)  # kısa mızrak
	elif kind == "healer":
		part(im, line(hx, hy + 3, hx, hy - 8, 1), WOOD)
		part(im, circ(hx, hy - 9, 1.8), GOLD)
	part(im, circ(hx, hy, 1.2), SKIN)
	if kind == "shield":  # belirgin büyük kalkan (öne)
		sh = poly([(cx + 1, 8 + bob), (cx + 10, 8 + bob), (cx + 10, 16 + bob), (cx + 5.5, 21 + bob), (cx + 1, 16 + bob)])
		part(im, sh, T["l"])
		fill(im, {(x, y) for x, y in sh if x > cx + 5}, T["m"])
		fill(im, rect(cx + 1, 8 + bob, cx + 9, 8 + bob), WHITE)
		fill(im, {(cx + 5, 13 + bob), (cx + 6, 13 + bob), (cx + 5, 14 + bob), (cx + 6, 14 + bob)}, GOLD)
	head = circ(cx + 1, 8 + bob, 4.6)
	part(im, head, SKIN)
	ey = 8 + bob
	fill(im, {(cx + 2, ey), (cx + 2, ey + 1), (cx + 5, ey), (cx + 5, ey + 1)}, OL)
	cap = {(x, y) for x, y in head if y < 7 + bob}
	if kind == "swordsman":
		fill(im, cap, STEEL)
		fill(im, {(x, y) for x, y in cap if y < 5 + bob and x < cx + 2}, WHITE)
		fill(im, rect(cx - 4, 7 + bob, cx + 6, 7 + bob) & head, STEEL_D)
		part(im, {(cx, 3 + bob), (cx + 1, 3 + bob), (cx + 2, 2 + bob), (cx - 1, 4 + bob)}, T["l"])
	elif kind == "archer":
		hood = cap | {(x, y) for x, y in head if x < cx - 1}
		fill(im, hood, T["m"])
		fill(im, {(x, y) for x, y in hood if y < 5 + bob}, T["l"])
		fill(im, {(cx + 3, 3 + bob), (cx + 4, 2 + bob), (cx + 5, 1 + bob)}, LEAF)
	elif kind == "shield":
		fill(im, cap, STEEL_D)
		fill(im, {(x, y) for x, y in cap if y < 5 + bob}, STEEL)
		fill(im, rect(cx - 4, 7 + bob, cx + 6, 7 + bob) & head, OL)
		fill(im, {(cx + 1, 3 + bob), (cx + 2, 3 + bob)}, T["l"])
	elif kind == "healer":
		hood = cap | {(x, y) for x, y in head if x < cx - 1}
		fill(im, hood, WHITE)
		fill(im, rect(cx - 4, 7 + bob, cx + 6, 7 + bob) & head, T["m"])
	return im


def cannon_frame(team, anim, f):
	T = TEAMS[team]
	im = Img(US, US)
	roll = 0 if anim == "idle" else f
	shadow(im, 12, 21, 9, 2.2)
	# namlu (sağa bakıyor)
	bar = poly([(4, 10), (19, 8), (21, 11), (19, 14), (4, 15)])
	part(im, bar, (62, 62, 78, 255))
	fill(im, {(x, y) for x, y in bar if y < 11}, (110, 112, 132, 255))
	part(im, rect(19, 8, 21, 14), (62, 62, 78, 255))
	fill(im, {(21, 11), (20, 11)}, OL)
	fill(im, rect(8, 9, 8, 14), GOLD_D)
	# gövde (takım renginde)
	cart = rect(5, 14, 17, 17)
	part(im, cart, T["m"])
	fill(im, rect(5, 14, 17, 14), T["l"])
	# tekerlek
	wr = 4.4
	part(im, circ(10, 18, wr), WOOD)
	fill(im, circ(10, 18, 2), WOOD_D)
	fill(im, {(10, 18)}, GOLD)
	a0 = roll * 0.8
	for k in range(4):
		a = a0 + k * math.pi / 2
		fill(im, {(int(round(10 + math.cos(a) * 3.6)), int(round(18 + math.sin(a) * 3.6)))}, WOOD_D)
	# topçu (arkada)
	head = circ(4, 8, 3.2)
	part(im, head, SKIN)
	fill(im, {(x, y) for x, y in head if y < 7}, T["d"])
	fill(im, {(5, 8), (6, 8)}, OL)
	part(im, rect(2, 11, 5, 14), T["m"])
	return im


# ---------------------------------------------------------------- yerleşim / şerit üretimi
ANIMS = {"idle": 2, "run": 4, "attack": 3}


def strip(frames):
	w = frames[0].w
	im = Img(w * len(frames), frames[0].h)
	for i, fr in enumerate(frames):
		im.blit(fr, i * w, 0)
	return im


# ---------------------------------------------------------------- zemin
def grass_tile(seed):
	r = random.Random(seed)
	im = Img(16, 16)
	base, dk, lt = (94, 170, 76, 255), (78, 148, 66, 255), (124, 196, 92, 255)
	for y in range(16):
		for x in range(16):
			im.set(x, y, base)
	for _ in range(14):
		im.set(r.randrange(16), r.randrange(16), r.choice((dk, dk, lt)))
	for _ in range(3):  # çim tutamı
		x, y = r.randrange(1, 15), r.randrange(2, 15)
		im.set(x, y, lt)
		im.set(x, y - 1, lt)
		im.set(x + 1, y, dk)
	return im


def dirt_tile(seed):
	r = random.Random(seed)
	im = Img(16, 16)
	base, dk, lt = (190, 150, 100, 255), (160, 120, 80, 255), (214, 178, 126, 255)
	for y in range(16):
		for x in range(16):
			im.set(x, y, base)
	for _ in range(16):
		im.set(r.randrange(16), r.randrange(16), r.choice((dk, lt)))
	for _ in range(2):  # küçük çakıl
		x, y = r.randrange(1, 14), r.randrange(1, 14)
		im.set(x, y, STEEL_D)
		im.set(x + 1, y, STEEL)
	return im


def stone_tile(seed):
	"""Tuğla/taş engel döşemesi (yinelenebilir, belirgin gri-mavi)."""
	r = random.Random(seed)
	im = Img(16, 16)
	face, lt, dk, mortar = (128, 138, 160, 255), (166, 176, 196, 255), (92, 100, 126, 255), (58, 62, 84, 255)
	for y in range(16):
		for x in range(16):
			im.set(x, y, face)
	for y in (0, 8):  # yatay harç
		for x in range(16):
			im.set(x, y + 7 if y == 0 else y + 7, mortar)
	for x in range(16):
		im.set(x, 7, mortar)
		im.set(x, 15, mortar)
	for x in (3, 11):  # düşey harç (sıralı kayık)
		for y in range(0, 7):
			im.set(x, y, mortar)
	for x in (7, 15):
		for y in range(8, 15):
			im.set(x, y, mortar)
	for y0 in (0, 8):  # tuğla üstü açık, altı koyu
		for x in range(16):
			if im.get(x, y0) == face:
				im.set(x, y0, lt)
			if im.get(x, y0 + 6) == face:
				im.set(x, y0 + 6, dk)
	for _ in range(6):
		x, y = r.randrange(16), r.randrange(16)
		if im.get(x, y) == face:
			im.set(x, y, dk if r.random() < 0.5 else lt)
	return im


def decor_strip():
	"""Çarpışmasız süs: çiçek (2), mantar, küçük çalı, taş (hepsi alçak/küçük, 12x12 kare)."""
	frames = []
	def f():
		return Img(12, 12)
	# çiçek sarı
	im = f(); fill(im, {(6, 7), (6, 8), (6, 9)}, LEAF)
	fill(im, {(5, 6), (7, 6), (6, 5), (6, 7)}, WHITE); fill(im, {(6, 6)}, GOLD); frames.append(im)
	# çiçek pembe/mor
	im = f(); fill(im, {(6, 7), (6, 8), (5, 9), (6, 9)}, LEAF)
	fill(im, {(5, 6), (7, 6), (6, 5), (6, 7)}, (255, 140, 190, 255)); fill(im, {(6, 6)}, GOLD); frames.append(im)
	# mantar
	im = f(); part(im, rect(5, 7, 6, 9), WHITE); part(im, ell(6, 6, 3, 1.6), (220, 70, 70, 255))
	fill(im, {(5, 5), (7, 6)}, WHITE); frames.append(im)
	# çalı (alçak yeşil topak)
	im = f(); b = ell(6, 7, 4.5, 3)
	part(im, b, (70, 150, 66, 255)); fill(im, {(x, y) for x, y in b if y < 6}, (104, 184, 84, 255))
	fill(im, {(4, 7), (8, 6)}, (200, 60, 70, 255)); frames.append(im)
	# küçük çakıl
	im = f(); part(im, ell(5, 8, 2.2, 1.4), STEEL_D); fill(im, {(4, 7), (5, 7)}, STEEL)
	part(im, ell(8, 9, 1.4, 1), STEEL_D); frames.append(im)
	return strip(frames)


# ---------------------------------------------------------------- üs ve bayrak
def castle(team):
	T = TEAMS[team]
	im = Img(64, 64)
	stone, stl, std = (150, 158, 180, 255), (184, 192, 210, 255), (104, 112, 140, 255)
	shadow(im, 32, 59, 29, 4)
	def tower(x0, y0, x1):
		body = rect(x0, y0, x1, 58)
		part(im, body, stone)
		fill(im, rect(x0, y0, x1, y0), stl)
		for y in range(y0 + 4, 58, 6):  # tuğla çizgileri
			for x in range(x0 + 1, x1):
				if (x + y) % 5 != 0:
					im.set(x, y, std)
		fill(im, rect(x0, y0 + 1, x0 + 1, 58), stl)
		fill(im, rect(x1 - 1, y0 + 1, x1, 58), std)
		# mazgal
		for x in range(x0, x1 + 1, 4):
			part(im, rect(x, y0 - 3, min(x + 2, x1), y0 - 1), stone)
		# takım renkli çatı
		mid = (x0 + x1) / 2
		roof = poly([(x0 - 2, y0 - 3), (mid + 0.5, y0 - 15), (x1 + 3, y0 - 3)])
		part(im, roof, T["m"])
		fill(im, {(x, y) for x, y in roof if x < mid}, T["l"])
		fill(im, line(int(mid), y0 - 15, int(mid), y0 - 20, 1), WOOD_D)
		fill(im, poly([(mid + 1, y0 - 20), (mid + 6, y0 - 18), (mid + 1, y0 - 16)]), T["m"])
		fill(im, rect(int(mid) - 1, y0 + 8, int(mid), y0 + 12), OL)  # mazgal penceresi
	tower(3, 26, 16)
	tower(47, 26, 60)
	keep = rect(14, 34, 49, 58)
	part(im, keep, stone)
	for y in range(38, 58, 6):
		for x in range(15, 49):
			if (x + y) % 6 != 0:
				im.set(x, y, std)
	fill(im, rect(14, 34, 49, 34), stl)
	for x in range(14, 50, 5):
		part(im, rect(x, 31, x + 2, 33), stone)
	# kapı
	gate = poly([(26, 58), (26, 46), (29, 42), (35, 42), (38, 46), (38, 58)])
	part(im, gate, WOOD_D)
	fill(im, rect(27, 47, 37, 57), WOOD)
	for x in (29, 32, 35):
		fill(im, line(x, 45, x, 57, 1), WOOD_D)
	fill(im, {(36, 52), (36, 53)}, GOLD)
	# takım flaması
	fill(im, rect(30, 36, 34, 40), T["m"])
	fill(im, poly([(30, 40), (34, 40), (32, 44)]), T["m"])
	fill(im, rect(30, 36, 34, 36), T["l"])
	return im


def flag_strip(team, n=4):
	T = TEAMS[team]
	frames = []
	for f in range(n):
		im = Img(24, 40)
		shadow(im, 4, 38, 4, 1.5)
		part(im, rect(3, 3, 4, 37), WOOD)
		fill(im, rect(3, 3, 3, 37), WOOD_D if False else (176, 120, 70, 255))
		part(im, circ(3.5, 2, 1.8), GOLD)
		cells = set()
		for i in range(0, 18):
			wv = int(round(math.sin(i / 2.6 - f * math.pi / 2) * 1.6))
			hgt = int(round(14 - i * 0.62))
			for j in range(hgt):
				cells.add((5 + i, 5 + j + wv + int(i * 0.15)))
		part(im, cells, T["m"])
		fill(im, {(x, y) for x, y in cells if y < 8 + int((x - 5) * 0.15) + 1 + int(round(math.sin((x - 5) / 2.6 - f * math.pi / 2) * 1.6))}, T["l"])
		fill(im, {(7, 11), (8, 10), (8, 11), (9, 11)}, WHITE)
		frames.append(im)
	return strip(frames)


# ---------------------------------------------------------------- efekt ve nesneler
def arrow_sprite():
	im = Img(16, 8)
	part(im, line(2, 4, 12, 4, 1), WOOD, ol=None)
	fill(im, line(2, 3, 12, 3, 1), (200, 150, 90, 255))
	part(im, poly([(11, 1), (15, 4), (11, 7)]), STEEL)
	fill(im, {(1, 3), (0, 2), (1, 5), (0, 6), (2, 2), (2, 6)}, WHITE)
	return im


def ball_sprite():
	im = Img(10, 10)
	part(im, circ(4.5, 4.5, 3.6), (70, 72, 90, 255))
	fill(im, {(3, 3), (4, 3), (3, 4)}, (150, 156, 180, 255))
	return im


def boom_strip():
	frames = []
	spec = [(5, (255, 244, 170, 255), (255, 170, 60, 255)), (10, (255, 220, 100, 255), (240, 110, 40, 255)),
		(14, (255, 170, 70, 255), (200, 60, 40, 255)), (15, (110, 70, 60, 200), (70, 50, 54, 160))]
	r = random.Random(7)
	for i, (rad, c1, c2) in enumerate(spec):
		im = Img(32, 32)
		blob = ell(16, 16, rad, rad * 0.9)
		pts = set(blob)
		for k in range(10):
			a = k * 0.628 + i * 0.4
			pts |= circ(16 + math.cos(a) * rad * 0.75, 16 + math.sin(a) * rad * 0.7, rad * 0.35)
		if i == 3:  # duman: delikli
			pts = {p for p in pts if (p[0] * 7 + p[1] * 13) % 5 != 0}
		part(im, pts, c2)
		inner = ell(16, 16, rad * 0.6, rad * 0.55)
		fill(im, inner, c1)
		if i < 3:
			fill(im, ell(16, 16, rad * 0.25, rad * 0.25), WHITE)
		frames.append(im)
	return strip(frames)


def wall_tile(kind):
	im = Img(20, 20)
	if kind == "wood":
		part(im, rect(1, 1, 18, 18), WOOD)
		for y in (6, 12):
			fill(im, rect(1, y, 18, y), WOOD_D)
		fill(im, rect(1, 1, 18, 1), (190, 134, 80, 255))
		for x, y in ((4, 3), (15, 3), (4, 9), (15, 9), (4, 15), (15, 15)):
			fill(im, {(x, y)}, STEEL_D)
	else:
		part(im, rect(1, 1, 18, 18), STEEL_D)
		for y in (6, 12):
			fill(im, rect(1, y, 18, y), OL)
		fill(im, rect(1, 1, 18, 1), STEEL)
		for x, y in ((7, 3), (13, 9), (5, 15)):
			fill(im, rect(x, y, x, y + 2), OL)
	return im


def coin_strip():
	frames = []
	for rx in (5, 3.5, 1.5, 3.5):
		im = Img(12, 12)
		e = ell(6, 6, rx, 5)
		part(im, e, GOLD)
		if rx > 2:
			fill(im, ell(6, 6, rx - 1.6, 3.4), GOLD_D)
			fill(im, ell(6, 6, max(rx - 2.4, 0.5), 2.6), GOLD)
			fill(im, {(4, 3)}, WHITE)
		frames.append(im)
	return strip(frames)


# ---------------------------------------------------------------- minik 3x5 yazı tipi (önizleme etiketleri)
FONT = {
	"A": "010101111101101", "B": "110101110101110", "C": "011100100100011", "D": "110101101101110",
	"E": "111100110100111", "F": "111100110100100", "G": "011100101101011", "H": "101101111101101",
	"I": "111010010010111", "J": "001001001101010", "K": "101101110101101", "L": "100100100100111",
	"M": "101111111101101", "N": "110101101101101", "O": "010101101101010", "P": "110101110100100",
	"Q": "010101101111011", "R": "110101110101101", "S": "011100010001110", "T": "111010010010010",
	"U": "101101101101111", "V": "101101101101010", "W": "101101111111101", "X": "101101010101101",
	"Y": "101101010010010", "Z": "111001010100111", "0": "111101101101111", "1": "010110010010111",
	"2": "110001010100111", "3": "110001010001110", "4": "101101111001001", "5": "111100110001110",
	"6": "011100111101111", "7": "111001010010010", "8": "111101111101111", "9": "111101111001110",
	"-": "000000111000000", ":": "000010000010000", " ": "000000000000000", "/": "001001010100100",
	"(": "010100100100010", ")": "010001001001010", ".": "000000000000010", "x": "000101010101000",
}


def text(img, x, y, s, col=(240, 240, 250, 255), k=1):
	for ch in s.upper():
		g = FONT.get(ch, FONT[" "])
		for i, v in enumerate(g):
			if v == "1":
				for a in range(k):
					for b in range(k):
						img.set(x + (i % 3) * k + a, y + (i // 3) * k + b, col)
		x += 4 * k


def label_w(s, k=1):
	return len(s) * 4 * k


# ---------------------------------------------------------------- ana akış
HEROES = [("warrior", "SAVASCI"), ("archer", "OKCU"), ("lancer", "MIZRAKCI")]
UNITS = [("swordsman", "KILICCI"), ("archer", "OKCU"), ("shield", "KALKANCI"), ("cannon", "TOPCU"), ("healer", "SIFACI")]
BG = (70, 130, 74, 255)
PANEL = (36, 40, 56, 255)


def build():
	files = {}
	# kahraman / birim şeritleri
	for team in TEAMS:
		for kind, _ in HEROES:
			for anim, n in ANIMS.items():
				files["units/%s/%s_%s.png" % (team, kind, anim)] = strip([hero_frame(kind, team, anim, f) for f in range(n)])
		for kind, _ in UNITS:
			for anim in ("idle", "run"):
				n = ANIMS[anim]
				files["units/%s/u_%s_%s.png" % (team, kind, anim)] = strip([unit_frame(kind, team, anim, f) for f in range(n)])
		files["buildings/%s_castle.png" % team] = castle(team)
		files["buildings/%s_flag.png" % team] = flag_strip(team)
	files["terrain/grass.png"] = strip([grass_tile(s) for s in (1, 2, 3)])
	files["terrain/dirt.png"] = strip([dirt_tile(s) for s in (11, 12)])
	files["terrain/stone.png"] = strip([stone_tile(s) for s in (21, 22)])
	files["terrain/decor.png"] = decor_strip()
	files["fx/arrow.png"] = arrow_sprite()
	files["fx/ball.png"] = ball_sprite()
	files["fx/boom.png"] = boom_strip()
	files["fx/wall_wood.png"] = wall_tile("wood")
	files["fx/wall_stone.png"] = wall_tile("stone")
	files["fx/coin.png"] = coin_strip()
	return files


def preview(files):
	# 1) kahramanlar ve birimler: tüm animasyon kareleri, Mavi (üst) ve Kırmızı (alt), 4x
	K = 4
	def sheet_block(items, size, team, anims, x0, y0, sheet, prefix):
		x = x0
		for kind, label in items:
			ax = x
			for anim in anims:
				im = files["units/%s/%s%s_%s.png" % (team, prefix, kind, anim)]
				sheet.blit(over(im.scaled(K), BG), x, y0 + 12)
				x += im.w * K + 4
			text(sheet, ax, y0 + 2, label + " " + team.upper(), (255, 255, 255, 255))
			x += 14
		return x
	def page(w, h, title):
		sh = Img(w, h)
		for i in range(w * h):
			sh.p[i] = PANEL
		text(sh, 6, 4, title, (255, 220, 120, 255))
		return sh
	for kind, label in HEROES:
		sh = page(1260, 320, "KAHRAMAN %s (32X32) - BEKLEME 2 / KOSU 4 / SALDIRI 3 - MAVI USTTE, KIRMIZI ALTTA - 4 KAT" % label)
		for r, team in enumerate(("blue", "red")):
			sheet_block([(kind, label)], 32, team, ("idle", "run", "attack"), 6, 18 + r * 150, sh, "")
		sh.save(os.path.join(OUT, "preview_kahraman_%s.png" % kind))
	sh = page(2500, 300, "BIRIMLER (24X24) - BEKLEME 2 / KOSU 4 - MAVI USTTE, KIRMIZI ALTTA - 4 KAT")
	for r, team in enumerate(("blue", "red")):
		sheet_block(UNITS, 24, team, ("idle", "run"), 6, 18 + r * 130, sh, "u_")
	sh.save(os.path.join(OUT, "preview_birimler.png"))
	# 2) zemin, üs, efekt
	sh2 = Img(1100, 560)
	for i in range(sh2.w * sh2.h):
		sh2.p[i] = PANEL
	text(sh2, 6, 4, "ZEMIN / US / EFEKT - 4 KAT", (255, 220, 120, 255))
	x = 6
	for name, lab in (("grass", "CIMEN 3"), ("dirt", "TOPRAK YOL 2"), ("stone", "TAS ENGEL 2"), ("decor", "SUS (CARPISMAZ) 5")):
		im = files["terrain/%s.png" % name]
		text(sh2, x, 16, lab)
		sh2.blit(over(im.scaled(4), BG), x, 26)
		x += im.w * 4 + 16
	y = 100
	text(sh2, 6, y, "US (KALE) VE BAYRAK 4 KARE", (255, 220, 120, 255))
	x = 6
	for team in TEAMS:
		c = files["buildings/%s_castle.png" % team]
		sh2.blit(over(c.scaled(3), BG), x, y + 12)
		x += c.w * 3 + 10
	for team in TEAMS:
		fl = files["buildings/%s_flag.png" % team]
		sh2.blit(over(fl.scaled(3), BG), x, y + 12)
		x += fl.w * 3 + 10
	y = 330
	text(sh2, 6, y, "EFEKT: OK / TOP / PATLAMA 4 KARE / TAHTA DUVAR / TAS DUVAR / COIN 4 KARE", (255, 220, 120, 255))
	x = 6
	for name in ("fx/arrow", "fx/ball", "fx/boom", "fx/wall_wood", "fx/wall_stone", "fx/coin"):
		im = files[name + ".png"]
		sh2.blit(over(im.scaled(4), BG), x, y + 14)
		x += im.w * 4 + 14
	sh2.save(os.path.join(OUT, "preview_zemin_us_efekt.png"))
	# 3) oyundaki gerçek boyut şeridi: 1 art pikseli = 2 ekran pikseli (dünya x3, ölçek 2/3)
	sh3 = Img(760, 260)
	for i in range(sh3.w * sh3.h):
		sh3.p[i] = BG
	g = Img(64, 64)
	rr = random.Random(5)
	sh3_tiles = [files["terrain/grass.png"]]
	for ty in range(0, sh3.h, 32):
		for tx in range(0, sh3.w, 32):
			v = rr.randrange(3)
			t = Img(16, 16)
			for yy in range(16):
				for xx in range(16):
					t.set(xx, yy, sh3_tiles[0].get(v * 16 + xx, yy))
			sh3.blit(t.scaled(2), tx, ty)
	text(sh3, 6, 4, "OYUNDAKI GERCEK BOYUT (2X): TAS ENGEL, KAHRAMANLAR, BIRIMLER, US", (255, 255, 255, 255))
	# taş engel dikdörtgeni
	st = files["terrain/stone.png"]
	for ty in range(0, 4):
		for tx in range(0, 3):
			t = Img(16, 16)
			for yy in range(16):
				for xx in range(16):
					t.set(xx, yy, st.get(xx, yy))
			sh3.blit(t.scaled(2), 600 + tx * 32, 40 + ty * 32)
	x = 20
	for team in TEAMS:
		for kind, _ in HEROES:
			im = files["units/%s/%s_idle.png" % (team, kind)]
			fr = Img(32, 32)
			for yy in range(32):
				for xx in range(32):
					fr.set(xx, yy, im.get(xx, yy))
			sh3.blit(fr.scaled(2), x, 30)
			x += 66
		x += 10
	x = 20
	for team in TEAMS:
		for kind, _ in UNITS:
			im = files["units/%s/u_%s_idle.png" % (team, kind)]
			sh3.blit(im.scaled(2), x, 120)
			x += 52
	c = files["buildings/blue_castle.png"]
	sh3.blit(c.scaled(2), 20, 160 - 20)
	c = files["buildings/red_castle.png"]
	sh3.blit(c.scaled(2), 160, 160 - 20)
	sh3.save(os.path.join(OUT, "preview_oyun_boyutu.png"))


if __name__ == "__main__":
	files = build()
	for path, im in files.items():
		im.save(os.path.join(OUT, path))
	preview(files)
	print("tamam: %d PNG -> %s" % (len(files), os.path.normpath(OUT)))
