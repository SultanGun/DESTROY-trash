extends Node

## State terpusat buat mekanik setor-pilah-recycle antar mesin.
## Mesin Pilah (E) mindahin sampah dari inventory player ke sorted di sini,
## Mesin Recycle (F) ngolah sorted jadi poin daur ulang.

signal stats_changed

var sorted_organic: int = 0
var sorted_anorganic: int = 0
var recycled_total: int = 0
var recycle_points: int = 0

func add_sorted(organic: int, anorganic: int) -> void:
	sorted_organic += organic
	sorted_anorganic += anorganic
	stats_changed.emit()

func recycle_all() -> int:
	var processed := sorted_organic + sorted_anorganic
	if processed <= 0:
		return 0
	recycled_total += processed
	recycle_points += processed * 2
	sorted_organic = 0
	sorted_anorganic = 0
	stats_changed.emit()
	return processed