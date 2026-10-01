extends CanvasLayer

## Menu di pintu rumah (HouseA).
## Punya pilihan SLOT 1 / SLOT 2 (ganti slot aktif) lalu:
##  - SIMPAN & TIDUR: lanjut hari berikutnya (06:00) + auto-save ke slot aktif
##  - KELUAR: tutup menu

signal close_requested

@onready var status_label: Label = $Dim/Status
@onready var slot_label: Label = $Dim/SlotLabel
@onready var slot1_btn: Button = $Dim/Slot1
@onready var slot2_btn: Button = $Dim/Slot2
@onready var save_sleep_btn: Button = $Dim/Save
@onready var close_btn: Button = $Dim/Close

func _ready() -> void:
	slot1_btn.pressed.connect(_pick_slot.bind(1))
	slot2_btn.pressed.connect(_pick_slot.bind(2))
	save_sleep_btn.pressed.connect(_on_save_sleep)
	close_btn.pressed.connect(close_requested.emit)
	_build_esc_hint()
	_sync_slot_ui()

func _build_esc_hint() -> void:
	var hint := Label.new()
	hint.name = "EscHint"
	hint.text = "[ESC] Tutup"
	hint.position = Vector2(560, 445)
	hint.size = Vector2(160, 24)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 4)
	$Dim.add_child(hint)

func _pick_slot(slot: int) -> void:
	_save_load().current_slot = slot
	_sync_slot_ui()

## Autoload SaveLoad diambil lewat /root, bukan identifier global, supaya
## skrip ini tetap bisa dikompilasi pada mode --script headless. Pola sama
## dengan NightPatrol._game_manager(). Menunjuk node autoload yang
## sungguhan -- tidak pernah membuat instance baru.
func _save_load() -> Node:
	return get_node("/root/SaveLoad")

## Tandai tombol slot yang aktif + update label status.
func _sync_slot_ui() -> void:
	var sl := _save_load()
	var slot: int = sl.current_slot
	slot_label.text = "SLOT %d" % slot
	slot1_btn.button_pressed = (slot == 1)
	slot2_btn.button_pressed = (slot == 2)
	if sl.has_save(slot):
		var data: Dictionary = sl.read_slot(slot)
		status_label.text = "Slot %d ada HARI %d. Simpan akan menimpa." % [slot, data.get("day", 1)]
	else:
		status_label.text = "Slot %d kosong — mulai dari sini." % slot

## --- SIMPAN & TIDUR: hari berikutnya + auto-save ke slot aktif ---

func _on_save_sleep() -> void:
	var tm := get_tree().get_first_node_in_group("time_manager")
	var sl := _save_load()
	var slot: int = sl.current_slot
	if tm:
		tm.call("sleep_one_day")
	if not sl.save_slot(slot):
		status_label.text = "Gagal nyimpen!"
		return
	status_label.text = "Tersimpan SLOT %d — HARI %d" % [slot, tm.day if tm else 2]
	_sync_slot_ui()
