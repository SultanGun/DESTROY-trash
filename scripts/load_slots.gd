extends Control

## Panel pemilihan slot di main menu (LOAD). Ini scene asli — penggeseran &
## styling semua node bebas di editor.

signal request_load(slot: int)

@onready var slot1_btn: Button = $Slot1
@onready var slot2_btn: Button = $Slot2
@onready var batal_btn: Button = $Batal

func _ready() -> void:
	slot1_btn.pressed.connect(_pick.bind(1))
	slot2_btn.pressed.connect(_pick.bind(2))
	batal_btn.pressed.connect(func() -> void: visible = false)

## Update label & disable slot yang kosong.func refresh() -> void:
	var slot1_data := SaveLoad.read_slot(1)
	var slot2_data := SaveLoad.read_slot(2)
	_configure_slot(slot1_btn, 1, slot1_data)
	_configure_slot(slot2_btn, 2, slot2_data)

func _configure_slot(btn: Button, slot: int, data: Dictionary) -> void:
	if SaveLoad.has_save(slot):
		btn.text = "SLOT %d — HARI %d" % [slot, data.get("day", 1)]
		btn.disabled = false
	else:
		btn.text = "SLOT %d — KOSONG" % slot
		btn.disabled = true

## Sembunyikan dulu sebelum kemungkinan ganti scene, biar kalau mau main baru
## tetap aman. Kalau slot kosong tombolnya udah disabled (ga bisa kepijit).
func _pick(slot: int) -> void:
	SaveLoad.pending_slot = slot
	print("LOAD slot ", slot)
	get_tree().change_scene_to_file("res://main.tscn")
