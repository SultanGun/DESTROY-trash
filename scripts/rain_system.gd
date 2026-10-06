extends Node2D

## Autoload "RainSystem": cuaca hujan.
##
## Hujan murni visual + audio. Tidak ada node collision, tidak ada Area2D, tidak
## ada cuerpos yang masuk physics: partikelnya GPUParticles2D, jadi tidak pernah
## bisa menusuk player, NPC, patrol, atau Sampah. Satu-satunya node non-partikel
## adalah ColorRect di CanvasLayer dengan `mouse_filter = IGNORE`, jadi juga
## tidak memblokir input maupun klik UI.
##
## Mengikuti kamera: emitter diletakkan di tengah viewport tiap frame, jadi
## player tidak pernah keluar dari area hujan. Karena ini AUTOLOAD (bukan anak
## Main), sistemnya hidup sekali untuk seluruh game: ganti scene atau menyeberang
## Map1<->Map2 tidak membuat hujan terduplikasi.
##
## Dipicu dari TimeManager lewat sinyal `day_started`, bukan dari _process: aturan
## "hujan setiap 3 hari" dievaluasi saat hari berganti saja, bukan 60x per detik.

## Texture tetes. `rain_drop.png` adalah tetes asli milik user (423x795), tapi
## proporsi gemuknya membuat tetes terlihat seperti balon biru kalau dipakai
## apa adanya. `rain_streak.png` adalah tetes yang sama, dipipihkan horizontal
## jadi goresan 96x300 - tetap artwork milik user, hanya proporsi yang diubah
## supaya terbaca sebagai hujan dan bukan lingkaran biru.
const DROP_TEXTURE := preload("res://assets/weather/rain_streak.png")
const RAIN_STREAM := preload("res://assets/audio/ambience_rain.mp3")


## Berapa tetes yang hidup sekaligus. Hujan yang terbaca sebagai hujan itu
## rapat dan tipis: 240 tetes besar di area sebesar layar cuma terlihat seperti
##gumpalan biru. 1100 tetes kecil yang tersebar di area lebih luas
## dari layar, menghasilkan ~400 tetes yang terlihat sekaligus - cukup rapat
## untuk terasa hujan, tetap ringan karena partikelnya cuma quad kecil.
const DROP_COUNT := 1100

## Ukuran tetes sebagai bagian dari texture. Texture streak 96x300, jadi
## 0.05-0.10 berarti tetes sekitar 5-10 px x 15-30 px di layar: cukup untuk
## terlihat, kecil enough so tidak menutupi gameplay.
const DROP_SCALE_MIN := 0.05
const DROP_SCALE_MAX := 0.10

## Kecepatan jatuh px/detik. Pelan, bukan seperti pisau, supaya player sempat
## melihat geraknya.
const FALL_SPEED := Vector2(40.0, 760.0)

## Umur satu tetes (detik). 1.1 s x 760 px/s = sekitar 836 px jatuh, cukup
## untuk melewati tinggi layar.
const DROP_LIFETIME := 1.1

## Offset emitter ke atas dari tengah layar, supaya tetes lahir dari area di
## atas layar dan turun melewatinya - bukan muncul mendadak di tengah layar.
const EMIT_OFFSET_Y := -300.0

## Sudut kemiringan. Hujan sedikit miring, bukan vertikal sempurna - itu yang
## membuatnya terbaca sebagai cuaca, bukan garis lurus.
const SLANT_DEG := 11.0

## Radius emisi di sekitar pusat. Lebih lebar dari viewport supaya tepinya
## tidak pernah terlihat.
const SPREAD := Vector2(1400.0, 800.0)

## Volume audio hujan. Cukup jadi lapisan ambience, tidak boleh mengalahkan
## musik (lihat GAME_MUSIC_VOL_DB = -14 di audio_manager.gd).
const RAIN_VOL_DB := -19.0

## Berapa hari sekali hujan. Hari 3, 6, 9, 12, 15, 18, ... sampai hari berganti.
const RAIN_EVERY_N_DAYS := 3

## Tint overcast: slate gelap yang dingin, alpha 0.24.
##
## Kenapa tidak pakai warna terang dengan alpha kecil: overlay terang hanya
## menambah warna biru, dan luminansi nyaris tidak turun (diukur hanya -0.67%,
## artinya cuaca tidak terbaca sama sekali). Slate gelap + alpha sedang
## menurunkan luminansi sekitar 8-10% - cukup terasa sebagai mendung, tapi map
## tetap jelas dibaca dan teks HUD tetap terbaca.
const TINT_COLOR := Color(0.28, 0.33, 0.42, 0.24)

signal rain_started
signal rain_stopped

var _particles: GPUParticles2D = null
var _tint_layer: CanvasLayer = null
var _tint_rect: ColorRect = null
var _audio: AudioStreamPlayer = null
var _raining := false

## TimeManager yang sedang dipantau. Dipantau lewat group "time_manager" yang
## sama dengan audio_manager.gd, jadi tidak perlu menambah API baru di sana.
var _tm: Node = null
var _watching := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _attach_time_manager():
		_start_watching()


## ------------------------------------------------------------- API publik
## Nyalakan hujan. Aman dipanggil berulang: kalau sudah hujan, tidak terjadi
## apa-apa (tidak ada duplikat).
func start_rain() -> void:
	if _raining:
		return
	_raining = true
	_build_particles()
	_build_tint()
	_build_audio()
	rain_started.emit()


## Matikan hujan dan lepaskan SEMUA node-nya. Partikel, tint, dan audio di-free
## di sini, jadi tidak ada jejak yang tertinggal kalau dipanggil di tengah game.
func stop_rain() -> void:
	if not _raining:
		return
	_raining = false
	if is_instance_valid(_particles):
		_particles.queue_free()
	_particles = null
	if is_instance_valid(_tint_rect):
		_tint_rect.queue_free()
	_tint_rect = null
	if is_instance_valid(_tint_layer):
		_tint_layer.queue_free()
	_tint_layer = null
	if is_instance_valid(_audio):
		_audio.stop()
		_audio.queue_free()
	_audio = null
	rain_stopped.emit()


## Status sederhana untuk dipakai logika lain / test.
func is_raining() -> bool:
	return _raining


## Hujan hari ini? Aturannya murni aritmetika supaya bisa diuji tanpa menunggu
## waktu game berjalan: hari 3, 6, 9, 12, ...
func is_rain_day(day: int) -> bool:
	if day < 3:
		return false
	return day % RAIN_EVERY_N_DAYS == 0


## Paksa evaluation untuk `day` tertentu. Dipakai test dan pemicu manual.
## `force`=false berarti "gantungkan ke aturan hari", jadi kalau sedang tidak
## hujan harian, hujan DIMATIKAN.
func apply_day(day: int) -> void:
	if is_rain_day(day):
		start_rain()
	else:
		stop_rain()


## ------------------------------------------------------------- tiap frame
## Emitter ikut kamera. Dipakai _process (bukan physics) supaya tetap jalan
## walau game di-pause; yang penting rain area selalu menutup layar.
func _process(_delta: float) -> void:
	if not _raining:
		return
	_center_on_camera()


func _center_on_camera() -> void:
	if not is_instance_valid(_particles):
		return
	var cam := _active_camera()
	if cam == null:
		# Belum ada kamera (mis. masih di menu): taruh di tengah layar.
		var vp := get_viewport()
		if vp != null:
			_particles.position = vp.get_visible_rect().size * 0.5
		return
	# Emitter digeser ke atas dari tengah layar: tetes lahir dari area di atas
	# layar lalu turun melewatinya, jadi tidak pernah "muncul" mendadak di tengah
	# layar. Posisi tetes yang sudah lahir tidak ikut bergeser karena
	# `local_coords = false`.
	_particles.position = cam.get_screen_center_position() + Vector2(0.0, EMIT_OFFSET_Y)


## Kamera yang sedang dipakai: Camera2D aktif kalau ada, kalau tidak ambil
## milik player. `get_screen_center_position()` sudah memperhitungkan zoom, jadi
## hasilnya tepat di tengah layar.
func _active_camera() -> Camera2D:
	var active := get_viewport().get_camera_2d()
	if active != null:
		return active
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		return player.get_node_or_null(^"Camera2D") as Camera2D
	return null


## ------------------------------------------------------------- pembuatan node
func _build_particles() -> void:
	_particles = GPUParticles2D.new()
	_particles.name = "RainParticles"
	_particles.texture = DROP_TEXTURE
	# Partikel murni visual: tidak ada collision sama sekali.
	_particles.emitting = true
	_particles.amount = DROP_COUNT
	_particles.lifetime = DROP_LIFETIME
	_particles.local_coords = false
	# z_index tinggi supaya hujan berada di atas map, tapi di bawah UI.
	_particles.z_index = 4000
	add_child(_particles)

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(SPREAD.x, SPREAD.y, 1.0)
	# Hujan mulai dari atas area dan jatuh ke bawah, sedikit miring.
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 3.0
	mat.initial_velocity_min = FALL_SPEED.y * 0.85
	mat.initial_velocity_max = FALL_SPEED.y
	mat.gravity = Vector3(0, 0, 0)
	mat.scale_min = DROP_SCALE_MIN
	mat.scale_max = DROP_SCALE_MAX
	# Tetes memanjang ke bawah, jadi sumbu panjangnya vertikal. Diputar sedikit
	# supaya miring, bukan lurus seperti garis.
	mat.angle_min = deg_to_rad(-SLANT_DEG)
	mat.angle_max = deg_to_rad(-SLANT_DEG)
	# Stretch lewat scale curve: tetes meninggi saat jatuh lalu memendek, supaya
	# tidak terlihat seperti salinan yang persis sama. Rentangnya sengaja sempit
	# - kalau lebar, tetes jadi sebesar bola.
	mat.scale_curve = _scale_curve()
	# Fade in/out sepanjang umur tetes. Tanpa ini tetes "muncul" dan "hilang"
	# mendadak di frame, dan itu langsung merusak kesan hujan.
	mat.color_ramp = _fade_ramp()
	_particles.process_material = mat


## Gradien alpha: masuk cepat, penuh, keluar cepat. Yang bikin tetes
## tidak terlihat popping di awal maupun akhir umurnya.
func _fade_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(0.80, 0.87, 0.97, 0.0))
	g.set_color(1, Color(0.80, 0.87, 0.97, 0.55))
	g.set_offset(0, 0.0)
	g.set_offset(1, 0.12)
	g.add_point(0.72, Color(0.80, 0.87, 0.97, 0.55))
	g.add_point(1.0, Color(0.80, 0.87, 0.97, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex


## Kurva yang bikin tetes meninggi sebentar lalu memendek di bawah. Ini yang
## membuat geraknya tidak terbaca sebagai "sprite yang diulang".
##
## PENTING: di Godot 4.4 properti `*_curve` milik ParticleProcessMaterial
## bertipe **CurveTexture**, bukan Curve polos. (Curve polos untuk scale baru
## ada di 4.5+; kalau langsung di-assign, parser melaporkan "Value of type
## Curve cannot be assigned to a variable of type Texture2D".)
func _scale_curve() -> CurveTexture:
	var c := Curve.new()
	c.min_value = 0.0
	c.max_value = 1.0
	c.add_point(Vector2(0.0, 0.75))
	c.add_point(Vector2(0.35, 1.0))
	c.add_point(Vector2(0.8, 0.9))
	c.add_point(Vector2(1.0, 0.6))
	var tex := CurveTexture.new()
	tex.curve = c
	return tex


## Lapisan tint untuk kesan mendung. CanvasLayer + ColorRect Penuh layar,
## `mouse_filter = IGNORE` supaya tidak pernah menelan klik UI.
func _build_tint() -> void:
	_tint_layer = CanvasLayer.new()
	_tint_layer.name = "RainTint"
	_tint_layer.layer = 1
	add_child(_tint_layer)
	_tint_rect = ColorRect.new()
	_tint_rect.name = "Overcast"
	_tint_rect.color = TINT_COLOR
	_tint_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Penuh layar, ukuran jendela berapa pun ikut.
	_tint_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint_layer.add_child(_tint_rect)


func _build_audio() -> void:
	_audio = AudioStreamPlayer.new()
	_audio.name = "RainAudio"
	_audio.stream = RAIN_STREAM
	_audio.volume_db = RAIN_VOL_DB
	# Loop: AudioStreamMP3 di Godot punya loop yang bisa dinyalakan lewat
	# `finished` signal, jadi kita putar ulang manual.
	_audio.finished.connect(_loop_audio)
	add_child(_audio)
	_audio.play()


func _loop_audio() -> void:
	if _raining and is_instance_valid(_audio):
		_audio.play()


## ------------------------------------------------------------- TimeManager
## Hujan mengikuti pergantian hari, jadi kita dengarkan sinyal `day_started`
## dari TimeManager kalau ada. Kalau TimeManager belum ada saat autoload siap,
## tunggu lewat node_added (pola yang sama dengan NightPatrol / AudioManager).
func _attach_time_manager() -> bool:
	for node in get_tree().get_nodes_in_group(&"time_manager"):
		if node.has_signal("day_started") or node.has_signal("midnight"):
			_tm = node
			_connect_day_signal()
			_apply_current_day()
			return true
	return false


func _connect_day_signal() -> void:
	if _tm == null or not is_instance_valid(_tm):
		return
	if _tm.has_signal("day_started"):
		_tm.day_started.connect(_on_day_started)
	elif _tm.has_signal("midnight"):
		# TimeManager lama hanya punya `midnight`. Dipakai sebagai fallback.
		_tm.midnight.connect(_on_day_started)
	# RainSystem adalah autoload: ia tetap hidup saat player keluar ke menu
	# (main.tscn di-free, TimeManager ikut mati), sementara hujan tidak mati
	# sendiri. Tanpa ini, hujan dari hari hujan ikut tampil di atas menu utama.
	if not _tm.tree_exiting.is_connected(_on_time_manager_exiting):
		_tm.tree_exiting.connect(_on_time_manager_exiting)


## TimeManager keluar dari tree = player meninggalkan sesi main (kembali ke
## menu, load ulang). Hujan tidak boleh ikut ke menu: matikan semuanya,
## lupakan TimeManager lama, dan pasang lagi watcher supaya sesi main
## berikutnya (TimeManager baru) langsung ketemu.
func _on_time_manager_exiting() -> void:
	stop_rain()
	_tm = null
	_start_watching()


func _on_day_started(day: int) -> void:
	apply_day(day)


## Nilai `day` dari TimeManager, atau -1 kalau belum ada.
func _tm_day() -> int:
	if _tm == null or not is_instance_valid(_tm):
		return -1
	if "day" in _tm:
		return int(_tm.get("day"))
	return -1


func _apply_current_day() -> void:
	var d := _tm_day()
	if d > 0:
		apply_day(d)


func _start_watching() -> void:
	if _watching:
		return
	_watching = true
	get_tree().node_added.connect(_on_node_added)


func _stop_watching() -> void:
	if not _watching:
		return
	_watching = false
	if get_tree().node_added.is_connected(Callable(self, "_on_node_added")):
		get_tree().node_added.disconnect(Callable(self, "_on_node_added"))


func _on_node_added(_node: Node) -> void:
	# node_added terpancar sebelum _ready() node itu jalan, sedangkan TimeManager
	# baru masuk grup di _ready(). Ceknya ditunda ke akhir frame.
	call_deferred("_retry_attach")


func _retry_attach() -> void:
	if _tm != null and is_instance_valid(_tm):
		_stop_watching()
		return
	if _attach_time_manager():
		_stop_watching()


func _exit_tree() -> void:
	# Autoload di-reload saat editor reopen: lepaskan audio supaya tidak
	# menggantung kalau scene di-ganti.
	if is_instance_valid(_audio):
		_audio.stop()
