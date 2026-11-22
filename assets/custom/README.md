# Özgün sprite paketi (repoda, telif sorunu yok)

Bu klasördeki PNG'lerin hepsi `tools/make_sprites.py` ile **kodla üretilir** (özgün, bağımlılıksız Python).
Elle düzenleme yapma; `tools/make_sprites.py` içindeki çizimi değiştirip yeniden üret:

```
python tools/make_sprites.py
```

- `units/<mavi|kırmızı>/` kahraman (`warrior|archer|lancer` x `idle|run|attack`, 32x32 kare) ve birim (`u_*`, 24x24 kare) şeritleri
- `terrain/` çimen (3), toprak yol (2), taş engel (2), süs (5, çarpışmasız); `buildings/` kale, bayrak (4 kare); `fx/` ok, top, patlama, duvarlar, coin
- `preview_*.png` etiketli önizleme sayfaları (her çalıştırmada yenilenir)
- Ölçek: 1 sanat pikseli = 2/3 dünya birimi = 1080p'de tam 2 ekran pikseli. Meta: `scripts/art.gd` `PACKS["custom"]`.
- Paket önceliği: `assets/custom/` -> `assets/tinyswords/` -> kutu çizimi. Test için: `-- pack=none|custom|tinyswords`.
