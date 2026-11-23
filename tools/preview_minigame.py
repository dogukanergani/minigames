"""Minigame önizleme sayfaları (tools/make_minigame_art.py çağırır).

preview_minigame_ortak.png  : yazı tipi, ortak efektler (4 kat)
preview_minigame_kosu.png   : Koşu parçaları (4 kat) + oyundaki boyutta kompozisyon
preview_minigame_coin.png   : Coin Toplama parçaları + kompozisyon
preview_minigame_refleks.png: Refleks parçaları + üç anın kompozisyonu (HAZIR OL / VUR! / ÇOK ERKEN)
Kompozisyonlar 1920x1080 (oyunun 1080p ekranı): minigames/*.gd çizim kodunun yaklaşık kopyasıdır
(isimler oyunda yumuşak yazı tipiyle çizilir; burada minik pixel yazı ile temsil edilir).
"""
import math
import os
import random

from make_sprites import Img, over, text, part, fill, rect, ell, OL, TEAMS

PANEL = (36, 40, 56, 255)
BG = (70, 130, 74, 255)
TITLE = (255, 220, 120, 255)
TEAM_COL = [(92, 148, 245, 255), (245, 107, 87, 255)]


def page(w, h, title):
	sh = Img(w, h)
	for i in range(w * h):
		sh.p[i] = PANEL
	text(sh, 6, 4, title, TITLE)
	return sh


def load_png(path):
	"""Basit PNG okuyucu (yalnızca make_sprites.py'nin yazdığı 8 bit RGBA, filtre 0)."""
	import struct
	import zlib
	d = open(path, "rb").read()
	w, h = struct.unpack(">II", d[16:24])
	i = 8
	idat = b""
	while i < len(d):
		n = struct.unpack(">I", d[i:i + 4])[0]
		t = d[i + 4:i + 8]
		if t == b"IDAT":
			idat += d[i + 8:i + 8 + n]
		i += 12 + n
	raw = zlib.decompress(idat)
	im = Img(w, h)
	stride = w * 4 + 1
	prev = bytearray(w * 4)
	for y in range(h):
		f = raw[y * stride]
		line = bytearray(raw[y * stride + 1:(y + 1) * stride])
		for x in range(w * 4):  # PNG filtreleri
			a = line[x - 4] if x >= 4 else 0
			b = prev[x]
			c = prev[x - 4] if x >= 4 else 0
			if f == 1:
				line[x] = (line[x] + a) & 255
			elif f == 2:
				line[x] = (line[x] + b) & 255
			elif f == 3:
				line[x] = (line[x] + (a + b) // 2) & 255
			elif f == 4:
				p = a + b - c
				pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
				line[x] = (line[x] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255
		for x in range(w):
			im.p[y * w + x] = tuple(line[x * 4:x * 4 + 4])
		prev = line
	return im


class Comp:
	"""Oyun ekranı taklidi: sanat pikseli ızgarası (960x540, dünya x1.5), sonra 2 katına çıkarılır."""

	def __init__(self, M, bg):
		self.M = M
		self.im = Img(960, 540)
		self.im.p = list(bg.p)
		root = os.path.join(M.ms.OUT)
		self.root = root
		self._tex = {}

	def tex(self, rel):
		if rel not in self._tex:
			self._tex[rel] = load_png(os.path.join(self.root, rel))
		return self._tex[rel]

	@staticmethod
	def w2a(v):
		return int(round(v * 1.5))

	def frame(self, rel, i, fw, center_w, k=1, tint=None, flip=False, alpha=255):
		t = self.tex(rel)
		fr = self.M.frame_of(t, i, fw)
		if flip:
			fr = self.M.flip_h(fr)
		if tint:
			fr = tinted_mul(fr, tint)
		if k != 1:
			fr = fr.scaled(k)
		x = self.w2a(center_w[0]) - fr.w // 2
		y = self.w2a(center_w[1]) - fr.h // 2
		blit_alpha(self.im, fr, x, y, alpha)

	def hero(self, team, anim, i, foot_w, flip=False, k=1, tint=None, fw=32):
		t = self.tex("units/%s/warrior_%s.png" % (["blue", "red"][team], anim))
		fw = t.h
		fr = self.M.frame_of(t, i % (t.w // fw), fw)
		if flip:
			fr = self.M.flip_h(fr)
		if tint:
			fr = tinted_mul(fr, tint)
		foot = 0.88 if fw == 32 else (0.88 * 32 + (fw - 32) * 0.5) / fw
		if k != 1:
			fr = fr.scaled(k)
		x = self.w2a(foot_w[0]) - fr.w // 2
		y = self.w2a(foot_w[1]) - int(fr.h * foot)
		blit_alpha(self.im, fr, x, y, 255)

	def rect(self, r, col, alpha=None):
		x0, y0 = self.w2a(r[0]), self.w2a(r[1])
		x1, y1 = self.w2a(r[0] + r[2]), self.w2a(r[1] + r[3])
		c = col if alpha is None else col[:3] + (alpha,)
		for y in range(y0, y1):
			for x in range(x0, x1):
				self.im.blend(x, y, c)

	def plate(self, r, fill_c, rim=(128, 140, 178, 255)):
		self.rect((r[0] - 1, r[1] - 1, r[2] + 2, r[3] + 2), (13, 10, 23, 255))
		self.rect(r, rim)
		self.rect((r[0] + 1, r[1] + 1, r[2] - 2, r[3] - 2), fill_c)
		lt = tuple(min(255, int(c + (255 - c) * 0.25)) for c in fill_c[:3]) + (fill_c[3],)
		self.rect((r[0] + 1, r[1] + 1, r[2] - 2, 1), lt)

	def ellipse(self, c, rx, ry, col, outline=None):
		cx, cy = c[0] * 1.5, c[1] * 1.5
		for x, y in ell(cx, cy, rx * 1.5, ry * 1.5):
			self.im.blend(x, y, col)
		if outline:
			inner = ell(cx, cy, rx * 1.5 - 1.5, ry * 1.5 - 1.5)
			for x, y in ell(cx, cy, rx * 1.5, ry * 1.5) - inner:
				self.im.blend(x, y, outline)

	def big(self, s, pos_w, sc_w, col, align="c", shadow=True):
		k = max(1, int(round(sc_w * 1.5)))
		w = self.M.big_w(s, k)
		x = self.w2a(pos_w[0])
		if align == "c":
			x -= w // 2
		elif align == "r":
			x -= w
		y = self.w2a(pos_w[1]) - 11 * k
		if shadow:
			self.M.big_text(self.im, x + 4, y + 4, s, (60, 40, 60, 255), k)  # oyundaki gibi ~3 birim gölge
		self.M.big_text(self.im, x, y, s, col, k)

	def small(self, s, pos_w, col=(255, 255, 255, 255), align="c"):
		s = s.upper()
		w = len(s) * 4
		x = self.w2a(pos_w[0])
		if align == "c":
			x -= w // 2
		elif align == "r":
			x -= w
		y = self.w2a(pos_w[1]) - 6
		for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1), (1, 1)):
			text(self.im, x + dx, y + dy, s, (13, 10, 23, 255))
		text(self.im, x, y, s, col)

	def ring(self, p, team, mine):
		c = (p[0], p[1] + 4)
		col = TEAM_COL[team]
		if mine:
			self.ellipse(c, 12, 6, col[:3] + (110,), tuple(min(255, v + 80) for v in col[:3]) + (255,))
			self.ellipse(c, 14.5, 7.25, (0, 0, 0, 0), (255, 216, 64, 220))
		else:
			self.ellipse(c, 9, 4.5, col[:3] + (90,), tuple(min(255, v + 50) for v in col[:3]) + (255,))

	def marker(self, p, team, mine):
		x, y = self.w2a(p[0]), self.w2a(p[1])
		if mine:
			pts = {(x + dx, y + dy) for dx in range(-7, 8) for dy in range(-9, 1)
				if dy >= -3 or (abs(dx) >= 5 and dy >= -9 + (7 - abs(dx)) // 1 - 2) or (abs(dx) <= 1 and dy >= -10)}
			part(self.im, {(x + dx, y + dy) for dx in range(-7, 8) for dy in range(-4, 1)}
				| {(x - 7, y - 8), (x - 7, y - 7), (x - 7, y - 6), (x - 7, y - 5), (x - 6, y - 5),
				(x + 7, y - 8), (x + 7, y - 7), (x + 7, y - 6), (x + 7, y - 5), (x + 6, y - 5),
				(x, y - 10), (x, y - 9), (x - 1, y - 8), (x + 1, y - 8), (x, y - 8), (x - 1, y - 7), (x + 1, y - 7), (x, y - 7),
				(x - 2, y - 6), (x - 1, y - 6), (x, y - 6), (x + 1, y - 6), (x + 2, y - 6), (x - 3, y - 5), (x + 3, y - 5)}, (255, 209, 51, 255))
		else:
			tri = {(x + dx, y + dy) for dy in range(-7, 1) for dx in range(-6, 7) if abs(dx) <= (dy + 7) * 6 // 7 and True}
			tri = {(x + dx, y + dy) for dy in range(-7, 1) for dx in range(-6, 7) if abs(dx) <= -dy * 6 // 7}
			part(self.im, tri, tuple(min(255, v + 40) for v in TEAM_COL[team][:3]) + (255,))

	def actor(self, team, anim, i, p, flip, mine, name):
		self.ring(p, team, mine)
		self.hero(team, anim, i, (p[0], p[1] + 4), flip)
		top = 21 + 2
		self.small(name, (p[0], p[1] - top + 1), (255, 235, 153, 255) if mine else (255, 255, 255, 255))
		self.marker((p[0], p[1] - top - 6), team, mine)

	def band(self, title, secs, urgent=False):
		for i in range(6):
			self.rect((0, i * 3, 640, 3), (13, 8, 23, int(255 * (0.42 - i * 0.07))))
		tw = (len(title) * 12 + 1) * (2 / 3)
		r = (4, 2, tw + 10, 14)
		r = (4, 2, tw + 10, 15)
		self.plate(r, (158, 41, 46, 255), (240, 190, 56, 255))
		self.big(title, (r[0] + 5 + (tw / 2), 9), 2 / 3, (255, 242, 217, 255), shadow=False)
		if secs is None:
			return
		pr = (592, 2, 44, 14)
		self.plate(pr, (115, 18, 26, 255) if urgent else (28, 26, 43, 255), (255, 90, 90, 255) if urgent else (128, 140, 178, 255))
		self.frame("minigame/clock.png", 0, 12, (pr[0] + 8, 9))
		self.big(str(secs), (pr[0] + pr[2] - 4, 9), 2 / 3, (255, 64, 64, 255) if urgent else (255, 230, 130, 255), "r", shadow=False)

	def save(self, sheet, x, y, label):
		text(sheet, x, y - 10, label, TITLE)
		sheet.blit(self.im.scaled(2), x, y)


def tinted_mul(im, col):
	o = Img(im.w, im.h)
	for i, c in enumerate(im.p):
		if c[3]:
			o.p[i] = tuple(c[k] * col[k] // 255 for k in range(3)) + (c[3],)
	return o


def blit_alpha(dst, src, ox, oy, alpha=255):
	for y in range(src.h):
		for x in range(src.w):
			c = src.p[y * src.w + x]
			if c[3]:
				dst.blend(ox + x, oy + y, c[:3] + (c[3] * alpha // 255,))


def strip_block(sheet, im, fw, x, y, k, label, bg=BG):
	text(sheet, x, y, label)
	n = im.w // fw
	for f in range(n):
		fr = Img(fw, im.h)
		for yy in range(im.h):
			for xx in range(fw):
				fr.p[yy * fw + xx] = im.p[yy * im.w + f * fw + xx]
		sheet.blit(over(fr, bg).scaled(k), x + f * (fw * k + 6), y + 10)
	return x + n * (fw * k + 6) + 14


# ================================================================
def make_previews(files, M):
	out = M.ms.OUT
	# ---------------- ortak
	sh = page(1500, 700, "MINIGAME ORTAK PARCALAR - BUYUK PIXEL YAZI (TINT ILE RENKLENIR) / EFEKTLER - 4 KAT")
	text(sh, 6, 18, "FONT.PNG 13X23 HUCRE: " + "".join(c for c in M.FONT_CHARS if ord(c) < 128))
	fnt = files["font.png"]
	sh.blit(over(fnt, PANEL).scaled(2), 6, 30)
	y = 90
	for s, col, k in (("3 2 1 BAŞLA!", (255, 230, 130, 255), 4), ("VUR! ÇOK ERKEN!", (140, 255, 115, 255), 3),
			("BİTTİ! 234 MS", (255, 80, 80, 255), 3), ("KOŞU COİN TOPLAMA REFLEKS ĞÜÖ", (255, 242, 217, 255), 2)):
		M.big_text(sh, 6, y, s, col, k)
		y += 23 * k + 8
	x = 6
	y = 480
	x = strip_block(sh, files["burst.png"], 48, x, y, 2, "BURST 4 KARE (GERI SAYIM)", PANEL)
	x = strip_block(sh, files["sparkle.png"], 20, x, y, 4, "SPARKLE 5 KARE (COIN)")
	x = strip_block(sh, files["dust.png"], 10, x, y, 6, "DUST 4 KARE (KOSU TOZU)")
	x = strip_block(sh, files["clock.png"], 12, x, y, 6, "SAAT", PANEL)
	y = 600
	x = 6
	x = strip_block(sh, files["pennant.png"], 8, x, y, 6, "FLAMA 3", PANEL)
	x = strip_block(sh, files["spectators.png"], 12, x, y, 4, "SEYIRCI 6 TUR X (BEKLEME / TEZAHURAT)")
	sh.save(os.path.join(out, "preview_minigame_ortak.png"))

	# ---------------- KOŞU
	sh = page(1960, 1500, "KOSU - ENGELLER (TAS / KUTUK / BARIKAT: UST KAPAK + YINELENEN ORTA + ALT YUZ), DIREKLER, KORKULUK - 4 KAT / ALTTA OYUNDAKI BOYUT 1920X1080")
	x = 6
	for name, lab in (("ob_stone", "TAS"), ("ob_log", "KUTUK"), ("ob_fence", "BARIKAT")):
		text(sh, x, 18, lab + " (PARCALAR)")
		sh.blit(over(files[name + ".png"], BG).scaled(4), x, 30)
		x += 21 * 4 + 20
	for name, fw, lab in (("finish_post", 16, "BITIS DIREGI"), ("start_post", 9, "BASLANGIC"), ("rail", 16, "KORKULUK")):
		text(sh, x, 18, lab)
		sh.blit(over(files[name + ".png"], BG).scaled(4), x, 30)
		x += files[name + ".png"].w * 4 + 20
	sh.blit(files["run_bg.png"].scaled(1).scaled(1), 1000, 30) if False else None
	text(sh, 1000, 18, "RUN_BG.PNG (960X540, 1/2 OLCEK)")
	half = Img(480, 270)
	bgimg = files["run_bg.png"]
	for yy in range(270):
		for xx in range(480):
			half.p[yy * 480 + xx] = bgimg.p[(yy * 2) * 960 + xx * 2]
	sh.blit(half, 1000, 30)
	c = Comp(M, files["run_bg.png"])
	compose_run(c, M)
	c.save(sh, 6, 360, "OYUNDAKI BOYUT (1080P, 3 OYUNCU, OYUN SIRASINDA): ARKA PLAN + ENGELLER + KAHRAMANLAR + HUD")
	sh.save(os.path.join(out, "preview_minigame_kosu.png"))

	# ---------------- COIN
	sh = page(1960, 1420, "COIN TOPLAMA - ARENA ZEMINI, COIN, PARILTI / ALTTA OYUNDAKI BOYUT 1920X1080 (SON 5 SN)")
	half = Img(480, 270)
	bgimg = files["coins_bg.png"]
	for yy in range(270):
		for xx in range(480):
			half.p[yy * 480 + xx] = bgimg.p[(yy * 2) * 960 + xx * 2]
	text(sh, 6, 18, "COINS_BG.PNG (1/2 OLCEK)")
	sh.blit(half, 6, 30)
	x = 520
	cn = load_png(os.path.join(out, "fx", "coin.png"))
	x = strip_block(sh, files["coin.png"], 16, x, 30, 5, "MINIGAME/COIN.PNG 6 KARE (ARENA COINI)")
	x = strip_block(sh, files["sparkle.png"], 20, 520, 150, 5, "TOPLAMA PARILTISI 5 KARE")
	c = Comp(M, files["coins_bg.png"])
	compose_coins(c, M)
	c.save(sh, 6, 330, "OYUNDAKI BOYUT (1080P, 4 OYUNCU, SON 5 SN KIRMIZI NABIZ)")
	sh.save(os.path.join(out, "preview_minigame_coin.png"))

	# ---------------- REFLEKS
	sh = page(1960, 3400, "REFLEKS - DUELLO SAHNESI: HAZIR OL (BEKLEME) / VUR! (YESIL FLAS) / SONUC (MS) / COK ERKEN (CATLAK) - 1920X1080")
	for i, (mode, lab) in enumerate((("wait", "1) HAZIR OL: RAKIPLER SILUET, KIZIL NABIZ"), ("go", "2) VUR! YESIL FLAS + SARSINTI"),
			("hit", "3) BASTI: ATILMA + SURE (MS)"))):
		c = Comp(M, files["reaction_bg.png"])
		compose_reaction(c, M, mode)
		c.save(sh, 6, 30 + i * 1110, lab)
	sh.save(os.path.join(out, "preview_minigame_refleks.png"))
	sh = page(1960, 1130, "REFLEKS - 4) COK ERKEN: KIRMIZI CATLAK + SENDELEME")
	c = Comp(M, files["reaction_bg.png"])
	compose_reaction(c, M, "early")
	c.save(sh, 6, 30, "COK ERKEN (5 OYUNCU)")
	sh.save(os.path.join(out, "preview_minigame_refleks_erken.png"))


# ---------------------------------------------------------------- kompozisyonlar (minigames/*.gd ile aynı yerleşim)
def compose_run(c, M):
	TT, TB, SX, FX = 28.0, 348.0, 22.0, 600.0
	r = random.Random(4)
	obstacles = []
	for i in range(12):
		x = 80.0 + i * 41.0
		h = r.uniform(60.0, 110.0)
		y = r.uniform(TT + 30.0, TB - 30.0 - h)
		obstacles.append((x, y, 14.0, h))
	# seyirciler ve korkuluk
	x, i = 30.0, 0
	while x < 585.0:
		kind = (i * 7 + 3) % 6
		up = (i * 3) % 4 < 2
		c.frame("minigame/spectators.png", kind * 2 + (1 if up else 0), 12, (x, 22.0 + (i * 5) % 3))
		x += 9.0 + (i * 13) % 5
		i += 1
	rail = c.tex("minigame/rail.png")
	for rx in range(0, 960, 16):
		blit_alpha(c.im, rail, rx, 36)
		blit_alpha(c.im, rail, rx, 526)
	items = []
	kinds = ["ob_stone", "ob_log", "ob_fence"]
	for i, o in enumerate(obstacles):
		items.append((o[1] + o[3], "ob", (i, o)))
	players = [((300.0, 120.0), 0, True, "SEN", "run", False), ((338.0, 228.0), 1, False, "RAKIP", "run", False),
		((250.0, 300.0), 0, False, "TAKIM", "run", False)]
	for p in players:
		items.append((p[0][1] + 4, "pl", p))
	for y in (TT + 1.0, TB + 9.0):
		items.append((y, "post", ("start_post", 9, (SX - 11.0, y))))
	items.append((TB + 9.0, "post", ("finish_post", 16, (FX + 6.0, TB + 9.0))))
	# toz
	for k, (px, py) in enumerate(((292.0, 123.0), (286.0, 122.0), (330.0, 231.0), (243.0, 303.0))):
		c.frame("minigame/dust.png", min(3, k), 10, (px, py))
	items.sort(key=lambda t: t[0])
	for _, kind, d in items:
		if kind == "ob":
			i, o = d
			t = c.tex("minigame/%s.png" % kinds[(i * 5 + int(o[3])) % 3])
			c.rect((o[0] + 3, o[1] + 4, o[2], o[3]), (13, 8, 20, 72))
			x0, y0 = c.w2a(o[0]), c.w2a(o[1])
			h = int(round(o[3] * 1.5))
			cut = lambda a, b: crop(t, 0, a, 21, b - a)  # noqa: E731
			blit_alpha(c.im, cut(0, 10), x0, y0)
			yy = 10
			while yy < h - 4:
				part_h = min(16, h - 4 - yy)
				blit_alpha(c.im, cut(10, 10 + part_h), x0, y0 + yy)
				yy += part_h
			blit_alpha(c.im, cut(26, 34), x0, y0 + h - 4)
		elif kind == "post":
			name, fw, foot = d
			t = c.tex("minigame/%s.png" % name)
			c.frame("minigame/%s.png" % name, 0, fw, (foot[0], foot[1] - t.h * (2 / 3) * 0.5))
			if name == "finish_post":
				for team, dx in ((0, -13), (1, 9)):
					fl = c.tex("buildings/%s_flag.png" % ["blue", "red"][team])
					fr = M.frame_of(fl, 1, 24)
					blit_alpha(c.im, fr, c.w2a(foot[0] + dx + 2) - 3, c.w2a(foot[1] - 1 + 2) - 38)
		else:
			(p, team, mine, name, anim, flip) = d
			c.actor(team, anim, 1, p, flip, mine, name)
			# sıra rozeti
			rank = {"SEN": 1, "RAKIP": 0, "TAKIM": 2}[name]
			b = (p[0] - len(name) * 4 / 1.5 / 2 - 10, p[1] - 23 - 4, 8, 8)
			c.plate(b, (158, 107, 20, 255) if rank == 0 else (46, 43, 66, 255), (255, 216, 77, 255) if rank == 0 else (128, 140, 178, 255))
			c.small(str(rank + 1), (b[0] + 4, b[1] + 5))
			if mine:
				x, y = c.w2a(p[0] + 12), c.w2a(p[1] - 8)
				fill(c.im, {(x + dx, y + dy) for dx in range(0, 7) for dy in range(-4, 5) if abs(dy) <= 4 - dx * 4 // 6}, (255, 216, 64, 255))
	# flamalı ip
	top, bot = (606.0, -2.0), (606.0, 329.0)
	pts = []
	for k in range(25):
		u = k / 24
		pts.append((top[0] + math.sin(u * math.pi) * 6, top[1] + (bot[1] - top[1]) * u))
	for k in range(24):
		for x, y in M.line(pts[k][0] * 1.5, pts[k][1] * 1.5, pts[k + 1][0] * 1.5, pts[k + 1][1] * 1.5, 1):
			c.im.set(x, y, (20, 13, 13, 255))
	for k in range(1, 24):
		c.frame("minigame/pennant.png", k % 3, 8, (pts[k][0] + 3, pts[k][1] + 2))
	c.band("KOŞU", 17)
	# ilerleme çubuğu
	r = (232, 3, 176, 12)
	c.plate(r, (23, 20, 38, 240))
	x0, x1, yc = r[0] + 8, r[0] + r[2] - 12, r[1] + 6
	c.rect((x0, yc - 1, x1 - x0, 2), (92, 77, 66, 255))
	for k in range(4):
		c.rect((x1 + 1 + (k % 2) * 2, yc - 4 + k * 2, 2, 2), (255, 255, 255, 255))
		c.rect((x1 + 1 + ((k + 1) % 2) * 2, yc - 4 + k * 2, 2, 2), (20, 15, 25, 255))
	for (p, team, mine, *_rest) in sorted(players, key=lambda t: t[2]):
		u = (p[0] - SX) / (FX - SX)
		cx = round(x0 + (x1 - x0) * u)
		if mine:
			c.rect((cx - 3, yc - 3, 6, 6), (255, 216, 64, 255))
		c.rect((cx - 2, yc - 2, 4, 4), (13, 10, 23, 255))
		c.rect((cx - 1.5, yc - 1.5, 3, 3), TEAM_COL[team])


def crop(t, x, y, w, h):
	o = Img(w, h)
	for yy in range(h):
		for xx in range(w):
			o.p[yy * w + xx] = t.p[(y + yy) * t.w + x + xx]
	return o


def compose_coins(c, M):
	r = random.Random(8)
	coins = [(r.uniform(20, 620), r.uniform(40, 340)) for _ in range(9)]
	for i, (x, y) in enumerate(coins):
		c.ellipse((x, y + 5), 4.5, 1.8, (10, 20, 10, 100))
		c.frame("minigame/coin.png", i % 6, 16, (x, y - 1))
	players = [((210.0, 150.0), 0, True, "SEN", 7, "run", False), ((400.0, 220.0), 1, False, "RAKIP", 9, "run", True),
		((120.0, 290.0), 1, False, "KIRMIZI2", 4, "idle", False), ((520.0, 120.0), 0, False, "MAVI2", 2, "run", True)]
	for (px, py) in ((203.0, 153.0), (409.0, 223.0)):
		c.frame("minigame/dust.png", 1, 10, (px, py))
	for p, team, mine, name, n, anim, flip in sorted(players, key=lambda t: t[0][1]):
		c.actor(team, anim, 2, p, flip, mine, name)
		pos = (p[0] + 7, p[1] - 23 - 9)
		c.frame("fx/coin.png", 0, 12, (pos[0] + 3, pos[1] + 3))
		c.small(str(n), (pos[0] + 8, pos[1] + 4), (255, 230, 115, 255), "l")
	# toplama anı
	c.frame("minigame/sparkle.png", 1, 20, (232.0, 146.0))
	c.ellipse((232.0, 146.0), 9, 9, (0, 0, 0, 0), (255, 242, 153, 160))
	c.big("+1", (210.0, 102.0), 2 / 3, (255, 230, 102, 255))
	# son 5 sn nabzı
	for i in range(4):
		a = int(255 * 0.27 * (1 - i * 0.22))
		col = (230, 26, 30, a)
		c.rect((0, 20 + i * 2, 640, 2), col)
		c.rect((0, 358 - i * 2, 640, 2), col)
		c.rect((i * 2, 18, 2, 342), col)
		c.rect((638 - i * 2, 18, 2, 342), col)
	c.band("COİN TOPLAMA", 4, urgent=True)
	# skor tablosu
	rows = sorted(players, key=lambda t: -t[4])
	r = (512, 21, 124, 6 + len(rows) * 11)
	c.plate(r, (23, 20, 38, 224))
	for i, (p, team, mine, name, n, *_x) in enumerate(rows):
		row = (r[0] + 3, r[1] + 3 + i * 11, r[2] - 6, 10)
		if mine:
			c.rect(row, (158, 115, 26, 140))
		c.rect((row[0], row[1], 2, row[3]), TEAM_COL[team])
		c.small(str(i + 1), (row[0] + 6, row[1] + 5), (255, 216, 77, 255) if i == 0 else (237, 235, 247, 255))
		c.small(name, (row[0] + 13, row[1] + 5), align="l")
		c.frame("fx/coin.png", 0, 12, (row[0] + row[2] - 18, row[1] + 5))
		c.small(str(n), (row[0] + row[2] - 1, row[1] + 5), (255, 230, 115, 255), "r")


def compose_reaction(c, M, mode):
	others = [(1, "RAKIP"), (0, "TAKIM"), (1, "KIRMIZI2"), (0, "MAVI2")]
	if mode in ("go", "hit"):
		others = others[:1]
	if mode == "wait" or mode == "early":
		c.rect((0, 0, 640, 360), (89, 5, 20, 40))
	else:
		c.rect((0, 0, 640, 360), (77, 255, 102, 31 if mode == "hit" else 110))
	foot_y = 255.0
	sc = 3 if len(others) <= 1 else (2 if len(others) <= 3 else 1.5)
	items = []
	for i, (team, name) in enumerate(others):
		col, row = i // 3, i % 3
		n_in = min(3, len(others) - col * 3)
		off = row - (n_in - 1) * 0.5
		items.append((foot_y + off * 30, team, name, 455.0 + col * 62 + abs(off) * 16))
	items.sort()
	lit = mode in ("go", "hit")
	for y, team, name, x in items:
		c.ellipse((x, y + 1), 9 * sc, 3 * sc, (13, 5, 15, 128))
		tint = (107, 92, 128, 255) if lit else (33, 18, 41, 255)
		c.hero(team, "idle", 0, (x, y), True, max(1, int(round(sc * 1.0))) if sc != 1.5 else 2, tint)  # 1.5 kat önizlemede 2
	for y, team, name, x in items:
		c.small(name, (x, y + 11), (255, 255, 255, 200))
	me = [170.0, foot_y]
	if mode == "hit":
		me[0] += 90
	if mode == "early":
		me[0] -= 12
	c.ellipse((me[0], me[1] + 1), 26, 8, (13, 5, 15, 128))
	if mode == "hit":
		c.hero(0, "attack", 3, tuple(me), False, 3)
	else:
		c.hero(0, "idle", 0, tuple(me), False, 3, (255, 115, 115, 255) if mode == "early" else None)
	c.small("SEN", (me[0], me[1] + 15), (255, 235, 153, 255))
	c.marker((me[0], me[1] - 62), 0, True)
	c.rect((0, 0, 640, 22), (5, 3, 10, 217))
	c.rect((0, 334, 640, 26), (5, 3, 10, 217))
	c.band("REFLEKS", None)
	cc = (320, 92)
	if mode == "wait":
		c.big("HAZIR OL", cc, 8 / 3, (255, 200, 120, 255))
		c.plate((190, 124, 260, 15), (23, 20, 38, 230))
		c.small("EKRAN YESIL OLUNCA BAS!  (BOSLUK / TIKLA)", (320, 131))
	elif mode == "go":
		c.frame("minigame/burst.png", 1, 48, cc, 6, alpha=200)
		c.big("VUR!", cc, 4, (140, 255, 115, 255))
	elif mode == "hit":
		w = (len("187 MS") * 12 + 1) * 8 / 3 + 20
		c.plate((320 - w / 2, cc[1] - 25, w, 50), (23, 20, 38, 230), (255, 216, 77, 255))
		c.big("187 MS", cc, 8 / 3, (255, 230, 130, 255))
		c.big("ŞİMŞEK!", (320, cc[1] + 42), 4 / 3, (140, 255, 115, 255))
		c.big("DİĞERLERİ BEKLENİYOR..", (320, 318), 2 / 3, (204, 199, 230, 255))
	else:
		ct = c.tex("minigame/crack.png")
		big = tinted_mul(ct, (255, 77, 77, 255)).scaled(2)
		blit_alpha(c.im, big, 480 - big.w // 2, 262 - big.h // 2)
		c.frame("minigame/burst.png", 2, 48, cc, 6, alpha=200)
		c.big("ÇOK ERKEN!", cc, 8 / 3, (255, 77, 77, 255))
		c.plate((190, 128, 260, 15), (23, 20, 38, 230))
		c.small("YESILI BEKLEMEDEN BASTIN: EN SONA DUSTUN.", (320, 135))
	# alt şerit
	names = [("SEN", 0)] + [(n, t) for t, n in others]
	w = min(120, 620 / len(names))
	x0 = 320 - w * len(names) / 2
	for i, (n, t) in enumerate(names):
		r = (x0 + i * w + 2, 339, w - 4, 15)
		mine = i == 0
		c.plate(r, (158, 115, 26, 230) if mine else (23, 20, 38, 230), (255, 216, 77, 255) if mine else (128, 140, 178, 255))
		c.rect((r[0] + 1, r[1] + 1, 3, r[3] - 2), TEAM_COL[t])
		c.small(n, (r[0] + 6, r[1] + 7), align="l")
