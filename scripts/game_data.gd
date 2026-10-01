extends Node

## Data ekonomi & buffer "sudah dipilah" (setor-pilah-olah) antar mesin.
## Alur:
##  1) Player ambil sampah -> Inventory (stok per jenis + total organic/anorganik)
##  2) Mesin Pilah (E): inventory.drain() -> add_sorted()  (buffer per jenis)
##  3) Mesin Olah (F): sell_sorted() -> GameManager.add_coins()
##
## Alur B (nanti, sesuai GDD): bahan olahan diolah lagi -> barang jadi,
## lalu dijual manual. Harga barang jadi > harga jual bahan olahan langsung.
## Siap-siap: kalau butuh, tambahin ITEM_PRODUCTS { kind_bahan: kind_barang }.

signal stats_changed
signal prologue_finished

## Nilai jual BAHAN OLAHAN langsung -> koin. Bedo tiap jenis sampah.
const ITEM_NAMES := {
	"koran": "Koran",
	"tulang_ikan": "Tulang Ikan",
	"eco_enzyme": "Eco Enzyme",
	"kulit_kacang": "Kulit Kacang",
	"pisang": "Pisang",
	"ranting": "Ranting",
	"roti": "Roti",
	"teh": "Teh",
	"kemasan": "Kemasan",
	"sedotan": "Sedotan",
}

## koin per 1 bahan olahan
const ITEM_PRICES := {
	"koran": 5,
	"tulang_ikan": 6,
	"eco_enzyme": 8,
	"kulit_kacang": 4,
	"pisang": 3,
	"ranting": 4,
	"roti": 4,
	"teh": 3,
	"kemasan": 5,
	"sedotan": 2,
}

## kind -> Trash.TrashType (buat total organic/anorganik di HUD & UI)
const ITEM_TYPE := {
	"koran": Trash.TrashType.ORGANIC,
	"tulang_ikan": Trash.TrashType.ORGANIC,
	"eco_enzyme": Trash.TrashType.ORGANIC,
	"kulit_kacang": Trash.TrashType.ORGANIC,
	"pisang": Trash.TrashType.ORGANIC,
	"ranting": Trash.TrashType.ORGANIC,
	"roti": Trash.TrashType.ORGANIC,
	"teh": Trash.TrashType.ORGANIC,
	"kemasan": Trash.TrashType.ANORGANIC,
	"sedotan": Trash.TrashType.ANORGANIC,
}

## Gambar per jenis, dipake HUD inventory & UI pilah/olah.
const ITEM_TEXTURES := {
	"koran": preload("res://assets/sampah/koran.png"),
	"tulang_ikan": preload("res://assets/sampah/tulang_ikan.png"),
	"eco_enzyme": preload("res://assets/sampah_organic/eco_enzyme.png"),
	"kulit_kacang": preload("res://assets/sampah_organic/kulit_kacang.png"),
	"pisang": preload("res://assets/sampah_organic/pisang.png"),
	"ranting": preload("res://assets/sampah_organic/ranting.png"),
	"roti": preload("res://assets/sampah_organic/roti.png"),
	"teh": preload("res://assets/sampah_organic/teh.png"),
	"kemasan": preload("res://assets/sampah/kemasan.png"),
	"sedotan": preload("res://assets/sampah/sedotan.png"),
}

var prologue_completed: bool = false:
	set(val):
		var was_completed := prologue_completed
		prologue_completed = val
		if val and not was_completed:
			prologue_finished.emit()

## Buffer hasil pilah, siap diolah jadi koin. kind -> qty.
var sorted: Dictionary = {}
var sorted_organic: int = 0
var sorted_anorganic: int = 0
var recycled_total: int = 0

func sorted_total() -> int:
	return sorted_organic + sorted_anorganic

## Gabung stok hasil tapisan dari inventory player (Dictionary kind -> qty).
func add_sorted(new_stocks: Dictionary) -> void:
	for kind in new_stocks:
		sorted[kind] = sorted.get(kind, 0) + new_stocks[kind]
		if ITEM_TYPE.get(kind, Trash.TrashType.ORGANIC) == Trash.TrashType.ORGANIC:
			sorted_organic += new_stocks[kind]
		else:
			sorted_anorganic += new_stocks[kind]
	stats_changed.emit()

## Total koin kalo seluruh buffer diolah/jual sekarang.
func sorted_value() -> int:
	var total := 0
	for kind in sorted:
		total += sorted[kind] * ITEM_PRICES.get(kind, 1)
	return total

## "Olah" -> semua bahan olahan langsung dijadiin koin (Alur A, MVP).
## Return koin yang didapat.
func sell_sorted() -> int:
	if sorted.is_empty():
		return 0
	var coins := sorted_value()
	recycled_total += sorted_total()
	sorted.clear()
	sorted_organic = 0
	sorted_anorganic = 0
	stats_changed.emit()
	return coins