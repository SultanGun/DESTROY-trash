extends Node
class_name Inventory

## Ransel/inventory sederhana buat nyimpen sampah sebelum disetor ke mesin.
## Slot terbatas sesuai GDD (BAB IV - SISTEM DASAR: "penyimpanan").
## Emit signal biar HUD/UI bisa reaktif tanpa nge-poll tiap frame.

signal inventory_changed(organic: int, anorganic: int, capacity: int)
signal inventory_full

@export var capacity: int = 10

var organic_count: int = 0
var anorganic_count: int = 0

func total_count() -> int:
	return organic_count + anorganic_count

func is_full() -> bool:
	return total_count() >= capacity

## trash_type: pakai Trash.TrashType.ORGANIC (0) atau ANORGANIC (1)
func add_trash(trash_type: int) -> bool:
	if is_full():
		inventory_full.emit()
		return false
	if trash_type == Trash.TrashType.ORGANIC:
		organic_count += 1
	else:
		anorganic_count += 1
	inventory_changed.emit(organic_count, anorganic_count, capacity)
	return true

## Dipanggil pas pemain nyetor sampah ke mesin pilah & olah (fitur berikutnya)
func clear() -> void:
	organic_count = 0
	anorganic_count = 0
	inventory_changed.emit(organic_count, anorganic_count, capacity)
