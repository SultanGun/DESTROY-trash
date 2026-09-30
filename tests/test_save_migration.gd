extends SceneTree

## Uji runtime untuk SaveMigration (scripts/save_migration.gd).
##
## Harness headless tanpa framework test project:
##   godot --headless --path <project> --script res://tests/test_save_migration.gd
##
## Yang diuji (kontrak save v1 -> v3, murni tanpa autoload):
##   1. Versi save saat ini = 3.
##   2. v3: peta dibaca apa adanya, TIDAK ada pollution di hasil normalize.
##   3. v1: peta 1 — WAJUH mengabaikan key current_map yang nyasar di save v1.
##   4. Key "version" hilang diperlakukan sebagai v1.
##   5. Save v2 (yang masih punya pollution) TETAP bisa dibaca: pollution
##      diabaikan, peta tetap dipakai. Ini yang menjaga save lama player.
##   6. current_map di luar peta yang dikenal jatuh ke peta 1.
##   7. Versi di masa depan (>= 3) tetap dibaca dengan layout v3.
##   8. Nilai non-bulat dikonversi ke int, nilai rusak jadi fallback.
##   9. stamp() tidak menulis pollution sama sekali.
##
## Modul ini sengaja stateless + static supaya bisa diuji tanpa autoload
## GameManager/NightPatrol di tree (mode --script memang tidak memuat autoload).

const SaveMigration := preload("res://scripts/save_migration.gd")

const CURRENT_VERSION := 3
const FALLBACK_MAP := 1

var _pass := 0
var _fail := 0
var _failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	await _run("versi save saat ini = 3", _test_current_version)
	await _run("v3: peta dibaca apa adanya, pollution hilang", _test_v3_reads_fields)
	await _run("v1: peta 1, key nyasar diabaikan", _test_v1_defaults)
	await _run("version hilang = v1", _test_missing_version_is_v1)
	await _run("save v2 lama: pollution diabaikan, peta dipakai", _test_legacy_v2)
	await _run("current_map tak dikenal jatuh ke peta 1", _test_bad_map_falls_back)
	await _run("versi masa depan tetap pakai layout v3", _test_forward_version)
	await _run("nilai rusak jadi fallback, bukan crash", _test_junk_values)
	await _run("stamp: hanya version + peta, tanpa pollution", _test_stamp_shape)
	_report()
	quit(0 if _fail == 0 else 1)


## --- test -----------------------------------------------------------------

func _test_current_version() -> void:
	_check(SaveMigration.CURRENT_VERSION == CURRENT_VERSION,
		"CURRENT_VERSION harus %d, dapat %d" % [CURRENT_VERSION, SaveMigration.CURRENT_VERSION])


## Pollution tidak boleh muncul lagi di hasil normalize sama sekali. Kalau
## masih ada, `_apply_data` akan terus membacanya dan GameManager harus
## menyimpan field yang sudah dihapus dari game.
func _test_v3_reads_fields() -> void:
	var r := SaveMigration.normalize({"version": 3, "current_map": 2})
	_check(r.current_map == 2, "current_map harus 2, dapat %s" % r.current_map)
	_check(r.version == 3, "version harus 3, dapat %s" % r.version)
	_check(not r.has("pollution"), "normalize tidak boleh mengembalikan key pollution")


func _test_v1_defaults() -> void:
	# Save v1 SENGAJA diberi key current_map di sini: key itu ga pernah ada di
	# v1, jadi kalau migrasi membacanya, save v1 half-written akan diam-diam
	# MEMBAWA peta palsu ke permainan.
	var r := SaveMigration.normalize({
		"version": 1, "coins": 30, "current_map": 2,
	})
	_check(r.version == 1, "version harus 1, dapat %s" % r.version)
	_check(r.current_map == FALLBACK_MAP,
		"v1 current_map harus %d, dapat %s" % [FALLBACK_MAP, r.current_map])


func _test_missing_version_is_v1() -> void:
	var r := SaveMigration.normalize({"coins": 12, "day": 3})
	_check(r.version == 1, "version hilang harus jadi 1, dapat %s" % r.version)
	_check(r.current_map == FALLBACK_MAP,
		"version hilang current_map harus %d, dapat %s" % [FALLBACK_MAP, r.current_map])


## Save v2 milik player lama yang sudah tercatat di disk. Kunci `pollution` di
## dalamnya harus diabaikan TANPA error, dan peta yang tersimpan harus tetap
## dipakai. Kalau test ini gagal, save lama player tidak bisa dimuat lagi.
func _test_legacy_v2() -> void:
	var r := SaveMigration.normalize({
		"version": 2, "coins": 250, "pollution": 84, "current_map": 2,
	})
	_check(r.version == 2, "version v2 harus dipertahankan, dapat %s" % r.version)
	_check(r.current_map == 2, "peta dari save v2 harus dipakai, dapat %s" % r.current_map)
	_check(not r.has("pollution"), "pollution v2 harus diabaikan, bukan diteruskan")
	# Pollution di luar rentang di file v2 juga harus tetap harmless.
	var hi := SaveMigration.normalize({"version": 2, "pollution": 150, "current_map": 1})
	_check(not hi.has("pollution"), "pollution 150 di save v2 harus diabaikan")


func _test_bad_map_falls_back() -> void:
	for bad in [0, 3, 99, -1]:
		var r := SaveMigration.normalize({"version": 3, "current_map": bad})
		_check(r.current_map == FALLBACK_MAP,
			"current_map %s harus jatuh ke %d, dapat %s" % [bad, FALLBACK_MAP, r.current_map])


func _test_forward_version() -> void:
	# Save dari versi yang lebih baru harus tetap bisa dibaca dengan layout v3,
	# bukan ditolak atau di-default ke v1.
	var r := SaveMigration.normalize({"version": 9, "current_map": 2})
	_check(r.version == 9, "version harus 9, dapat %s" % r.version)
	_check(r.current_map == 2, "current_map harus 2, dapat %s" % r.current_map)


func _test_junk_values() -> void:
	var r := SaveMigration.normalize({
		"version": 3,
		"current_map": "dua",
	})
	_check(r.current_map == FALLBACK_MAP,
		'current_map "dua" harus %d, dapat %s' % [FALLBACK_MAP, r.current_map])
	var no_version := SaveMigration.normalize({"current_map": "abc"})
	_check(no_version.current_map == FALLBACK_MAP,
		'current_map "abc" tanpa version harus %d' % FALLBACK_MAP)


## Bentuk file yang ditulis ke disk. Pollution tidak boleh ikut: kalau masih
## ditulis, save baru akan membawa kunci mati yang tidak pernah dibaca.
func _test_stamp_shape() -> void:
	var s := SaveMigration.stamp(2)
	_check(s.version == CURRENT_VERSION,
		"stamp version harus %d, dapat %s" % [CURRENT_VERSION, s.version])
	_check(s.current_map == 2, "stamp current_map harus 2, dapat %s" % s.current_map)
	_check(not s.has("pollution"), "stamp tidak boleh menulis pollution")
	var bad := SaveMigration.stamp(9)
	_check(bad.current_map == FALLBACK_MAP,
		"stamp peta ngawur harus jatuh ke %d, dapat %s" % [FALLBACK_MAP, bad.current_map])


## --- harness --------------------------------------------------------------

func _run(label: String, fn: Callable) -> void:
	var before := _fail
	await fn.call()
	if _fail == before:
		_pass += 1
		print("  LULUS  ", label)
	else:
		print("  GAGAL  ", label)


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
