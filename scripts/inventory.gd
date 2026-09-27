extends Node
class_name Inventory

## Ransel/inventory sederhana buat nyimpen sampah sebelum disetor ke mesin.
## Slot terbatas sesuai GDD (BAB IV - SISTEM DASAR: "penyimpanan").
## Stok dihitung PER JENIS (kind) karena tiap jenis punya harga jual beda.
## Emit signal biar HUD/UI bisa reaktif tanpa nge-poll tiap frame.

signal inventory_changed(organic: int, anorganic: int, capacity: int)
signal inventory_full

@export var capacity: int = 10

## Batas atas kapasitas (upgrade toko mentok di 20 slot).
const MAX_CAPACITY := 20

var organic_count: int = 0
var anorganic_count: int = 0
## kind -> qty (mengikuti trash.gd / GameData.ITEM_NAMES)
var stocks: Dictionary = {}

func total_count() -> int:
	return organic_count + anorganic_count

## Ubah kapasitas (upgrade toko / load save). Dijepit ke 1..MAX_CAPACITY
## supaya ga bisa melebihi batas upgrade, lalu emit signal biar UI sinkron.
func set_capacity(value: int) -> void:
	capacity = clampi(value, 1, MAX_CAPACITY)
	emit_signal_refresh()

func emit_signal_refresh() -> void:
	inventory_changed.emit(organic_count, anorganic_count, capacity)

func is_full() -> bool:
	return total_count() >= capacity

## trash_type: Trash.TrashType.ORGANIC (0) / ANORGANIC (1); kind: id jenis sampah.
func add_trash(trash_type: int, kind: String) -> bool:
	if is_full():
		inventory_full.emit()
		return false
	if trash_type == Trash.TrashType.ORGANIC:
		organic_count += 1
	else:
		anorganic_count += 1
	stocks[kind] = stocks.get(kind, 0) + 1
	inventory_changed.emit(organic_count, anorganic_count, capacity)
	return true

## Ambil satu butir sampah jenis tertentu (dipakai UI pilah satuan).
func take_one(kind: String) -> bool:
	if not stocks.has(kind) or stocks[kind] <= 0:
		return false
	stocks[kind] -= 1
	if stocks[kind] <= 0:
		stocks.erase(kind)
	if GameData.ITEM_TYPE.get(kind, Trash.TrashType.ORGANIC) == Trash.TrashType.ORGANIC:
		organic_count -= 1
	else:
		anorganic_count -= 1
	inventory_changed.emit(organic_count, anorganic_count, capacity)
	return true

## Ambil SEMUA sampah buat disetor ke mesin pilah; inventory kosong lagi.
## Return Dictionary kind -> qty buat GameData.add_sorted().
func drain() -> Dictionary:
	var out := stocks.duplicate()
	stocks.clear()
	organic_count = 0
	anorganic_count = 0
	inventory_changed.emit(organic_count, anorganic_count, capacity)
	return out

func clear() -> void:
	stocks.clear()
	organic_count = 0
	anorganic_count = 0
	inventory_changed.emit(organic_count, anorganic_count, capacity)
