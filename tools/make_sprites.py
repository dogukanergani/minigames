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
OL = (14, 10, 22, 255)            # koyu çerçeve
SKIN = (236, 190, 152, 255)
SKIN_D = (192, 136, 104, 255)
STEEL = (178, 188, 206, 255)
STEEL_D = (86, 96, 122, 255)
GOLD = (240, 190, 56, 255)
GOLD_D = (200, 138, 40, 255)
WOOD = (150, 96, 52, 255)
WOOD_D = (98, 62, 38, 255)
WHITE = (250, 250, 255, 255)
LEAF = (88, 170, 74, 255)
SHADOW = (10, 10, 30, 80)
TEAMS = {
	"blue": {"m": (40, 84, 204, 255), "l": (92, 146, 244, 255), "d": (18, 34, 108, 255)},
	"red": {"m": (204, 36, 38, 255), "l": (244, 98, 78, 255), "d": (104, 16, 28, 255)},
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
BONE = (226, 216, 190, 255)
SCAR = (170, 44, 52, 255)


def brows(im, xl, xr, ey, up=3):
	"""V şeklinde çatık kaşlar: dış uçlar yüksek, iç uçlar (burun üstü) alçak."""
	fill(im, {(xl - 1, ey - up), (xl, ey - up), (xl, ey - up + 1), (xl + 1, ey - up + 1), (xl + 2, ey - up + 1)}, OL)
	fill(im, {(xr + 2, ey - up), (xr + 1, ey - up), (xr + 1, ey - up + 1), (xr, ey - up + 1), (xr - 1, ey - up + 1)}, OL)


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
		lean = (-2, 1, 3)[f]
		bob = (0, 1, 1)[f]
	cx = 15 + lean
	shadow(im, 16, 29, 9, 2.5)
	# yırtık uzun pelerin
	flap = (0, 1, 2, 1)[f % 4] + (2 if anim == "run" else 0)
	cape = poly([(cx - 7, 13 + bob), (cx + 6, 13 + bob), (cx + 7, 27 + bob), (cx - 10 - flap, 30 + bob)])
	cape = {(x, y) for x, y in cape if not (y >= 27 + bob and (x + f) % 3 == 0)}  # tırtıklı etek
	part(im, cape, T["d"])
	fill(im, {(x, y) for x, y in cape if y > 21 + bob and x < cx - 3}, T["m"])
	# bacaklar
	for i, bx in enumerate((cx - 3, cx + 2)):
		dx, dy = legs[i]
		part(im, rect(bx + dx // 2, 24 + bob // 2, bx + 1 + dx // 2, 27 - dy), STEEL_D)
		part(im, rect(bx + dx - 1, 27 - dy, bx + 2 + dx, 28 - dy), WOOD_D)
	# gövde (koyu zırhlı tunik)
	body = ell(cx, 19 + bob, 6, 5.5)
	part(im, body, T["m"])
	fill(im, {(x, y) for x, y in body if x < cx - 1 and y < 19 + bob}, T["l"])
	fill(im, rect(cx - 5, 22 + bob, cx + 5, 22 + bob), OL)  # kemer
	fill(im, {(cx, 22 + bob), (cx + 1, 22 + bob)}, GOLD_D)
	fill(im, {(cx - 1, 17 + bob), (cx + 2, 17 + bob), (cx, 18 + bob), (cx + 1, 18 + bob)}, STEEL)  # göğüs plakası
	# omuz zırhı (dikenli)
	for sx, sg in ((cx - 6, -1), (cx + 6, 1)):
		pad = ell(sx, 15 + bob, 3, 2.3)
		part(im, pad, STEEL_D)
		fill(im, {(x, y) for x, y in pad if y < 15 + bob}, STEEL)
		part(im, poly([(sx - 1, 14 + bob), (sx + sg * 1, 10 + bob), (sx + 2, 14 + bob)]), STEEL)
		fill(im, {(sx, 16 + bob)}, T["l"])
	hx, hy = cx + 7, 21 + bob  # sağ el
	spark = set()
	if kind == "warrior":
		sh = circ(cx - 7, 21 + bob, 4)  # sol kolda dikenli kalkan
		part(im, sh, T["d"])
		fill(im, circ(cx - 7, 21 + bob, 2.6), T["m"])
		fill(im, circ(cx - 7, 21 + bob, 1), STEEL)
		part(im, {(cx - 7, 16 + bob), (cx - 7, 15 + bob)}, STEEL)
		if anim == "attack":
			sw = ((hx - 3, hy - 3, hx - 7, hy - 16), (hx - 1, hy - 4, hx + 6, hy - 10), (hx - 1, hy - 1, hx + 5, hy + 7))[f]
		elif anim == "run":
			sw = (hx, hy - 1, hx + 5, hy - 13)
		else:
			sw = (hx, hy - 1, hx + 2, hy - 15)
		if anim == "attack" and f >= 1:  # geniş savuruş izi
			a0, a1 = ((-2.1, -0.5), (-0.5, 1.0))[f - 1]
			for t in range(11):
				a = a0 + (a1 - a0) * t / 10.0
				for rr in (11, 12):
					fill(im, {(int(cx + 4 + math.cos(a) * rr), int(20 + bob + math.sin(a) * rr))}, WHITE if rr == 12 else T["l"])
			spark = {(sw[2] + 2, sw[3] - 1), (sw[2] + 1, sw[3] + 2), (sw[2] + 3, sw[3] + 1), (sw[2], sw[3] - 3)}
		part(im, line(sw[0], sw[1], sw[2], sw[3], 3), STEEL_D)
		fill(im, line(sw[0], sw[1], sw[2], sw[3], 2), STEEL)
		fill(im, line(sw[0] - 1, sw[1], sw[2] - 1, sw[3], 1), WHITE)
		ux, uy = sw[2] - sw[0], sw[3] - sw[1]
		ln = math.hypot(ux, uy)
		ux, uy = ux / ln, uy / ln
		for k in (0.35, 0.6, 0.85):  # tırtıklı kenar
			fill(im, {(int(sw[0] + ux * ln * k - uy * 2.2), int(sw[1] + uy * ln * k + ux * 2.2))}, STEEL_D)
		part(im, line(sw[0] - 2, sw[1] + 1, sw[0] + 2, sw[1] - 1, 1), GOLD_D)
	elif kind == "lancer":
		if anim == "attack":
			dx = (-4, 2, 0)[f]
			sp = (hx - 14 + dx, hy + 1, hx + 1 + dx, hy - 1)
			if f >= 1:
				fill(im, {(sp[2] + 6, sp[3] - 2), (sp[2] + 7, sp[3] + 1), (sp[2] + 5, sp[3] + 3)}, GOLD)
		elif anim == "run":
			sp = (hx - 8, hy + 7, hx + 6, hy - 8)
		else:
			sp = (hx + 1, hy + 9, hx + 2, hy - 14)
		part(im, line(sp[0], sp[1], sp[2], sp[3], 1), WOOD_D)
		ux, uy = sp[2] - sp[0], sp[3] - sp[1]
		ln = math.hypot(ux, uy)
		ux, uy = ux / ln, uy / ln
		tip = poly([(sp[2] - ux * 1 - uy * 3, sp[3] - uy * 1 + ux * 3), (sp[2] + ux * 6, sp[3] + uy * 6),
			(sp[2] - ux * 1 + uy * 3, sp[3] - uy * 1 - ux * 3)])
		part(im, tip, STEEL)
		fill(im, {(int(sp[2] - ux * 2), int(sp[3] - uy * 2))}, WHITE)
		fx, fy = int(sp[2] - ux * 5), int(sp[3] - uy * 5)  # yırtık flama
		fill(im, {(fx, fy), (fx - 1, fy), (fx - 2, fy + 1), (fx - 3, fy + 1), (fx - 1, fy + 1), (fx - 3, fy + 2)}, T["m"])
	elif kind == "archer":
		part(im, line(cx - 5, 12 + bob, cx - 8, 22 + bob, 2), WOOD_D)  # sadak
		fill(im, {(cx - 5, 11 + bob), (cx - 4, 10 + bob), (cx - 6, 10 + bob), (cx - 7, 11 + bob)}, BONE)
		pull = (3, 6, 0)[f] if anim == "attack" else 0
		bow_x = hx + 2
		arc = [i * 0.05 for i in range(-32, 33)]
		bow = {(int(bow_x + math.cos(a) * 10 * 0.5), int(hy + math.sin(a) * 10)) for a in arc}
		bow |= shift(bow, 1, 0)
		part(im, bow, WOOD_D)
		top, bot = (int(bow_x + math.cos(-1.6) * 5), hy - 10), (int(bow_x + math.cos(1.6) * 5), hy + 10)
		part(im, {(top[0] + 1, top[1] - 1), (bot[0] + 1, bot[1] + 1)}, STEEL)  # dikenli uçlar
		sx = hx - pull + 1
		fill(im, line(top[0], top[1], sx, hy, 1), WHITE)
		fill(im, line(sx, hy, bot[0], bot[1], 1), WHITE)
		if anim == "attack" and f < 2:
			part(im, line(sx, hy, bow_x + 6, hy, 1), WOOD_D, ol=None)
			fill(im, {(bow_x + 7, hy), (bow_x + 6, hy - 1), (bow_x + 6, hy + 1), (bow_x + 8, hy)}, STEEL)
		elif anim == "attack":
			part(im, line(bow_x + 4, hy, bow_x + 10, hy, 1), WOOD_D, ol=None)
			fill(im, {(bow_x + 11, hy), (bow_x + 10, hy - 1), (bow_x + 10, hy + 1)}, STEEL)
			spark = {(bow_x + 5, hy - 3), (bow_x + 7, hy + 3)}
	part(im, circ(hx, hy, 1.7), STEEL_D)  # zırh eldiveni
	# kafa
	hdx = lean
	head = circ(16 + hdx, 10 + bob, 6.4)
	part(im, head, SKIN)
	fill(im, {(x, y) for x, y in head if x < 12 + hdx and y > 10 + bob}, SKIN_D)
	ey = 12 + bob
	xl, xr = 16 + hdx, 20 + hdx
	fill(im, {(xl, ey), (xr, ey), (xl, ey + 1), (xr, ey + 1)}, OL)
	fill(im, {(xl + 1, ey), (xr + 1, ey)}, WHITE)
	# sıkılmış dişli ağız
	fill(im, rect(17 + hdx, ey + 3, 21 + hdx, ey + 3), OL)
	fill(im, {(18 + hdx, ey + 3), (20 + hdx, ey + 3)}, WHITE)
	capmask = {(x, y) for x, y in head if y < 9 + bob}
	if kind == "warrior":
		fill(im, line(14 + hdx, ey - 1, 15 + hdx, ey + 2, 1), SCAR)  # yara izi
		fill(im, capmask, STEEL_D)
		fill(im, {(x, y) for x, y in capmask if y < 7 + bob and x < 17 + hdx}, STEEL)
		fill(im, rect(10 + hdx, 9 + bob, 22 + hdx, 9 + bob) & head, OL)
		fill(im, line(19 + hdx, 6 + bob, 19 + hdx, 11 + bob, 1), STEEL_D)  # burun siperi
		for hs in (-1, 1):  # kıvrık boynuzlar
			hxx = 16 + hdx + hs * 6
			part(im, line(hxx, 8 + bob, hxx + hs * 3, 6 + bob, 2) | line(hxx + hs * 3, 6 + bob, hxx + hs * 3, 2 + bob, 2), BONE)
		crest = poly([(11 + hdx, 5 + bob), (15 + hdx, 0 + bob), (21 + hdx, 3 + bob), (17 + hdx, 6 + bob)])
		part(im, crest | {(10 + hdx - flap // 2, 6 + bob), (9 + hdx - flap // 2, 7 + bob)}, T["m"])
		fill(im, {(15 + hdx, 3 + bob), (16 + hdx, 2 + bob)}, T["l"])
	elif kind == "archer":
		hood = capmask | {(x, y) for x, y in head if x < 11 + hdx} | {(x, y) for x, y in head if y > ey + 1 and x > 13 + hdx}
		fill(im, hood, T["d"])  # kukuleta + yüz maskesi
		fill(im, {(x, y) for x, y in hood if y < 6 + bob and x < 17 + hdx}, T["m"])
		fill(im, {(xl, ey), (xr, ey)}, OL)
		fill(im, {(xl + 1, ey), (xr + 1, ey)}, GOLD)  # parlayan göz
		fill(im, {(xl, ey - 1), (xr, ey - 1)}, T["d"])
		fill(im, {(14 + hdx, ey), (14 + hdx, ey + 1), (15 + hdx, ey + 2)}, SCAR)  # savaş boyası
		part(im, line(14 + hdx, 4 + bob, 21 + hdx, -1 + bob, 2), OL)
		fill(im, line(14 + hdx, 4 + bob, 21 + hdx, -1 + bob, 1), BONE)  # sert tüy/kemik
	elif kind == "lancer":
		fill(im, capmask, STEEL_D)
		fill(im, {(x, y) for x, y in capmask if y < 7 + bob and x < 16 + hdx}, GOLD)
		fill(im, rect(10 + hdx, 9 + bob, 22 + hdx, 9 + bob) & head, OL)
		fill(im, line(19 + hdx, 6 + bob, 19 + hdx, 11 + bob, 1), GOLD_D)
		wing = poly([(10 + hdx, 8 + bob), (4 + hdx, 2 + bob), (5 + hdx, 6 + bob), (4 + hdx, 9 + bob)]) | \
			poly([(22 + hdx, 8 + bob), (28 + hdx, 2 + bob), (27 + hdx, 6 + bob), (28 + hdx, 9 + bob)])
		part(im, wing, STEEL)
		part(im, line(16 + hdx, 4 + bob, 16 + hdx, 1 + bob, 3), T["m"])
		fill(im, {(15 + hdx, ey - 1), (16 + hdx, ey - 1)}, T["m"])  # savaş boyası şeridi
		fill(im, rect(14 + hdx, ey + 1, 16 + hdx, ey + 1), T["m"])
	brows(im, xl, xr, ey, 2)
	fill(im, spark, GOLD)
	return im


# ---------------------------------------------------------------- birimler (24x24)
US = 24


def unit_face(im, cx, ey, mouth=True):
	fill(im, {(cx + 2, ey), (cx + 2, ey + 1), (cx + 5, ey), (cx + 5, ey + 1)}, OL)
	fill(im, {(cx + 3, ey), (cx + 6, ey)}, WHITE)
	fill(im, {(cx + 1, ey - 2), (cx + 2, ey - 1), (cx + 3, ey - 1)}, OL)  # V kaşlar
	fill(im, {(cx + 6, ey - 2), (cx + 5, ey - 1), (cx + 4, ey - 1)}, OL)
	if mouth:
		fill(im, {(cx + 3, ey + 3), (cx + 4, ey + 3), (cx + 5, ey + 3)}, OL)
		fill(im, {(cx + 4, ey + 3)}, WHITE)


def unit_frame(kind, team, anim, f):
	T = TEAMS[team]
	im = Img(US, US)
	if kind == "cannon":
		return cannon_frame(team, anim, f)
	bob = 0 if anim == "idle" and f == 0 else (-1 if anim == "idle" else (0, -1, 0, -1)[f])
	legs = (((-1, 0), (1, 0)), ((0, 1), (0, 0)), ((1, 0), (-1, 0)), ((0, 0), (0, 1)))[f] if anim == "run" else ((0, 0), (0, 0))
	cx = 11
	shadow(im, 12, 21, 6, 2)
	for i, bx in enumerate((cx - 2, cx + 1)):
		dx, dy = legs[i]
		part(im, rect(bx + dx, 17, bx + dx, 19 - dy), STEEL_D)
	robe = kind == "healer"
	ROBE = (58, 46, 78, 255)
	if robe:  # karanlık rahip cüppesi, geniş takım renkli şerit
		body = poly([(cx - 4, 11 + bob), (cx + 5, 11 + bob), (cx + 7, 20), (cx - 6, 20)])
		part(im, body, ROBE)
		fill(im, rect(cx - 1, 12 + bob, cx + 2, 19), T["m"])
		fill(im, rect(cx - 1, 12 + bob, cx - 1, 19), T["l"])
		fill(im, rect(cx - 5, 19, cx + 6, 19), T["m"])
	else:
		body = ell(cx + 0.5, 14 + bob, 4.4, 4.2)
		part(im, body, T["m"])
		fill(im, {(x, y) for x, y in body if x < cx and y < 14 + bob}, T["l"])
		fill(im, rect(cx - 3, 16 + bob, cx + 4, 16 + bob), OL)
	hx, hy = cx + 5, 14 + bob
	if kind == "swordsman":
		part(im, line(hx, hy, hx + 2, hy - 10, 2), STEEL)  # daha iri kılıç
		fill(im, line(hx - 1, hy - 1, hx + 1, hy - 9, 1), WHITE)
		fill(im, {(hx + 3, hy - 5)}, STEEL_D)
		part(im, line(hx - 2, hy - 1, hx + 2, hy - 2, 1), GOLD_D)
	elif kind == "archer":
		bow = {(int(hx + 1 + math.cos(a) * 3), int(hy + math.sin(a) * 7)) for a in [i * 0.06 for i in range(-26, 27)]}
		part(im, bow, WOOD_D)
		fill(im, line(hx + 1, hy - 7, hx + 1, hy + 7, 1), WHITE)
		part(im, {(hx + 2, hy - 8), (hx + 2, hy + 8)}, STEEL)
	elif kind == "shield":
		part(im, line(hx - 2, hy - 1, hx + 1, hy - 9, 1), STEEL)  # kısa mızrak
	elif kind == "healer":
		part(im, line(hx, hy + 4, hx, hy - 8, 1), WOOD_D)
		part(im, circ(hx, hy - 9, 2.2), T["l"])  # parlayan küre
		fill(im, {(hx, hy - 10)}, WHITE)
	part(im, circ(hx, hy, 1.3), STEEL_D if kind != "healer" else ROBE)
	if kind == "shield":  # belirgin büyük dikenli kalkan (öne)
		sh = poly([(cx + 1, 8 + bob), (cx + 10, 8 + bob), (cx + 10, 16 + bob), (cx + 5.5, 21 + bob), (cx + 1, 16 + bob)])
		part(im, sh, STEEL_D)
		inner = poly([(cx + 2, 10 + bob), (cx + 9, 10 + bob), (cx + 9, 15 + bob), (cx + 5.5, 19 + bob), (cx + 2, 15 + bob)])
		fill(im, inner, T["m"])
		fill(im, rect(cx + 2, 10 + bob, cx + 5, 12 + bob), T["l"])
		part(im, {(cx + 5, 13 + bob), (cx + 6, 13 + bob), (cx + 5, 14 + bob), (cx + 6, 14 + bob), (cx + 5, 12 + bob)}, STEEL)
		part(im, {(cx + 10, 8 + bob), (cx + 11, 7 + bob)}, STEEL)
	head = circ(cx + 1, 8 + bob, 4.2)
	part(im, head, SKIN)
	ey = 8 + bob
	cap = {(x, y) for x, y in head if y < 7 + bob}
	if kind == "swordsman":
		fill(im, cap, STEEL_D)
		fill(im, {(x, y) for x, y in cap if y < 5 + bob and x < cx + 2}, STEEL)
		fill(im, rect(cx - 4, 7 + bob, cx + 6, 7 + bob) & head, OL)
		part(im, {(cx + 1, 3 + bob), (cx + 1, 2 + bob), (cx, 1 + bob)}, T["m"])  # dikenli tepelik
		part(im, {(cx - 3, 6 + bob), (cx - 4, 5 + bob)}, BONE)
		unit_face(im, cx, ey)
	elif kind == "archer":  # maskeli, kukuletalı (yüzün alt yarısı kapalı)
		hood = cap | {(x, y) for x, y in head if x < cx - 1} | {(x, y) for x, y in head if y > ey + 1}
		fill(im, hood, T["d"])
		fill(im, {(x, y) for x, y in hood if y < 5 + bob}, T["m"])
		unit_face(im, cx, ey, mouth=False)
		fill(im, {(cx + 3, ey), (cx + 6, ey)}, GOLD)
	elif kind == "shield":
		fill(im, cap, STEEL_D)
		fill(im, {(x, y) for x, y in cap if y < 5 + bob}, STEEL)
		fill(im, rect(cx - 4, 7 + bob, cx + 6, 7 + bob) & head, OL)
		part(im, line(cx - 3, 6 + bob, cx - 5, 2 + bob, 1), BONE)  # boynuzlar
		part(im, line(cx + 5, 6 + bob, cx + 7, 2 + bob, 1), BONE)
		unit_face(im, cx, ey)
	elif kind == "healer":
		hood = cap | {(x, y) for x, y in head if x < cx - 1} | {(x, y) for x, y in head if y > ey + 2}
		fill(im, hood, ROBE)
		fill(im, {(x, y) for x, y in hood if y < 5 + bob}, T["d"])
		fill(im, rect(cx - 4, 6 + bob, cx + 6, 6 + bob) & head, T["m"])
		fill(im, {(x, y) for x, y in head if x > cx - 2 and 6 + bob < y <= ey + 2}, (30, 24, 44, 255))  # gölgeli yüz
		fill(im, {(cx + 3, ey), (cx + 6, ey), (cx + 3, ey + 1), (cx + 6, ey + 1)}, T["l"])  # parlayan gözler
	return im


def cannon_frame(team, anim, f):
	T = TEAMS[team]
	im = Img(US, US)
	roll = 0 if anim == "idle" else f
	shadow(im, 12, 21, 10, 2.2)
	IRON, IRON_L = (44, 46, 62, 255), (112, 116, 138, 255)
	bar = poly([(3, 7), (19, 5), (22, 8), (22, 13), (19, 15), (3, 16)])  # iri namlu
	part(im, bar, IRON)
	fill(im, {(x, y) for x, y in bar if y < 9}, IRON_L)
	part(im, rect(19, 5, 22, 15), IRON)
	fill(im, rect(21, 8, 22, 12), OL)
	fill(im, rect(7, 6, 7, 15), GOLD_D)
	fill(im, rect(12, 6, 12, 15), GOLD_D)
	cart = rect(4, 15, 18, 18)
	part(im, cart, T["m"])
	fill(im, rect(4, 15, 18, 15), T["l"])
	fill(im, rect(4, 18, 18, 18), T["d"])
	part(im, circ(10, 18.5, 5), WOOD_D)
	fill(im, circ(10, 18.5, 3), WOOD)
	fill(im, {(10, 18), (11, 18), (10, 19), (11, 19)}, STEEL)
	a0 = roll * 0.8
	for k in range(4):
		a = a0 + k * math.pi / 2
		fill(im, {(int(round(10 + math.cos(a) * 3.8)), int(round(18 + math.sin(a) * 3.8)))}, OL)
	head = circ(4, 9, 3.4)  # topçu: miğferli, kızgın
	part(im, head, SKIN)
	fill(im, {(x, y) for x, y in head if y < 8}, STEEL_D)
	fill(im, {(5, 9), (6, 9)}, OL)
	fill(im, {(4, 7), (5, 8)}, OL)
	part(im, {(3, 5), (3, 4)}, BONE)
	part(im, rect(1, 12, 5, 15), T["m"])
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
	base, dk, lt = (72, 130, 66, 255), (58, 110, 56, 255), (92, 150, 76, 255)
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
	base, dk, lt = (158, 122, 84, 255), (132, 98, 68, 255), (182, 146, 104, 255)
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
	"""Taş engel döşemesi: büyük koyu bloklar (az harç çizgisi), yinelenebilir."""
	r = random.Random(seed)
	im = Img(16, 16)
	face, lt, dk, mortar = (100, 106, 126, 255), (128, 134, 154, 255), (74, 80, 102, 255), (44, 46, 62, 255)
	for y in range(16):
		for x in range(16):
			im.set(x, y, face)
	for x in range(16):
		im.set(x, 15, mortar)
		im.set(x, 0, lt)
		im.set(x, 14, dk)
	for y in range(15):
		im.set(15, y, mortar)
	for y in range(1, 6):
		im.set(7 + seed % 2 * 2, y, dk)
	for _ in range(14):
		x, y = r.randrange(15), r.randrange(1, 14)
		im.set(x, y, dk if r.random() < 0.6 else lt)
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
	stone, stl, std = (84, 88, 106, 255), (116, 122, 144, 255), (56, 60, 78, 255)
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
	for tx in (21, 43):  # meşaleler
		fill(im, line(tx, 44, tx, 50, 1), WOOD_D)
		part(im, {(tx, 42), (tx - 1, 43), (tx + 1, 43), (tx, 43), (tx, 41)}, (255, 150, 40, 255))
		fill(im, {(tx, 43), (tx, 42)}, (255, 226, 110, 255))
	for gx in (28, 36):  # kapı üstü dikenler
		fill(im, {(gx, 41), (gx, 40)}, STEEL)
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
