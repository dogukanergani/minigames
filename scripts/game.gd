extends Node
## Oyun durumu (autoload: Game): coinler, envanter, tur sayısı.
## Her istemci aynı olaylardan (sıralama, satın alma RPC'leri) aynı durumu üretir.

signal coins_changed

const Items = preload("res://scripts/items.gd")

## Sıralamaya göre coin (1., 2., 3., ...). Son değer geri kalanlara uygulanır.
const COIN_TABLE := [100, 80, 60, 40, 30, 20, 10, 10, 5, 5]

## Satış iadesi: alış fiyatının oranı (LoL gibi %70).
const SELL_RATE := 0.7

## Birlik: oyuncu başına en fazla bu kadar birim. Herkes bedava Kılıççı ile başlar.
const UNIT_CAP := 4
const STARTING_UNITS := ["unit_swordsman", "unit_swordsman"]

var coins: Dictionary = {}  # peer_id -> int
var inventory: Dictionary = {}  # peer_id -> Array[String] (eşya id'leri, kalıcı)
var last_ranking: Array = []  # son minigame sıralaması (market sırası)
var round_no := 0


func reset() -> void:
	round_no = 0
	coins.clear()
	inventory.clear()
	last_ranking.clear()
	for id in Net.players.keys():
		coins[id] = 0
		inventory[id] = STARTING_UNITS.duplicate()
	coins_changed.emit()


func unit_count(id: int) -> int:
	var n := 0
	for item_id in inventory.get(id, []):
		if Items.get_item(item_id).get("kind", "") == "Birim":
			n += 1
	return n


## Parası yetiyor mu ve (birimse) birlik sınırı doluyor mu?
func can_buy(id: int, item: Dictionary) -> bool:
	if coins.get(id, 0) < item.cost:
		return false
	return item.kind != "Birim" or unit_count(id) < UNIT_CAP


## Savaşta ölen birimleri envanterden kalıcı olarak siler.
func remove_units(id: int, item_ids: Array) -> void:
	for item_id in item_ids:
		inventory.get(id, []).erase(item_id)


func coins_for_rank(rank_index: int) -> int:
	return COIN_TABLE[mini(rank_index, COIN_TABLE.size() - 1)]


## ranking: peer id'ler, en iyiden en kötüye.
func award(ranking: Array) -> void:
	last_ranking = ranking.duplicate()
	for i in ranking.size():
		var id: int = ranking[i]
		coins[id] = coins.get(id, 0) + coins_for_rank(i)
	coins_changed.emit()


func buy(id: int, item_id: String) -> void:
	var item := Items.get_item(item_id)
	if item.is_empty():
		return
	coins[id] = coins.get(id, 0) - item.cost
	if not inventory.has(id):
		inventory[id] = []
	inventory[id].append(item_id)
	coins_changed.emit()


func sell_price(item: Dictionary) -> int:
	return roundi(item.cost * SELL_RATE)


## Eşyayı envanterden çıkarıp iade coin'ini verir. Başarılıysa true.
func sell(id: int, item_id: String) -> bool:
	var item := Items.get_item(item_id)
	if item.is_empty() or not inventory.get(id, []).has(item_id):
		return false
	inventory[id].erase(item_id)  # ilk eşleşeni siler
	coins[id] = coins.get(id, 0) + sell_price(item)
	coins_changed.emit()
	return true


func inventory_text(id: int) -> String:
	var names: Array = []
	for item_id in inventory.get(id, []):
		names.append(Items.display_name(item_id))
	return ", ".join(names) if not names.is_empty() else "-"
