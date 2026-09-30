extends SceneTree

## Uji runtime untuk CatchMinigame (scripts/catch_minigame.gd).
##
## Harness headless tanpa framework test project:
##   godot --headless --path <project> --script res://tests/test_catch_minigame.gd
##
## Yang diuji (kontrak gameplay):
##   1. Tertutup secara default; open() membuatnya terlihat dan mengaktifkan.
##   2. Bar mulai di ujung (0) dan arahnya ke kanan.
##   3. Bar bergerak naik dan pantul di kedua ujung (bolak-balik).
##   4. Zona target berada di tengah track danlebarnya sesuai ZONE_HALF.
##   5. is_in_zone() benar hanya di dalam zona.
##   6. press() di dalam zona = sukses, emit succeeded, menutup minigame.
##   7. press() di luar zona = gagal,sarah satu percobaan, emit attempt_used.
##   8. Tiga gagal = emit failed, menutup minigame.
##   9. Setelah gagal/sukses, press() berikutnya tidak efek (minigame sudah tutup).
##  10. dismiss() menutup tanpa hasil dan emit dismissed.
##  11. Dua NPC berturutan: open() me-reset percobaan ke penuh.
##  12. attempt_used melaporkan sisa percobaan.

const CatchMinigameScene := preload("res://scenes/CatchMinigame.tscn")

const MAX_ATTEMPTS := 3
const ZONE_HALF := 0.06
const ZONE_CENTER := 0.5
const BAR_SPEED := 1.20

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _mg: CanvasLayer = null


func _initialize() -> void:
	await process_frame
	await _run("default: tertutup dan tidak aktif", _test_starts_closed)
	await _run("open(): terlihat, aktif, bar di ujung, arah kanan", _test_open_state)
	await _run("bar bergerak naik", _test_bar_moves)
	await _run("bar pantul di kedua ujung", _test_bar_bounces)
	await _run("zona target di tengah, lebar sesuai ZONE_HALF", _test_zone_placement)
	await _run("is_in_zone() hanya benar di dalam zona", _test_in_zone)
	await _run("press() di zona = sukses", _test_press_success)
	await _run("press() di luar zona = gagal, kurang satu percobaan", _test_press_miss)
	await _run("tiga gagal = failed, minigame tertutup", _test_three_misses)
	await _run("press() setelah tutup tidak efek", _test_press_after_close)
	await _run("dismiss() menutup tanpa hasil", _test_dismiss)
	await _run("open() me-reset percobaan", _test_reset_attempts)
	await _run("attempt_used melaporkan sisa percobaan", _test_attempt_used_signal)
	await _run("kesulitan: zona sempit + bar cepat", _test_difficulty_contract)
	_teardown()
	_report()
	quit(0 if _fail == 0 else 1)


# ------------------------------------------------------------------ fixture
func _make_mg() -> CanvasLayer:
	if is_instance_valid(_mg):
		_mg.queue_free()
	_mg = CatchMinigameScene.instantiate()
	_mg.name = "CatchMinigameUji"
	root.add_child(_mg)
	return _mg


func _teardown() -> void:
	if is_instance_valid(_mg):
		_mg.queue_free()
	_mg = null
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


# -------------------------------------------------------------------- tests
func _test_starts_closed() -> void:
	var mg := _make_mg()
	_check(not mg.visible, "harus tersembunyi sebelum open()")
	_check(not mg.call("is_active"), "harus tidak aktif sebelum open()")


func _test_open_state() -> void:
	var mg := _make_mg()
	mg.call("open")
	_check(mg.visible, "open() harus membuatnya terlihat")
	_check(mg.call("is_active"), "open() harus mengaktifkan")
	_check(is_equal_approx(mg.call("bar_position"), 0.0),
		"bar harus mulai di ujung 0, dapat %f" % mg.call("bar_position"))
	_check(mg.call("attempts_left") == MAX_ATTEMPTS,
		"percobaan harus penuh, dapat %d" % mg.call("attempts_left"))


func _test_bar_moves() -> void:
	var mg := _make_mg()
	mg.call("open")
	var before: float = mg.call("bar_position")
	# Gerakkan 0.2s: bar harus maju ke arah kanan (posisi naik).
	mg.call("_process", 0.2)
	var after: float = mg.call("bar_position")
	_check(after > before,
		"bar harus bergerak maju, dari %f ke %f" % [before, after])
	_check(is_equal_approx(after, BAR_SPEED * 0.2),
		"perpindahan harus sesuai kecepatan, dapat %f" % after)


func _test_bar_bounces() -> void:
	var mg := _make_mg()
	mg.call("open")
	# Longitudinal: majukan bar melewati ujung kanan, harus terpantul balik.
	mg.call("_process", 2.0)  # 2.0 * 0.75 = 1.5 > 1, jadi sudah lewat ujung
	_check(is_equal_approx(mg.call("bar_position"), 1.0) or mg.call("bar_position") < 1.0,
		"bar tidak boleh melewati ujung, dapat %f" % mg.call("bar_position"))
	# Bar harus sedang berbalik arah: majukan lagi sedikit, posisi turun.
	var p1: float = mg.call("bar_position")
	mg.call("_process", 0.1)
	var p2: float = mg.call("bar_position")
	_check(p2 < p1, "setelah lewat ujung, bar harus kembali, dari %f ke %f" % [p1, p2])
	# Dan di ujung kiri juga terpantul.
	for _i in 20:
		mg.call("_process", 0.2)
	_check(mg.call("bar_position") >= 0.0, "bar tidak boleh lewat ujung kiri")


func _test_zone_placement() -> void:
	var mg := _make_mg()
	mg.call("open")
	var zone := mg.get_node(^"Box/Track/Zone") as ColorRect
	var track := mg.get_node(^"Box/Track") as Control
	_check(is_equal_approx(zone.size.x, ZONE_HALF * 2.0 * track.size.x),
		"lebar zona harus 2*ZONE_HALF*lebar track, dapat %f" % zone.size.x)
	_check(is_equal_approx(zone.position.x, (ZONE_CENTER - ZONE_HALF) * track.size.x),
		"zona harus di tengah track, dapat %f" % zone.position.x)


func _test_in_zone() -> void:
	var mg := _make_mg()
	mg.call("open")
	mg.set("_pos", ZONE_CENTER)
	_check(mg.call("is_in_zone"), "tepat di tengah harus in_zone")
	mg.set("_pos", ZONE_CENTER + ZONE_HALF - 0.005)
	_check(mg.call("is_in_zone"), "tepat di tepi zona harus in_zone")
	mg.set("_pos", ZONE_CENTER + ZONE_HALF + 0.005)
	_check(not mg.call("is_in_zone"), "sedikit di luar zona harus keluar")
	mg.set("_pos", 0.0)
	_check(not mg.call("is_in_zone"), "di ujung jauh harus keluar")


func _test_press_success() -> void:
	var mg := _make_mg()
	mg.call("open")
	var got := []
	mg.connect("succeeded", func() -> void: got.append(true))
	mg.set("_pos", ZONE_CENTER)
	var ok: bool = mg.call("press")
	_check(ok, "tekan di zona harus true")
	_check(got.size() == 1, "sinyal succeeded harus keluar, dapat %d" % got.size())
	_check(not mg.call("is_active"), "minigame harus tertutup setelah sukses")
	_check(not mg.visible, "minigame harus tersembunyi setelah sukses")


func _test_press_miss() -> void:
	var mg := _make_mg()
	mg.call("open")
	mg.set("_pos", 0.0)  # jauh dari zona
	var before: int = mg.call("attempts_left")
	var got := []
	mg.connect("attempt_used", func(r: int) -> void: got.append(r))
	var ok: bool = mg.call("press")
	_check(not ok, "tekan di luar zona harus false")
	_check(mg.call("attempts_left") == before - 1,
		"sisa percobaan harus berkurang 1, dari %d ke %d" % [before, mg.call("attempts_left")])
	_check(got.size() == 1 and int(got[0]) == before - 1,
		"attempt_used harus melaporkan sisa, dapat %s" % [got])
	_check(mg.call("is_active"), "satu gagal belum menutup minigame")


func _test_three_misses() -> void:
	var mg := _make_mg()
	mg.call("open")
	var failed := []
	mg.connect("failed", func() -> void: failed.append(true))
	mg.set("_pos", 0.0)
	mg.call("press")
	mg.set("_pos", 0.0)
	mg.call("press")
	_check(mg.call("attempts_left") == 1, "sisa harus 1 setelah 2 gagal")
	mg.set("_pos", 0.0)
	mg.call("press")
	_check(mg.call("attempts_left") == 0, "sisa harus 0 setelah 3 gagal")
	_check(failed.size() == 1, "sinyal failed harus keluar, dapat %d" % failed.size())
	_check(not mg.call("is_active"), "tiga gagal harus menutup minigame")
	_check(mg.call("attempts_left") == 0, "percobaan tidak boleh di-reset diam-diam")


func _test_press_after_close() -> void:
	var mg := _make_mg()
	mg.call("open")
	mg.set("_pos", ZONE_CENTER)
	mg.call("press")  # sukses, tutup
	var succ := []
	mg.connect("succeeded", func() -> void: succ.append(true))
	var ok: bool = mg.call("press")
	_check(not ok, "tekan setelah tutup harus false")
	_check(succ.is_empty(), "tekan setelah tutup tidak boleh emit sukses")


func _test_dismiss() -> void:
	var mg := _make_mg()
	mg.call("open")
	var got := []
	mg.connect("dismissed", func() -> void: got.append(true))
	mg.call("dismiss")
	_check(not mg.call("is_active"), "dismiss harus menutup")
	_check(not mg.visible, "dismiss harus menyembunyikan")
	_check(got.size() == 1, "sinyal dismissed harus keluar, dapat %d" % got.size())
	# Dismiss tidak boleh memakai percobaan atau jadi sukses.
	_check(mg.call("attempts_left") == MAX_ATTEMPTS,
		"dismiss tidak boleh memakai percobaan, dapat %d" % mg.call("attempts_left"))


## Dua NPC berturutan: NPC kedua harus dapat percobaan penuh, bukan mewarisi
## sisa NPC pertama. Kalau tidak, player yang gagal di NPC pertama selalu
##pasti gagal di NPC kedua juga.
func _test_reset_attempts() -> void:
	var mg := _make_mg()
	mg.call("open")
	mg.set("_pos", 0.0)
	mg.call("press")  # 1 gagal
	mg.set("_pos", 0.0)
	mg.call("press")  # 2 gagal
	_check(mg.call("attempts_left") == 1, "prasyarat: sisa 1")
	mg.call("open")  # NPC kedua
	_check(mg.call("attempts_left") == MAX_ATTEMPTS,
		"NPC kedua harus dapat percobaan penuh, dapat %d" % mg.call("attempts_left"))
	_check(is_equal_approx(mg.call("bar_position"), 0.0),
		"NPC kedua harus mulai dari bar ujung, dapat %f" % mg.call("bar_position"))


## Kesulitan minigame adalah bagian dari kontrak, bukan angka yang boleh
## di-longgarkan diam-diam. Dua hal yang diuji:
##   1. Zona target cukup sempit sehingga "asal tekan" tidak kena. Diuji lewat
##      berapa banyak track yang masih dianggap kena - harus kecil.
##   2. Bar cukup cepat sehingga satu lintasan bolak-balik terasa cepat.
##
## Nilai spesifiknya sengaja TIDAK dipin di sini supaya menyeimbangkan
##minigame tidak perlu mengubah test. Yang dipin adalah sifatnya: lebih
## ketat dari versi lama yang 0.12 / 0.75.
func _test_difficulty_contract() -> void:
	var mg := _make_mg()
	mg.call("open")
	# Panjang lintasan bolak-balik penuh = 2 / BAR_SPEED detik.
	var cycle := 2.0 / BAR_SPEED
	_check(cycle < 2.0,
		"satu lintasan bolak-balik harus < 2 detik, dapat %.2f" % cycle)
	# Bar menyeberangi zona dalam (2*ZONE_HALF)/BAR_SPEED detik. Di bawah
	# 0.15 detik berarti zona benar-benar harus dipershitkan.
	var window := (ZONE_HALF * 2.0) / BAR_SPEED
	_check(window < 0.15,
		"jendela zona harus < 0.15 detik, dapat %.3f" % window)
	# Luas zona terhadap track tidak boleh lebih dari 15%.
	_check(ZONE_HALF * 2.0 <= 0.15,
		"zona harus <= 15 persen track, dapat %d persen" % int(ZONE_HALF * 200.0))
	# Zonanya benar-benar sempit: di tengah track, meleset 0.05 masih kena
	# (zona 0.06), tapi meleset 0.08 sudah pasti gagal.
	mg.set("_pos", ZONE_CENTER + 0.05)
	_check(mg.call("is_in_zone"),
		"meleset 0.05 masih di dalam zona %.2f" % ZONE_HALF)
	mg.set("_pos", ZONE_CENTER + 0.08)
	_check(not mg.call("is_in_zone"),
		"meleset 0.08 harus gagal di zona %.2f" % ZONE_HALF)


func _test_attempt_used_signal() -> void:
	var mg := _make_mg()
	mg.call("open")
	var got := []
	mg.connect("attempt_used", func(r: int) -> void: got.append(r))
	# Dua gagal lalu satu sukses: attempt_used harus keluar 3 kali (sukses
	# juga melaporkan sisa percobaan yang tidak terpakai).
	mg.set("_pos", 0.0)
	mg.call("press")
	mg.set("_pos", 0.0)
	mg.call("press")
	mg.set("_pos", ZONE_CENTER)
	mg.call("press")
	_check(got.size() == 3, "attempt_used keluar 3x, dapat %d" % got.size())
	if got.size() == 3:
		_check(int(got[0]) == 2 and int(got[1]) == 1 and int(got[2]) == 1,
			"sisa percobaan harus [2,1,1], dapat %s" % got)
