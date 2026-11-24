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
	"""`ox, oy`: çizim orijini kaydırması. Saldırı kareleri büyük tuvale (48x48 / 32x32) aynı koordinatlarla
	çizilir, karakter ortada kalır, silah ve efekt çerçeve dışına taşabilir."""
	def __init__(self, w, h, ox=0, oy=0):
		self.w, self.h = w, h
		self.ox, self.oy = ox, oy
		self.p = [(0, 0, 0, 0)] * (w * h)

	def set(self, x, y, c):
		x += self.ox
		y += self.oy
		if 0 <= x < self.w and 0 <= y < self.h:
			self.p[y * self.w + x] = c

	def blend(self, x, y, c):
		"""Yarı saydam rengi alttaki pikselin üstüne karıştırır (yarı saydam boyama alttakini silmesin)."""
		x += self.ox
		y += self.oy
		if not (0 <= x < self.w and 0 <= y < self.h):
			return
		b = self.p[y * self.w + x]
		a = c[3] / 255.0
		if b[3] == 0 or a >= 1.0:
			self.p[y * self.w + x] = c
			return
		ba = b[3] / 255.0
		oa = a + ba * (1 - a)
		self.p[y * self.w + x] = tuple(int((c[k] * a + b[k] * ba * (1 - a)) / oa) for k in range(3)) + (int(oa * 255),)

	def get(self, x, y):
		x += self.ox
		y += self.oy
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


def fill_a(img, s, col):
	"""Yarı saydam boyama (alttakiyle karışır)."""
	for x, y in s:
		img.blend(x, y, col)


def _ang_in(ang, a0, a1):
	"""ang (derece) a0 -> a1 aralığında mı? Aralıktaki konumunu 0..1 döndürür, değilse -1."""
	while ang < a0:
		ang += 360
	while ang >= a0 + 360:
		ang -= 360
	if ang > a1:
		return -1.0
	return (ang - a0) / max(a1 - a0, 1e-6)


def smear(img, px, py, a0, a1, r_out, th, fade=1.0, cw=None, taper=False):
	"""Silah savuruş izi (smear): (px, py) etrafında a0 -> a1 derecelik hilal. Kuyrukta ince, başta kalın.
	Dış kenar beyaz, içe doğru solar. `fade` < 1: dağınık/sönen iz."""
	cw = cw or ((250, 250, 255, 255), (206, 226, 255, 235), (150, 186, 246, 150))
	R = int(r_out) + 2
	rnd = random.Random(int(px * 7 + py * 13 + a0))
	for y in range(int(py) - R, int(py) + R + 1):
		for x in range(int(px) - R, int(px) + R + 1):
			d = math.hypot(x - px, y - py)
			if d > r_out:
				continue
			u = _ang_in(math.degrees(math.atan2(y - py, x - px)), a0, a1)
			if u < 0:
				continue
			t = th * (0.2 + 0.8 * u ** 0.8)
			if taper:  # hilalin başı da sivri
				t *= min(1.0, (1.0 - u) * 5.0 + 0.25)
			depth = r_out - d
			if depth > t:
				continue
			if fade < 1.0 and rnd.random() > fade * (0.4 + 0.6 * u):
				continue
			c = cw[0] if depth < 1.3 else (cw[1] if depth < t * 0.55 + 1 else cw[2])
			img.blend(x, y, c)


def spark_star(img, x, y, r=3, col=GOLD, core=WHITE):
	"""Vuruş kıvılcımı: 4 uzun + 4 kısa ışın, beyaz çekirdek."""
	pts = {(x, y)}
	for k in range(1, r + 1):
		pts |= {(x + k, y), (x - k, y), (x, y + k), (x, y - k)}
	for k in range(1, max(2, r - 1)):
		pts |= {(x + k, y + k), (x - k, y - k), (x + k, y - k), (x - k, y + k)}
	part(img, pts, col, ol=None)
	fill(img, {(x, y), (x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)}, core)


def speed_lines(img, x0, x1, ys, col=(240, 246, 255, 200), seed=1):
	"""Yatay hız çizgileri (x0 -> x1), her satır farklı uzunlukta."""
	r = random.Random(seed)
	for y in ys:
		a = x0 + r.randint(0, max(0, (x1 - x0) // 3))
		for x in range(int(a), int(x1)):
			img.blend(x, y, col)


# ---------------------------------------------------------------- kahramanlar (32x32)
HS = 32
BONE = (226, 216, 190, 255)
SCAR = (170, 44, 52, 255)


def brows(im, xl, xr, ey, up=3):
	"""V şeklinde çatık kaşlar: dış uçlar yüksek, iç uçlar (burun üstü) alçak."""
	fill(im, {(xl - 1, ey - up), (xl, ey - up), (xl, ey - up + 1), (xl + 1, ey - up + 1), (xl + 2, ey - up + 1)}, OL)
	fill(im, {(xr + 2, ey - up), (xr + 1, ey - up), (xr + 1, ey - up + 1), (xr, ey - up + 1), (xr - 1, ey - up + 1)}, OL)


# Saldırı animasyonları (sağa bakış; oyunda sola bakınca aynalanır). Klasik ilkeler: hazırlık (geri çekilme,
# çömelme), hızlı vuruş (savuruş izi / smear), çarpma (kıvılcım, ağırlık öne), toparlanma.
# Saldırı kareleri 48x48 tuvaldedir (32'lik karakter ortada, ATK_PAD kadar boşluk): kılıç ve efekt çerçeveye sığar.
HERO_ATK = {("warrior", "attack"): 6, ("warrior", "punch"): 4, ("lancer", "attack"): 6, ("archer", "attack"): 6}
ATK_PAD = 8
LANCER_PAD = 16  # mızrakçı saldırısı 64x64 tuval: yatay mızrak çerçeveye sığsın
# Kare başına poz: (gövde eğimi: + öne / - geri, çömelme, (arka ayak, ön ayak) kayması, pelerin savrulması)
ATK_POSE = {
	("warrior", "attack"): [(-2, 1, (-2, 1), 0), (-3, 2, (-2, 2), 0), (2, 0, (-3, 3), 3), (3, 1, (-3, 4), 4),
		(3, 1, (-3, 4), 3), (1, 0, (-1, 1), 1)],
	("warrior", "punch"): [(-2, 1, (-2, 1), 0), (3, 0, (-3, 3), 3), (3, 1, (-3, 3), 3), (1, 0, (-1, 1), 1)],
	("lancer", "attack"): [(-2, 1, (-2, 1), 0), (-4, 2, (-3, 1), 0), (3, 0, (-4, 3), 4), (5, 1, (-5, 4), 5),
		(4, 1, (-4, 3), 3), (1, 0, (-1, 1), 1)],
	("archer", "attack"): [(-1, 1, (-2, 1), 0), (-2, 0, (-2, 1), 2), (-2, 0, (-2, 1), 1), (-1, 0, (-1, 1), 0),
		(0, 0, (-1, 1), 0), (0, 1, (-1, 1), 0)],
}
# Kılıç: (el kayması, kılıç açısı (derece; 0 ileri, -90 yukarı), savuruş izi (a0, a1, yoğunluk) | None,
# kalkan kayması (+ öne), kıvılcım). 0-1 hazırlık (kılıç başın arkasına), 2 savuruş, 3 çarpma, 4 devam, 5 toparlanma.
SWORD_SEQ = [((-1, -11), -125, None, 3, False), ((-2, -17), -168, None, 4, False),
	((0, -6), -40, (-165, -40, 1.0), -2, False), ((2, -2), 15, (-75, 15, 1.0), -3, True),
	((1, 0), 55, (5, 55, 0.5), -2, False), ((0, -2), -72, None, 0, False)]
# Yumruk: (el kayması, kol uzanmış mı, kıvılcım, kalkan kayması)
PUNCH_SEQ = [((-6, -3), False, False, 2), ((5, -3), True, False, -2), ((6, -3), True, True, -3), ((1, -1), False, False, 0)]
# Mızrak: ön elin karakter ortasından ileri uzaklığı (sanat pikseli). Mızrak bu noktada yatay tutulur ve
# silah katmanında (wpn_spear_attack.png) gövdeyle aynı karede çizilir; saplama efekti (fx/thrust) buradan başlar.
SPEAR_GRIP = [-3, -6, 9, 13, 11, 5]
# Yay: (kiriş çekme, ok durumu, yay kayması, parlama). 0 tam gerili, 1 bırakma (ok çıkar), 2 geri tepme,
# 3 kol geride, 4 sadaktan ok alma, 5 yeni ok yerleşir.
BOW_SEQ = [(10, "nock", 0, False), (-2, None, -1, True), (1, None, -1, False), (0, None, 0, False),
	(0, "reach", 0, False), (4, "nock", 0, False)]
BOW_BEND = [7.5, 4.0, 5.8, 5.0, 5.0, 6.0]  # yayın bükülmesi (5 = gevşek)
YELL = {("warrior", "attack"): (2, 3), ("warrior", "punch"): (1, 2), ("lancer", "attack"): (2, 3, 4)}


def blade(im, px, py, ang, L=13):
	"""Döndürülmüş kılıç: el (px, py), açı (derece). Kalın çelik, parlak kenar, tırtıklı sırt, altın balçak."""
	a = math.radians(ang)
	ux, uy = math.cos(a), math.sin(a)
	x0, y0 = px + ux * 1.5, py + uy * 1.5
	x1, y1 = px + ux * L, py + uy * L
	part(im, line(x0, y0, x1, y1, 3), STEEL_D)
	fill(im, line(x0, y0, x1, y1, 2), STEEL)
	nx, ny = uy, -ux  # kenar normali (sağa bakan kılıçta yukarı)
	fill(im, line(x0 + nx * 0.9, y0 + ny * 0.9, x1 + nx * 0.9 - ux, y1 + ny * 0.9 - uy, 1), WHITE)
	for k in (0.4, 0.62, 0.84):
		fill(im, {(int(round(px + ux * L * k - nx * 1.6)), int(round(py + uy * L * k - ny * 1.6)))}, STEEL_D)
	fill(im, {(int(round(x1 + ux)), int(round(y1 + uy)))}, STEEL)
	part(im, line(px - nx * 2.5, py - ny * 2.5, px + nx * 2.5, py + ny * 2.5, 1), GOLD_D)
	return x1 + ux * 2, y1 + uy * 2


def dust(im, x, y, k=1.0, seed=3):
	"""Ayak tozu (ağırlık aktarımı): yerde küçük yarı saydam bulut."""
	r = random.Random(seed)
	for _ in range(int(9 * k)):
		dx, dy = r.uniform(-3.5, 3.5) * k, r.uniform(-1.6, 0.6)
		im.blend(int(round(x + dx)), int(round(y + dy)), (214, 196, 160, 170))


def atk_pad(kind):
	"""Saldırı tuvalinin kenar boşluğu: mızrak ileri uzandığı için mızrakçıda daha geniş (64x64)."""
	return LANCER_PAD if kind == "lancer" else ATK_PAD


def spear_h(im, gx, gy, T):
	"""Saldırıdaki yatay mızrak (sağa bakar): ön el (gx, gy) ortada; sap, yaprak uç, takım flaması."""
	part(im, line(gx - 15, gy, gx + 11, gy, 1), WOOD_D)
	fill(im, line(gx - 13, gy, gx + 10, gy, 1), WOOD)
	tip = poly([(gx + 11, gy - 2), (gx + 15, gy - 1.5), (gx + 19, gy + 0.5), (gx + 15, gy + 2.5), (gx + 11, gy + 3)])
	part(im, tip, STEEL)
	fill(im, line(gx + 12, gy, gx + 17, gy, 1), WHITE)
	fill(im, {(gx + 11, gy), (gx + 10, gy)}, GOLD_D)
	part(im, rect(gx - 16, gy - 1, gx - 15, gy + 1), STEEL_D)  # dip başlığı
	flag = {(gx + 5, gy + 1), (gx + 6, gy + 1), (gx + 7, gy + 1), (gx + 8, gy + 1), (gx + 5, gy + 2), (gx + 6, gy + 2),
		(gx + 7, gy + 2), (gx + 5, gy + 3), (gx + 6, gy + 3), (gx + 6, gy + 4)}
	part(im, flag, T["m"])
	fill(im, {(gx + 5, gy + 1), (gx + 6, gy + 1)}, T["l"])


def hero_frame(kind, team, anim, f, wpn=True):
	"""Kahraman karesi. `wpn=False`: SİLAHSIZ gövde (eller, kollar, poz aynı; kılıç/kalkan, mızrak, yay ve ok yok).
	Oyunda gövde ve silah ayrı katmandır: silah şeridi = (silahlı kare) - (silahsız gövde) farkı (bkz. layer_diff)."""
	T = TEAMS[team]
	atk = anim in ("attack", "punch")
	pad = atk_pad(kind)
	im = Img(HS + 2 * pad, HS + 2 * pad, pad, pad) if atk else Img(HS, HS)
	bob = 0
	lean = 0
	legs = ((0, 0), (0, 0))
	flap_x = 0
	if anim == "idle":
		bob = (0, -1)[f]
	elif anim == "run":
		bob = (0, -1, 0, -1)[f]
		legs = (((-2, 0), (2, 1)), ((0, 1), (0, 0)), ((2, 0), (-2, 1)), ((0, 0), (0, 1)))[f]
		lean = 1
	else:
		lean, bob, (lb, lf), flap_x = ATK_POSE[(kind, anim)][f]
		legs = ((lb, 0), (lf, 0))
	cx = 15 + lean
	lx = 15 if atk else cx  # saldırıda ayaklar yere basılı kalır, gövde ağırlığı öne/geri aktarır
	shadow(im, 16, 29, 9, 2.5)
	if atk:
		shadow(im, 16 + lean, 29, 7, 2)  # gövde eğilince gölge de kayar
	# yırtık uzun pelerin
	flap = flap_x if atk else (0, 1, 2, 1)[f % 4] + (2 if anim == "run" else 0)
	lift = flap // 2 if atk else 0  # saldırıda pelerin savrulup kalkar
	cape = poly([(cx - 7, 13 + bob), (cx + 6, 13 + bob), (cx + 7, 27 + bob), (cx - 10 - flap, 30 + bob - lift)])
	cape = {(x, y) for x, y in cape if not (y >= 27 + bob - lift and (x + f) % 3 == 0)}  # tırtıklı etek
	part(im, cape, T["d"])
	fill(im, {(x, y) for x, y in cape if y > 21 + bob and x < cx - 3}, T["m"])
	# bacaklar
	for i, bx in enumerate((lx - 3, lx + 2)):
		dx, dy = legs[i]
		if atk:  # geniş duruş: kalçadan ayağa eğik bacak
			part(im, line(bx + (cx - lx) // 2, 23 + bob, bx + dx, 27, 2), STEEL_D)
		else:
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
	glove = True
	post = []  # kafadan SONRA çizilecekler (başın üstüne kaldırılan kılıç)
	if kind == "warrior":
		shdx = 0
		if anim == "attack":
			shdx = SWORD_SEQ[f][3]
		elif anim == "punch":
			shdx = PUNCH_SEQ[f][3]
		scx = cx - 7 + shdx
		# kalkan kılıçla birlikte silah katmanındadır (kılıç + kalkan takımı); yumrukta iki el de boş
		if wpn and anim != "punch":
			sh = circ(scx, 21 + bob, 4)  # sol kolda dikenli kalkan
			part(im, sh, T["d"])
			fill(im, circ(scx, 21 + bob, 2.6), T["m"])
			fill(im, circ(scx, 21 + bob, 1), STEEL)
			part(im, {(scx, 16 + bob), (scx, 15 + bob)}, STEEL)
		else:  # boş sol el: gardda sıkılı yumruk (kalkanın altında kalır)
			part(im, circ(scx + 1, 20 + bob, 1.7), STEEL_D)
			fill(im, {(scx, 19 + bob)}, STEEL)
		if anim == "attack":
			(hdx_, hdy_), ang, sm, _, spk = SWORD_SEQ[f]
			hx, hy = hx + hdx_, hy + hdy_
			if sm and wpn:  # savuruş izi kılıcın parçası: silah katmanında
				smear(im, hx, hy, sm[0], sm[1], 16, 6.5, sm[2])
			arm = line(cx + 4, 16 + bob, hx, hy, 2)  # kılıç kolu (omuzdan ele)
			tip = None
			if f in (0, 1):  # başın üstünde: kol + kılıç kafadan sonra
				def raised(a=arm, x=hx, y=hy, g=ang):
					part(im, a, T["m"])
					if wpn:
						blade(im, x, y, g, 13)
					part(im, circ(x, y, 1.7), STEEL_D)
				post.append(raised)
				glove = False
			else:
				part(im, arm, T["m"])
				if wpn:
					tip = blade(im, hx, hy, ang, 13)
			if spk and tip:  # uçta parıltı (asıl vuruş kıvılcımı oyunda nişan yönünde, fx/spark.png)
				tx_, ty_ = int(round(tip[0])), int(round(tip[1]))
				fill(im, {(tx_, ty_), (tx_ + 1, ty_), (tx_, ty_ - 1), (tx_, ty_ + 1)}, WHITE)
			if f in (2, 3):
				dust(im, lx - 5, 28, 1.0 if f == 3 else 0.6, seed=f)
		elif anim == "punch":
			(hdx_, hdy_), ext, spk, _ = PUNCH_SEQ[f]
			hx, hy = hx + hdx_, hy + hdy_
			if ext:
				speed_lines(im, cx - 4, hx - 2, (hy - 2, hy + 2), seed=f)
				part(im, line(cx + 4, 17 + bob, hx - 1, hy, 2), T["m"])  # uzanan kol
			else:
				part(im, line(cx + 4, 17 + bob, hx, hy, 2), T["m"])
			part(im, circ(hx, hy, 2.3), STEEL_D)
			fill(im, {(hx - 1, hy - 1), (hx, hy - 1)}, STEEL)
			fill(im, {(hx + 1, hy), (hx + 1, hy + 1)}, OL)  # parmak boğumları
			glove = False  # vuruş kıvılcımı oyunda nişan yönünde çizilir (fx/spark.png)
		elif anim == "run":
			sw = (hx, hy - 1, hx + 5, hy - 13)
		else:
			sw = (hx, hy - 1, hx + 2, hy - 15)
		if not atk and wpn:
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
			glove = False  # iki el mızrağı tutar (gövdede), mızrak silah katmanında
			if f in (2, 3):  # atılma: gövdenin arkasında hız çizgileri, arka ayakta toz
				speed_lines(im, cx - 15, cx - 7, (14 + bob, 18 + bob, 23 + bob), (236, 242, 255, 170), seed=f)
				dust(im, lx - 6, 28, 1.0, seed=f + 5)
			gx, gy = 16 + SPEAR_GRIP[f], 21 + bob
			if wpn:
				spear_h(im, gx, gy, T)
			for ex in (gx - 7, gx):  # arka el, ön el
				part(im, circ(ex, gy, 1.7), STEEL_D)
				fill(im, {(ex - 1, gy - 1)}, STEEL)
		elif wpn:
			if anim == "run":
				sp = (hx - 8, hy + 7, hx + 6, hy - 8)
			else:
				sp = (hx + 1, hy + 9, hx + 2, hy - 14)
			spear_line(im, sp, T)
	elif kind == "archer":
		part(im, line(cx - 5, 12 + bob, cx - 8, 22 + bob, 2), WOOD_D)  # sadak
		fill(im, {(cx - 5, 11 + bob), (cx - 4, 10 + bob), (cx - 6, 10 + bob), (cx - 7, 11 + bob)}, BONE)
		pull, arrow, bdx, flash = BOW_SEQ[f] if atk else (0, None, 0, False)
		bow_x = hx + 2 + bdx
		bend = BOW_BEND[f] if atk else 5.0
		back = bend - 5.0  # gerilince uçlar geriye ve içe çekilir
		arc = [i * 0.05 for i in range(-32, 33)]
		bow = {(int(round(bow_x + math.cos(a) * bend - back)), int(round(hy + math.sin(a) * (10 - back * 0.7)))) for a in arc} 			if atk else {(int(bow_x + math.cos(a) * 10 * 0.5), int(hy + math.sin(a) * 10)) for a in arc}
		bow |= shift(bow, 1, 0)
		if atk:
			top = (int(round(bow_x - back)), int(round(hy - 10 + back * 0.7)))
			bot = (int(round(bow_x - back)), int(round(hy + 10 - back * 0.7)))
		else:
			top, bot = (int(bow_x + math.cos(-1.6) * 5), hy - 10), (int(bow_x + math.cos(1.6) * 5), hy + 10)
		sx = hx - pull + 1 + bdx
		if wpn:  # yay, kiriş, ok ve bırakma parlaması: silah katmanı
			part(im, bow, WOOD_D)
			part(im, {(top[0] + 1, top[1] - 1), (bot[0] + 1, bot[1] + 1)}, STEEL)  # dikenli uçlar
			if atk and f == 2:  # bırakmadan sonra titreyen kiriş
				fill(im, line(top[0], top[1], sx + 1, hy - 4, 1) | line(sx + 1, hy - 4, sx, hy + 3, 1) | line(sx, hy + 3, bot[0], bot[1], 1), WHITE)
			else:
				fill(im, line(top[0], top[1], sx, hy, 1), WHITE)
				fill(im, line(sx, hy, bot[0], bot[1], 1), WHITE)
			if arrow == "nock":
				ax = bow_x + int(bend) + 3  # ok ucu yayın önünde
				part(im, line(sx, hy, ax, hy, 1), WOOD_D, ol=None)
				part(im, {(ax + 1, hy), (ax, hy - 1), (ax, hy + 1), (ax + 2, hy)}, STEEL)
				fill(im, {(sx - 1, hy - 1), (sx - 1, hy + 1)}, WHITE)  # tüy
			elif arrow == "reach":  # sadaktan çekilen yeni ok
				part(im, line(cx - 6, 9 + bob, cx - 1, 13 + bob, 1), WOOD_D, ol=None)
			if flash:  # bırakma: yayın önünde parlama ve ok izi
				speed_lines(im, bow_x + 4, bow_x + 18, (hy,), (255, 250, 220, 230), seed=9)
				speed_lines(im, bow_x + 6, bow_x + 15, (hy - 2, hy + 2), (240, 246, 255, 150), seed=10)
				spark_star(im, bow_x + 6, hy, 3)
		# çeken / ok alan el gövdenin parçası
		if arrow == "nock":
			part(im, circ(sx - 1, hy, 1.4), STEEL_D)  # çeken el
		elif arrow == "reach":  # el sadakta
			part(im, circ(cx - 3, 12 + bob, 1.4), STEEL_D)
		elif atk:
			hb = (hx - 6, hy - 3) if f == 3 else (hx - 5, hy)  # bırakan el geride kalır
			part(im, circ(hb[0], hb[1], 1.4), STEEL_D)
	if glove:
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
	if f in YELL.get((kind, anim), ()):  # vuruşta bağırış: açık ağız
		fill(im, rect(17 + hdx, ey + 2, 21 + hdx, ey + 4), OL)
		fill(im, rect(18 + hdx, ey + 3, 20 + hdx, ey + 3), SCAR)
		fill(im, {(18 + hdx, ey + 2), (20 + hdx, ey + 2)}, WHITE)
	else:  # sıkılmış dişli ağız
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
	for fn in post:
		fn()
	return im


def spear_line(im, sp, T):
	"""Mızrak (sap + çelik uç + yırtık flama), sp = (dip x, dip y, uç x, uç y)."""
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


# ---------------------------------------------------------------- birimler (24x24)
US = 24


def unit_face(im, cx, ey, mouth=True, yell=False):
	fill(im, {(cx + 2, ey), (cx + 2, ey + 1), (cx + 5, ey), (cx + 5, ey + 1)}, OL)
	fill(im, {(cx + 3, ey), (cx + 6, ey)}, WHITE)
	fill(im, {(cx + 1, ey - 2), (cx + 2, ey - 1), (cx + 3, ey - 1)}, OL)  # V kaşlar
	fill(im, {(cx + 6, ey - 2), (cx + 5, ey - 1), (cx + 4, ey - 1)}, OL)
	if mouth and yell:
		fill(im, rect(cx + 3, ey + 2, cx + 5, ey + 3), OL)
		fill(im, {(cx + 4, ey + 3)}, SCAR)
	elif mouth:
		fill(im, {(cx + 3, ey + 3), (cx + 4, ey + 3), (cx + 5, ey + 3)}, OL)
		fill(im, {(cx + 4, ey + 3)}, WHITE)


# Birim saldırıları (24x24 karakter, 32x32 tuval, UNIT_PAD boşluk). Şifacı saldırmaz.
UNIT_PAD = 6
UNIT_ATK = {"swordsman": 4, "archer": 4, "shield": 4, "cannon": 5}
# Kılıççı: (eğim, çömelme, el kayması, kılıç açısı, savuruş izi (a0, a1, yoğunluk) | None, kıvılcım)
U_SWORD_SEQ = [(-1, 1, (-1, -8), -112, None, False), (1, 0, (0, -2), -25, (-165, -25, 1.0), False),
	(2, 1, (1, 0), 45, (-40, 45, 0.8), True), (0, 0, (0, 0), -75, None, False)]
# Okçu: (eğim, kiriş çekme, ok, parlama)
U_BOW_SEQ = [(-1, 3, True, False), (-1, -1, False, True), (-1, 0, False, False), (0, 1, True, False)]
# Kalkancı: (eğim, çömelme, kalkan kayması, kıvılcım)
U_SHIELD_SEQ = [(-2, 1, -2, False), (2, 0, 2, False), (3, 1, 3, True), (1, 0, 1, False)]


def u_blade(im, px, py, ang, L=10):
	a = math.radians(ang)
	ux, uy = math.cos(a), math.sin(a)
	x1, y1 = px + ux * L, py + uy * L
	part(im, line(px + ux, py + uy, x1, y1, 2), STEEL)
	nx, ny = uy, -ux
	fill(im, line(px + ux + nx * 0.6, py + uy + ny * 0.6, x1 + nx * 0.6 - ux, y1 + ny * 0.6 - uy, 1), WHITE)
	part(im, line(px - nx * 2, py - ny * 2, px + nx * 2, py + ny * 2, 1), GOLD_D)
	return x1 + ux, y1 + uy


def unit_frame(kind, team, anim, f):
	T = TEAMS[team]
	atk = anim == "attack"
	if kind == "cannon":
		return cannon_frame(team, anim, f)
	im = Img(US + 2 * UNIT_PAD, US + 2 * UNIT_PAD, UNIT_PAD, UNIT_PAD) if atk else Img(US, US)
	bob = 0 if anim == "idle" and f == 0 else (-1 if anim == "idle" else (0, -1, 0, -1)[f] if anim == "run" else 0)
	legs = (((-1, 0), (1, 0)), ((0, 1), (0, 0)), ((1, 0), (-1, 0)), ((0, 0), (0, 1)))[f] if anim == "run" else ((0, 0), (0, 0))
	lean = 0
	if atk:
		if kind == "swordsman":
			lean, bob = U_SWORD_SEQ[f][0], U_SWORD_SEQ[f][1]
		elif kind == "archer":
			lean = U_BOW_SEQ[f][0]
		elif kind == "shield":
			lean, bob = U_SHIELD_SEQ[f][0], U_SHIELD_SEQ[f][1]
		if lean > 0:
			legs = ((-1, 0), (1, 0))  # öne adım: geniş duruş
	lx = 11
	cx = 11 + lean
	shadow(im, 12, 21, 6, 2)
	for i, bx in enumerate((lx - 2, lx + 1)):
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
	yell = False
	post = []
	if kind == "swordsman":
		if atk:
			_, _, (hdx, hdy), ang, sm, spk = U_SWORD_SEQ[f]
			hx, hy = hx + hdx, hy + hdy
			if sm:
				smear(im, hx, hy, sm[0], sm[1], 12, 4.5, sm[2])
			if f == 0:  # başın üstünde: kafadan sonra çizilir
				post.append(lambda x=hx, y=hy, g=ang: u_blade(im, x, y, g))
				tip = (0, 0)
			else:
				tip = u_blade(im, hx, hy, ang)
			if spk:
				spark_star(im, int(round(tip[0])), int(round(tip[1])), 3)
			yell = f in (1, 2)
		else:
			part(im, line(hx, hy, hx + 2, hy - 10, 2), STEEL)  # daha iri kılıç
			fill(im, line(hx - 1, hy - 1, hx + 1, hy - 9, 1), WHITE)
			fill(im, {(hx + 3, hy - 5)}, STEEL_D)
			part(im, line(hx - 2, hy - 1, hx + 2, hy - 2, 1), GOLD_D)
	elif kind == "archer":
		_, pull, arrow, flash = U_BOW_SEQ[f] if atk else (0, 0, False, False)
		bow = {(int(hx + 1 + math.cos(a) * 3), int(hy + math.sin(a) * 7)) for a in [i * 0.06 for i in range(-26, 27)]}
		part(im, bow, WOOD_D)
		sx = hx + 1 - pull
		if atk and f == 2:  # titreyen kiriş
			fill(im, line(hx + 1, hy - 7, hx, hy - 2, 1) | line(hx, hy - 2, hx + 1, hy + 7, 1), WHITE)
		else:
			fill(im, line(hx + 1, hy - 7, sx, hy, 1) | line(sx, hy, hx + 1, hy + 7, 1), WHITE)
		part(im, {(hx + 2, hy - 8), (hx + 2, hy + 8)}, STEEL)
		if arrow:
			part(im, line(sx, hy, hx + 5, hy, 1), WOOD_D, ol=None)
			fill(im, {(hx + 6, hy), (hx + 5, hy - 1), (hx + 5, hy + 1)}, STEEL)
		if flash:
			speed_lines(im, hx + 3, hx + 13, (hy,), (255, 250, 220, 230), seed=4)
			spark_star(im, hx + 4, hy, 2)
	elif kind == "shield":
		part(im, line(hx - 2, hy - 1, hx + 1, hy - 9, 1), STEEL)  # kısa mızrak
	elif kind == "healer":
		part(im, line(hx, hy + 4, hx, hy - 8, 1), WOOD_D)
		part(im, circ(hx, hy - 9, 2.2), T["l"])  # parlayan küre
		fill(im, {(hx, hy - 10)}, WHITE)
	part(im, circ(hx, hy, 1.3), STEEL_D if kind != "healer" else ROBE)
	if kind == "shield":  # belirgin büyük dikenli kalkan (öne)
		sdx = U_SHIELD_SEQ[f][2] if atk else 0
		if atk and f in (1, 2):
			speed_lines(im, cx - 9, cx - 2, (8 + bob, 12 + bob, 16 + bob), (236, 242, 255, 170), seed=f)
		s0 = cx + sdx
		sh = poly([(s0 + 1, 8 + bob), (s0 + 10, 8 + bob), (s0 + 10, 16 + bob), (s0 + 5.5, 21 + bob), (s0 + 1, 16 + bob)])
		part(im, sh, STEEL_D)
		inner = poly([(s0 + 2, 10 + bob), (s0 + 9, 10 + bob), (s0 + 9, 15 + bob), (s0 + 5.5, 19 + bob), (s0 + 2, 15 + bob)])
		fill(im, inner, T["m"])
		fill(im, rect(s0 + 2, 10 + bob, s0 + 5, 12 + bob), T["l"])
		part(im, {(s0 + 5, 13 + bob), (s0 + 6, 13 + bob), (s0 + 5, 14 + bob), (s0 + 6, 14 + bob), (s0 + 5, 12 + bob)}, STEEL)
		part(im, {(s0 + 10, 8 + bob), (s0 + 11, 7 + bob)}, STEEL)
		if atk and U_SHIELD_SEQ[f][3]:
			spark_star(im, s0 + 12, 13 + bob, 4)
			yell = True
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
		unit_face(im, cx, ey, yell=yell)
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
		unit_face(im, cx, ey, yell=yell)
	elif kind == "healer":
		hood = cap | {(x, y) for x, y in head if x < cx - 1} | {(x, y) for x, y in head if y > ey + 2}
		fill(im, hood, ROBE)
		fill(im, {(x, y) for x, y in hood if y < 5 + bob}, T["d"])
		fill(im, rect(cx - 4, 6 + bob, cx + 6, 6 + bob) & head, T["m"])
		fill(im, {(x, y) for x, y in head if x > cx - 2 and 6 + bob < y <= ey + 2}, (30, 24, 44, 255))  # gölgeli yüz
		fill(im, {(cx + 3, ey), (cx + 6, ey), (cx + 3, ey + 1), (cx + 6, ey + 1)}, T["l"])  # parlayan gözler
	for fn in post:
		fn()
	return im


SMOKE = ((150, 146, 150, 220), (196, 192, 196, 200), (110, 106, 116, 200))


def smoke_puff(im, x, y, r, k, seed):
	"""Gri duman bulutu: k 1 -> 0 seyrelir."""
	rnd = random.Random(seed)
	for px, py in circ(x, y, r):
		if rnd.random() > 0.35 + 0.6 * k:
			continue
		c = SMOKE[1] if py < y - r * 0.3 else (SMOKE[2] if py > y + r * 0.4 else SMOKE[0])
		im.blend(px, py, (c[0], c[1], c[2], int(c[3] * (0.45 + 0.55 * k))))


def cannon_frame(team, anim, f):
	T = TEAMS[team]
	atk = anim == "attack"
	im = Img(US + 2 * UNIT_PAD, US + 2 * UNIT_PAD, UNIT_PAD, UNIT_PAD) if atk else Img(US, US)
	roll = 0 if anim == "idle" else f
	rc = (0, -3, -2, -1, 0)[f] if atk else 0  # geri tepme: top arabası geri kayar
	if atk:
		roll = (0, -2, -3, -3, -2)[f]
	shadow(im, 12, 21, 10, 2.2)
	IRON, IRON_L = (44, 46, 62, 255), (112, 116, 138, 255)
	lift = -1 if atk and f == 1 else 0  # ateşte namlu hafifçe kalkar
	bar = poly([(3 + rc, 7), (19 + rc, 5 + lift), (22 + rc, 8 + lift), (22 + rc, 13 + lift), (19 + rc, 15), (3 + rc, 16)])  # iri namlu
	part(im, bar, IRON)
	fill(im, {(x, y) for x, y in bar if y < 9}, IRON_L)
	part(im, rect(19 + rc, 5 + lift, 22 + rc, 15 + lift), IRON)
	fill(im, rect(21 + rc, 8 + lift, 22 + rc, 12 + lift), OL)
	if atk and f in (1, 2):  # kızgın namlu ağzı
		fill(im, rect(21 + rc, 9 + lift, 22 + rc, 11 + lift), (255, 150, 60, 255))
	fill(im, rect(7 + rc, 6, 7 + rc, 15), GOLD_D)
	fill(im, rect(12 + rc, 6, 12 + rc, 15), GOLD_D)
	cart = rect(4 + rc, 15, 18 + rc, 18)
	part(im, cart, T["m"])
	fill(im, rect(4 + rc, 15, 18 + rc, 15), T["l"])
	fill(im, rect(4 + rc, 18, 18 + rc, 18), T["d"])
	part(im, circ(10 + rc, 18.5, 5), WOOD_D)
	fill(im, circ(10 + rc, 18.5, 3), WOOD)
	fill(im, {(10 + rc, 18), (11 + rc, 18), (10 + rc, 19), (11 + rc, 19)}, STEEL)
	a0 = roll * 0.8
	for k in range(4):
		a = a0 + k * math.pi / 2
		fill(im, {(int(round(10 + rc + math.cos(a) * 3.8)), int(round(18 + math.sin(a) * 3.8)))}, OL)
	hb = -1 if atk and f in (1, 2) else 0  # topçu sarsıntıyla geri savrulur
	head = circ(4 + hb, 9, 3.4)  # topçu: miğferli, kızgın
	part(im, head, SKIN)
	fill(im, {(x, y) for x, y in head if y < 8}, STEEL_D)
	fill(im, {(5 + hb, 9), (6 + hb, 9)}, OL)
	fill(im, {(4 + hb, 7), (5 + hb, 8)}, OL)
	part(im, {(3 + hb, 5), (3 + hb, 4)}, BONE)
	part(im, rect(1 + hb, 12, 5 + hb, 15), T["m"])
	if atk:
		mx, my = 23 + rc, 10 + lift  # namlu ağzı
		if f == 0:  # fitil yanar: barutta kıvılcım
			part(im, line(6, 6, 8, 3, 1), WOOD_D, ol=None)
			spark_star(im, 8, 2, 2, (255, 170, 60, 255))
		elif f == 1:  # ATEŞ: büyük namlu alevi
			flame = poly([(mx, my - 4), (mx + 5, my - 6), (mx + 4, my - 2), (mx + 9, my), (mx + 4, my + 2), (mx + 5, my + 6), (mx, my + 4)])
			part(im, flame, (255, 150, 50, 255), ol=(200, 60, 30, 255))
			fill(im, ell(mx + 2, my, 2.5, 2), (255, 236, 150, 255))
			fill(im, {(mx + 1, my), (mx + 2, my)}, WHITE)
			smoke_puff(im, 3 + rc, 20, 2.5, 0.6, 3)  # tekerlek tozu
		else:  # duman: namlu ağzından çıkıp yükselir, seyrelir
			k = (1.0, 0.65, 0.35)[f - 2]
			up = (0, 2, 4)[f - 2]
			smoke_puff(im, mx + 2 + (f - 2), my - up, 3 + (f - 2), k, f)
			smoke_puff(im, mx - 1, my - up - 2, 2 + (f - 2) * 0.5, k * 0.9, f + 10)
			if f == 2:
				fill(im, {(mx, my), (mx + 1, my - 1)}, (255, 200, 90, 255))
	return im


# ---------------------------------------------------------------- yerleşim / şerit üretimi
ANIMS = {"idle": 2, "run": 4}


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


# ---------------------------------------------------------------- saldırı efektleri (oyunda nişana döndürülür)
# Hepsi sağa (açı 0) bakar; oyunda draw_set_transform ile kahramanın nişan açısına döndürülür.
# Ölçek oyundakiyle aynı: 1 sanat pikseli = 2/3 dünya birimi. Kılıç menzili 24 (+8 hedef yarı boyu),
# isabet yayı ±60° (battle.gd _attack / _in_arc): kesme izi yarıçapı 40 px ≈ 27 birim, ±75° (biraz taşkın).
SLASH = 96   # kesme izi karesi 96x96, pivot (48, 48) = kahramanın göğsü
THRUST_W, THRUST_H, THRUST_PX = 64, 20, 12   # saplama efekti, pivot (12, 10) = mızrağı tutan el


def slash_strip():
	"""Kılıç kesme izi, 4 kare: 0 savuruş (yarım hilal), 1 çarpma (tam, en parlak), 2 sönme, 3 dağılma."""
	frames = []
	spec = [(-75, -5, 10, 1.0), (-75, 75, 14, 1.0), (-35, 80, 8, 0.55), (10, 82, 4.5, 0.3)]
	for i, (a0, a1, th, fd) in enumerate(spec):
		im = Img(SLASH, SLASH)
		# altta koyu ince gölge: açık zeminde (toprak yol) de okunsun
		smear(im, 48, 49, a0, a1, 39, th + 1, fd, ((40, 50, 90, 110),) * 3, taper=True)
		smear(im, 48, 48, a0, a1, 38, th, fd, taper=True)
		if i == 0:  # savuruşun başı: kılıca yakın iç iz (göğüsten kopuk görünmesin)
			smear(im, 48, 48, a0 + 20, a1, 26, 5, 0.8, taper=True)
		if i == 1:  # çarpma: hilalin önünde küçük parıltılar
			for a in (20, 45, 66):
				r = math.radians(a)
				spark_star(im, int(48 + math.cos(r) * 40), int(48 + math.sin(r) * 40), 2, (255, 236, 150, 255))
		frames.append(im)
	return strip(frames)


def thrust_strip():
	"""Mızrak saplaması, 3 kare: 0 atılma (hız çizgileri), 1 çarpma (uçta patlama), 2 sönme."""
	frames = []
	py = THRUST_H // 2
	for i in range(3):
		im = Img(THRUST_W, THRUST_H)
		if i == 0:
			speed_lines(im, 14, 40, (py - 5, py - 2, py + 3, py + 6), (236, 244, 255, 170), seed=21)
			speed_lines(im, 18, 48, (py,), (255, 255, 255, 200), seed=22)
		elif i == 1:
			speed_lines(im, 16, 48, (py - 6, py - 3, py + 3, py + 6), (236, 244, 255, 200), seed=23)
			speed_lines(im, 22, 50, (py - 1, py + 1), (255, 255, 255, 140), seed=24)
			for px, pyy in circ(55, py, 5.5) - circ(55, py, 3.5):  # şok halkası
				im.blend(px, pyy, (255, 240, 190, 190))
			spark_star(im, 55, py, 5, (255, 220, 90, 255))
		else:
			speed_lines(im, 20, 40, (py - 5, py + 5), (236, 244, 255, 90), seed=25)
			for px, pyy in circ(57, py, 7) - circ(57, py, 5.5):
				if (px + pyy) % 2 == 0:
					im.blend(px, pyy, (255, 240, 190, 140))
			fill(im, {(56, py), (57, py - 1), (57, py + 1), (58, py)}, (255, 236, 150, 255))
		frames.append(im)
	return strip(frames)


def spark_strip():
	"""Vuruş kıvılcımı (isabet anı), 4 kare 16x16."""
	frames = []
	for i in range(4):
		im = Img(16, 16)
		if i == 0:
			fill(im, circ(8, 8, 3), WHITE)
			spark_star(im, 8, 8, 6, (255, 236, 150, 255))
		elif i == 1:
			spark_star(im, 8, 8, 7, GOLD)
			for px, py in circ(8, 8, 5) - circ(8, 8, 4):
				im.blend(px, py, (255, 250, 220, 200))
		elif i == 2:
			for a in range(8):
				r = math.radians(a * 45 + 22)
				fill(im, line(8 + math.cos(r) * 4, 8 + math.sin(r) * 4, 8 + math.cos(r) * 6.5, 8 + math.sin(r) * 6.5, 1), GOLD)
		else:
			for a in range(8):
				r = math.radians(a * 45)
				fill(im, {(int(8 + math.cos(r) * 7), int(8 + math.sin(r) * 7))}, GOLD_D)
		frames.append(im)
	return strip(frames)


def puff_strip():
	"""Ölüm 'puf' bulutu, 5 kare 24x24: beyaz patlama, gri duman, savrulan parçalar."""
	frames = []
	for i in range(5):
		im = Img(24, 24)
		k = 1.0 - i / 5.0
		r = 4 + i * 1.8
		rnd = random.Random(40 + i)
		for j in range(6):
			a = j * math.pi / 3 + i * 0.3
			cx, cy = 12 + math.cos(a) * r * 0.6, 12 + math.sin(a) * r * 0.5 - i * 0.6
			smoke_puff(im, cx, cy, 2.2 + i * 0.5, k, 40 + i * 7 + j)
		if i == 0:
			fill(im, circ(12, 12, 4), WHITE)
			fill(im, circ(12, 12, 2), (255, 236, 150, 255))
		elif i == 1:
			fill(im, circ(12, 11, 2.5), (255, 255, 255, 200))
		for j in range(5):  # savrulan küçük parçalar
			a = j * 1.3 + 0.4
			d = 5 + i * 2.2
			px, py = int(12 + math.cos(a) * d), int(12 + math.sin(a) * d * 0.8 - i)
			if rnd.random() < k + 0.2:
				fill(im, {(px, py)}, STEEL if j % 2 else WOOD)
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
	"+": "000010111010000", "(": "010100100100010", ")": "010001001001010", ".": "000000000000010", "x": "000101010101000",
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


def layer_diff(full, body):
	"""Silah katmanı = silahlı karenin silahsız gövdeden farklı pikselleri. Gövde + katman üst üste = silahlı kare
	(baş kılıcın önündeyse o pikseller aynıdır, katmana girmez: çizim sırası korunur)."""
	o = Img(full.w, full.h)
	bad = 0
	for i, (a, b) in enumerate(zip(full.p, body.p)):
		if a != b:
			o.p[i] = a
			if a[3] == 0:
				bad += 1  # katman bir pikseli silemez: gövdede olup silahlı karede olmayan piksel
	return o, bad


# silah -> (gövde, gövdenin saldırı animasyonu). Yumrukta silah katmanı yoktur.
HERO_WEAPON = {"sword": ("warrior", "attack"), "spear": ("lancer", "attack"), "bow": ("archer", "attack")}


def build():
	files = {}
	bad_total = 0
	# kahraman: silahsız gövde (hero_*), silah katmanı (wpn_*) ve birleşik (eski adlar: minigame'ler, önizleme)
	for team in TEAMS:
		for weapon, (kind, atk_anim) in HERO_WEAPON.items():
			for anim, n in list(ANIMS.items()) + [(atk_anim, HERO_ATK[(kind, atk_anim)])]:
				full = [hero_frame(kind, team, anim, f, True) for f in range(n)]
				body = [hero_frame(kind, team, anim, f, False) for f in range(n)]
				layer = []
				for fu, bo in zip(full, body):
					lay, bad = layer_diff(fu, bo)
					layer.append(lay)
					bad_total += bad
				files["units/%s/%s_%s.png" % (team, kind, anim)] = strip(full)
				files["units/%s/hero_%s_%s.png" % (team, kind, anim)] = strip(body)
				files["units/%s/wpn_%s_%s.png" % (team, weapon, anim)] = strip(layer)
		n = HERO_ATK[("warrior", "punch")]  # yumruk: yalnızca silahsız gövde
		body = strip([hero_frame("warrior", team, "punch", f, False) for f in range(n)])
		files["units/%s/warrior_punch.png" % team] = body
		files["units/%s/hero_warrior_punch.png" % team] = body
	if bad_total:
		print("UYARI: silah katmanında silinemeyen %d piksel (gövde silahlı karede görünmeyen şey çiziyor)" % bad_total)
	for team in TEAMS:
		for kind, _ in UNITS:
			for anim in ("idle", "run"):
				n = ANIMS[anim]
				files["units/%s/u_%s_%s.png" % (team, kind, anim)] = strip([unit_frame(kind, team, anim, f) for f in range(n)])
			if kind in UNIT_ATK:  # saldırı: 32x32 kareler
				files["units/%s/u_%s_attack.png" % (team, kind)] = strip([unit_frame(kind, team, "attack", f) for f in range(UNIT_ATK[kind])])
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
	files["fx/slash.png"] = slash_strip()
	files["fx/thrust.png"] = thrust_strip()
	files["fx/spark.png"] = spark_strip()
	files["fx/puff.png"] = puff_strip()
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
		sh = page(1260, 320, "KAHRAMAN %s (32X32) - BEKLEME 2 / KOSU 4 (SALDIRI: PREVIEW_SALDIRI_*) - MAVI USTTE, KIRMIZI ALTTA - 4 KAT" % label)
		for r, team in enumerate(("blue", "red")):
			sheet_block([(kind, label)], 32, team, ("idle", "run"), 6, 18 + r * 150, sh, "")
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


# ---------------------------------------------------------------- saldırı önizlemeleri
# Kare süreleri (ms) ve vuruş karesi: scripts/art.gd ATK_MS / ATK_HIT ile AYNI tutulmalı.
ATK_MS = {
	"sword": ([55, 45, 35, 45, 60, 70], 3), "fist": ([60, 45, 60, 75], 2),
	"spear": ([60, 60, 35, 55, 60, 70], 3), "bow": ([50, 45, 60, 70, 80, 90], 1),
	"u_swordsman": ([70, 40, 60, 80], 2), "u_archer": ([60, 60, 80, 90], 1),
	"u_shield": ([70, 50, 70, 80], 2), "u_cannon": ([90, 70, 90, 110, 120], 1),
}
SPEAR_GRIP_W = [g * 2.0 / 3.0 for g in SPEAR_GRIP]  # dünya birimi (art.gd SPEAR_GRIP)


def blit_a(dst, src, ox, oy, fx=0, fw=None):
	"""src'nin [fx, fx+fw) sütunlarını dst'ye yarı saydamlıkla karıştırarak yapıştırır."""
	fw = fw or src.w
	for y in range(src.h):
		for x in range(fw):
			c = src.p[y * src.w + fx + x]
			if c[3] > 0:
				dst.blend(ox + x, oy + y, c)


WEAPON_BODY = {"fist": "warrior", "sword": "warrior", "spear": "lancer", "bow": "archer"}  # art.gd WEAPON_SPRITE
COMP_W, COMP_H, COMP_CX, COMP_CY = 112, 96, 36, 50  # birleşik önizleme tuvali, karakter ortası


def hero_layers(files, team, weapon, anim):
	"""Oyundaki gibi katmanlar (art.gd hero_layers): [silahsız gövde, silah şeridi | None]."""
	kind = WEAPON_BODY[weapon]
	banim = ("punch" if weapon == "fist" else "attack") if anim == "attack" else anim
	body = files["units/%s/hero_%s_%s.png" % (team, kind, banim)]
	lay = None if weapon == "fist" else files["units/%s/wpn_%s_%s.png" % (team, weapon, anim)]
	return body, lay


def hero_comp(files, team, weapon, anim, f, with_fx=True, with_wpn=True):
	"""Oyundaki gibi birleşik kare (nişan sağa): gövde + silah katmanı + efekt katmanları. 112x96 tuval."""
	C = Img(COMP_W, COMP_H)
	body, lay = hero_layers(files, team, weapon, anim)
	fs = body.h
	X0, Y0 = COMP_CX - fs // 2, COMP_CY - fs // 2
	blit_a(C, body, X0, Y0, f * fs, fs)
	if lay is not None and with_wpn:
		blit_a(C, lay, X0, Y0, f * fs, fs)
	if not with_fx or anim != "attack":
		return C
	px, py = COMP_CX, COMP_CY + 3  # göğüs (oyunda pos + (0, -2))
	if weapon == "sword":
		if f >= 2:
			sl = files["fx/slash.png"]
			blit_a(C, sl, px - 48, py - 48, (f - 2) * SLASH, SLASH)
		if f >= 3:
			sp = files["fx/spark.png"]
			blit_a(C, sp, px + 33 - 8, py - 8, (f - 3) * 16, 16)
	elif weapon == "spear":
		gx, gy = COMP_CX + SPEAR_GRIP[f], COMP_CY + 5
		if 2 <= f <= 4:
			blit_a(C, files["fx/thrust.png"], gx - THRUST_PX, gy - THRUST_H // 2, (f - 2) * THRUST_W, THRUST_W)
	elif weapon == "fist":
		if f >= 2:
			sp = files["fx/spark.png"]
			blit_a(C, sp, px + 18 - 8, py - 8, (f - 2) * 16, 16)
	return C


def preview_attacks(files):
	K = 4
	def page(w, h, title):
		sh = Img(w, h)
		for i in range(w * h):
			sh.p[i] = PANEL
		text(sh, 6, 4, title, (255, 220, 120, 255))
		return sh
	def framebox(sh, im, x, y, k):
		sh.blit(over(im.scaled(k), BG), x, y)
	def ms_label(sh, x, y, key, f):
		ms, hit = ATK_MS[key]
		t0 = sum(ms[:f])
		lab = "%d  %dMS (T=%d)" % (f, ms[f], t0)
		text(sh, x, y, lab, (255, 230, 120, 255) if f == hit else (220, 220, 230, 255))
		if f == hit:
			text(sh, x, y + 8, "VURUS %d%%" % round(100 * t0 / sum(ms)), (255, 120, 90, 255))
	for kind, anim, weapon, name, label in (("warrior", "attack", "sword", "kilic", "KILIC"),
			("lancer", "attack", "spear", "mizrak", "MIZRAK"), ("archer", "attack", "bow", "yay", "YAY"),
			("warrior", "punch", "fist", "yumruk", "YUMRUK")):
		n = HERO_ATK[(kind, anim)]
		fs = HS + 2 * atk_pad(kind)
		cw = COMP_W * K + 10
		sh = page(max(n * cw + 12, 2 * n * (COMP_W * 2 + 4) + 40), 2 * (fs * K + COMP_H * K + 70) + COMP_H * 2 + 60,
			"SALDIRI %s - %s_%s.PNG (%dX%d X %d KARE, GOVDE + SILAH BIRLESIK) - USTTE EFEKTSIZ, ALTTA OYUNDAKI GIBI EFEKTLI (NISAN SAGA) - 4 KAT"
			% (label, kind.upper(), anim.upper(), fs, fs, n))
		y = 18
		for team in ("blue", "red"):
			text(sh, 6, y, "%s - EFEKTSIZ" % team.upper(), (255, 255, 255, 255))
			for f in range(n):
				x = 6 + f * cw
				ms_label(sh, x, y + 10, weapon, f)
				st = files["units/%s/%s_%s.png" % (team, kind, anim)]
				fr = Img(fs, fs)
				blit_a(fr, st, 0, 0, f * fs, fs)
				framebox(sh, fr, x, y + 28, K)
			y += fs * K + 34
			text(sh, 6, y, "%s - EFEKTLI" % team.upper(), (255, 255, 255, 255))
			for f in range(n):
				framebox(sh, hero_comp(files, team, weapon, "attack", f), 6 + f * cw, y + 10, K)
			y += COMP_H * K + 24
		text(sh, 6, y, "OYUNDAKI BOYUT (2 KAT = 1080P): MAVI EFEKTLI, SONRA KIRMIZI", (255, 255, 255, 255))
		x = 6
		for team in ("blue", "red"):
			for f in range(n):
				framebox(sh, hero_comp(files, team, weapon, "attack", f), x, y + 10, 2)
				x += COMP_W * 2 + 4
			x += 16
		sh.save(os.path.join(OUT, "preview_saldiri_%s.png" % name))
	# birimler
	kinds = [(k, l) for k, l in UNITS if k in UNIT_ATK]
	UC = US + 2 * UNIT_PAD
	cw = UC * K + 8
	sh = page(2 * 5 * cw + 60, len(kinds) * (UC * K + 40) + 40,
		"BIRIM SALDIRILARI (36X36 TUVAL) - SOLDA MAVI, SAGDA KIRMIZI - 4 KAT - SIFACI SALDIRMAZ")
	y = 18
	for kind, label in kinds:
		x = 6
		for team in ("blue", "red"):
			text(sh, x, y, "%s %s" % (label, team.upper()), (255, 255, 255, 255))
			st = files["units/%s/u_%s_attack.png" % (team, kind)]
			for f in range(UNIT_ATK[kind]):
				ms_label(sh, x + f * cw, y + 8, "u_" + kind, f)
				fr = Img(UC, UC)
				blit_a(fr, st, 0, 0, f * UC, UC)
				framebox(sh, fr, x + f * cw, y + 26, K)
			x += 5 * cw + 30
		y += UC * K + 40
	sh.save(os.path.join(OUT, "preview_saldiri_birimler.png"))
	# efekt katmanları
	sh = page(1700, 900, "SALDIRI EFEKTLERI (FX/) - SAGA BAKAR, OYUNDA NISAN ACISINA DONDURULUR - 4 KAT")
	y = 18
	for name, fw, lab in (("slash", SLASH, "SLASH.PNG KESME IZI 4 KARE (96X96, PIVOT 48,48)"),):
		text(sh, 6, y, lab)
		im = files["fx/%s.png" % name]
		for f in range(im.w // fw):
			fr = Img(fw, im.h)
			blit_a(fr, im, 0, 0, f * fw, fw)
			framebox(sh, fr, 6 + f * (fw * 4 // 2 + 10), y + 10, 2)
		y += im.h * 2 + 24
	for name, fw, lab, k in (("thrust", THRUST_W, "THRUST.PNG SAPLAMA 3 KARE", 4), ("spark", 16, "SPARK.PNG VURUS KIVILCIMI 4 KARE", 4),
			("puff", 24, "PUFF.PNG OLUM BULUTU 5 KARE", 4)):
		text(sh, 6, y, lab)
		im = files["fx/%s.png" % name]
		for f in range(im.w // fw):
			fr = Img(fw, im.h)
			blit_a(fr, im, 0, 0, f * fw, fw)
			framebox(sh, fr, 6 + f * (fw * k + 10), y + 10, k)
		y += im.h * k + 24
	sh.save(os.path.join(OUT, "preview_saldiri_efekt.png"))


def crop(im, x0, y0, w, h):
	o = Img(w, h)
	for y in range(h):
		for x in range(w):
			o.p[y * w + x] = im.get(x0 + x, y0 + y)
	return o


def preview_weapons(files):
	"""preview_silah_*.png: her silah için gövde (silahsız) / silah katmanı / gövde + silah / efektli, kare kare.
	Hepsi aynı orijinde (karakter ortası) kırpılır: katmanların hizası ve tek silah kuralı gözle denetlenir."""
	K = 3
	CW, CH = 64, 52  # kırpma: karakter ortasının -24..+40 ve -34..+18 çevresi
	FW, FH = 100, 88  # efektli kırpma
	seq = [("idle", f) for f in range(2)] + [("run", f) for f in range(4)]
	for weapon, name, label in (("fist", "yumruk", "YUMRUK (SILAHSIZ)"), ("sword", "kilic", "KILIC (+ KALKAN)"),
			("spear", "mizrak", "MIZRAK"), ("bow", "yay", "YAY")):
		body_atk, _ = hero_layers(files, "blue", weapon, "attack")
		n = body_atk.w // body_atk.h
		cols = seq + [("attack", f) for f in range(n)]
		cw = CW * K + 8
		w = len(cols) * cw + 120
		h = 2 * (3 * (CH * K + 22) + FH * 2 + 40) + 40
		sh = Img(w, h)
		for i in range(w * h):
			sh.p[i] = PANEL
		text(sh, 6, 4, "SILAH %s - GOVDE (SILAHSIZ) / SILAH KATMANI / GOVDE + SILAH / EFEKTLI - BEKLEME 2, KOSU 4, SALDIRI %d - %d KAT"
			% (label, n, K), (255, 220, 120, 255))
		y = 18
		for team in ("blue", "red"):
			text(sh, 6, y, "TAKIM " + ("MAVI" if team == "blue" else "KIRMIZI"), (255, 255, 255, 255))
			y += 10
			for row, rlab in (("body", "GOVDE"), ("wpn", "SILAH"), ("comp", "GOVDE+SILAH")):
				text(sh, 6, y + CH * K // 2, rlab, (255, 255, 255, 255))
				for c, (anim, f) in enumerate(cols):
					x = 110 + c * cw
					if row == "body":
						lab = "%s %d" % ({"idle": "BEKLEME", "run": "KOSU", "attack": "SALDIRI"}[anim], f)
						text(sh, x, y - 1, lab, (200, 200, 215, 255))
					body, lay = hero_layers(files, team, weapon, anim)
					C = Img(COMP_W, COMP_H)
					fs = body.h
					X0, Y0 = COMP_CX - fs // 2, COMP_CY - fs // 2
					if row != "wpn":
						blit_a(C, body, X0, Y0, f * fs, fs)
					if row != "body" and lay is not None:
						blit_a(C, lay, X0, Y0, f * fs, fs)
					cc = crop(C, COMP_CX - 24, COMP_CY - 34, CW, CH)
					sh.blit(over(cc.scaled(K), BG), x, y + 7)
					if row == "wpn" and lay is None:
						text(sh, x + 8, y + 7 + CH * K // 2, "YOK", (255, 255, 255, 255))
				y += CH * K + 22
			text(sh, 6, y + FH, "EFEKTLI", (255, 255, 255, 255))
			for f in range(n):
				C = hero_comp(files, team, weapon, "attack", f)
				cc = crop(C, COMP_CX - 30, COMP_CY - 48, FW, FH)
				sh.blit(over(cc.scaled(2), BG), 110 + (6 + f) * cw, y)  # saldırı sütunlarının altında
			y += FH * 2 + 40
		sh.save(os.path.join(OUT, "preview_silah_%s.png" % name))


if __name__ == "__main__":
	files = build()
	for path, im in files.items():
		im.save(os.path.join(OUT, path))
	preview(files)
	preview_attacks(files)
	preview_weapons(files)
	print("tamam: %d PNG -> %s" % (len(files), os.path.normpath(OUT)))
