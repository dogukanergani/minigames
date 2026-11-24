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
	{"id": "unit_artillery", "name": "Topçu", "kind": "Birim", "cost": 80, "stock": 2},
	{"id": "unit_shieldbearer", "name": "Kalkancı", "kind": "Birim", "cost": 60, "stock": 3},
	{"id": "unit_healer", "name": "Şifacı", "kind": "Birim", "cost": 60, "stock": 3},
	# Yetenekler: savaşta tuşla kullanılır (Boşluk = 1. yetenek, F = 2. yetenek). En fazla 2 tane taşınır.
	{"id": "ability_dash", "name": "Atılma", "kind": "Yetenek", "cost": 60, "stock": 4},
	{"id": "ability_burst", "name": "Kalkan Patlaması", "kind": "Yetenek", "cost": 80, "stock": 3},
	{"id": "ability_rally", "name": "Savaş Narası", "kind": "Yetenek", "cost": 70, "stock": 3},
	# Savunma kuleleri: her savaşın başında yerleştirme aşamasında kurulur. En fazla 2 tane (Game.TOWER_CAP).
	{"id": "tower_archer", "name": "Okçu Kulesi", "kind": "Kule", "cost": 90, "stock": 4},
	{"id": "tower_stone", "name": "Taş Kule", "kind": "Kule", "cost": 70, "stock": 3},
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
