# Roller ve dosya sahipliği

Bir dosyanın tek sahibi vardır. Sahibi olmayan o dosyaya **yazmaz**, değişikliği yöneticiden ister.
Önce `CLAUDE.md` ve `GDD.md` okunur.

| Rol | Sahibi olduğu dosyalar | Görev alanı |
|---|---|---|
| **Yönetici** (ana oturum) | `GDD.md`, `CLAUDE.md`, `ROLES.md`, `scripts/main.gd`, `scripts/game.gd`, `scenes/main.tscn`, `project.godot` | Görev dağıtır, GDD'yi günceller, dalları inceler ve birleştirir, entegrasyon |
| **Savaş / Yapay zekâ** | `battle/*` | Birim türleri, birim zekâsı, komutlar, savaş dengesi, arena |
| **Minigame** | `minigames/*` | Yeni minigame'ler, sıralama/ödül arayüzü (`finished(ranking, labels)` sinyali) |
| **Market / Ekonomi** | `shop/*`, `scripts/items.gd` | Eşya/birim kataloğu, fiyat, stok, coin tablosu, denge, satma |
| **Test / Kalite** | `scenes/net_test.tscn`, `scripts/net_test.gd`, `tests/*` | Otomatik bot testleri, hata avı, regresyon; kod değiştirmez, hata raporlar |
| **Ağ / Altyapı** (sonra) | `scripts/net.gd`, `scripts/lobby.gd` | Bağlantı, tahmin (prediction), hile koruması, ayrı sunucu |
| **Sanat / Arayüz** (sonra) | `assets/*` | Pixel art, yazı tipi, menüler |

## İstisna: `scripts/items.gd` ortak dosya
- **Savaş / Yapay zekâ**, yeni **birim** satırlarını (`"kind": "Birim"`) listenin **sonuna** ekleyebilir. Başka satıra dokunmaz.
- **Market / Ekonomi** birim olmayan satırları ve fiyatları yönetir. Birim satırlarının fiyatı için Savaş rolüyle yönetici üzerinden konuşur.
- Birleştirmede çakışma olursa yönetici çözer.

## Yeni minigame ekleme
- **Minigame** rolü sahnesini `minigames/` altına koyar ama `scripts/main.gd` içindeki `MINIGAMES` listesine **yönetici** ekler (raporda yolunu yaz).

## Kurallar
- **Her oturum kendi dalında çalışır:** `git switch -c <rol>/<konu>`. Yönetici inceleyip `main`'e birleştirir.
- Ortak dosyalarda (`main.gd`, `game.gd`, `project.godot`) değişiklik gerekiyorsa raporunun "yöneticiden istekler" bölümüne tam olarak ne istediğini yaz.
- Yeni bir autoload, yeni faz ya da ağ mesajı gerekiyorsa uygulamadan önce yöneticiye danış.
- GDD'deki ❓ (açık) kararları kendin verme. Öneri sun, yönetici onaylatır.
- Bitmiş saymak için: tam tur testi (bkz. `CLAUDE.md`) hatasız geçmeli. Çalıştıramadıysan açıkça yaz.

## Rapor formatı
`CLAUDE.md` sonundaki "Raporlama formatı"nı kullan.
