extends SceneTree

## Round-trip save v2 lewat jalur disk sungguhan (user://).
##
## test_save_migration.gd menguji normalize()/stamp() sebagai fungsi murni --
## fast, tapi tidak pernah menyentuh file. File ini menutup celah yang belum
## ada: save ditulis ke disk sungguhan, dibaca lagi lewat read_slot(),
## lalu diterapkan ke dunia nyata lewat apply_slot(). Bug yang paling
##-exposed di game ini (current_slot geser, JSON half-written, apply yang
## diam-diam tidak mengembalikan apa pun) hanya terlihat di jalur ini.
##
## Keamanan data: slot yang dipakai test di-backup dulu dan dipulihkan di
## akhir, jadi file save asli pemain tidak hilang atau tertimpa.

const TimeManagerScript := preload("res://scripts/time_manager.gd")

## Slot yang dipakai. Dua slot, dipulihkan persis seperti semula.
const SLOT_A := 1
const SLOT_B := 2

## Node2D dummy dengan satu properti `inventory`. Sengaja bukan Player.tscn
## sungguhan: _ready() player membangun InventoryUI + HUD, yang menarik
## banyak skrip UI ke dalam compile test ini. Yang diuji di sini kontrak
## save-nya, bukan UI.
const StubPlayerSource := """
extends Node2D
var inventory
"""

## Nilai yang harus pulih persis setelah apply. Dipilih yang tidak ambigu:
## bukan 0, bukan default, bukan pembulatan.
const GOLD := {
	"coins": 37,
	"day": 5,
	"current_time": 1234.5,
	"seconds_per_game_hour": 33.0,
	"map": 2,
	"pos": Vector2(321.0, 654.0),
	"capacity": 7,
	# Lifetime counter. Dipilih jauh dari total buffer (9+1=10) supaya assertion
	# membuktikan nilai dipulihkan apa adanya, bukan dihitung ulang dari buffer.
	"recycled_total": 777,
}

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
## slot -> {"existed": bool, "text": String}
var _backup: Dictionary = {}
var _player: Node2D = null
var _tm: Node = null


func _initialize() -> void:
	await process_frame
	_backup_slot(SLOT_A)
	_backup_slot(SLOT_B)
	await _build_world()
	await _run("disk: save v2 ditulis dan dibaca kembali utuh", _test_write_read)
	await _run("disk: apply mengembalikan dunia ke state tersimpan", _test_apply_restores_world)
	await _run("disk: save v1 di disk dimigrasi ke peta 1", _test_v1_on_disk)
	await _run("disk: save v2 lama (punya pollution) tetap bisa di-load", _test_legacy_v2_on_disk)
	await _run("disk: file korup ditolak tanpa merusak dunia", _test_corrupt_file)
	_restore_all()
	_teardown()
	_report()
	quit(0 if _fail == 0 else 1)


# --------------------------------------------------------------------- harness
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


# ------------------------------------------------------------------- autoload
## Autoload hidup di mode --script; diambil lewat /root/ dengan nama eksplisit
## supaya test ini gagal keras kalau nama autoload berubah.
func _gd() -> Node:
	return root.get_node("GameData")


func _gm() -> Node:
	return root.get_node("GameManager")


func _sl() -> Node:
	return root.get_node("SaveLoad")


func _np() -> Node:
	return root.get_node("NightPatrol")


# -------------------------------------------------------------------- fixture
func _build_world() -> void:
	var scr := GDScript.new()
	scr.source_code = StubPlayerSource
	scr.reload()
	_player = Node2D.new()
	_player.set_script(scr)
	_player.name = "StubPlayer"
	_player.inventory = Inventory.new()
	root.add_child(_player)
	_player.add_to_group("player")

	_tm = TimeManagerScript.new()
	_tm.name = "TimeManagerStub"
	root.add_child(_tm)

	# Static var global: mulai dari kondisi terbuang supaya test tidak bisa
	# lulus hampa karena sisa nilai run sebelumnya.
	_sl().set("current_slot", 0)
	_sl().set("pending_slot", -1)


func _teardown() -> void:
	for n in [_player, _tm]:
		if is_instance_valid(n):
			n.free()
	_player = null
	_tm = null


## Set dunia ke kondisi GOLD, supaya gather_data() punya sumber yang dikenal.
func _seed_gold() -> void:
	_gm().set_coins(int(GOLD.coins))
	_tm.set("day", int(GOLD.day))
	_tm.set("current_time", float(GOLD.current_time))
	_tm.set("seconds_per_game_hour", float(GOLD.seconds_per_game_hour))
	_np().set_current_map(int(GOLD.map))
	_player.global_position = GOLD.pos
	var inv: Inventory = _player.inventory
	inv.set_capacity(int(GOLD.capacity))
	inv.stocks = {"pisang": 4, "sedotan": 2}
	_gd().set("sorted", {"pisang": 9, "sedotan": 1})
	_gd().set("sorted_organic", 9)
	_gd().set("sorted_anorganic", 1)
	_gd().set("recycled_total", int(GOLD.recycled_total))


## Rusak dunia dengan nilai yang pasti berbeda dari GOLD, supaya apply yang
## diam-diam tidak jalan akan ketahuan.
func _clobber_world() -> void:
	_gm().set_coins(0)
	_tm.set("day", 99)
	_tm.set("current_time", 0.0)
	_tm.set("seconds_per_game_hour", 999.0)
	_np().set_current_map(1)
	_player.global_position = Vector2(-50.0, -50.0)
	var inv: Inventory = _player.inventory
	inv.set_capacity(1)
	inv.stocks = {}
	_gd().set("sorted", {})
	_gd().set("sorted_organic", 0)
	_gd().set("sorted_anorganic", 0)
	_gd().set("recycled_total", 42)


# ------------------------------------------------------------------- backups
func _slot_path(slot: int) -> String:
	return _sl().call("slot_path", slot)


func _backup_slot(slot: int) -> void:
	var path := _slot_path(slot)
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		_backup[slot] = {"existed": true, "text": f.get_as_text()}
		f.close()
	else:
		_backup[slot] = {"existed": false, "text": ""}


func _restore_all() -> void:
	for slot in _backup:
		var entry: Dictionary = _backup[slot]
		var path := _slot_path(slot)
		if entry.existed:
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_string(String(entry.text))
			f.close()
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _write_raw(slot: int, text: String) -> void:
	var f := FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	f.store_string(text)
	f.close()


# ---------------------------------------------------------------------- tests
func _test_write_read() -> void:
	_seed_gold()
	_sl().set("current_slot", 0)
	if not _check(_sl().call("save_slot", SLOT_A),
			"save_slot(%d) harus berhasil" % SLOT_A):
		return
	_check(_sl().call("has_save", SLOT_A), "has_save harus true setelah tulis")

	var back: Dictionary = _sl().call("read_slot", SLOT_A)
	_check(not back.is_empty(), "read_slot tidak boleh kosong")
	if back.is_empty():
		return
	_check(int(back.get("version", -1)) == 3,
		"version di disk harus 3, dapat %s" % back.get("version"))
	_check(not back.has("pollution"),
		"pollution tidak boleh ditulis ke disk lagi (v3)")
	_check(int(back.get("current_map", -1)) == int(GOLD.map),
		"current_map di disk harus %d, dapat %s" % [GOLD.map, back.get("current_map")])
	_check(int(back.get("coins", -1)) == int(GOLD.coins),
		"coins di disk harus %d, dapat %s" % [GOLD.coins, back.get("coins")])
	_check(int(back.get("day", -1)) == int(GOLD.day),
		"day di disk harus %d, dapat %s" % [GOLD.day, back.get("day")])
	# Field harus benar-benar ada di file, bukan hanya default saat baca.
	_check(back.has("recycled_total"),
		"gather_data() harus menulis key recycled_total")
	_check(int(back.get("recycled_total", -1)) == int(GOLD.recycled_total),
		"recycled_total di disk harus %d, dapat %s" % [GOLD.recycled_total, back.get("recycled_total")])
	_check(is_equal_approx(float(back.get("current_time", -1.0)), float(GOLD.current_time)),
		"current_time di disk harus %s, dapat %s" % [GOLD.current_time, back.get("current_time")])
	_check(int(back.get("inventory_capacity", -1)) == int(GOLD.capacity),
		"inventory_capacity di disk harus %d, dapat %s" % [GOLD.capacity, back.get("inventory_capacity")])
	var stocks: Dictionary = back.get("inventory_stocks", {})
	_check(int(stocks.get("pisang", -1)) == 4 and int(stocks.get("sedotan", -1)) == 2,
		"inventory_stocks harus ikut_disk, dapat %s" % stocks)
	# current_slot harus bergeser ke slot yang ditulis -- ini yang dipakai
	# SaveMenu untuk menentukan slot aktif setelah load.
	_check(int(_sl().get("current_slot")) == SLOT_A,
		"current_slot harus %d setelah tulis, dapat %s"
		% [SLOT_A, _sl().get("current_slot")])


func _test_apply_restores_world() -> void:
	# Pakai GOLD sebagai save aktif, lalu hancurkan dunia.
	_seed_gold()
	_sl().call("save_slot", SLOT_A)
	_clobber_world()
	_check(int(_gm().coins) == 0, "prasyarat: dunia harus sudah dikacaukan")
	if not _check(_sl().call("apply_slot", SLOT_A), "apply_slot harus mengembalikan true"):
		return
	_check(int(_gm().coins) == int(GOLD.coins),
		"coins harus %d, dapat %d" % [GOLD.coins, _gm().coins])
	_check(int(_tm.day) == int(GOLD.day),
		"day harus %d, dapat %d" % [GOLD.day, _tm.day])
	_check(is_equal_approx(float(_tm.current_time), float(GOLD.current_time)),
		"current_time harus %s, dapat %s" % [GOLD.current_time, _tm.current_time])
	_check(is_equal_approx(float(_tm.seconds_per_game_hour), float(GOLD.seconds_per_game_hour)),
		"seconds_per_game_hour harus %s, dapat %s"
		% [GOLD.seconds_per_game_hour, _tm.seconds_per_game_hour])
	_check(int(_np().get("current_map")) == int(GOLD.map),
		"current_map harus %d, dapat %s" % [GOLD.map, _np().get("current_map")])
	_check(_player.global_position.distance_to(GOLD.pos) < 0.01,
		"posisi harus %s, dapat %s" % [GOLD.pos, _player.global_position])
	var inv: Inventory = _player.inventory
	_check(inv.capacity == int(GOLD.capacity),
		"capacity harus %d, dapat %d" % [GOLD.capacity, inv.capacity])
	_check(int(inv.stocks.get("pisang", -1)) == 4,
		"stocks.pisang harus 4, dapat %s" % inv.stocks.get("pisang"))
	# apply harus sync turunan jumlah sampah, kalau tidak HUD akan stale.
	_check(inv.organic_count == 4 and inv.anorganic_count == 2,
		"turunan jumlah harus 4/2, dapat %d/%d" % [inv.organic_count, inv.anorganic_count])
	var sorted: Dictionary = _gd().get("sorted")
	_check(int(sorted.get("pisang", -1)) == 9,
		"buffer sorted harus pulih, dapat %s" % sorted)
	# sorted_organic/sorted_anorganic adalah turunan yang dihitung add_sorted(),
	# terpisah dari dict `sorted`. Kalau apply tidak menghitung ulang, dua
	# angka ini stale -> sorted_total() melapor 0 padahal buffer berisi,
	# dan recycled_total di sell_sorted() jadi kurang hitung.
	_check(int(_gd().get("sorted_organic")) == 9,
		"sorted_organic harus dihitung ulang jadi 9, dapat %s" % _gd().get("sorted_organic"))
	_check(int(_gd().get("sorted_anorganic")) == 1,
		"sorted_anorganic harus dihitung ulang jadi 1, dapat %s" % _gd().get("sorted_anorganic"))
	# recycle_total harus pulih persis, bukan dihitung ulang dari buffer (10).
	_check(int(_gd().get("recycled_total")) == int(GOLD.recycled_total),
		"recycled_total harus pulih jadi %d, dapat %s" % [GOLD.recycled_total, _gd().get("recycled_total")])
	_check(int(_sl().get("current_slot")) == SLOT_A,
		"current_slot harus tetap %d setelah apply" % SLOT_A)


func _test_v1_on_disk() -> void:
	# Save v1 sungguhan di disk: ada koin/hari/stok, tapi TIDAK ada version
	# maupun current_map. Hasilnya peta 1.
	_write_raw(SLOT_B, JSON.stringify({
		"coins": 12,
		"day": 3,
		"current_time": 100.0,
		"seconds_per_game_hour": 40.0,
		"player_pos": [10.0, 20.0],
		"inventory_stocks": {"organik": 1},
		"inventory_capacity": 5,
		"sorted": {"organik": 2},
	}, "\t"))
	_check(_sl().call("has_save", SLOT_B), "file v1 harus terdeteksi ada")
	var v1: Dictionary = _sl().call("read_slot", SLOT_B)
	# Pastikan jalur "field hilang" benar-benar diuji, bukan kebetulan cocok.
	_check(not v1.has("recycled_total"),
		"save v1 memang tidak punya key recycled_total (fixture)")
	if not _check(_sl().call("apply_slot", SLOT_B), "save v1 harus tetap bisa di-load"):
		return
	_check(int(_gm().coins) == 12, "v1 coins harus 12, dapat %d" % _gm().coins)
	_check(int(_np().get("current_map")) == 1,
		"v1 harus jadi peta 1, dapat %s" % _np().get("current_map"))
	_check(int(_tm.day) == 3, "v1 day harus 3, dapat %d" % _tm.day)
	# Backward compatibility: v1 tidak punya field ini, jadi harus default 0 --
	# bukan mempertahankan nilai sesi sebelumnya (777), dan bukan error.

	_check(int(_gd().get("recycled_total")) == 0,
		"v1 tanpa recycled_total harus default 0, dapat %s" % _gd().get("recycled_total"))


## Save v2 milik player yang sudah pernah main sebelum pollution dicabut. File
## ini masih punya key `pollution` dan `version: 2`. Harus tetap bisa di-load
## tanpa error, pollution-nya diabaikan, dan peta yang tersimpan tetap dipakai.
## Ini yang menjaga save lama player tidak jadi rusak oleh penghapusan ini.
func _test_legacy_v2_on_disk() -> void:
	_write_raw(SLOT_B, JSON.stringify({
		"version": 2,
		"coins": 120,
		"day": 4,
		"current_time": 500.0,
		"seconds_per_game_hour": 45.0,
		"player_pos": [44.0, 55.0],
		"inventory_stocks": {"kaca": 3},
		"inventory_capacity": 6,
		"sorted": {"kaca": 4},
		"pollution": 84,
		"current_map": 2,
		"recycled_total": 12,
	}, "\t"))
	_check(_sl().call("has_save", SLOT_B), "file v2 harus terdeteksi ada")
	if not _check(_sl().call("apply_slot", SLOT_B),
			"save v2 lama harus tetap bisa di-load tanpa error"):
		return
	_check(int(_gm().coins) == 120, "v2 coins harus 120, dapat %d" % _gm().coins)
	_check(int(_np().get("current_map")) == 2,
		"peta dari save v2 harus dipakai, dapat %s" % _np().get("current_map"))
	_check(int(_tm.day) == 4, "v2 day harus 4, dapat %d" % _tm.day)
	_check(int(_gd().get("recycled_total")) == 12,
		"v2 recycled_total harus 12, dapat %s" % _gd().get("recycled_total"))


func _test_corrupt_file() -> void:
	# JSON rusak: apply harus menolak (false) dan tidak mengikis dunia.
	_seed_gold()
	var coins_before := int(_gm().coins)
	_write_raw(SLOT_B, "{ ini bukan json")
	_check(not _sl().call("apply_slot", SLOT_B),
		"file korup harus ditolak, tidak boleh true")
	_check(int(_gm().coins) == coins_before,
		"dunia tidak boleh berubah setelah file korup, dapat %d" % _gm().coins)
	# Slot yang tidak ada juga harus ditolak tanpa error.
	_write_raw(SLOT_B, "")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_slot_path(SLOT_B)))
	_check(not _sl().call("apply_slot", SLOT_B),
		"slot kosong harus ditolak, tidak boleh true")
	_check(int(_gm().coins) == coins_before,
		"dunia tidak boleh berubah setelah slot hilang, dapat %d" % _gm().coins)
