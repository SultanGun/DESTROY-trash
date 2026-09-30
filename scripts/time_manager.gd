extends Node
class_name TimeManager

## STEP 8 — Sistem Waktu (Day/Night) + Jam 24h ala Stardew.
## Tanpa asset lighting: gelap dinaikin lewat CanvasModulate (WorldLight di
## main.tscn), HUD di CanvasLayer layer atas nggak kena.
##
## Jadwal (game time):
##   06:00 - 16:00  SIANG (terang penuh)
##   16:00 - 18:00  SENJA / SUNSET (semi-gelap, hangat)
##   18:00 - 06:00  MALAM (gelap)
##   00:00          batas tidur/save -> signal midnight
##
## 1 hari penuh = 24 jam game. Durasi diatur dari inspector (node TimeManager
## di main.tscn): seconds_per_game_hour = detik real utk 1 jam game.
## Default 20 detik/jam -> 1 hari game = 8 menit real.

enum Phase { DAY, SUNSET, NIGHT }

signal phase_changed(phase: int)
signal time_updated(current_time: float, day_length: float)
signal midnight
## Dipancarkan sekali tiap kali `day` naik, dengan angka hari BARU. Dipakai
## RainSystem supaya aturan "hujan setiap 3 hari" dievaluasi saat hari
## berganti, bukan tiap frame.
signal day_started(day: int)

## Detik real per 1 jam game. 20 = 24 jam game = 8 menit real.
@export var seconds_per_game_hour: float = 20.0
## Nomor hari; naik tiap ganti hari (saat lewat 00:00).
@export var day: int = 1

var current_time: float = 0.0
## Total detik real utk 1 hari penuh (24 jam game).
var day_length: float = 1440.0

var _phase: int = Phase.DAY
var _prev_hour: float = 6.0
var _world_light: CanvasModulate = null

const TINT_DAY := Color(1.0, 1.0, 1.0)
const TINT_SUNSET := Color(1.0, 0.85, 0.7)
const TINT_NIGHT := Color(0.35, 0.42, 0.65)

func _ready() -> void:
	add_to_group("time_manager")
	day_length = 24.0 * seconds_per_game_hour
	_world_light = get_node_or_null("../WorldLight")
	_update_light(0.0)

func _process(delta: float) -> void:
	current_time += delta
	var hour := game_hour()
	if hour < _prev_hour:
		# lewat tengah malam (00:00) => hari baru
		day += 1
		midnight.emit()
		day_started.emit(day)
	_update_phase()
	_update_light(delta)
	_prev_hour = hour
	time_updated.emit(current_time, day_length)

## Shortcut debug (tanpa nunggu phase alami):
##   F1 -> lompat ke 16:00 (mulai senja)   F2 -> lompat ke 18:00 (malam tiba)
##   F3 -> balik ke 06:00 (pagi, hari masih jalan normal)
## Shortcut debug (tanpa nunggu phase alami):
##   G -> 16:00 (mulai senja)   H -> 18:00 (malam tiba)   J -> 06:00 (pagi)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_G: jump_to_hour(16.0)
			KEY_H: jump_to_hour(18.0)
			KEY_J: jump_to_hour(6.0)

## Set jam game ke target tertentu (0.0-24.0). Buat tes phase pengaman.
func jump_to_hour(target_hour: float) -> void:
	current_time = fposmod((target_hour - 6.0) * seconds_per_game_hour, day_length)
	_prev_hour = target_hour
	_update_phase()
	_update_light(0.0)
	time_updated.emit(current_time, day_length)
	print("[DEBUG] jam lompat -> ", clock_text(), " (", Phase.keys()[phase()], ")")

## Jam game sekarang, 0.0 = 00:00, 6.0 = 06:00 pagi (hari dimulai jam 6).
func game_hour() -> float:
	return fmod(6.0 + current_time / seconds_per_game_hour, 24.0)

## Tidur: maju ke hari berikutnya, mulai lagi jam 06:00.
## Reset _prev_hour biar _process nggak salah duga tengah malam (hari bakal
## naik dua kali kalau cuma ubah current_time).
func sleep_one_day() -> void:
	day += 1
	current_time = 0.0
	_prev_hour = game_hour()
	_update_phase()
	_update_light(0.0)
	time_updated.emit(current_time, day_length)
	# Tidur juga menaikkan hari, jadi cuaca harus ikut di-update. Kalau tidak,
	# RainSystem masih memegang cuaca lama sampai tengah malam pertama.
	day_started.emit(day)

func phase() -> int:
	var h := game_hour()
	if h >= 18.0 or h < 6.0:
		return Phase.NIGHT
	if h >= 16.0:
		return Phase.SUNSET
	return Phase.DAY

func clock_text() -> String:
	var h := int(game_hour())
	var m := int(fmod(game_hour(), 1.0) * 60.0)
	return "%02d:%02d" % [h, m]

func _update_phase() -> void:
	var p := phase()
	if p != _phase:
		_phase = p
		phase_changed.emit(_phase)

## Warna cahaya dunia, mulus (bukan lompatan) antara siang-senja-malam.
func tint() -> Color:
	var h := game_hour()
	if h < 6.0:
		h += 24.0
	if h <= 15.5:
		return TINT_DAY
	if h <= 17.0:
		return TINT_DAY.lerp(TINT_SUNSET, (h - 15.5) / 1.5)
	if h <= 19.0:
		return TINT_SUNSET.lerp(TINT_NIGHT, (h - 17.0) / 2.0)
	if h <= 29.0:
		return TINT_NIGHT
	return TINT_NIGHT.lerp(TINT_DAY, (h - 29.0) / 1.0)

func _update_light(_delta: float) -> void:
	if _world_light == null:
		return
	_world_light.color = tint()
