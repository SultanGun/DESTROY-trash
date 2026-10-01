extends SceneTree

## Uji runtime untuk PatrolHUD (scripts/patrol_hud.gd + scenes/PatrolHUD.tscn).
##
## Harness headless tanpa framework test project:
##   godot --headless --path <project> --script res://tests/test_patrol_hud.gd
##
## Yang diuji:
##   1. Scene benar-benar punya script terpasang (guard anti-lolos-hampa).
##   2. Struktur: ada judul, label "TERTANGKAP n/2", dan tombol klaim.
##   3. Bar pollution dan bar aggregate "MEMBUANG" SUDAH HILANG.
##   4. Posisi: panel di kiri-tengah layar.
##   5. patrol_progress: "n/2" dari (caught, total), "TERTANGKAP -" saat total 0.
##   6. Tombol klaim: mati sebelum 2/2, hidup tepat di 2/2.
##   7. Klik tombol: memanggil claim_reward() NightPatrol, sekali saja.
##   8. Setelah diklaim: tombol mati lagi (lewat sinyal patrol_claimed).
##   9. Tanpa autoload NightPatrol tidak crash.
##  10. Tidak ada lagi jalur kode ke pollution.
##
## PENTING: HUD menyambung ke signal NightPatrol di dalam `_ready()`, jadi test
## TIDAK bisazypmeng-assign `_night_patrol` setelah HUD jadi. Stub harus
## dipasang sebagai `/root/NightPatrol` DULUAN, baru HUD di-instantiate —
## kalau tidak, test menguji handler yang tidak pernah terhubung dan semuanya
## lolos hampa.

const PatrolHUDScene := preload("res://scenes/PatrolHUD.tscn")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _hud: CanvasLayer = null

## Nama yang dipakai untuk autoload NightPatrol asli selama stub dipasang.
const REAL_PARKED := &"NightPatrolAsli"

## Stub NightPatrol: hanya menyiarkan signal dan mencatat claim_reward().
class ClaimStub:
	extends Node
	var calls := 0
	signal patrol_progress(caught: int, total: int)
	signal patrol_claimed()

	func claim_reward() -> bool:
		calls += 1
		return true


# ------------------------------------------------------------------ fixture
## Pasang stub NightPatrol sungguhan di /root, sembunyikan autoload asli.
## HARUS dipanggil sebelum `_make_hud()`.
func _install_stub_patrol() -> Node:
	_park_real_patrol()
	var s := ClaimStub.new()
	s.name = &"NightPatrol"
	root.add_child(s)
	return s


## Autoload NightPatrol milik project hidup di /root pada mode --script. Kalau
## tidak disingkirkan, HUD akan menyambung ke autoload asli, bukan ke stub, dan
## sinyal dari stub tidak pernah sampai.
func _park_real_patrol() -> void:
	var real := root.get_node_or_null(^"NightPatrol")
	if real != null:
		real.name = REAL_PARKED


func _restore_real_patrol() -> void:
	var parked := root.get_node_or_null(NodePath(REAL_PARKED))
	if parked != null:
		parked.name = &"NightPatrol"
	var stub := root.get_node_or_null(^"NightPatrol")
	if stub is ClaimStub:
		stub.free()


func _make_hud() -> CanvasLayer:
	if is_instance_valid(_hud):
		_hud.free()
	_hud = PatrolHUDScene.instantiate()
	_hud.name = "PatrolHUDUji"
	root.add_child(_hud)
	return _hud


func _teardown() -> void:
	_restore_real_patrol()
	if is_instance_valid(_hud):
		_hud.free()
	_hud = null
	await process_frame


func _run(label: String, fn: Callable) -> void:
	_fail = 0
	await fn.call()
	if _fail == 0:
		_pass += 1
		print("  LULUS  ", label)
	else:
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
	print("  lulus=%d  gagal=%d" % [_pass, _fail])
	if _fail > 0:
		print("  --- kegagalan ---")
		for f in _failures:
			print("  * ", f)
	print("===================================================")


func _initialize() -> void:
	await process_frame
	await _run("scene punya script terpasang", _test_script_attached)
	await _run("struktur: judul + label + tombol klaim", _test_structure)
	await _run("bar pollution dan bar MEMBUANG sudah hilang", _test_bars_removed)
	await _run("posisi: kiri-tengah", _test_left_center)
	await _run("minimize: panel jadi tab kecil lalu kembali", _test_minimize_toggle)
	await _run("progres: n/2 dan fallback '-' saat total 0", _test_progress_labels)
	await _run("klaim: tombol mati sebelum 2/2, hidup di 2/2", _test_claim_button_state)
	await _run("klaim: klik memanggil claim_reward, sekali saja", _test_claim_click)
	await _run("klaim: patrol_claimed ikut mengunci tombol", _test_claim_signal_locks)
	await _run("tanpa autoload NightPatrol tidak crash", _test_no_autoload)
	await _run("tidak lagi memakai pollution", _test_pollution_gone)
	await _teardown()
	_report()
	quit(0 if _fail == 0 else 1)


# -------------------------------------------------------------------- tests
## Guard paling penting di file ini. Scene TANPA script akan lolos semua
## assertion lain diam-diam, karena `hud.call("_on_...")` hanya jadi SCRIPT
## ERROR tanpa exception dan `_check` tetap hijau. Root scene harus punya
## patrol_hud.gd-nya terpasang - dan ini yang menguju kalau scene ditulis
## ulang tanpa baris `script = ExtResource(...)`.
func _test_script_attached() -> void:
	var hud := _make_hud()
	_check(hud.get_script() != null,
		"PatrolHUD harus punya script terpasang; kalau tidak semua test lain lolos hampa")
	_check(hud.has_method("_on_patrol_progress"),
		"PatrolHUD harus punya _on_patrol_progress")
	_check(hud.has_method("_on_patrol_claimed"),
		"PatrolHUD harus punya _on_patrol_claimed")


func _test_structure() -> void:
	_install_stub_patrol()
	var hud := _make_hud()
	var title := hud.get_node_or_null(^"Box/Title") as Label
	_check(title != null, "harus ada node Box/Title")
	if title != null:
		# Judul PENUH harus tampil: panel sengaja dibesarkan supaya kalimatnya
		# terbaca, bukan dipendekkan jadi satu kata.
		_check(title.text == "TANGKAP PEMBUANG SAMPAH",
			"judul harus 'TANGKAP PEMBUANG SAMPAH', dapat '%s'" % title.text)
	var caught := hud.get_node_or_null(^"Box/CaughtLabel") as Label
	_check(caught != null, "harus ada Box/CaughtLabel")
	if caught != null:
		_check(caught.text.begins_with("TERTANGKAP"),
			"label harus diawali TERTANGKAP, dapat '%s'" % caught.text)
	var btn := hud.get_node_or_null(^"Box/ClaimButton") as Button
	_check(btn != null, "harus ada Box/ClaimButton")
	if btn != null:
		_check(btn.text.find("KLAIM") != -1,
			"tombol harus menyebut KLAIM, dapat '%s'" % btn.text)
	_restore_real_patrol()


## Dua bar yang dulu ada harus benar-benar hilang dari scene. Kalau hanya
## disembunyikan, node-nya masih di tree dan test lama masih bisa "menemukan"
## sesuatu yang sudah tidak ada artinya.
func _test_bars_removed() -> void:
	_install_stub_patrol()
	var hud := _make_hud()
	for gone in ["Box/PollutionBar", "Box/DumpBar", "Box/PollutionBar/Box/Fill",
			"Box/DumpBar/Box/Fill"]:
		_check(hud.get_node_or_null(NodePath(gone)) == null,
			"%s harus sudah dihapus" % gone)
	var box := hud.get_node(^"Box")
	var leftovers: Array = []
	_collect_named(box, "PollutionBar", leftovers)
	_collect_named(box, "DumpBar", leftovers)
	_check(leftovers.is_empty(), "sisa bar: %s" % [leftovers])
	_restore_real_patrol()


func _collect_named(n: Node, needle: String, out: Array) -> void:
	if String(n.name).find(needle) != -1:
		out.append(n.name)
	for c in n.get_children():
		_collect_named(c, needle, out)


## Panel di kiri-tengah: anchor_x dekat 0, anchor_y 0.5. Ini yang diminta
## ("left-center"), dan yang membuatnya stabil di resolusi apa pun.
func _test_left_center() -> void:
	_install_stub_patrol()
	var hud := _make_hud()
	var box := hud.get_node(^"Box") as Control
	_check(is_equal_approx(box.anchor_left, 0.0),
		"anchor_left harus 0 (kiri), dapat %f" % box.anchor_left)
	_check(is_equal_approx(box.anchor_right, 0.0),
		"anchor_right harus 0, dapat %f" % box.anchor_right)
	_check(is_equal_approx(box.anchor_top, 0.5),
		"anchor_top harus 0.5 (tengah), dapat %f" % box.anchor_top)
	_check(is_equal_approx(box.anchor_bottom, 0.5),
		"anchor_bottom harus 0.5, dapat %f" % box.anchor_bottom)
	# Panel harus cukup besar supaya judul + angka + tombol muat tanpa saling
	# tumpang tindih, dan TIDAK gepeng. Yang dijaga: ada ruang untuk isi.
	var w := box.size.x
	var h := box.size.y
	_check(w >= 260.0, "lebar panel harus >= 260 agar isi terbaca, dapat %f" % w)
	_check(h >= 195.0, "tinggi panel harus >= 195, dapat %f" % h)
	# Tombol klaim harus muat di dalam panel, bukan meluber.
	var btn := hud.get_node(^"Box/ClaimButton") as Control
	_check(btn.position.y + btn.size.y <= box.size.y + 1.0,
		"tombol klaim harus di dalam panel (y=%f h=%f panel=%f)"
			% [btn.position.y, btn.size.y, box.size.y])
	# Judul tidak boleh menimpa tombol minimize.
	var minb := hud.get_node(^"Box/MinimizeButton") as Control
	var ttl := hud.get_node(^"Box/Title") as Control
	_check(not _overlaps(ttl, minb),
		"judul dan tombol minimize tidak boleh tumpang tindih")
	_restore_real_patrol()


func _overlaps(a: Control, b: Control) -> bool:
	var ra := Rect2(a.position, a.size)
	var rb := Rect2(b.position, b.size)
	return ra.intersects(rb)


## Angka HUD harus datang lewat SIGNAL NightPatrol, bukan lewat panggilan
## langsung ke handler. Kalau tesnya memanggil `hud.call("_on_patrol_progress")`,
## tes itu tidak membuktikan apa pun soal koneksi - dan koneksi itu justru
## bagian yang paling mudah rusak.
## Tombol minimize harus benar-benar mengubah panel jadi tab kecil, dan
## menekan lagi mengembalikannya ke ukuran penuh. Isi (judul, angka, status,
## tombol klaim) disembunyikan; tombol minimize sendiri TIDAK, supaya panel
## tidak pernah hilang total.
func _test_minimize_toggle() -> void:
	var stub := _install_stub_patrol()
	var hud := _make_hud()
	var box := hud.get_node(^"Box") as Control
	var minb := hud.get_node(^"Box/MinimizeButton") as Button
	var title := hud.get_node(^"Box/Title") as Label
	var caught := hud.get_node(^"Box/CaughtLabel") as Label
	var claim := hud.get_node(^"Box/ClaimButton") as Button
	var full_size := box.size
	_check(full_size.x >= 260.0, "ukuran penuh harus >= 260, dapat %f" % full_size.x)
	_check(not hud.call("is_minimized"), "panel harus mulai dalam keadaan penuh")

	# --- perkecil ---
	minb.pressed.emit()
	_check(hud.call("is_minimized"), "tombol harus menandai panel jadi kecil")
	_check(box.size.x < full_size.x,
		"lebar harus mengecil, dari %f jadi %f" % [full_size.x, box.size.x])
	_check(not caught.visible, "label TERTANGKAP harus disembunyikan saat kecil")
	_check(not claim.visible, "tombol klaim harus disembunyikan saat kecil")
	_check(minb.visible, "tombol minimize sendiri harus tetap terlihat")
	_check(minb.text == "+", "tombol harus berubah jadi '+', dapat '%s'" % minb.text)
	# Tab kecil harus tetap menulis progresnya sendiri.
	stub.emit_signal("patrol_progress", 1, 2)
	_check(title.visible, "tab kecil harus tetap menampilkan judul ringkas")
	_check(title.text == "1/2",
		"tab kecil harus menulis '1/2', dapat '%s'" % title.text)

	# --- perbesar ---
	minb.pressed.emit()
	_check(not hud.call("is_minimized"), "tekan kedua harus mengembalikan ukuran penuh")
	_check(is_equal_approx(box.size.x, full_size.x),
		"lebar harus kembali ke %f, dapat %f" % [full_size.x, box.size.x])
	_check(caught.visible, "label TERTANGKAP harus muncul lagi")
	_check(claim.visible, "tombol klaim harus muncul lagi")
	_check(minb.text == "–", "tombol harus kembali jadi '–', dapat '%s'" % minb.text)
	_check(title.text == "TANGKAP PEMBUANG SAMPAH",
		"judul penuh harus kembali, dapat '%s'" % title.text)
	_restore_real_patrol()


func _test_progress_labels() -> void:
	var stub := _install_stub_patrol()
	var hud := _make_hud()
	var caught := hud.get_node(^"Box/CaughtLabel") as Label
	# total 0 = siang / tidak ada rute.
	stub.emit_signal("patrol_progress", 0, 0)
	_check(caught.text == "TERTANGKAP -",
		"total 0 harus 'TERTANGKAP -', dapat '%s'" % caught.text)
	stub.emit_signal("patrol_progress", 0, 2)
	_check(caught.text == "TERTANGKAP 0/2",
		"harus 'TERTANGKAP 0/2', dapat '%s'" % caught.text)
	stub.emit_signal("patrol_progress", 1, 2)
	_check(caught.text == "TERTANGKAP 1/2",
		"harus 'TERTANGKAP 1/2', dapat '%s'" % caught.text)
	stub.emit_signal("patrol_progress", 2, 2)
	_check(caught.text == "TERTANGKAP 2/2",
		"harus 'TERTANGKAP 2/2', dapat '%s'" % caught.text)
	_restore_real_patrol()


func _test_claim_button_state() -> void:
	var stub := _install_stub_patrol()
	var hud := _make_hud()
	var btn := hud.get_node(^"Box/ClaimButton") as Button
	stub.emit_signal("patrol_progress", 0, 2)
	_check(btn.disabled, "tombol harus mati di 0/2")
	stub.emit_signal("patrol_progress", 1, 2)
	_check(btn.disabled, "tombol harus mati di 1/2")
	stub.emit_signal("patrol_progress", 2, 2)
	_check(not btn.disabled, "tombol harus hidup di 2/2")
	# Malam tanpa rute: tidak ada yang bisa diklaim.
	stub.emit_signal("patrol_progress", 0, 0)
	_check(btn.disabled, "tombol harus mati saat total 0")
	_restore_real_patrol()


## Klik tombol harus benar-benar memanggil claim_reward() pada NightPatrol.
## Diuji dengan stub yang mencatat panggilan, supaya tidak bergantung pada
## ekonomi sungguhan.
func _test_claim_click() -> void:
	var stub := _install_stub_patrol()
	var hud := _make_hud()
	var btn := hud.get_node(^"Box/ClaimButton") as Button
	stub.emit_signal("patrol_progress", 2, 2)
	_check(not btn.disabled, "prasyarat: tombol harus hidup di 2/2")
	btn.pressed.emit()
	_check(int(stub.get("calls")) == 1,
		"tombol harus memanggil claim_reward sekali, dapat %d" % int(stub.get("calls")))
	btn.pressed.emit()
	_check(int(stub.get("calls")) == 1,
		"klik kedua tidak boleh memanggil lagi, dapat %d" % int(stub.get("calls")))
	_restore_real_patrol()


## Path kedua: NightPatrol memancarkan patrol_claimed (mis. klaim di-resolve
## dari jalur lain). Tombol harus ikut mati tanpa perlu diklik.
func _test_claim_signal_locks() -> void:
	var stub := _install_stub_patrol()
	var hud := _make_hud()
	var btn := hud.get_node(^"Box/ClaimButton") as Button
	stub.emit_signal("patrol_progress", 2, 2)
	_check(not btn.disabled, "prasyarat: tombol harus hidup di 2/2")
	stub.emit_signal("patrol_claimed")
	_check(btn.disabled, "setelah patrol_claimed tombol harus mati")
	var caught := hud.get_node(^"Box/CaughtLabel") as Label
	_check(caught.text == "TERTANGKAP 2/2",
		"label tetap 2/2 setelah klaim, dapat '%s'" % caught.text)
	_restore_real_patrol()


func _test_no_autoload() -> void:
	# HUD harus aman kalau NightPatrol tidak ada di /root sama sekali.
	_park_real_patrol()
	var hud := _make_hud()
	_check(hud.get("_night_patrol") == null,
		"HUD harus scouting jalan tanpa NightPatrol, bukan crash di _ready")
	var caught := hud.get_node(^"Box/CaughtLabel") as Label
	_check(caught.text == "TERTANGKAP -",
		"tanpa autoload label harus fallback '-', dapat '%s'" % caught.text)
	var btn := hud.get_node(^"Box/ClaimButton") as Button
	btn.pressed.emit()  # patrol null: tidak boleh crash
	_check(true, "klik tanpa NightPatrol tidak crash")
	_restore_real_patrol()


## Pollution dicabut dari game; HUD tidak boleh punya jalur kode ke sana.
func _test_pollution_gone() -> void:
	_install_stub_patrol()
	var hud := _make_hud()
	for gone in ["_on_pollution_changed", "_pollution_fill", "_pollution_label",
			"_dump_fill", "_dump_label", "_on_dump_progress", "_game_manager"]:
		_check(not _has_member(hud, gone),
			"HUD tidak boleh punya %s lagi" % gone)
	_restore_real_patrol()


func _has_member(obj: Object, name: String) -> bool:
	for m in obj.get_property_list():
		if String(m.get("name", "")) == name:
			return true
	var scr: Script = obj.get_script() as Script
	if scr == null:
		return false
	for s in scr.get_script_method_list():
		if String(s.get("name", "")) == name:
			return true
	return false
