# Minigames: proje kuralları (her oturum önce bunu okur)

## Önce bunu yap
1. **`GDD.md` dosyasını oku.** Oyun tasarımı oradadır. GDD ile çelişen bir şey yapma.
   Karar eksikse ya da değişmesi gerekiyorsa kendin karar verme: yöneticiye (ana oturum) sor.
2. **`ROLES.md` dosyasını oku**, rolünü ve dokunabileceğin dosyaları öğren. Rolünün dışındaki dosyaya yazma.
3. Çalışmaya başlamadan önce `git status` ile temiz durumda olduğunu kontrol et.

## Oyun nedir (3 satır)
Online, takımlı (1v1 → 5v5) oyun. Minigame'lerde bireysel sıralamaya göre coin kazanılır,
markette eşya ve birim alınır/satılır, sonra takımlı bayrak savaşı oynanır. Her oyuncu bir
kahramanı doğrudan, birliğini komutla yönetir. Pixel art, Godot 4.7, GDScript.

## Proje yapısı
- `scripts/net.gd` (autoload `Net`): ağ, oda, takım, hazır durumu. Sunucu otoriter.
- `scripts/game.gd` (autoload `Game`): coin, envanter, birlik sınırı, satma.
- `scripts/items.gd`: eşya/birim kataloğu (`preload` ile kullanılır, `class_name` YOK).
- `scripts/main.gd` + `scenes/main.tscn`: faz akışı (minigame → sonuç → market → savaş), süreli geçişler.
- `scripts/lobby.gd`: lobi arayüzü (kodla kurulur).
- `minigames/`: minigame sahneleri. `shop/`: market. `battle/`: savaş. `scenes/`: giriş sahneleri.

## Çalıştırma ve test
Godot yolu (winget ile kurulu, PATH yenilenmediyse tam yolu kullan):
```
$g = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"
```
- Hızlı sözdizimi/yükleme kontrolü: `& $g --headless --path . --quit-after 5`
  (Not: `--check-only` autoload'ları tanımaz, işe yaramaz. Sahneler ilk yüklenince hata verir, bu yüzden gerçek testi çalıştır.)
- **Tam tur otomatik test** (iki işlem, bot oynar; minigame → market → savaş → "SAVAŞ BİTTİ" yazmalı):
  ```
  Start-Process $g -ArgumentList "--headless","--path",".","res://scenes/net_test.tscn","--","host","auto","fast" -RedirectStandardOutput host.txt -PassThru
  # 2 sn sonra:
  Start-Process $g -ArgumentList "--headless","--path",".","res://scenes/net_test.tscn","--","join","auto","fast" -RedirectStandardOutput join.txt -PassThru
  ```
  İki çıktıda da `SAVAŞ BİTTİ: kazanan=...` satırı ve hata çıktısı (`.err`) boş olmalı.
- **Kötü internet taklidi** (arkadaşsız ağ testi): `tests/netsim.py` istemci ile sunucu arasına gecikme/titreşim/paket kaybı koyar.
  Host normal çalışır (port 7777), bozucu 7778'de dinler, istemci `port=7778` argümanıyla bozucuya bağlanır:
  ```
  python tests/netsim.py --listen 7778 --target 7777 --latency 120 --jitter 40 --loss 8 --seconds 150
  # host:    ... -- host auto fast timeout=40
  # istemci: ... -- join auto fast timeout=40 port=7778
  ```
  Savaş sonunda istemci `[net ...] anlık görüntü=... ort aralık=... maks=...` satırı yazar (takılma göstergesi).
  5v5 ölçeği için: `host players=10` + 9 istemci (`join idx=1..9`), hepsi aynı bilgisayarda çalışır.
- El ile deneme (iki pencere): `--resolution 640x360 -- quick-host` ve `-- quick-join` argümanlarıyla iki ayrı örnek aç.
- Değişiklikten sonra mutlaka tam tur testini çalıştır. Çalışmayan şeyi "bitti" diye bildirme.

## Mimari kurallar
- **Sunucu otoriterdir.** Oyun mantığı (hasar, bayrak, coin, stok) sunucuda hesaplanır, istemci istek yollar.
  İstemci verisine güvenme: sunucu her istekte doğrular.
- Çok oyunculu durum RPC ile herkese yansır; coin/envanter her istemcide aynı olaylardan deterministik üretilir.
- Çizim koda gömülüdür (`_draw`); harici görsel eklemeden önce yöneticiye sor (Sanat rolü hariç).
- Pixel art: iç çözünürlük 640x360, nearest filtre, tamsayı ölçek. Yazı boyutları küçük tutulur.
- Yorumlar ve oyuncuya görünen metinler Türkçe, kod/değişken adları İngilizce. Girinti: tab.

## Bu projede yaşanmış tuzaklar (tekrarlama)
- **RPC için düğüm yolu tüm oyuncularda aynı olmalı.** Faz sahneleri `"Minigame"`, `"Shop"`, `"Battle"` adıyla eklenir.
  Yeni sahne eklerken eski düğümü önce `remove_child` et ki ad boşalsın (yoksa ad `@Node@2` olur, RPC kırılır).
- **Yükleme yarışı:** Bir oyuncu mesaj atarken diğerinin sahnesi yüklenmemiş olabilir ve mesaj kaybolur
  (`Node not found` hatası). Her faz girişinde "hazırım" el sıkışması, karşı taraf cevap verene kadar **tekrar denenir**.
  Yeni bir faz/sahne eklersen aynı kalıbı kullan (`main.gd`, `shop.gd`, `battle.gd`'ye bak).
- Godot'un yerleşik adlarını ezme: `request_ready`, `owner`, `name` gibi. (`Node.request_ready()` yüzünden betik yüklenmedi.)
- `var x := <Variant>` tip çıkarımı hata verir (Dictionary'den gelen değerlerde). `var x: float = ...` gibi tipi yaz.
- Kamera (Camera2D) varken varsayılan katmandaki arayüz de kayar. HUD'u `CanvasLayer`'a koy, sonuç ekranından önce kamerayı kapat.
- `--check-only` autoload'ları bilmez, güvenme.
- Bir `.gd` dosyası sahne ilk yüklendiğinde derlenir; hata geç ortaya çıkabilir. Her değişiklikten sonra tam tur testini çalıştır.

## Git kuralları
- Her oturum kendi dalında çalışır (`git switch -c rol/kisa-konu`), `main`'e doğrudan yazmaz.
- Küçük, anlamlı commit'ler. Commit mesajı Türkçe ya da İngilizce olabilir ama açık olsun.
- Rolünün dışındaki dosyaya dokunman gerekiyorsa değişikliği yapma, yöneticiye iste.
- `GDD.md`'yi sadece yönetici günceller. Bir karar/öneri ürettiysen raporuna yaz, yönetici işler.

## Raporlama formatı (bitirince)
1. Ne yaptın (dosya listesi).
2. Nasıl test ettin (komut + sonuç; çalıştıramadığını açıkça yaz).
3. Açık sorular / GDD'ye eklenmesi gerekenler.
4. Rolünün dışındaki dosyalarda gerekli değişiklikler (yönetici yapsın).
