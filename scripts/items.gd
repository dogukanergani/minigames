extends RefCounted
## Eşya kataloğu. Kullanım: const Items = preload("res://scripts/items.gd")
## stock = 10 oyunculu maç için stok; az oyuncuda orantılı azalır (en az 1).

const ITEMS := [
	{"id": "sword", "name": "Kılıç", "kind": "Silah", "cost": 60, "stock": 4},
	{"id": "spear", "name": "Mızrak", "kind": "Silah", "cost": 70, "stock": 3},
	{"id": "bow", "name": "Yay", "kind": "Silah", "cost": 80, "stock": 3},
	{"id": "shield_wood", "name": "Tahta Kalkan", "kind": "Kalkan", "cost": 40, "stock": 5},
	{"id": "shield_iron", "name": "Demir Kalkan", "kind": "Kalkan", "cost": 90, "stock": 2},
	{"id": "wall_wood", "name": "Tahta Duvar", "kind": "Duvar", "cost": 30, "stock": 6},
	{"id": "wall_stone", "name": "Taş Duvar", "kind": "Duvar", "cost": 70, "stock": 3},
	{"id": "boots", "name": "Hız Botu", "kind": "Ekstra", "cost": 50, "stock": 3},
	{"id": "heart", "name": "Ekstra Can", "kind": "Ekstra", "cost": 50, "stock": 3},
	# Birimler: kahramanın birliğine katılır. Savaşta ölünce kalıcı gider.
	{"id": "unit_swordsman", "name": "Kılıççı", "kind": "Birim", "cost": 40, "stock": 8},
	{"id": "unit_archer", "name": "Okçu", "kind": "Birim", "cost": 50, "stock": 6},
]


static func get_item(id: String) -> Dictionary:
	for it in ITEMS:
		if it.id == id:
			return it
	return {}


static func stock_for(item: Dictionary, player_count: int) -> int:
	return maxi(1, roundi(item.stock * player_count / 10.0))


static func display_name(id: String) -> String:
	return get_item(id).get("name", id)
