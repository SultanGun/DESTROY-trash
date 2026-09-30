extends Node2D

## Main scene handler. Setelah scene siap, kalau main menu memilih slot
## untuk di-load (SaveLoad.pending_slot), terapkan save ke dunia.

func _ready() -> void:
	call_deferred("_apply_pending_load")

## Autoload SaveLoad diambil lewat /root, bukan identifier global, supaya
## skrip ini tetap bisa dikompilasi pada mode --script headless. Pola sama
## dengan NightPatrol._game_manager(). Menunjuk node autoload yang
## sungguhan -- tidak pernah membuat instance baru.
func _save_load() -> Node:
	return get_node("/root/SaveLoad")

func _apply_pending_load() -> void:
	var sl := _save_load()
	var slot: int = sl.pending_slot
	if slot < 1:
		return
	sl.pending_slot = -1
	if sl.apply_slot(slot):
		print("Main: slot ", slot, " di-load.")
	else:
		print("Main: slot ", slot, " kosong/tidak ada.")