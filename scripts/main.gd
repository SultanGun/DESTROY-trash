extends Node2D

## Main scene handler. Setelah scene siap, kalau main menu memilih slot
## untuk di-load (SaveLoad.pending_slot), terapkan save ke dunia.

func _ready() -> void:
	call_deferred("_apply_pending_load")

func _apply_pending_load() -> void:
	var slot := SaveLoad.pending_slot
	if slot < 1:
		return
	SaveLoad.pending_slot = -1
	if SaveLoad.apply_slot(slot):
		print("Main: slot ", slot, " di-load.")
	else:
		print("Main: slot ", slot, " kosong/tidak ada.")