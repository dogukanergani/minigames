# Sprite'lar (repoda YOK, kendin indir)

Oyun görselleri için **Tiny Swords (Free Pack)** kullanır: https://pixelfrog-assets.itch.io/tiny-swords (Pixel Frog).
Lisansı ticari ve kişisel kullanıma izin verir ama **dosyaların yeniden dağıtılmasını yasaklar**, bu yüzden
sprite'lar bu depoda bulunmaz (`.gitignore` ile dışarıda tutulur).

## Kurulum

1. Siteden "Tiny Swords (Free Pack).zip" dosyasını indir (ücretsiz, 3.3 MB, 0 dolar yazıp "No thanks, just take me to the downloads").
2. Zip'i aç ve şu dosyaları `assets/tinyswords/` altına, **küçük harf ve alt çizgiyle** kopyala:

```
assets/tinyswords/
  units/blue/   warrior_idle.png  warrior_run.png  warrior_attack1.png  archer_idle.png  archer_run.png
                archer_shoot.png  archer_arrow.png  lancer_idle.png  lancer_run.png  lancer_right_attack.png
                monk_*.png  pawn_idle.png  pawn_run.png      (Units/Blue Units/<Birim>/ içindeki dosyalar)
  units/red/    aynıları (Units/Red Units/<Birim>/)
  buildings/    blue_castle.png  red_castle.png  blue_tower.png  red_tower.png
  terrain/      tilemap_color1.png  shadow.png               (Terrain/Tileset/)
```

Dosya adı kuralı: orijinal adı küçük harfe çevir, boşlukları `_` yap, başında birim adı yoksa ekle
(ör. `Units/Blue Units/Monk/Idle.png` -> `units/blue/monk_idle.png`).

## Dosyalar yoksa

Oyun çalışmaya devam eder, eski **kutu çizimine** döner (`scripts/art.gd` `Art.available` ile kontrol eder).
Testler sprite gerektirmez.

## Notlar
- Sprite karesi kare şeklindedir (192x192, Mızrakçı 320x320), kare sayısı genişlik / yükseklik ile bulunur.
- Oyun penceresi 1920x1080, mantık dünyası 640x360 (3 kat ölçek), sprite'lar 1080p'de birebir piksel boyutundadır.
