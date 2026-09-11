extends Node
class_name TimeManager

## STEP 8 — Sistem Waktu (Day/Night), tanpa asset lighting dulu.
## Sederhana: waktu jalan terus; pas current_time lewat day_length, fase
## ganti siang/malam. 1 hari penuh = 2x day_length (siang + malam).
## Dipasang sebagai node di main.tscn biar day_length gampang diatur
## dari inspector (bukan autoload, jadi editable di editor).

signal phase_changed(is_day: bool)
signal time_updated(current_time: float, day_length: float)

## Detik per fase (siang ATAU malam). 180 = siang 3 menit, malam 3 menit.
@export var day_length: float = 180.0
## Nomor hari; naik tiap pagi baru (fase ganti malam -> siang).
@export var day: int = 1

var current_time: float = 0.0
var is_day: bool = true

func _ready() -> void:
	add_to_group("time_manager")

func _process(delta: float) -> void:
	current_time += delta
	time_updated.emit(current_time, day_length)
	if current_time >= day_length:
		current_time = 0.0
		_toggle_phase()

func _toggle_phase() -> void:
	is_day = not is_day
	if is_day:
		day += 1
	phase_changed.emit(is_day)

## Format jam in-game ala Stardew (mulai jam 06:00).
## Siang: 06:00-18:00  |  Malam: 18:00-06:00.
func clock_text() -> String:
	var frac: float = clampf(current_time / day_length, 0.0, 1.0)
	var hours: float = (6.0 + 12.0 * frac) if is_day else (18.0 + 12.0 * frac)
	var h := int(hours) % 24
	var m := int(fmod(hours * 60.0, 60.0))
	return "%02d:%02d" % [h, m]