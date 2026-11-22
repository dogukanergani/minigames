# Kod incelemesi bulguları

Kapsam: `scripts/net.gd`, `scripts/main.gd`, `shop/shop.gd`, `battle/battle.gd` (+ `minigames/reaction.gd`, `scripts/game.gd`, `scripts/items.gd` okundu).
Satır numaraları incelendiği andaki (`a59b6d6`) koda aittir. **Düzeltmeyi bu rol yapmaz**, sahibine iletilmelidir.
Durum etiketi: **[ölçüldü]** testte gözlendi · **[kod]** yalnızca kod okuyarak çıkarıldı, çalıştırılıp doğrulanmadı.

Özet: 1 yüksek, 6 orta, geri kalanı düşük. Otomatik testte (1v1, 2v2, 3v3, geç katılım, geç sahne yükleme) kilitlenme yok.

---

## YÜKSEK

### 1. Host koparsa istemci oyunda sonsuza dek donar [kod]
- `scripts/net.gd:192` `_on_server_disconnected` → `leave()` + `lost_connection`. Bu sinyali **yalnızca** `scripts/lobby.gd:22` dinliyor; oyun sırasında lobi sahnesi yok. `main.gd`, `shop.gd`, `battle.gd` dinlemiyor.
- Tetik: oyun sırasında host kapanır / ağ koparsa. `Net.players` temizlenir, `multiplayer_peer = null`, ama Main sahnesi açık kalır; faz zamanlayıcıları sunucuda olduğundan hiçbir şey ilerlemez. Ayrıca `shop.gd:149`, `battle.gd:107` `multiplayer.get_unique_id()` artık 1 döner.
- Düzeltme: `main.gd` `_ready` içinde `Net.lost_connection.connect(...)` ile lobiye dön (`change_scene_to_file("res://scenes/lobby.tscn")`). Sahibi: yönetici (`main.gd`).

---

## ORTA

### 2. "Herkes hazır" kontrolü üye değil sayı karşılaştırıyor; oyuncu ayrılırsa erken başlar ya da hiç başlamaz [kod]
- `main.gd:60`, `shop.gd:76`, `battle.gd:155`: `ready_peers.size() >= Net.players.size()` / `hello.size() >= ...`.
- (a) **Erken başlama:** A "hazırım" dedikten sonra ayrılırsa `hello={host, A}` (2) ≥ `Net.players={host, B}` (2). B henüz sahneyi yüklemediği hâlde faz başlar; B'ye giden tek seferlik güvenilir RPC (`_sync`, `_begin_*`) kaybolur. Market'te B ilk sırayı kaçırır (sonraki `_sync`'e, en kötü 15 sn'ye kadar boş ekran). Savaşta `_snapshot` sürekli gittiği için toparlar.
- (b) **Kilitlenme:** Eksik tek kişi (henüz hello atmamış) ayrılırsa, `_mark_*` bir daha çağrılmaz; kontrol yalnızca yeni hello gelince yapılıyor. Tüm kalan oyuncular "Market hazırlanıyor…" / "Savaş yükleniyor…" ekranında sonsuza kadar kalır.
- Tetik: faz geçişi sırasında (sonuç → market, market → savaş) bir istemcinin çökmesi / kapatılması.
- Düzeltme: sayı yerine üyelik: `Net.players.keys().all(func(k): return hello.has(k))`; ve `Net.players_changed` (ya da `peer_disconnected`) olunca aynı kontrolü yeniden çalıştır.
- Not: `leave` senaryosu (`run_all.ps1 -Scenario leave`) minigame sırasında ayrılmayı dener ve geçer; faz geçişi anındaki ayrılmayı tam zamanlamayla tetikleyemedim.

### 3. Snapshot paketi MTU'yu aşıyor (fragmentasyon + kayıp) [ölçüldü]
- `battle.gd:239` `_snapshot.rpc(snap)` güvenilmez, her 2. fizik karesinde (~30 Hz), `Dictionary` olarak.
- Testte uyarı: 4 oyuncu 1407 bayt, 6 oyuncu **1963 bayt** (`MTU 1392`: "higher packet loss"). Test botlarında yalnızca 2 bedava birim var; 5v5 + 4'er birim (≈60 varlık) ≈ 4-6 KB olur. ENet güvenilmez paketi parçalar, bir parça kaybolursa tüm snapshot düşer; LAN dışında takılma/atlama olur. Her paket için host'un yükü: 9 istemci × 30 Hz × birkaç KB ≈ 1 MB/sn.
- Düzeltme: `PackedByteArray` / `PackedFloat32Array` ile sıkı kodlama (konumlar 16-bit, hp bayt), değişmeyen alanları (`max_hp`, `team`, `owner`) bir kez güvenilir yolla gönder; ya da uzak/ölü varlıkları kırp. Ağ rolü + savaş rolü ortak çalışmalı.

### 4. Refleks sonucunu istemci belirliyor; sunucu hiç doğrulamıyor (hile) [kod]
- `minigames/reaction.gd:86` `_srv_result(ms)`: `ms` istemciden geldiği gibi kabul ediliyor; `_go` öncesi bile (state WAIT iken) gönderilebilir, `ms=0` her zaman 1. olur. Sunucu "GO" zamanını hiç kaydetmiyor.
- Tetik: değiştirilmiş istemci `_srv_result.rpc_id(1, 0)` çağırır → bol coin + market öncelik hakkı.
- Düzeltme: sunucu `_go.rpc()` anını `Time.get_ticks_msec()` ile saklar; gelen sonucun üst sınırı `şimdi - go_zamanı`, alt sınırı makul bir insan eşiği (≈100 ms) olmalı; `_go` öncesi gelen sonuç = erken basış. (Sahibi: Minigame rolü.)

### 5. Ayrılan oyuncunun cevabı refleks turunu erken bitiriyor [kod]
- `reaction.gd:95` `results.size() >= Net.players.size()`. A cevap verip ayrılırsa `results` A'yı hâlâ sayar, `Net.players` saymaz: kalan sonuçlardan biri eksikken bile eşik aşılır, `_finalize` erken çalışır; cevap vermemiş oyuncu "cevap yok" olarak en sona düşer.
- Düzeltme: sayı yerine `Net.players.keys().all(func(k): return results.has(k))`; `peer_disconnected`'ta yeniden kontrol (ayrılan kimse bekleniyorsa tur bitebilsin).

### 6. Takım tamamen boşalırsa / sudden death'te maç hiç bitmeyebilir [kod]
- `battle.gd:630` `_on_peer_left`: yalnızca kahraman/birim siler; bir takımın tüm oyuncuları ayrılırsa kazanan ilan edilmez. 5 dk sonra skor eşitse (`:269`) `sudden=true` ve süre sınırı kalkar; iki takım da bayrak alamazsa (tahta duvarlarla örülü üs vb.) savaş **sonsuz** sürer, `main.gd` sonraki faza hiç geçmez.
- Düzeltme: `_on_peer_left` içinde takımda canlı/bağlı oyuncu kalmadıysa `_finish(diğer takım)`; sudden death için üst süre (örn. +2 dk, sonra en çok hasar/yakınlık kazanır).

### 7. Market sırasındaki oyuncu ayrılırsa sıra 15 sn takılır [kod]
- `shop.gd:265` zamanlayıcı tek yol; `_next_turn` yalnızca sıra devredilirken `Net.players.has` bakıyor. Sırası gelen kişi ayrılırsa kalan herkes 15 sn "SIRA: ?" ekranı izler.
- Düzeltme: `peer_disconnected` ile `turn_id == id` ise `turn_timer.stop(); done[id]=true; _next_turn()`.

---

## DÜŞÜK

### 8. Aynı anda iki istek / istek seli
- `battle.gd:647` `_srv_input` ve `:659` `_srv_action` için hız sınırı yok. Silah değiştirme (`kind 1`) ve komut (`kind 2-4`) sınırsız spam edilebilir (CPU yükü, `feed` yok ama RPC işleme var). Saldırı hızı sunucuda `cd` ile sınırlı: hile yok.
- `net.gd:110` `_srv_register` aynı istemciden ikinci kez çağrılırsa kaydı sıfırlar (takım ve `ready` yeniden); lobide saldırı yüzeyi. Düzeltme: `if players.has(id): return`.
- `net.gd:81` `start_game` tekrar çağrılırsa `_begin_game` ikinci kez yayınlanır (`in_game` kontrolü yok). Düzeltme: başında `if in_game: return "..."`.
- `shop.gd:210` satış, sırası olmayan oyuncu için her zaman açık (tasarım gereği); `_srv_sell` `ended` kontrolü var ve çift istek sıralı işlendiği için çift satış olmuyor [kod].

### 9. Kayıt olmayan bağlantı slot tutar
- `net.gd:32` `create_server(PORT, MAX_PLAYERS - 1)`: bağlanıp `_srv_register` göndermeyen peer ENet slotunu tutar, kayıtlı oyuncu sayısı < 10 olsa bile gerçek oyuncular reddedilebilir. Düzeltme: kayıt için zaman aşımı (örn. 3 sn) sonra `disconnect_peer`.

### 10. Sıfıra bölme / null / imza riskleri (şu an tetiklenmiyor)
- `battle.gd:906,888,930`: `hp/max_hp`, `w[2]/w[3]`, `a[2]/a[3]`. Bugün max değerler > 0, ama yeni birim/duvar türü `hp: 0` ile eklenirse bölme. `clampf` yalnızca sonucu sınırlıyor.
- `battle.gd:531` `(tp - u.pos).normalized()`: okçu hedefin tam üstündeyse sıfır vektör → hareketsiz ok (zararsız, 0.15 sn sonra silinir).
- `battle.gd:705,714` `UNIT_ORDER.find(u.type)`: yeni birim `UNIT_TYPES`'a eklenip `UNIT_ORDER`'a eklenmezse sessizce -1 gider; istemci yanlış çizer. Düzeltme: iki yerde tanım yerine tek kaynak (`UNIT_TYPES.keys()`).
- `battle.gd:654` `mv.limit_length` iyi; `aim`/`cur` NaN/Inf gelirse `_rect_blocked` her şeyi engelli sayar ve hareket/duvar durur (çökme yok), ama o oyuncunun `aim`'i kalıcı bozulur. Düzeltme: `is_finite` kontrolü.
- `main.gd:186` / `shop.gd:152,301` ayrılan oyuncu için `"?"` adı gösteriliyor; kozmetik.
- RPC imza uyuşmazlığı: o anki kodda yok; testte başka bir oturumun (farklı battle.gd sürümlü) işlemi aynı porta bağlanınca `rpc node checksum failed` görüldü. Sürümleri farklı iki istemci bağlanabiliyor. Düzeltme: `net.gd`'de bağlantıda sürüm/checksum el sıkışması, uyuşmazsa reddet.

### 11. Faz akışı notları
- `main.gd:176` savaş sonrası `_next_round` ile tur sonsuza kadar döner (`TODO: maç yapısı`); `Game.reset()` yalnızca `_ready`'de, yani yeni maçta coin/envanter sıfırlanmaz.
- `reaction.gd:77` sunucu GO'yu `1 + 2..5` sn sonra gönderiyor; sahneyi 3 sn'den geç yükleyen istemci GO'yu kaçırır (`state != WAIT` kontrolü yok → `_go` yoksa basış "erken bastın"). Test: `race-load` (3 sn gecikme) geçti, ama marj ince.

---

## Testle doğrulanan (sorun çıkmayanlar)
- `main.gd`/`shop.gd`/`battle.gd` el sıkışmaları, sahne yüklenmeden kaybolan mesajlardan sonra tekrar deneyerek toparlıyor: `race-load` senaryosunda host `Node not found: "Main"` hatalarını logluyor (mesajlar gerçekten düşüyor) ve akış yine de bitiyor. Hata geri gelirse bu senaryo kilitlenme (150 sn zaman aşımı) ile kalır.
- 2v2, 3v3: sıralama, coin, envanter ve savaş sonucu tüm oyuncularda birebir aynı.
- Test gözlemi: port 7777 sabit olduğundan aynı anda iki test (başka oturum dahil) birbirini bozuyor; `run_all.ps1` başka bir `net_test` host'u varsa bekler. Ayrıca bir istemci başka bir test oturumunun host'una bağlanabilir. `Net.PORT`'un argümanla değiştirilebilmesi (ağ rolü) bunu çözer.
