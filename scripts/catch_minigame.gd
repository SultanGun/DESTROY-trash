extends CanvasLayer

## Minigame tangkapan: tekan E saat bar berayun pas di zona target.
##
## Kenapa bukan "tekan E = langsung tertangkap": tangkapan yang gratis membuat
## tombol E jadi tanpa keputusan. Player bisa saja cuma berlari mengikz NPC
## tanpa pernah berpikir. Minigame ini mengubah E jadi keputusan yang
## jarang tapi murah: skill timing sederhana, tiga percobaan, dan kalau gagal
## benar-benar kabur. Failed berarti konsekuensi, bukan animasi.
##
## Modul ini sengaja TIDAK tahu apa-apa soal NPC. Dia cuma:
## `press()` -> sukses/gagal, lalu serah terima lewat dua signal. Player yang
## tahu harus menusuk NPC-nya atau melepaskannya. Itu menjaga supaya minigame
## bisa diuji tanpa scene Main, sama seperti PatrolHUD.
## Bar bergerak bolak-balik (triangle wave) antara 0 dan 1. Zona target adalah
## satu interval [center - half, center + half]. Jarak bar ke pusat zona
## dibandingkan dengan `half`: memakai jarak ke pusat, bukan "bar di dalam
## interval", karena yang membuat satu tekan terasa adil adalah
## "berapa jauh meleset", bukan "ya/tidak".

signal succeeded
signal failed
signal attempt_used(remaining: int)
signal dismissed

## Berapa banyak tekan E yang boleh meleset sebelum NPC menyerah.
const MAX_ATTEMPTS := 3

## Seberapa kecil zona target. 0.06 = 12% lebar track, jadi bar harus berada
## di sekitar seperdelapan track untuk dianggap tepat. Turun dari 0.12 karena
## pada nilai lama hampir semua tekan yang "agak benar" langsung dianggap
## kena - tantangannya jadi tidak terasa.
const ZONE_HALF := 0.06

## Kecepatan ayunan dalam satuan track per detik. 1.20 berarti satu lintasan
## bolak-balik penuh (0 -> 1 -> 0) memakan 2/1.20 = 1.67 detik, naik dari
## 2.67 detik. Bar sekarang menyeberangi zona dalam ~0.1 detik, jadi menekan
## tepat butuh timing nyata, bukan asal tekan saat lewat.
const BAR_SPEED := 1.20

## Di mana zona target duduk, dalam 0..1. 0.5 = tengah track. Tidak acak,
## supaya zone bisa dipelajari dan tesnya deterministik.
const ZONE_CENTER := 0.5

@onready var _track: Control = $Box/Track
@onready var _zone: ColorRect = $Box/Track/Zone
@onready var _bar: ColorRect = $Box/Track/Bar
@onready var _hint: Label = $Box/Hint
@onready var _attempts_label: Label = $Box/Attempts

## true selama minigame terbuka dan menunggu tekan E.
var _active := false

## Posisi bar sekarang dalam 0..1.
var _pos := 0.0

## Arah ayunan: +1 ke kanan, -1 ke kiri.
var _dir := 1.0

## Sisa percobaan yang boleh meleset.
var _attempts_left := MAX_ATTEMPTS

## True setelah tekan E pertama, dipakai untuk animasi umpan balik singkat.
var _resolved := false


func _ready() -> void:
	visible = false
	_place_zone()
	_place_bar()
	_update_attempts_label()
	set_process(false)


## Buka minigame untuk satu target. Memulai dari 0 dengan percobaan penuh,
## jadi dua NPC dalam satu malam tidak saling mewarisi sisa percobaan.
func open() -> void:
	_active = true
	_resolved = false
	_pos = 0.0
	_dir = 1.0
	_attempts_left = MAX_ATTEMPTS
	visible = true
	_place_zone()
	_place_bar()
	_update_attempts_label()
	set_process(true)


## Tutup tanpa hasil. Dipakai saat NPC kabur/keluar jangkauan di tengah
## minigame, atau saat player menekan E lagi untuk membatalkan.
func dismiss() -> void:
	if not _active:
		return
	_active = false
	_resolved = false
	visible = false
	set_process(false)
	dismissed.emit()


func is_active() -> bool:
	return _active


func attempts_left() -> int:
	return _attempts_left


## Diperluas untuk test: posisi bar sekarang dalam 0..1.
func bar_position() -> float:
	return _pos


## Diperluas untuk test: apakah posisi sekarang dianggap tepat.
func is_in_zone() -> bool:
	return absf(_pos - ZONE_CENTER) <= ZONE_HALF


func _process(delta: float) -> void:
	if not _active or _resolved:
		return
	_pos += _dir * BAR_SPEED * delta
	# Pantul di ujung. Pakai > / < supaya tepat di 0 atau 1 tidak memantul dua
	# kali dalam satu frame (yang lainya bar akan/get stuck di ujung).
	if _pos >= 1.0:
		_pos = 1.0
		_dir = -1.0
	elif _pos <= 0.0:
		_pos = 0.0
		_dir = 1.0
	_place_bar()


## Satu tekan E. Mengembalikan true kalau tekan itu strained (sukses), false
## kalau meleset atau minigame sudah selesai.
##
## Efek sampingnya: `succeeded` / `failed` dipancarkan, dan `attempt_used`
## dipancarkan tiap kali percobaan terpakai (sukses termasuk, biar HUD bisa
## mengunci tombolnya).
func press() -> bool:
	if not _active or _resolved:
		return false
	if is_in_zone():
		_active = false
		_resolved = true
		visible = false
		set_process(false)
		attempt_used.emit(_attempts_left)
		succeeded.emit()
		return true
	_attempts_left -= 1
	_update_attempts_label()
	attempt_used.emit(_attempts_left)
	if _attempts_left <= 0:
		# Tiga meleset: NPC menyerah dan kabur. Tidak ada tekan keempat yang
		# bisa menyelamatkan, jadi minigame ditutup sekarang, bukan
		# menunggu player realizes they've lost.
		_active = false
		_resolved = true
		visible = false
		set_process(false)
		failed.emit()
	return false


func _place_zone() -> void:
	if _zone == null or _track == null:
		return
	var w: float = _track.size.x
	_zone.size = Vector2(ZONE_HALF * 2.0 * w, _track.size.y)
	# Pivot di kiri supaya zone bisa di-place lewat position dengan lebar tetap.
	_zone.position = Vector2((ZONE_CENTER - ZONE_HALF) * w, 0.0)
	_zone.pivot_offset = Vector2.ZERO


func _place_bar() -> void:
	if _bar == null or _track == null:
		return
	var w: float = _track.size.x
	_bar.position = Vector2(clampf(_pos, 0.0, 1.0) * w, 0.0)
	_bar.pivot_offset = Vector2.ZERO


func _update_attempts_label() -> void:
	if _attempts_label != null:
		_attempts_label.text = "PERCOBAAN %d/%d" % [MAX_ATTEMPTS - _attempts_left, MAX_ATTEMPTS]
	if _hint != null:
		if _attempts_left <= 0:
			_hint.text = "GAGAL"
		elif _attempts_left == 1:
			_hint.text = "TEKAN E - TERAKHIR!"
		else:
			_hint.text = "TEKAN E SAAT BAR DI ZONA"
