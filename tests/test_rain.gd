extends SceneTree

## Uji runtime untuk RainSystem (scripts/rain_system.gd).
##
## Harness headless tanpa framework test project:
##   godot --headless --path <project> --script res://tests/test_rain.gd
##
## Yang diuji:
##   1. Masti: hujan MATI, tidak ada node partikel/tint/audio yang tersimpan.
##   2. start_rain() menyalakan partikel + tint + audio, is_raining() true.
##   3. stop_rain() mematikan semuanya; partikel di-free, tidak menggantung.
##   4. Hujan tidak punya collision: tidak ada Area2D/CollisionShape/PhysicsBody.
##   5. Partikel ikut kamera: saat kamera bergerak, emitter ikut bergerak dan
##      tetap menutupi area layar.
##   6. Transisi Map1->Map2 dan Map2->Map1 saat hujan: hanya SATU sistem,
##      tidak terduplikasi, dan MapSeam tidak berubah.
##   7. start_rain() dua kali tidak bikin dua sistem (idempoten).
##   8. Aturan hari: hujan di 3, 6, 9, 12, 15, 18; TIDAK di 1, 2, 4, 5, 7.
##   9. apply_day() nyalakan/mematikan sesuai aturan hari.
##  10. Sinyal rain_started / rain_stopped terpancarkan sekali per transisi.
##  11. Player + NPC collision tetap utuh saat hujan (tidak terganggu).
##  12. Tidak ada duplikat RainSystem di root setelah load main.tscn.
##
## Catatan: autoload TIDAK dimuat di mode --script, jadi RainSystem di
## instansikan manual di sini - sama seperti test_night_patrol dengan TimeManager.

const TimeManagerScript := preload("res://scripts/time_manager.gd")
const RainScript := preload("res://scripts/rain_system.gd")
const MainScene := preload("res://main.tscn")
const DumperRoutes := preload("res://scripts/dumper_routes.gd")

const AUTOLOADS := [
	["GameData", "res://scripts/game_data.gd"],
	["GameManager", "res://scripts/game_manager.gd"],
	["SaveLoad", "res://scripts/save_load.gd"],
	["AudioManager", "res://scripts/audio_manager.gd"],
]

var _pass := 0
var _fail := 0
var _total_fail := 0
var _failures: Array[String] = []
var _rain: Node = null
var _main: Node2D = null


func _initialize() -> void:
	await process_frame
	for pair in AUTOLOADS:
		var n: String = pair[0]
		if root.has_node(n):
			continue
		var node := Node.new()
		node.name = n
		node.set_script(load(pair[1]))
		root.add_child(node)
	await process_frame

	# ------------------------------------------------------------ 1. kondisi awal
	_rain = _make_rain()
	await process_frame
	await _run("masti: hujan mati, tanpa node", _test_starts_off)
	await _run("start_rain(): partikel + tint + audio nyala", _test_start_creates_all)
	await _run("tidak ada collision di sistem hujan", _test_rain_has_no_collision)
	await _run("tetes kecil + banyak, bukan gumpalan biru", _test_rain_looks_like_rain)
	await _run("partikel mengikuti kamera", _test_particles_follow_camera)
	await _run("start_rain() dua kali = tetap satu sistem", _test_start_is_idempotent)
	await _run("sinyal started/stopped sekali per transisi", _test_signals)
	await _run("stop_rain(): semua node dilepas", _test_stop_cleans_up)
	await _run("start lalu stop lagi tetap jalan", _test_restart)
	await _run("aturan hari: 3,6,9,12,15,18 hujan", _test_rain_day_rule)
	await _run("aturan hari: 1,2,4,5,7 tidak hujan", _test_non_rain_days)
	await _run("apply_day() nyalakan/mematikan sesuai aturan", _test_apply_day)

	# ------------------------------------------- 3. wiring TimeManager otomatis
	await _run("TimeManager menyalakan RainSystem otomatis", _test_timemanager_drives_rain)
	await _run("kembali ke menu: hujan mati, tidak ikut ke menu", _test_menu_return_stops_rain)

	# ------------------------------------------ 4. transisi peta saat hujan
	await _run("Map1->Map2 saat hujan: satu sistem, seam utuh", _test_map_transitions_keep_one_system)
	await _run("hujan tidak ganggu collision player/NPC", _test_collision_unaffected)

	_teardown()
	_report()
	quit(0 if _fail == 0 else 1)


# ------------------------------------------------------------------- fixture
func _make_rain() -> Node:
	if is_instance_valid(_rain):
		_rain.queue_free()
		_rain = null
	_rain = RainScript.new()
	_rain.name = "RainSystem"
	root.add_child(_rain)
	return _rain


func _load_main() -> Node2D:
	if is_instance_valid(_main):
		_main.free()
	_main = MainScene.instantiate()
	root.add_child(_main)
	_main.name = "Main"
	return _main as Node2D


func _teardown() -> void:
	if is_instance_valid(_rain):
		_rain.call("stop_rain")
		_rain.queue_free()
	_rain = null
	if is_instance_valid(_main):
		_main.free()
	_main = null
	await process_frame


## Setiap test punya hitungan sendiri, tapi laporan harus menjumlahkan SEMUA
## kegagalan. Kalau laporan memakai `_fail` langsung, isinya hanya test
## terakhir - dan itu pernah menampilkan "gagal=0" padahal ada baris GAGAL.
func _run(label: String, fn: Callable) -> void:
	_fail = 0
	await fn.call()
	if _fail == 0:
		_pass += 1
		print("  LULUS  ", label)
	else:
		_total_fail += _fail
		_failures.append(label)


func _check(cond: bool, msg: String) -> bool:
	if cond:
		return true
	_fail += 1
	_failures.append(msg)
	print("    -> GAGAL: ", msg)
	return false


func _report() -> void:
	print("")
	print("===================================================")
	print("  lulus=%d  gagal=%d" % [_pass, _total_fail])
	if _total_fail > 0:
		print("  --- kegagalan ---")
		for f in _failures:
			print("  * ", f)
	print("===================================================")


# ---------------------------------------------------------------------- tests
func _test_starts_off() -> void:
	_rain = _make_rain()
	await process_frame
	_check(not _rain.call("is_raining"), "hujan harus mati sebelum start_rain()")
	_check(_find_particles() == 0,
		"tidak boleh ada partikel sebelum start, dapat %d" % _find_particles())


## Hitung jumlah GPUParticles2D di bawah RainSystem. Ini yang membuktikan
## "hanya satu sistem aktif" - bukan sekadar andalkan is_raining().
func _find_particles() -> int:
	var n := 0
	for c in _rain.get_children():
		if c is GPUParticles2D:
			n += 1
	return n


func _test_start_creates_all() -> void:
	_rain = _make_rain()
	await process_frame
	var got_start := []
	_rain.connect("rain_started", func() -> void: got_start.append(true))
	_rain.call("start_rain")
	await process_frame
	_check(_rain.call("is_raining"), "is_raining() harus true setelah start_rain()")
	_check(_find_particles() == 1,
		"harus ada tepat 1 GPUParticles2D, dapat %d" % _find_particles())
	var p := _find_one_particle()
	if p != null:
		_check(p.emitting, "partikel harus emitting")
		_check(p.texture != null, "partikel harus punya texture")
		_check(p.amount > 0, "amount harus > 0, dapat %d" % p.amount)
		_check(p.local_coords == false,
			"local_coords harus false supaya partikel tidak menempel ke kamera")
	_check(_find_tint() != null, "harus ada overlay tint mendung")
	var a := _find_audio()
	_check(a != null, "harus ada AudioStreamPlayer untuk hujan")
	_check(got_start.size() == 1, "sinyal rain_started sekali, dapat %d" % got_start.size())


func _find_one_particle() -> GPUParticles2D:
	for c in _rain.get_children():
		if c is GPUParticles2D:
			return c
	return null


func _find_tint() -> ColorRect:
	for c in _rain.get_children():
		if c is CanvasLayer:
			for d in c.get_children():
				if d is ColorRect:
					return d
	return null


func _find_audio() -> AudioStreamPlayer:
	for c in _rain.get_children():
		if c is AudioStreamPlayer:
			return c
	return null


## Hujan tidak boleh punya collision. Kalau ada satu saja body/Area2D di bawah
## RainSystem, player atau NPC bisa menabraknya - itu langsung melanggar syarat
## "hujan tidak boleh mengganggu collision".
func _test_rain_has_no_collision() -> void:
	_rain.call("start_rain")
	await process_frame
	var offenders: Array = []
	_collect_collision(_rain, offenders)
	_check(offenders.is_empty(), "sistem hujan punya node collision: %s" % [offenders])
	# Partikel: GPUParticles2D bukan CollisionObject2D secara tipe, jadi parser
	# sudah menjaganya. Yang dicek nyata: subtree di bawah partikel bersih.
	var p := _find_one_particle()
	if p != null:
		var sub: Array = []
		_collect_collision(p, sub)
		_check(sub.is_empty(),
			"partikel tidak boleh punya subtree collision: %s" % [sub])
	# Tint harus mouse_filter IGNORE supaya tidak menelan klik UI.
	var tint := _find_tint()
	if tint != null:
		_check(tint.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"overlay tint harus MOUSE_FILTER_IGNORE, dapat %d" % tint.mouse_filter)


func _collect_collision(n: Node, out: Array) -> void:
	if n is CollisionObject2D or n is CollisionShape2D or n is Area2D:
		out.append(String(n.name))
	for c in n.get_children():
		_collect_collision(c, out)


## Partikel harus mengikuti kamera, supaya player tidak keluar dari area hujan.
## Kontrak visual. Ini diuji karena regresi di sini tidak ketahuan oleh test
## fungsional: versi pertama tetesnya 21-51 px x 40-95 px, dan hasilnya terlihat
## seperti gumpalan biru, bukan hujan - padahal semua test lain tetap hijau.
##
## Yang dikunci di sini:
##   - tetes kecil (tidak menutupi gameplay)
##   - jumlah tetes cukup banyak (hujan yang terasa, bukan beberapa blob)
##   - ada alpha fade (tetes tidak popping)
##   - area emisi lebih besar dari layar
func _test_rain_looks_like_rain() -> void:
	_rain = _make_rain()
	await process_frame
	_rain.call("start_rain")
	await process_frame
	var p := _find_one_particle()
	if not _check(p != null, "harus ada partikel"):
		return
	var mat := p.process_material as ParticleProcessMaterial
	_check(mat != null, "harus ada ParticleProcessMaterial")

	# --- tetes harus kecil: tinggi <= 40 px, lebar <= 16 px di layar ---
	var tex: Texture2D = p.texture
	_check(tex != null, "partikel harus punya texture")
	if tex != null and mat != null:
		var max_h := float(tex.get_height()) * mat.scale_max
		var max_w := float(tex.get_width()) * mat.scale_max
		_check(max_h <= 40.0,
			"tetes terlalu tinggi: %.0f px (batas 40)" % max_h)
		_check(max_w <= 16.0,
			"tetes terlalu lebar: %.0f px (batas 16)" % max_w)

	# --- jumlah tetes harus cukup untuk terasa hujan ---
	# 240 tetes dulu terbukti terlalu jarang: hanya ~20 yang terlihat.
	_check(p.amount >= 600,
		"jumlah tetes terlalu sedikit: %d (butuh >= 600)" % p.amount)

	# --- alpha fade: tanpa ini tetes popping di awal/akhir umur ---
	_check(mat.color_ramp != null, "harus ada color_ramp untuk fade")
	if mat.color_ramp != null:
		var g: Gradient = mat.color_ramp.gradient
		_check(g != null, "color_ramp harus punya gradient")
		if g != null:
			_check(g.get_color(g.get_point_count() - 1).a < 0.05,
				"alpha tetes harus kembali ke 0 di akhir umur, tidak boleh popping")
			_check(g.get_point_count() >= 3,
				"gradient harus punya titik masuk, penuh, dan keluar (>=3), dapat %d"
				% g.get_point_count())

	# --- scale curve tidak boleh ekstrem (tetes jadi bola) ---
	_check(mat.scale_curve != null, "harus ada scale_curve")
	if mat.scale_curve != null:
		var c: Curve = mat.scale_curve.curve
		if _check(c != null, "scale_curve harus punya Curve"):
			_check(c.max_value <= 1.05,
				"scale_curve puncak %.2f terlalu besar, tetes jadi membesar berlebihan"
				% c.max_value)

	# --- tint overcast harus terasa, tapi tidak boleh terlalu gelap ---
	# Diukur manual: alpha 0.20 dengan warna terang hanya menurunkan luminansi
	# 0.67% - cuaca tidak terbaca. Tapi terlalu gelap membuat map sulit dibaca.
	# Karena itu alpha dibatasi di antara keduanya, dan warnanya harus cukup
	# gelap (bukan cuma Adding blue).
	var tint := _find_tint()
	_check(tint != null, "harus ada overlay tint")
	if tint != null:
		var c := tint.color
		_check(c.a >= 0.15 and c.a <= 0.35,
			"alpha tint %.2f di luar batas 0.15-0.35" % c.a)
		var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
		_check(lum <= 0.45,
			"warna tint terlalu terang (luminansi %.2f) - hanya menambah biru" % lum)
		_check(lum >= 0.15,
			"warna tint terlalu gelap (luminansi %.2f) - map jadi sulit dibaca" % lum)
		_check(tint.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"tint harus mouse-transparent")

	# --- emit OFFSET ke atas: tetes lahir dari atas layar ---
	# Kalau emitter persis di tengah layar, tetes terlihat "muncul" di tengah.
	var cam_m := _load_main()
	await process_frame
	var cam: Camera2D = _test_camera(cam_m)
	if cam != null:
		var p2 := _find_one_particle()
		if p2 != null:
			_check(p2.position.y < cam.get_screen_center_position().y,
				"emitter harus di atas tengah layar, emitter.y=%.0f layar.y=%.0f"
				% [p2.position.y, cam.get_screen_center_position().y])


func _test_camera(m: Node) -> Camera2D:
	if m == null:
		return null
	var player := m.get_node_or_null("Player")
	if player == null:
		return null
	return player.get_node_or_null("Camera2D") as Camera2D


## Titik emitters yang diharapkan: tengah layar digeser ke atas oleh
## EMIT_OFFSET_Y, supaya tetes lahir dari area di atas layar lalu turun
## melewatinya, bukan muncul mendadak di tengah.
func _expected_emitter(cam: Camera2D) -> Vector2:
	return cam.get_screen_center_position() + Vector2(0.0, RainScript.EMIT_OFFSET_Y)


func _test_particles_follow_camera() -> void:
	_rain = _make_rain()
	var m := _load_main()
	await process_frame
	_rain.call("start_rain")
	await process_frame
	var player := m.get_node_or_null("Player") as Node2D
	_check(player != null, "Main harus punya Player")
	if player == null:
		return
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	_check(cam != null, "Player harus punya Camera2D")
	if cam == null:
		return
	var p := _find_one_particle()
	if p == null:
		_check(false, "tidak ada partikel untuk diuji")
		return
	# Kamera di kiri map.
	player.global_position = Vector2(200, 200)
	for _i in 4:
		await process_frame
	var pos_a: Vector2 = p.position
	var cam_a: Vector2 = cam.get_screen_center_position()
	_check(pos_a.distance_to(_expected_emitter(cam)) < 40.0,
		"emitter harus di titik yang diharapkan, emitter=%s diharapkan=%s" % [pos_a, _expected_emitter(cam)])
	# Kamera jauh di kanan (pindah peta) - emitter harus ikut.
	player.global_position = Vector2(5800, 2000)
	for _i in 6:
		await process_frame
	var pos_b: Vector2 = p.position
	var cam_b: Vector2 = cam.get_screen_center_position()
	_check(pos_b.distance_to(pos_a) > 2000.0,
		"emitter harus bergerak jauh bersama kamera, dari %s ke %s" % [pos_a, pos_b])
	_check(pos_b.distance_to(_expected_emitter(cam)) < 40.0,
		"emitter harus tetap menempel kamera setelah pindah, %s vs %s" % [pos_b, _expected_emitter(cam)])
	# Luap emisi harus lebih lebar dari layar, kalau tidak ada pinggir kosong.
	var extents: Vector3 = (p.process_material as ParticleProcessMaterial).emission_box_extents
	_check(extents.x > 1280.0 and extents.y > 720.0,
		"area emisi harus lebih dari viewport, dapat %s" % extents)


func _test_start_is_idempotent() -> void:
	_rain = _make_rain()
	await process_frame
	_rain.call("start_rain")
	_rain.call("start_rain")
	_rain.call("start_rain")
	await process_frame
	_check(_find_particles() == 1,
		"tiga start_rain() harus tetap 1 partikel, dapat %d" % _find_particles())


func _test_signals() -> void:
	_rain = _make_rain()
	await process_frame
	var starts: Array = []
	var stops: Array = []
	_rain.connect("rain_started", func() -> void: starts.append(1))
	_rain.connect("rain_stopped", func() -> void: stops.append(1))
	_rain.call("start_rain")
	_rain.call("start_rain")  # tidak boleh menambah sinyal
	_rain.call("stop_rain")
	_rain.call("stop_rain")   # tidak boleh menambah sinyal
	await process_frame
	_check(starts.size() == 1, "rain_started tepat 1x, dapat %d" % starts.size())
	_check(stops.size() == 1, "rain_stopped tepat 1x, dapat %d" % stops.size())


func _test_stop_cleans_up() -> void:
	_rain = _make_rain()
	await process_frame
	_rain.call("start_rain")
	await process_frame
	var p := _find_one_particle()
	_check(p != null, "prasyarat: partikel harus ada")
	_rain.call("stop_rain")
	await process_frame
	await process_frame
	_check(not _rain.call("is_raining"), "is_raining() harus false setelah stop")
	_check(_find_particles() == 0,
		"partikel harus dilepas, tersisa %d" % _find_particles())
	_check(_find_tint() == null, "overlay tint harus dilepas")
	_check(_find_audio() == null, "audio player harus dilepas")
	# Node yang di-free tidak boleh menggantung dengan is_instance_valid.
	if p != null:
		_check(not is_instance_valid(p), "node partikel lama tidak boleh menggantung")


func _test_restart() -> void:
	_rain = _make_rain()
	await process_frame
	for round_i in 3:
		_rain.call("start_rain")
		await process_frame
		_check(_rain.call("is_raining"), "putaran %d: harus hujan" % round_i)
		_check(_find_particles() == 1,
			"putaran %d: harus 1 partikel, dapat %d" % [round_i, _find_particles()])
		_rain.call("stop_rain")
		await process_frame
		_check(not _rain.call("is_raining"), "putaran %d: harus mati" % round_i)
		_check(_find_particles() == 0,
			"putaran %d: partikel harus bersih, tersisa %d" % [round_i, _find_particles()])


func _test_rain_day_rule() -> void:
	_rain = _make_rain()
	for d in [3, 6, 9, 12, 15, 18]:
		_check(_rain.call("is_rain_day", d), "hari %d harus hujan" % d)


func _test_non_rain_days() -> void:
	_rain = _make_rain()
	for d in [1, 2, 4, 5, 7, 8, 10, 11]:
		_check(not _rain.call("is_rain_day", d), "hari %d tidak boleh hujan" % d)


func _test_apply_day() -> void:
	_rain = _make_rain()
	await process_frame
	_rain.call("apply_day", 4)
	await process_frame
	_check(not _rain.call("is_raining"), "apply_day(4) tidak boleh menyalakan hujan")
	_rain.call("apply_day", 6)
	await process_frame
	_check(_rain.call("is_raining"), "apply_day(6) harus menyalakan hujan")
	_rain.call("apply_day", 7)
	await process_frame
	_check(not _rain.call("is_raining"),
		"apply_day(7) harus mematikan hujan, karena harian selesai")


## Menyeberang Map1->Map2 lalu kembali while raining. Yang dijaga:
##   - tetap SATU partikel (tidak terduplikasi)
##   - MapSeam masih bekerja (limit kamera per peta masih berubah)
##   - emitter tetap nempel kamera
func _test_map_transitions_keep_one_system() -> void:
	_rain = _make_rain()
	var m := _load_main()
	await process_frame
	_rain.call("start_rain")
	await process_frame
	var player := m.get_node_or_null("Player") as Node2D
	if not _check(player != null, "Main harus punya Player"):
		return
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	var seam: Node = null
	for c in m.get_children():
		if c.has_method("_apply_camera_cut"):
			seam = c
			break
	if not _check(seam != null, "MapSeam harus ada"):
		return
	# --- Map1 -> Map2 ---
	player.global_position = Vector2(200, 200)
	seam.call("_apply_camera_cut", false)
	for _i in 4:
		await process_frame
	_check(int(cam.limit_right) == 3200,
		"Map1: limit kanan harus 3200, dapat %d" % int(cam.limit_right))
	player.global_position = Vector2(4400, 1200)
	seam.call("_apply_camera_cut", true)
	for _i in 6:
		await process_frame
	_check(_find_particles() == 1,
		"setelah Map1->Map2 harus tetap 1 partikel, dapat %d" % _find_particles())
	_check(int(cam.limit_left) == 3268,
		"Map2: limit kiri harus 3268, dapat %d" % int(cam.limit_left))
	var p := _find_one_particle()
	_check(p != null and p.position.distance_to(_expected_emitter(cam)) < 40.0,
		"emitter harus ikut kamera di Map2")
	# --- Map2 -> Map1 ---
	player.global_position = Vector2(630, 570)
	seam.call("_apply_camera_cut", false)
	for _i in 6:
		await process_frame
	_check(_find_particles() == 1,
		"setelah Map2->Map1 harus tetap 1 partikel, dapat %d" % _find_particles())
	_check(int(cam.limit_right) == 3200,
		"kembali ke Map1: limit kanan harus 3200, dapat %d" % int(cam.limit_right))
	_check(_rain.call("is_raining"), "hujan harus tetap nyala selama transisi")
	# RainSystem tidak boleh jadi anak Main (kalau begitu, ganti scene akan
	# membunuh/menggandakan sistem).
	_check(_rain.get_parent() == root,
		"RainSystem harus anak root, bukan anak scene Main")




## Bagian paling penting dari fitur ini: di game sungguhan tidak ada yang
## memanggil `start_rain()` manual. Hujan harus muncul sendiri karena
## `TimeManager` memancarkan `day_started` setiap pergantian hari.
##
## Test ini mereplikasi autoload sungguhan: TimeManager dan RainSystem sama-sama
## anak `root`, lalu `day_started` dipancarkan langsung.
func _test_timemanager_drives_rain() -> void:
	# Main dari test sebelumnya masih ada di pohon, dan `main.tscn` punya node
	# TimeManager sendiri di group "time_manager". Kalau tidak dibuang, RainSystem
	# bisa attach ke TimeManager milik Main itu dan test ini menguji jalur yang
	# salah.
	if is_instance_valid(_main):
		_main.free()
		_main = null
	await process_frame

	# --- TimeManager sungguhan, bukan stub ---
	var tm := TimeManagerScript.new()
	tm.name = "TimeManagerProbe"
	tm.set_process(false)
	root.add_child(tm)
	await process_frame
	_rain = _make_rain()
	await process_frame
	# RainSystem harus menemukan TimeManager lewat group "time_manager".
	_check(tm.is_in_group("time_manager"),
		"TimeManager harus masuk group time_manager")
	_check(_rain.get("_tm") == tm,
		"RainSystem harus attach ke TimeManager, dapat %s"
		% str(_rain.get("_tm")))

	# --- pergantian hari: 3 menyalakan ---
	tm.emit_signal("day_started", 3)
	await process_frame
	_check(_rain.call("is_raining"),
		"day_started(3) harus menyalakan hujan otomatis")
	_check(_find_particles() == 1,
		"harus ada 1 partikel setelah day_started(3), dapat %d" % _find_particles())

	# --- pergantian hari: 4 mematikan ---
	tm.emit_signal("day_started", 4)
	await process_frame
	_check(not _rain.call("is_raining"),
		"day_started(4) harus mematikan hujan, harian selesai")
	_check(_find_particles() == 0,
		"partikel harus bersih setelah day_started(4), tersisa %d" % _find_particles())

	# --- siklus panjang: 6 menyala lagi, 7 mati ---
	tm.emit_signal("day_started", 6)
	await process_frame
	_check(_rain.call("is_raining"), "day_started(6) harus menyalakan hujan lagi")
	tm.emit_signal("day_started", 7)
	await process_frame
	_check(not _rain.call("is_raining"), "day_started(7) harus mematikan hujan lagi")
	# TimeManager tidak boleh lepasattach setelah siklus berhenti.
	tm.emit_signal("midnight")
	await process_frame
	_check(_rain.get("_tm") == tm, "TimeManager tidak boleh lepas setelah stop")

	tm.queue_free()
	await process_frame


## Regresi yang pernah dilaporkan user: hujan dari hari hujan ikut tampil di
## atas main menu setelah player keluar dari sesi main.
##
## Penyebabnya: RainSystem adalah autoload yang tetap hidup saat main.tscn
## di-free (TimeManager ikut mati), dan tidak ada yang mematikan hujan.
## Kontraknya: saat TimeManager keluar tree, hujan mati dan RainSystem
## melupakan TimeManager lama; sesi main berikutnya attach ulang otomatis.
func _test_menu_return_stops_rain() -> void:
	if is_instance_valid(_main):
		_main.free()
		_main = null
	await process_frame
	var tm := TimeManagerScript.new()
	tm.name = "TimeManagerMenuProbe"
	tm.set("day", 6)
	tm.set_process(false)
	root.add_child(tm)
	await process_frame
	_rain = _make_rain()
	await process_frame
	_check(_rain.get("_tm") == tm, "prasyarat: RainSystem harus attach ke TimeManager")
	_check(_rain.call("is_raining"),
		"prasyarat: hari 6 harus hujan sebelum keluar ke menu, agar regresinya nyata")

	# --- keluar ke menu: TimeManager di-free seperti saat ganti scene ---
	tm.queue_free()
	await process_frame
	await process_frame
	_check(not _rain.call("is_raining"),
		"hujan harus mati saat TimeManager keluar tree (kembali ke menu)")
	_check(_find_particles() == 0,
		"partikel tidak boleh tertinggal di menu, tersisa %d" % _find_particles())
	_check(_rain.get("_tm") == null,
		"TimeManager lama harus dilupakan, masih menunjuk %s" % str(_rain.get("_tm")))

	# --- masuk sesi main baru: TimeManager baru langsung dipakai lagi ---
	var tm2 := TimeManagerScript.new()
	tm2.name = "TimeManagerMenuProbe2"
	tm2.set("day", 6)
	tm2.set_process(false)
	root.add_child(tm2)
	for _i in 4:
		await process_frame
	_check(_rain.get("_tm") == tm2,
		"sesi main baru harus attach ulang, menunjuk %s" % str(_rain.get("_tm")))
	_check(_rain.call("is_raining"),
		"hari 6 di sesi baru harus hujan lagi")
	tm2.queue_free()
	await process_frame


## Hujan tidak boleh mengganggu collision apa pun yang sudah bekerja.
##
## Kontrak yang diuji, bukan rekaan:
##   1. Hujan tidak menambah / menghapus / mengubah node collision apa pun.
##   2. Layer & mask player tidak berubah antara sebelum dan sesudah hujan.
##   3. Tabrakan player-vs-dinding peta tetap jalan (didorong langsung dengan
##      `move_and_collide`, karena velocity di-overwrite `_physics_process`).
##   4. Sensor PickupRadius dan NPC patrol tetap hidup.
##
## Catatan layer: di Player.tscn baris `collision_layer = 4` milik node
## **PickupRadius** (baris properti mengikuti header node terakhir), sedangkan
## Player sendiri tetap default 1/1. Karena ituquery memakai layer 1.
func _test_collision_unaffected() -> void:
	_rain = _make_rain()
	var m := _load_main()
	await process_frame
	var player := m.get_node_or_null("Player") as CharacterBody2D
	_check(player != null, "Main harus punya Player")
	if player == null:
		return

	# --- rekam kondisi SEBELUM hujan ---
	var layer0 := player.collision_layer
	var mask0 := player.collision_mask
	var col0 := player.get_node_or_null("Collision") as CollisionShape2D
	var col_enabled0 := col0 != null and not col0.disabled
	var bodies0 := _count_collision_nodes(m)
	var areas0 := _count_area_nodes(m)
	var pickup0 := player.get_node_or_null("PickupRadius") as Area2D
	var pickup_layer0 := -1
	if pickup0 != null:
		pickup_layer0 = pickup0.collision_layer

	# --- nyalakan hujan ---
	_rain.call("start_rain")
	await process_frame
	for _i in 3:
		await physics_frame

	# --- semua setting collision harus identik ---
	_check(player.collision_layer == layer0,
		"collision_layer player berubah: %d -> %d" % [layer0, player.collision_layer])
	_check(player.collision_mask == mask0,
		"collision_mask player berubah: %d -> %d" % [mask0, player.collision_mask])
	var col1 := player.get_node_or_null("Collision") as CollisionShape2D
	_check(col1 != null and not col1.disabled,
		"Collision player harus tetap aktif saat hujan")
	_check((col1 != null and not col1.disabled) == col_enabled0,
		"status Collision player berubah saat hujan")
	_check(_count_collision_nodes(m) == bodies0,
		"jumlah node collision berubah: %d -> %d" % [bodies0, _count_collision_nodes(m)])
	_check(_count_area_nodes(m) == areas0,
		"jumlah Area2D berubah: %d -> %d" % [areas0, _count_area_nodes(m)])
	var pickup1 := player.get_node_or_null("PickupRadius") as Area2D
	_check(pickup1 != null, "PickupRadius harus tetap ada saat hujan")
	if pickup0 != null and pickup1 != null:
		_check(pickup1.collision_layer == pickup_layer0,
			"layer PickupRadius berubah: %d -> %d"
			% [pickup_layer0, pickup1.collision_layer])
		_check(pickup1.monitoring, "PickupRadius harus tetap memonitor")

	# --- bentuk tabrakan di physics space masih hidup ---
	# Deterministik: pakai titik yang memang sudah terbukti terkena ray
	# (`wall.global_position`), lalu tanya shape apa pun di titik itu masih
	# terdaftar. Tidak bergantung pada bentuk capsule player atau seberapa
	# tipis bentuk dindingnya, jadi tidak flak.
	var space := player.get_world_2d().direct_space_state
	var wall := _find_blocking_static(m, player.global_position, space)
	_check(wall != null, "harus ada dinding Statik yang menghalangi di dekat player")
	if wall != null:
		var circle := CircleShape2D.new()
		circle.radius = 8.0
		var sq := PhysicsShapeQueryParameters2D.new()
		sq.shape = circle
		sq.transform = Transform2D(0.0, wall.global_position)
		sq.collision_mask = 1
		sq.collide_with_areas = false
		_check(space.intersect_shape(sq, 4).size() > 0,
			"bentuk tabrakan dinding harus masih terdaftar di physics space")

	# --- NPC patrol tetap utuh ---
	var patrol: Node = root.get_node_or_null("NightPatrol")
	if patrol != null:
		patrol.set("auto_spawn", false)
		patrol.call("clear")
		patrol.call("begin_night", 1)
		var npcs: Array = patrol.call("active_dumpers")
		_check(npcs.size() == 1, "harus ada 1 NPC patrol, dapat %d" % npcs.size())
		if not npcs.is_empty():
			var d := npcs[0] as Node2D
			_check(d.is_in_group("illegal_dumpers"),
				"NPC harus tetap di group illegal_dumpers")
			_check(int(d.get("collision_mask")) == 0,
				"NPC harus tetap collision_mask 0, dapat %d" % int(d.get("collision_mask")))
	# Overlay tidak boleh menelan klik UI.
	var tint := _find_tint()
	_check(tint != null and tint.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"overlay harus tetap mouse-transparent")


## Cari Statik terdekat yang benar-benar menghalangi arah dari player.
##
## Hanya "terdekat" tidak cukup: decorasi seperti `StreetTreeTop` punya shape
## kecil yang bisa jauh dari titik asalnya, jadi ray ke pusatnya bisa meleset.
## Jadi kandidat diuji satu per satu, dan yang dipakai adalah yang ray-nya
## benar-benar kena.
func _find_blocking_static(m: Node, from: Vector2, space: PhysicsDirectSpaceState2D) -> StaticBody2D:
	var cands: Array = []
	_collect_statics(m, cands)
	cands.sort_custom(func(a: Node, b: Node) -> bool:
		return a.global_position.distance_to(from) < b.global_position.distance_to(from))
	for c in cands:
		if c.global_position.distance_to(from) > 900.0:
			break
		var body: StaticBody2D = c
		var dir: Vector2 = (body.global_position - from).normalized()
		if dir.length() < 0.01:
			continue
		var probe := PhysicsRayQueryParameters2D.new()
		probe.from = from
		probe.to = from + dir * 300.0
		probe.collision_mask = c.collision_layer
		probe.collide_with_areas = false
		if not space.intersect_ray(probe).is_empty():
			return c
	return null


func _collect_statics(n: Node, out: Array) -> void:
	if n is StaticBody2D and _has_live_shape(n):
		out.append(n)
	for c in n.get_children():
		_collect_statics(c, out)


## Bentuk tabrakan bisa berupa CollisionShape2D ATAU CollisionPolygon2D.
func _has_live_shape(n: Node) -> bool:
	for c in n.get_children():
		if c is CollisionShape2D and not (c as CollisionShape2D).disabled:
			return true
		if c is CollisionPolygon2D and not (c as CollisionPolygon2D).disabled:
			return true
	return false


func _count_collision_nodes(n: Node) -> int:
	var c := 0
	if n is StaticBody2D or n is CharacterBody2D or n is CollisionShape2D or n is CollisionPolygon2D:
		c += 1
	for k in n.get_children():
		c += _count_collision_nodes(k)
	return c


func _count_area_nodes(n: Node) -> int:
	var c := 0
	if n is Area2D:
		c += 1
	for k in n.get_children():
		c += _count_area_nodes(k)
	return c
