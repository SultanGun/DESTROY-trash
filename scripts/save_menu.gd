extends CanvasLayer

## Menu di pintu rumah (HouseA).
## Punya pilihan SLOT 1 / SLOT 2 (ganti slot aktif) lalu:
##  - SIMPAN & TIDUR: lanjut hari berikutnya (06:00) + auto-save ke slot aktif
##  - KELUAR: tutup menu

signal close_requested

@onready var status_label: Label = $Dim/Panel/VBox/Status
@onready var slot_label: Label = $Dim/Panel/VBox/SlotLabel
@onready var slot1_btn: Button = $Dim/Panel/VBox/Slots/Slot1
@onready var slot2_btn: Button = $Dim/Panel/VBox/Slots/Slot2
@onready var save_sleep_btn: Button = $Dim/Panel/VBox/Save
@onready var close_btn: Button = $Dim/Panel/VBox/Close

func _ready() -> void:
	slot1_btn.pressed.connect(_pick_slot.bind(1))
	slot2_btn.pressed.connect(_pick_slot.bind(2))
	save_sleep_btn.pressed.connect(_on_save_sleep)
	close_btn.pressed.connect(close_requested.emit)
	_sync_slot_ui()

func _pick_slot(slot: int) -> void:
	SaveLoad.current_slot = slot
	_sync_slot_ui()

## Tandai tombol slot yang aktif + update label status.
func _sync_slot_ui() -> void:
	var slot := SaveLoad.current_slot
	slot_label.text = "SLOT %d" % slot
	slot1_btn.button_pressed = (slot == 1)
	slot2_btn.button_pressed = (slot == 2)
	if SaveLoad.has_save(slot):
		var data: Dictionary = SaveLoad.read_slot(slot)
		status_label.text = "Slot %d ada HARI %d. Simpan akan menimpa." % [slot, data.get("day", 1)]
	else:
		status_label.text = "Slot %d kosong — mulai dari sini." % slot

## --- SIMPAN & TIDUR: hari berikutnya + auto-save ke slot aktif ---

func _on_save_sleep() -> void:
	var tm := get_tree().get_first_node_in_group("time_manager")
	var slot := SaveLoad.current_slot
	if tm:
		tm.call("sleep_one_day")
	if not SaveLoad.save_slot(slot):
		status_label.text = "Gagal nyimpen!"
		return
	status_label.text = "Tersimpan SLOT %d — HARI %d" % [slot, tm.day if tm else 2]
	_sync_slot_ui()