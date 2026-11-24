# Minigames - Oyun Tasarım Belgesi (GDD)

> Durum: TASLAK v0.1. ✅ = karar verildi, ❓ = açık soru, 🧪 = öneri / test edilecek.
> Bu belge canlıdır: karar verildikçe güncellenir.

## 1. Özet

Online, takımlı bir oyun. Oyuncular önce **minigame'lerde tek tek yarışır**, sıralamalarına göre **coin** kazanır.
Coin'lerle **markette** silah, kalkan ve duvar alır, sonra **takımlar halinde bayrak savaşında** çarpışır.

**Fantezi:** "Minigame'de yetenekli ol, savaşta güçlü ol, takımınla kazan."

## 2. Tasarım sütunları

1. **İki aşama birbirini besler.** Minigame başarısı savaş gücüne dönüşür. Aşamalar birbirinden kopuk hissettirmemeli.
2. **Kısa ve anlaşılır.** Her minigame kuralı 5 saniyede anlaşılır. Tur tempolu ilerler.
3. **Adil ve telafili.** Geride kalan oyuncu oyundan kopmamalı. 🧪

## 3. Oyun döngüsü ✅

```
Lobi → [Minigame → Sonuç/coin → Market → Savaş] → ... tekrar
```

| Faz | Ne olur | Durum |
|---|---|---|
| Lobi | Oda kur/katıl, takım seç, host başlatır | ✅ yapıldı |
| Minigame | Herkes bireysel yarışır, sunucu sıralar | ✅ 1 minigame (refleks) |
| Sonuç | Sıralamaya göre coin dağıtılır | ✅ yapıldı |
| Market | Sıralamaya göre sırayla alışveriş (1. önce seçer) | ✅ yapıldı (ilk sürüm) |
| Savaş | Takımlı bayrak savaşı | ✅ prototip (kodla çizim, kutu grafikler) |

✅ **Akış otomatiktir, hiçbir oyuncu yönetmez.** Lobide herkes "Hazır" der (host hariç, host başlatır). Sonrasında sonuç ekranı (6 sn) ve market özeti (5 sn) süreli, sunucu geçişleri kendiliğinden yapar. Host'un "devam et" butonu yoktur.

✅ **Maç yapısı (🧪 sayılar oynayarak ayarlanır):** Maç, "minigame → market → savaş" turlarından oluşur. **İlk 2 savaşı kazanan takım maçı kazanır** (en fazla 3 tur, `ROUNDS_TO_WIN`). Eşyalar kalıcı olduğu için kısa maç seçildi (uzun maçta öndeki hep öne geçer). Maç boyunca coin, envanter ve birimler turlar arasında kalır. Maç sonu ekranı 12 sn gösterilir, sonra herkes aynı odanın lobisine döner (hazır durumları sıfırlanır, host yeni maç başlatabilir). Yeni maçta coin ve envanter sıfırlanır.
- Her sonuç ekranında "Maç: Mavi 1 - 0 Kırmızı" skoru görünür.
- ❓ Maç sonunda oyuncu istatistikleri (en çok öldüren, en çok coin vb.) gösterilsin mi?

## 4. Oyuncular ve ağ ✅

- **Online**, 1v1'den **5v5'e** kadar (en fazla 10 oyuncu).
- **Takım tabanlı:** 1v1 sadece "1 kişilik iki takım". Ayrı mod gerekmez.
- Takımlar: Mavi, Kırmızı. Gelen oyuncu küçük takıma yerleşir, takım değiştirilebilir (takım başına en fazla 5).
- **Sunucu otoriter:** oyun mantığı sunucuda, istemciler girdi gönderir.
- Şimdilik host bir oyuncu (ENet, port 7777). 🧪 İleride ayrı sunucu / relay.

## 5. Minigame'ler

**Ortak kurallar:** Bireysel yarış. Çıktı = sıralama. Süre kısa (~15-30 sn).
Her minigame şu arayüzü sağlar: sahne + `finished(ranking, labels)` sinyali.

| Minigame | Fikir | Durum |
|---|---|---|
| Refleks | Yeşil olunca ilk basan kazanır | ✅ |
| Koşu / engel | Üst görünüm pist, ilk bitiren kazanır | 🧪 |
| Coin toplama | Arenada en çok toplayan kazanır | 🧪 |
| Hafıza / dizi | Gösterilen diziyi tekrar et | 🧪 |
| Hedef atış | Hareketli hedefleri vur | 🧪 |

❓ Her turda rastgele mi seçilir, yoksa oyuncular oylar mı?
❓ Takım skoru da hesaba katılacak mı, yoksa tamamen bireysel mi? (şu an tamamen bireysel)

## 6. Ekonomi ✅ (sayılar taslak)

- Coin sıralamaya göre verilir ✅ (x1.5 yapıldı): 1.→150, 2.→120, 3.→90, 4.→60, 5.→45, 6.→30, 7-8.→15, 9-10.→8
- ✅ **Savaş bonusu:** savaş bitince kazanan takımın herkesi +80, kaybeden +40 coin alır (`Game.BATTLE_WIN_BONUS/LOSE_BONUS`). 🧪 Henüz yok: öldürme/bayrak/kule yıkma bonusu, sonuç ekranında kazanç dökümü, fiyatların yeni coine göre dengelenmesi.
- ✅ **Minigame sonu:** son oyuncu bitirince 2.2 sn "HERKES BİTİRDİ!" anı gösterilir, sonra sonuç ekranı gelir.
- Coin **bireyseldir**, herkes kendi alışverişini yapar.
- ✅ **Alınan eşyalar kalıcıdır:** bir kez alınan eşya maç boyunca oyuncuda kalır (ölünce de kaybolmaz).
- ❓ Harcanmayan coin sonraki tura devreder mi? 🧪 Evet, devretsin (biriktirip pahalı eşya almak mümkün olsun).
- ⚠️ **Risk:** Kalıcı eşya + sıralama avantajı = kartopu etkisi (öndeki hep öne geçer). Bu yüzden telafi mekaniği önemli.
- 🧪 **Telafi:** Geride kalanlara küçük bir bonus (örn. son sıraya ekstra coin) ya da markette ucuz eşya.

## 7. Market

- Sıra: minigame sıralaması (1. önce seçer). Böylece iyi oynayanın avantajı sadece coin değil, seçim önceliği de olur ✅
- Her oyuncunun seçim süresi sınırlı. 🧪
- **Eşya kategorileri (taslak):**

| Kategori | Örnek | Not |
|---|---|---|
| Silah | Kılıç, yay, mızrak | Menzil / hasar dengesi |
| Kalkan | Tahta, demir | Hasar azaltır |
| Duvar | Tahta, taş duvar | Yerleştirilebilir, bayrağı korur |
| Ekstra | Hız, can, tuzak | 🧪 "ekstra özellikler" |
| **Yetenek** | Atılma, Kalkan Patlaması, Savaş Narası | ✅ tuşla kullanılır, en fazla 2 (bkz. bölüm 8c) |

- ✅ **Stok sınırlıdır:** bir eşyayı alan oyuncu onu diğerlerinden alır. Bu yüzden minigame sıralaması (ilk seçme hakkı) gerçekten değerli olur.
- ✅ **Uygulanan akış:** Sıra minigame sıralamasına göre döner. Sırası gelen **1 eşya alır ya da pas geçer** (15 sn süre). Pas geçen / süresi dolan / parası yetmeyen oyuncu o marketten çıkar. Herkes bitince market kapanır.
- ✅ **Stok:** Katalogda 10 oyunculu maç için yazılı, oyuncu sayısına göre orantılı azalır (en az 1). Her market ziyaretinde stok yenilenir 🧪 (alınan eşya oyuncuda kalır).
- Katalog: `scripts/items.gd` (Kılıç, Mızrak, Yay, Tahta/Demir Kalkan, Tahta/Taş Duvar, Hız Botu, Ekstra Can). Fiyatlar taslak.
- ✅ Eşyaların savaştaki etkisi prototipte var (bkz. bölüm 8).

**Satma mekaniği (LoL tarzı)** ✅ eşyalar için uygulandı, birimler birim sistemiyle gelecek
- Oyuncu envanterindeki **eşyaları ve birimleri geri satabilir**. ✅ Satış iadesi **%70** (`Game.SELL_RATE`).
- Satılan eşya/birim **stoğa geri döner**: sonra sırası gelen biri onu alabilir. Böylece stok sınırı ve satma birbirini etkiler.
- Satma yalnızca **market fazında** yapılır, savaş sırasında yapılamaz. 🧪
- Satma **sıra hakkını harcamaz** (alışverişten önce/sonra istediğin kadar sat). 🧪 Aksi hâlde market çok yavaşlar.
- Birim satılırsa birlik sınırında yer açılır (yeni birim alınabilir).
- Hile kapısı: bir eşyayı satıp aynı tur geri alarak %30 kaybetmek istemezsin, bu doğal bir frendir. Aynı turda başkasının satıp bıraktığı eşyayı kapmak mümkün, bu bir strateji.
- ❓ Savaşta ölen birim "satılabilir" değil, kayıp. Ölen birim için kısmi iade olsun mu? 🧪 Hayır, ölüm gerçek kayıp olsun.
- ❓ Duvarlar savaştan önce mi yerleştirilir, yoksa savaş sırasında mı?
- ❓ Sırası gelene kadar beklerken diğerlerinin seçimlerini görebilir mi? 🧪 Evet, herkes canlı görsün.

## 8. Savaş: bayrak savaşı

- **Gerçek zamanlı, üst görünüm (top-down), pixel art** ✅. Oyuncular karakterlerini doğrudan yönetir ✅.
- **Hedef:** Rakibin bayrağını alıp kendi üssüne getirmek ✅.
- Tek küçük arena, iki takım üssü. 🧪
- ✅ **Kontroller: klavye + fare.** WASD hareket, fareyle nişan/yön, sol tık saldırı. 🧪 Kalkan/ekstra için ek tuşlar.
- 🧪 **Kazanma koşulu:** İlk **3 bayrak** alan takım kazanır. 5 dakika dolarsa en çok bayrağı olan kazanır. Eşitlikte altın bayrak: ilk alan kazanır.
- 🧪 **Ölünce:** 5 sn sonra kendi üssünde yeniden doğar. Taşıdığı bayrak düştüğü yerde kalır, 10 sn sonra kendi üssüne döner (ya da biri alırsa taşınır). **Eşyalar kaybolmaz** (kalıcı kuralı gereği).
- 🧪 Bayrağı taşıyan biraz yavaşlar (bayrağı kapıp kaçmak kolay olmasın).
- ❓ Ölüm ve yeniden doğma değerleri oynayarak ayarlanacak.

### Savaş prototipi: şu an ne var (`battle/battle.gd`)
- **Kontroller:** WASD hareket, fare nişan, sol tık saldırı, **Q** silah değiştir, **E / sağ tık** duvar koy, **1 / 2 / 3** birlik komutu (Takip / Saldır imlece / Bayrak).
- **Arena:** 1280x720 (ekran 640x360, **kamera kahramanı takip eder**, sağ altta mini harita). Mavi sol / Kırmızı sağ, simetrik engeller, orta şerit açık. Başta 3 sn geri sayım.
- **Eşya etkileri (taslak sayılar):**

| Eşya | Savaştaki etki |
|---|---|
| Yumruk (varsayılan) | 10 hasar, 18 menzil, 0.5 sn |
| Kılıç | 20 hasar, 24 menzil, 0.45 sn |
| Mızrak | 16 hasar, 36 menzil, 0.6 sn |
| Yay | 12 hasar, ok fırlatır (220 hız), 0.7 sn |
| Tahta / Demir Kalkan | %15 / %30 hasar azaltma |
| Hız Botu | %20 hız |
| Ekstra Can | +40 can (toplam 140) |
| Tahta / Taş Duvar | Her biri 1 duvar koyma hakkı (40 / 100 can). Düşman duvarına vurulabilir |

- **Bayrak kuralları:** Düşman bayrağını alıp **kendi bayrağın evdeyse** üssüne getirince sayı. Yerdeki kendi bayrağına dokunan geri gönderir. Yerdeki bayrak 10 sn sonra kendiliğinden eve döner. Taşıyan %15 yavaşlar.
- **Kazanma:** İlk 3 bayrak ya da 5 dk. Süre dolunca beraberlikte altın bayrak. Dost ateşi yok.
- **Ağ:** Sunucu simülasyonu çalıştırır, istemciler girdi yollar, ~30 Hz anlık görüntü alır. ✅ Anlık görüntü tek `PackedInt32Array` olarak sıkıştırılmıştır (5v5'te ~300 bayt, MTU 1392 altında). ✅ **Kendi kahramanın için istemci tarafı tahmin (prediction)** var: girdi hemen uygulanır, sunucu cevabı gelince onaylanmamış girdiler yeniden oynatılarak düzeltilir (ping ~240 ms'de ort. sapma ~6 px). Diğer oyuncular ve birimler sunucudan gelen görüntüyle çizilir.
- **Test:** `net_test` + `fast` argümanı ile otomatik bot testi (öldürme, bayrak, kazanma).

## 8c. Kahraman kimliği: yetenekler marketten ✅

**Karar:** Kahraman **sınıfı yoktur**. Herkes aynı kahramanla başlar, kimlik **marketten alınan eşyalar, birimler ve yeteneklerden** gelir. Böylece "güç marketten gelsin" sütunu korunur, denge tek yerde kalır, yanlış alım satılarak düzeltilir.

**Yetenekler** (markette "Yetenek" kategorisi, kahraman en fazla **2** taşır, `Game.ABILITY_CAP`):

| Yetenek | Tuş | Etki | Bekleme | Fiyat |
|---|---|---|---|---|
| **Atılma** | Boşluk / F | Bakılan yöne anında 70 piksel ilerler (engelde durur) | 6 sn | 60 |
| **Kalkan Patlaması** | Boşluk / F | Etraftaki düşmanlara 15 hasar + geri itme (yarıçap 40), 2 sn %50 hasar azaltma | 10 sn | 80 |
| **Savaş Narası** | Boşluk / F | 5 sn boyunca birliğin %40 hızlı ve %50 güçlü olur | 20 sn | 70 |

- 1. yetenek **Boşluk**, 2. yetenek **F**. Ekranın altında bekleme süresi görünür ("[Boşluk] Atılma HAZIR").
- Kahraman ölüyken yetenek kullanılamaz. Yetenekler satılabilir (%70 iade), sınır dolunca yenisi için birini satmak gerekir.
- 🧪 Sayılar taslak, oynayarak ayarlanır. Atılma şu an sunucuda işlenir (ping yüksekse kısa bir gecikme hissedilir, tahmin dışı).
- ❓ Sonraki yetenek fikirleri: tuzak koyma, bayrağı geri çağırma, görünmezlik, birlik çağırma, iyileşme.

## 8d. Savunma kuleleri ✅ (ilk sürüm, 🧪 sayılar taslak)

- **Markette "Kule" kategorisi:** Okçu Kulesi (90 coin, stok 4, can 160, menzil 120, hasar 9, bekleme 0.8 sn, ok atar) ve Taş Kule (70 coin, stok 3, can 320, menzil 90, hasar 6, bekleme 1.0 sn). Kahraman başına **en fazla 2 kule** (`Game.TOWER_CAP`). Kule kalıcı envanter eşyasıdır, satılabilir (%70 iade).
- **Yerleştirme aşaması:** Her savaşın başında, geri sayımdan önce **15 sn** (`PLACEMENT_TIME`). Kahramanlar hareket eder ama saldıramaz ve hasar almaz. **T** kule seçer, **sol tık** koyar, **sağ tık** geri alır (aşama bitene kadar taşınabilir), **Enter** hazır der. İmleci takip eden hayalet geçerli yerde yeşil, geçersizde kırmızı. Süre bitince ya da herkes hazırsa yerleştirilmeyenler otomatik yerleşir. Kimsenin kulesi yoksa aşama hiç başlamaz.
- **Yerleştirme kuralları (sunucu doğrular):** Yalnızca kendi tarafının ilk %40'ı, üs bölgesi (`BASE_W`) hariç, bayrağa en az 40 birim, kuleler arası en az 40 birim, engel/duvar/kahraman/birimle çakışmaz. **Orta şerit (y = 360 ± 28) kuleye kapalı** (kule bayrak yolunu tıkamasın).
- **Savaşta:** Kule en yakın düşman kahraman ya da birime ok atar. Çarpışma kutusu engeldir (kahraman ve birimler içinden geçemez). Düşman kahraman, birim, ok ve top kuleye hasar verir, birimler yakındaki düşman kuleye saldırır. **Yıkılan kule sonraki savaşta tam canla yeniden gelir** (kalıcı kayıp yok).
- ❓ Açık: yerleştirme düşmana görünüyor, gizlensin mi? Kule hasar ve menzil sayıları denge testinden geçmedi (5v5'te 20 kule olan bot maçı Mavi için zor geçti). Kule sprite ve market ikonları henüz yok (şimdilik kutu çizimi): bkz. aşağıdaki spesifikasyon.
- **Sprite spesifikasyonu (çizim oturumu için):** `assets/custom/buildings/tower_archer_{blue,red}.png` ve `tower_stone_{blue,red}.png`, 24x32; durumlar: bekleme 1 kare, hasarlı 1 kare (can %50 altı), ok atma 3 kare, yıkılma 4 kare. Market ikonları 16x16: `assets/custom/ui/icon_tower_archer.png`, `icon_tower_stone.png`. Kod şu an tek kare okuyor, animasyon için `Art`'ta kare kesme eklenecek.

## 8b. Kahraman + Birlik sistemi (yeni yön, 🧪 taslak)

> Bu yön, savaş prototipinden sonra ortaya çıktı: oyuncular tek karakter yerine **kendi kahramanını** doğrudan yönetir, yanında marketten aldığı **birliği** komutla yönetir.
>
> **Durum: ilk sürüm uygulandı ✅** Birim türleri: **Kılıççı** (40 coin) ve **Okçu** (50 coin). Birlik sınırı 4, herkes **2 bedava Kılıççı** ile başlar. Birimler marketten alınır/satılır. **Savaşta ölen birim bir süre sonra sahibinin üssünde yeniden doğar (kalıcı kayıp yok, bkz. aşağı).** Komutlar (Takip / Saldır / Bayrak) çalışır, birim zekâsı sunucuda. Türler: Kılıççı, Okçu, Kalkancı, Topçu, **Şifacı** ✅ (60 coin, stok 3, 32 can, menzil 70, saniyede 6 can iyileştirir, en yaralı dosta öncelik, düşmandan kaçar, saldırmaz; 🧪 denge: 2 Şifacı = 12 can/sn). Koşucu ve Mühendis henüz yok.

**Temel fikir**
- Her oyuncunun bir **kahramanı** (büyük, belirgin) ve en fazla **4 birimlik birliği** (küçük) var. 5v5'te takım başına 5 kahraman + 20 birim = 25, toplam 50 birim.
- **Birimler marketten alınır** (coin ile). ✅ **Ölen birim yeniden doğar:** savaş sırasında ölünce, türüne göre bir süre sonra sahibinin üssünde **tam canla** geri gelir (`UNIT_RESPAWN`: Kılıççı 12 sn, Okçu 14, Kalkancı 20, Topçu 28, Şifacı 16; 🧪 ayarlanır). Birim envanterden **silinmez** (eski "kalıcı kayıp" kuralı kalktı). Bunun sonucu: birim almak "bir kere öde, hep yenilen" hâline geldi, markette birim değeri biraz düştü; birlik sınırı (4) ve fiyatla dengelenir. HUD'da birlik sayısının altında "(N doğuyor)" yazar.
- Kahramanı oyuncu doğrudan yönetir (WASD + fare). Birlik **komutla** yönetilir, tek tek kontrol yok.

**Komutlar (taslak):** 1 = Takip (varsayılan, formasyonla izle, yakındakine saldır) · 2 = Saldır (imleci takip et, gördüğüne dal) · 3 = Bayrak (düşman bayrağına git / taşıyanı koru)

**Birim çeşitleri (taslak, sayılar ve fiyatlar oynayarak ayarlanacak)**

| Birim | Rol | Özellik |
|---|---|---|
| Kılıççı | Yakın dövüş | Ucuz, dengeli. Temel birim |
| Okçu | Menzilli | Uzaktan hasar, düşük can |
| Topçu | Kuşatma | Yavaş, çok uzun menzil, alan hasarı, **duvarlara ekstra hasar** |
| Kalkancı | Tank | Çok can, düşmanı üstüne çeker, hasar azaltır |
| Şifacı | Destek | Yakındaki dostları iyileştirir, saldırmaz |
| Koşucu | Hızlı | Çok hızlı, zayıf. **Bayrak taşıyabilir** (diğer birimler taşıyamaz) 🧪 |
| Mühendis | Destek | Savaşta duvar kurar/tamir eder 🧪 |

**Sınırlar ve kurallar**
- ✅ **Birlik üst sınırı vardır:** oyuncu başına en fazla 4 birim (🧪 sayı oynayarak ayarlanır). Sınıra ulaşınca yeni birim almak için birini satman gerekir.
- Birimlerin stoğu sınırlı mı, yoksa fiyatla mı dengelenir? ❓
- Birimler kahramanın silah/kalkan eşyalarından etkilenir mi? 🧪 İlk sürümde **hayır**, kahraman eşyaları sadece kahramana etki eder, birimler kendi sabit gücünde.
- Kahraman ölünce birimler ne yapar? ❓ 🧪 Kahraman yeniden doğana kadar son komutu sürdürür.

**Teknik not:** Birim zekâsı (hedef seçme, engel aşma, formasyon) sunucuda çalışır. 50 birim anlık görüntüyle taşınabilir. Harita büyütülmeli ve kamera kahramanı takip etmeli (640x360'a 50 birim sığmaz). Bu iş savaş fazının büyük bir yeniden yazımıdır.

**Açık sorular**
1. ✅ (varsayılan olarak uygulandı, değişebilir) Savaşa **2 bedava Kılıççı** ile başlanır. Bedava birimler de satılabilir/ölebilir.
2. Birim fiyatları ve coin ekonomisi: 100 coin ile 1 birim mi alınır? (şu anki coin tablosu yeniden ayarlanmalı)
3. Kartopu riski: öndeki hem daha çok coin hem daha çok birim alırsa dengesizlik artar. Telafi şart.

## 9. Görsel ve ses ✅

- **Pixel art**, mantık dünyası **640x360** birim, pencere **1920x1080** (`canvas_items` ölçekleme, nearest filtre). Sprite'lar 1080p'de birebir piksel boyutunda görünür.
- ✅ **Sprite paketi sırası:** `assets/custom/` (**özgün, repoda**) → `assets/tinyswords/` (Pixel Frog, repoda YOK) → kutu çizimi. Test için `-- pack=none|custom|tinyswords` argümanı.
- ✅ **Özgün paket (`assets/custom/`, `tools/make_sprites.py` kodla üretir):** Sert/agresif tarz: çatık kaşlı yüzler, boynuzlu ve kanatlı miğferler, omuz zırhı, koyu doygun palet. Kahramanlar 32x32 (Savaşçı, Okçu, Mızrakçı: bekleme 2, koşu 4, saldırı 3 kare), birimler 24x24 (Kılıççı, Okçu, Kalkancı, Topçu, Şifacı: bekleme 2, koşu 4 kare), Mavi/Kırmızı varyantlı. Zemin: çimen, toprak yol, taş engel, çarpışmasız süsler (mantar, çiçek). Takım renkli kale ve dalgalanan bayrak, ok, top mermisi, patlama, tahta/taş duvar, coin. Sprite ölçeği 2/3 birim/piksel (1080p'de tam 2 ekran pikseli). Önizleme sayfaları: `assets/custom/preview_*.png`.
- Kahramanın görünümü silahına göre değişir: **yay = Okçu, mızrak = Mızrakçı, diğerleri = Savaşçı**. Kahramanlar birimlerden belirgin büyük.
- ⚠️ Tiny Swords yedek paketinin lisansı kullanımı serbest bırakır ama **yeniden dağıtımı yasaklar**: dosyaları `assets/tinyswords/` altında, `.gitignore`'da tutulur (`assets/README.md`). Oyunun derlenmiş sürümünü paylaşmadan önce o paketin şartları tekrar okunmalı. Özgün paket için böyle bir kısıt yok.
- ✅ **Kahraman vurgusu:** Her kahramanın ayağında takım renkli halka (kendi halkan altın çizgili, kalın ve nabız atar), başının üstünde taç (kendi kahramanın altın taç, diğerleri takım renginde üçgen). Birimlerde işaret yoktur. Oklar uçuş yönüne döner (mermi paketinde 8 bit açı).
- ✅ **Arayüz teması** (`scripts/ui_theme.gd`, `tools/make_ui.py`, `assets/custom/ui/`): Lobi, market (ikon, fiyat, stok, sıra listesi, envanter), sonuç ekranları (madalyalı sıralama, maç skoru), maç sonu, savaş HUD'u (skor bandı, can, silah/yetenek/duvar/birlik kutuları, komut düğmeleri, mini harita, kill feed). Önizlemeler: `assets/custom/ui/preview_*.png`. UI görselleri yoksa tema düz stile düşer.
- ✅ **Kale savunması:** her kalenin arkasında 2 otomatik kule (`tower_base`, sahipsiz, yıkılamaz; menzil 140, hasar 5, bekleme 1 sn). Önce bayrak taşıyan düşman kahramanı, yoksa en yakın düşmanı vurur. 🧪 Sayılar taslak; sprite sonra (`buildings/tower_base_<takım>.png`).
- 🧪 Açık: minigame ekranlarının (Refleks, Koşu, Coin) görsel tasarımı, yetenek efektleri, ses, isteğe bağlı bitmap pixel yazı tipi (Türkçe karakterli).
- Ton: ❓ (şu an çizgi film / şirin yönünde)
- Ses: ❓ henüz yok.

## 10. Teknik

- **Motor:** Godot 4.7.2 ✅ (GDScript). Proje klasörü: `minigames/`
- **Ağ:** Godot yerleşik multiplayer (ENet), sunucu otoriter ✅
- Klasörler: `scenes/`, `scripts/`, `minigames/`, `shop/`, `battle/`, `net/`, `assets/`
- Autoload'lar: `Net` (ağ, lobi, takımlar), `Game` (coin, tur)
- Test: iki başsız (headless) Godot işlemiyle ağ testi (`scenes/net_test.tscn`)
- **Ağ testi:** `tests/netsim.py` ile aynı bilgisayarda yapay gecikme/kayıp. Ping ~120-500 ms ve %3-15 kayıpta tam tur bitiyor. Gerçek internet (farklı ağlar) henüz denenmedi.
- ✅ **Oyuncu ayrılması:** İstemci ayrılırsa kalan oyuncular devam eder; bir takım tamamen boşalırsa maç biter ve herkes aynı odanın lobisine döner. Host kapanırsa istemciler lobiye döner (sebep gösterilir). Refleks sonucu sunucuda sınırlanır, altın bayrak 120 sn ile sınırlı.
- Bilinen teknik borç: istemci hile koruması sınırlı (istek hızı sınırı yok, "0 ms" yollayan bot ayırt edilemez), bağlantıda sürüm/checksum denetimi yok, bağlantı kurma çok kötü ağda (%15 kayıp) arada başarısız olabiliyor, ayrı sunucu modu yok, internetten oynamak için port yönlendirme/relay gerekli. Ayrıntı: `tests/BULGULAR.md`.
- Test: `tests/leave_sweep.ps1` tam maçı da (2 tur + lobiye dönüş) çalıştırır. El ile lobiye dönüşü görmek için testlere `keeplobby` argümanı verilir.

## 11. Yol haritası

1. ✅ Proje iskeleti, pixel art ayarları
2. ✅ Lobi + ağ (takım, oda)
3. ✅ Tur döngüsü: refleks minigame + sıralama + coin
4. ✅ **Market:** sıralamaya göre sırayla alışveriş, eşya listesi, sınırlı stok, kalıcı envanter
5. ✅ **Savaş prototipi:** arena, hareket, bayrak, saldırı (ağda senkron)
6. ✅ Market eşyalarını savaşa bağla (silah/kalkan/duvar): ilk sürüm, denge ayarı yapılacak
7. ⬜ Hareketli minigame'ler (koşu, toplama)
8. ⬜ Maç yapısı (kaç tur, kazanma), menüler, cila
9. ⬜ İnternet üzerinden oynanış (relay/sunucu), hile koruması

## 12. Açık sorular özeti (öncelik sırasıyla)

Kararlar: stok sınırlı ✅, eşyalar kalıcı ✅, klavye+fare ✅, kazanma/ölüm 🧪 (öneri, oynayarak ayarlanacak).

1. Duvarlar ne zaman yerleştirilir (savaştan önce / sırasında)?
2. Maç kaç döngü sürüyor? (kalıcı eşya olduğu için çok uzun sürerse dengesizleşir)
3. Telafi mekaniği (kalıcı eşya kartopu riskini artırıyor)
4. Harcanmayan coin devreder mi?
5. Ton ve sanat yönü
