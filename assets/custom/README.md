# Özgün sprite paketi (repoda, telif sorunu yok)

Bu klasördeki PNG'lerin hepsi `tools/make_sprites.py` ile **kodla üretilir** (özgün, bağımlılıksız Python).
Elle düzenleme yapma; `tools/make_sprites.py` içindeki çizimi değiştirip yeniden üret:

```
python tools/make_sprites.py
```

- `units/<mavi|kırmızı>/` kahraman (`warrior|archer|lancer` x `idle|run`, 32x32 kare) ve birim (`u_*`, 24x24 kare) şeritleri
- **Kahraman katmanları (savaş bunları çizer):** `hero_<gövde>_<anim>.png` SİLAHSIZ gövde, `wpn_<sword|spear|bow>_<anim>.png`
  silah katmanı (anim: `idle|run|attack`). Silah şeridi gövdeyle aynı kare boyu, sırası ve orijinindedir: aynı kare üst üste çizilir.
  Katman = silahlı kare ile silahsız gövdenin farkı (çizim sırası korunur). Kılıç katmanı kalkanı da taşır; yumrukta (`hero_warrior_punch`) silah yok.
  Gövde silaha göre: kılıç/yumruk = `warrior`, mızrak = `lancer`, yay = `archer`. Önizleme: `preview_silah_*.png`.
  Eski adlı `warrior_*`, `lancer_*`, `archer_*` şeritleri gövde + silah birleşik hâlidir (minigame'ler kullanır).
- Saldırılar: kahraman `warrior_attack` (kılıç, 6), `warrior_punch` (yumruk, 4), `archer_attack` (6), **48x48 kare**; `lancer_attack` (6) **64x64 kare**;
  birim `u_swordsman|u_archer|u_shield|u_cannon_attack` (4/4/4/5), **36x36 kare**. Karakter tuvalin ortasında, silah/efekt çerçeveye sığsın diye.
  Kare süreleri `scripts/art.gd` `ATK_MS` = `tools/make_sprites.py` `ATK_MS` (vuruş anı ~%45).
- `terrain/` çimen (3), toprak yol (2), taş engel (2), süs (5, çarpışmasız); `buildings/` kale, bayrak (4 kare); `fx/` ok, top, patlama, duvarlar, coin
- Saldırı efektleri (`fx/`, sağa bakar, oyunda nişan açısına döndürülür; silahın kendisini çizmezler): `slash` (kılıç kesme izi 4x 96x96),
  `thrust` (saplama 3x 64x20), `spark` (vuruş kıvılcımı 4x 16x16), `puff` (ölüm bulutu 5x 24x24)
- `preview_*.png` etiketli önizleme sayfaları (her çalıştırmada yenilenir)
- Ölçek: 1 sanat pikseli = 2/3 dünya birimi = 1080p'de tam 2 ekran pikseli. Meta: `scripts/art.gd` `PACKS["custom"]`.
- Paket önceliği: `assets/custom/` -> `assets/tinyswords/` -> kutu çizimi. Test için: `-- pack=none|custom|tinyswords`.
