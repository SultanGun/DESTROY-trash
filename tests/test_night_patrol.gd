extends SceneTree

## Uji runtime untuk NightPatrol (scripts/night_patrol.gd).
##
## Harness headless tanpa framework test project:
##   godot --headless --path <project> --script res://tests/test_night_patrol.gd
##
## Yang diuji (kontrak gameplay, bukan detail visual):
##   1. Rute per peta: Map 1 punya 3 rute, Map 2 punya 4, peta ngawur kosong.
##   2. Rute rogue dipin: Map 1 = rute 0, Map 2 = rute 3, peta lain -1.
##   3. Peta saat ini: terima 1/2, tolak yang lain.
##   4. Spawn: TEPAT SATU NPC Map 1 di awal malam; NPC Map 2 belum muncul.
##   5. Spawn berurutan: NPC Map 2 baru muncul setelah NPC Map 1 selesai
##      (tertangkap ATAU lolos) - tidak hanya saat tertangkap.
##   6. Spawn NPC Map 2 juga saat NPC Map 1 KABUR karena minigame gagal.
##   7. Spawn: route_id dan tint diteruskan, NPC langsung menyala.
##   8. Spawn tanpa host: dilewati dengan peringatan, bukan crash.
##   9. Pagi: semua NPC dibuang dan hilang dari tree.
##  10. active_count() tidak menghitung NPC yang sudah hilang.
##  11. Fase NIGHT: malam dimulai dan hanya Map 1 yang spawn.
##  12. NIGHT berulang di malam yang sama tidak spawning dua kali.
##  13. Fase DAY: NPC dibuang + patrol_cleared.
##  14. TimeManager yang muncul belakangan tetap tertangkap.
##  15. rebind() berulang tidak menggandakan koneksi.
##  16. Progres: penyebut 2 dari awal, bahkan sebelum NPC kedua muncul.
##  17. Progres: clear() mengembalikan n/m ke 0/0.
##  18. Ekonomi: tangkapan TIDAK membayar per NPC.
##  19. Klaim: 2/2 + tombol = +100 sekali, tidak bisa diklik dua kali.
##  20. Klaim ditolak kalau belum 2/2 atau belum diklaim sekali.
##  21. Resolusi: 2/2 + diklaim = +100, dan fajar tidak menambah penalti.
##  22. Resolusi: 2/2 tapi TIDAK diklaim = netral (tidak +100, tidak -50).
##  23. Resolusi: ada yang lolos = -50 SEKALI di fajar, bukan per NPC.
##  24. Ekonomi tanpa GameManager di tree dilewati, tidak crash.

const NightPatrolScript := preload("res://scripts/night_patrol.gd")
const DumperRoutes := preload("res://scripts/dumper_routes.gd")
const TimeManagerScript := preload("res://scripts/time_manager.gd")

const P_DAY := 0
const P_SUNSET := 1
const P_NIGHT := 2

## Kontrak ekonomi per malam. Ditiru di sini, bukan dibaca dari GameManager,
## supaya test ini benar-benar menguji angka yang disepakati, bukan cuma
## mengulang apa yang terjadi.
const WIN := 100
const LOSS := -50

## Dua pembuang per malam, satu per peta.
const EXPECTED_PER_NIGHT := 2

var _pass := 0
var _fail := 0
var _failures: Array[String] = []

var _patrol: Node = null
var _tm: Node = null
var _main: Node2D = null


func _initialize() -> void:
	await process_frame
	await _run("rute: Map 1 punya 3, Map 2 punya 4", _test_routes_for_map)
	await _run("rute: peta ngawur mengembalikan kosong", _test_routes_invalid_map)
	await _run("rute rogue dipin: peta 1 = 0, peta 2 = 3", _test_rogue_routes)
	await _run("peta: terima 1/2, tolak yang lain", _test_set_current_map)
	await _run("spawn: malam mulai dengan 1 NPC, hanya peta 1", _test_spawn_one_first)
	await _run("spawn: NPC kedua muncul setelah pertama tertangkap", _test_second_after_catch)
	await _run("spawn: NPC kedua muncul setelah pertama KABUR", _test_second_after_escape)
	await _run("spawn: route_id dan tint diteruskan, NPC menyala", _test_spawn_wiring)
	await _run("spawn: tanpa host dilewati, tidak crash", _test_spawn_without_host)
	await _run("pagi: clear() membuang semua NPC", _test_clear)
	await _run("active_count() mengabaikan NPC hilang", _test_active_count_prunes)
	await _run("fase NIGHT: malam mulai, hanya peta 1", _test_night_spawns)
	await _run("NIGHT berulang tidak double-spawn", _test_duplicate_night)
	await _run("fase DAY: dibuang + patrol_cleared", _test_day_clears)
	await _run("TimeManager telat tetap tertangkap", _test_late_attach)
	await _run("rebind() berulang tidak menggandakan", _test_rebind_idempotent)
	await _run("progres: penyebut 2 sejak awal malam", _test_total_is_two)
	await _run("progres: clear() mengembalikan n/m ke 0/0", _test_clear_resets_progress)
	await _run("progres: tangkapan menaikkan n, tidak membayar", _test_catch_no_per_npc_payout)
	await _run("klaim: 2/2 + tombol = +100 sekali saja", _test_claim_pays_once)
	await _run("klaim: ditolak sebelum 2/2 dan setelah diklaim", _test_claim_rejects)
	await _run("resolusi: 2/2 + diklaim = +100, tanpa penalti", _test_resolve_win)
	await _run("resolusi: 2/2 tanpa klaim = netral", _test_resolve_win_unclaimed)
	await _run("resolusi: ada yang lolos = -50 sekali saat fajar", _test_resolve_loss_once)
	await _run("ekonomi: tanpa GameManager tidak crash", _test_economy_without_game_manager)
	await _teardown()
	_report()
	quit(0 if _fail == 0 else 1)


# --------------------------------------------------------------- progres HUD
## Rekam semua nilai patrol_progress yang dipancarkan, supaya test bisa
## memeriksa nilai TERAKHIR - bukan menebak dari state internal.
func _record_progress() -> Array:
	var seen: Array = []
	_patrol.connect("patrol_progress",
		func(c: int, t: int) -> void: seen.append(Vector2i(c, t)))
	return seen


## Penyebut n/m adalah 2 dari MENITik awal malam, bukan "berapa NPC yang sudah
## muncul". Kalau penyebut ikut ikut naik spawn, HUD akan menulis "TERTANGKAP
## 0/1" selama NPC pertama masih hidup lalu melompat ke "0/2" - dan player
## mengira malam ini cuma satu pembuang.
func _test_total_is_two() -> void:
	_make_main()
	_patrol = _make_patrol()
	var seen := _record_progress()
	_patrol.call("begin_night", 1)
	_check(not seen.is_empty(), "begin_night harus memancarkan progres")
	if seen.is_empty():
		return
	var first: Vector2i = seen[0]
	_check(first == Vector2i(0, EXPECTED_PER_NIGHT),
		"penyebut harus %d sejak awal, dapat %d" % [EXPECTED_PER_NIGHT, first.y])
	# Setelah NPC pertama tertangkap, penyebut tetap 2.
	var made: Array = _patrol.call("active_dumpers")
	if not made.is_empty():
		made[0].emit_signal("intercepted", "Kurir Pasar", Vector2.ZERO)
	var last: Vector2i = seen[seen.size() - 1]
	_check(last == Vector2i(1, EXPECTED_PER_NIGHT),
		"setelah 1 tertangkap harus 1/%d, dapat %d/%d"
		% [EXPECTED_PER_NIGHT, last.x, last.y])


## Setelah clear() layar harus kosong, bukan masih menampilkan "TERTANGKAP 2/2"
## milik malam yang sudah berakhir.
func _test_clear_resets_progress() -> void:
	_make_main()
	_patrol = _make_patrol()
	_patrol.call("begin_night", 1)
	var seen := _record_progress()
	_patrol.call("clear")
	_check(not seen.is_empty(), "harus ada sinyal untuk diperiksa")
	if not seen.is_empty():
		var last: Vector2i = seen[seen.size() - 1]
		_check(last == Vector2i(0, 0),
			"setelah clear harus 0/0, dapat %d/%d" % [last.x, last.y])


# ----------------------------------------------------------------- harness
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


## Bandingkan isi dua array secara berurutan. Dipakai untuk array integer
## dari kode produksi, yang tipenya belum bisa disimpulkan di sini.
func _same(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for i in actual.size():
		if int(actual[i]) != int(expected[i]):
			return false
	return true


func _report() -> void:
	print("")
	print("===================================================")
	print("  lulus=%d  gagal=%d" % [_pass, _fail])
	if _fail > 0:
		print("  --- kegagalan ---")
		for f in _failures:
			print("  * ", f)
	print("===================================================")


# ------------------------------------------------------------------ fixture
## Buang sisa dari test sebelumnya: NightPatrol, TimeManager, dan Main.
func _teardown() -> void:
	if is_instance_valid(_patrol):
		_patrol.call("clear")
		_patrol.free()
	_patrol = null
	if is_instance_valid(_tm):
		_tm.free()
	_tm = null
	if is_instance_valid(_main):
		_main.free()
	_main = null
	var hidden := root.get_node_or_null(^"GameManagerHidden")
	if hidden != null:
		hidden.name = &"GameManager"
	await process_frame


func _make_patrol() -> Node:
	if is_instance_valid(_patrol):
		_patrol.call("clear")
		_patrol.free()
		_patrol = null
	_patrol = NightPatrolScript.new()
	root.add_child(_patrol)
	return _patrol


## Host /root/Main. Rute memakai koordinat global Main, jadi NPC harus
## menjadi anak node ini, bukan anak Map1/Map2.
func _make_main() -> Node2D:
	if is_instance_valid(_main):
		return _main
	_main = Node2D.new()
	_main.name = "Main"
	root.add_child(_main)
	return _main


func _make_time_manager() -> Node:
	# Buang TM sebelumnya dulu. Kalau ada dua TimeManager di tree, patrol yang
	# baru bisa saja attach ke yang lama (yang fase-nya sudah NIGHT), sehingga
	# _emit_phase di TM baru tidak sampai ke patrol dan malam tidak pernah mulai.
	# Bersihkan lebih dulu supaya test benar-benar terisolasi.
	if is_instance_valid(_tm):
		_tm.free()
		_tm = null
	_tm = TimeManagerScript.new()
	_tm.set("seconds_per_game_hour", 100000.0)
	root.add_child(_tm)
	_tm.set_process(false)
	return _tm


## Emisi manual, sama dengan yang dilakukan TimeManager saat jam bergeser.
func _emit_phase(phase: int) -> void:
	_tm.emit_signal("phase_changed", phase)


## Autoload GameManager sungguhan yang sudah ada di /root. JANGAN membuat
## GameManager manual di sini - node buatan akan di-rename Godot.
func _real_game_manager() -> Node:
	var gm := root.get_node_or_null(^"GameManager")
	_check(gm != null, "autoload /root/GameManager harus ada di mode --script")
	return gm


## Autoload NightPatrol milik project juga hidup di /root pada mode --script.
## Kalau tidak dimatikan, dia ikut subscribe ke TimeManager yang sama dan
## setiap NIGHT/DAY di-resolve DUA kali: instantiate test ikut??? dan autoload
## ikut. Ujinya jadi mengukur GADU, bukan kontrak NightPatrol.
##
## Dipakai oleh test yang menghitung koin lewat GameManager sungguhan.
func _silence_autoload_patrol() -> void:
	var auto_patrol := root.get_node_or_null(^"NightPatrol")
	if auto_patrol != null:
		auto_patrol.set("auto_spawn", false)


## Peta yang sedang di stack dumper berdasarkan rute-nya, untuk mengecek
## urutan spawn tanpa bergantung pada urutan array.
func _dumper_map(d: Node2D) -> int:
	var rid: int = int(d.get("route_id"))
	return int(DumperRoutes.ALL[rid].get("map", 0))


# -------------------------------------------------------------- 1. data rute
func _test_routes_for_map() -> void:
	_patrol = _make_patrol()
	_check(_same(_patrol.routes_for_map(1), [0, 1, 2]),
		"Map 1 harus rute [0,1,2], dapat %s" % [_patrol.routes_for_map(1)])
	_check(_same(_patrol.routes_for_map(2), [3, 4, 5, 6]),
		"Map 2 harus rute [3,4,5,6], dapat %s" % [_patrol.routes_for_map(2)])


func _test_routes_invalid_map() -> void:
	_patrol = _make_patrol()
	_check(_patrol.routes_for_map(7).is_empty(),
		"peta 7 harus kosong, dapat %s" % [_patrol.routes_for_map(7)])


## Rute rogue dipin supaya dua pembuang selalu orang yang sama.
func _test_rogue_routes() -> void:
	_patrol = _make_patrol()
	_check(_patrol.rogue_route_id(1) == 0,
		"peta 1 harus rute 0, dapat %d" % _patrol.rogue_route_id(1))
	_check(_patrol.rogue_route_id(2) == 3,
		"peta 2 harus rute 3, dapat %d" % _patrol.rogue_route_id(2))
	_check(_patrol.rogue_route_id(7) == -1,
		"peta 7 harus -1, dapat %d" % _patrol.rogue_route_id(7))
	# Rute yang dipin harus benar-benar milik peta itu.
	_check(int(DumperRoutes.ALL[0].get("map", 0)) == 1,
		"rute 0 harus milik peta 1")
	_check(int(DumperRoutes.ALL[3].get("map", 0)) == 2,
		"rute 3 harus milik peta 2")


func _test_set_current_map() -> void:
	_patrol = _make_patrol()
	_patrol.set_current_map(2)
	_check(_patrol.current_map == 2, "peta 2 harus diterima, dapat %d" % _patrol.current_map)
	_patrol.set_current_map(7)
	_check(_patrol.current_map == 2,
		"peta ngawur harus ditolak dan peta lama dipertahankan, dapat %d" % _patrol.current_map)


# ------------------------------------------------------------------ spawning
## Malam dimulai dengan SATU NPC di peta 1. NPC peta 2 belum boleh muncul,
## karena urutannya adalah "satu per satu".
func _test_spawn_one_first() -> void:
	_make_main()
	_patrol = _make_patrol()
	_patrol.call("begin_night", 1)
	var made: Array = _patrol.call("active_dumpers")
	_check(made.size() == 1, "harus ada tepat 1 NPC di awal, dapat %d" % made.size())
	if made.is_empty():
		return
	_check(_dumper_map(made[0]) == 1,
		"NPC pertama harus di peta 1, dapat peta %d" % _dumper_map(made[0]))


## Tangkapan NPC pertama membebaskan giliran NPC kedua.
func _test_second_after_catch() -> void:
	_make_main()
	_patrol = _make_patrol()
	_patrol.call("begin_night", 1)
	var made: Array = _patrol.call("active_dumpers")
	if made.is_empty():
		_check(false, "tidak ada NPC awal untuk diuji")
		return
	made[0].emit_signal("intercepted", "Kurir Pasar", Vector2.ZERO)
	var after: Array = _patrol.call("active_dumpers")
	_check(after.size() == 2, "setelah tangkapan harus ada 2 NPC, dapat %d" % after.size())
	var maps: Array = []
	for d in after:
		maps.append(_dumper_map(d))
	_check(maps.has(2), "NPC kedua harus di peta 2, dapat peta %s" % [maps])
	# Dan hanya dua, tidak lebih: pola lama spawn 4 NPC peta 2 sekaligus.
	_check(_count_map(after, 2) == 1,
		"peta 2 harus punya tepat 1 NPC, dapat %d" % _count_map(after, 2))


## NPC pertama yang KABUR (gagal minigame) juga harus melepas giliran.
## Kalau hanya `intercepted` yang melepas, NPC pertama yang kabur akan
## menggantung malam ini selamanya dan pemain kedua tidak pernah muncul.
func _test_second_after_escape() -> void:
	_make_main()
	_patrol = _make_patrol()
	_patrol.call("begin_night", 1)
	var made: Array = _patrol.call("active_dumpers")
	if made.is_empty():
		_check(false, "tidak ada NPC awal untuk diuji")
		return
	made[0].emit_signal("escaped", "Kurir Pasar", Vector2.ZERO)
	var after: Array = _patrol.call("active_dumpers")
	_check(after.size() == 2, "setelah kabur harus ada 2 NPC, dapat %d" % after.size())
	_check(_count_map(after, 2) == 1,
		"peta 2 harus punya tepat 1 NPC setelah NPC pertama kabur, dapat %d"
		% _count_map(after, 2))


func _count_map(made: Array, map_id: int) -> int:
	var n: int = 0
	for d in made:
		if is_instance_valid(d) and _dumper_map(d) == map_id:
			n += 1
	return n


func _test_spawn_wiring() -> void:
	_make_main()
	_patrol = _make_patrol()
	_patrol.call("begin_night", 1)
	var made: Array = _patrol.call("active_dumpers")
	if made.is_empty():
		_check(false, "tidak ada NPC untuk diuji")
		return
	var d: Node2D = made[0]
	_check(d.get_parent() == _main, "NPC harus anak /root/Main")
	_check(int(d.get("route_id")) == _patrol.rogue_route_id(1),
		"route_id harus sesuai peta, dapat %s" % d.get("route_id"))
	# current_state() hanya tersedia lewat call() (bukan properti), jadi
	# hasilnya Variant dan harus lewat int() setelah call.
	var state: int = d.call("current_state")
	_check(state != 0,
		"NPC harus langsung menyala (bukan IDLE), dapat state %d" % state)
	# Tint harus diteruskan supaya dua pembuang tidak terlihat sama.
	var route: Dictionary = DumperRoutes.ALL[int(d.get("route_id"))]
	_check(d.get("tint") == route.get("tint"),
		"tint harus mengikuti rute, dapat %s" % d.get("tint"))


func _test_spawn_without_host() -> void:
	# Buang host lebih dulu: Main dari test sebelumnya masih di tree, dan kalau
	# tidak dibuang test ini diam-diam menguji jalur yang salah (spawn BERHASIL,
	# jadi test ini diam-diam menguji jalur yang SALAH.)
	if is_instance_valid(_main):
		_main.free()
		_main = null
	_check(root.get_node_or_null(^"Main") == null,
		"prasyarat: /root/Main harus benar-benar tidak ada")
	_patrol = _make_patrol()
	# Tanpa /root/Main: spawn harus dilewati, tidak crash, tidak menghasilkan NPC.
	var made: Node2D = _patrol.call("spawn_rogue", 1)
	_check(made == null, "tanpa host harus mengembalikan null, dapat %s" % made)
	_check(_patrol.active_count() == 0, "tidak boleh ada NPC yang menggantung")


func _test_clear() -> void:
	_make_main()
	_patrol = _make_patrol()
	_patrol.call("begin_night", 1)
	var made: Array = _patrol.call("active_dumpers")
	if not made.is_empty():
		made[0].emit_signal("intercepted", "Kurir Pasar", Vector2.ZERO)
	_check(_patrol.active_count() == 2, "prasyarat: 2 NPC aktif")
	_patrol.call("clear")
	await process_frame
	_check(_patrol.active_count() == 0, "clear() harus membuang semua NPC")
	for d in made:
		if is_instance_valid(d):
			_check(false, "NPC masih hidup setelah clear: %s" % d.get("route_id"))


func _test_active_count_prunes() -> void:
	_make_main()
	_patrol = _make_patrol()
	_patrol.call("begin_night", 1)
	var made: Array = _patrol.call("active_dumpers")
	if not made.is_empty():
		made[0].emit_signal("intercepted", "Kurir Pasar", Vector2.ZERO)
	# Buang NPC pertama di luar clearing: NightPatrol tidak diberi tahu.
	if not made.is_empty() and is_instance_valid(made[0]):
		made[0].queue_free()
	await process_frame
	_check(_patrol.active_count() == 1,
		"NPC yang hilang harus dikeluarkan dari hitungan, dapat %d" % _patrol.active_count())


# ------------------------------------------------------------------- fase
func _test_night_spawns() -> void:
	_make_main()
	_patrol = _make_patrol()
	_tm = _make_time_manager()
	await process_frame
	_patrol.call("rebind")
	_emit_phase(P_NIGHT)
	_check(_patrol.night_number == 1, "satu NIGHT harus malam ke-1, dapat %d" % _patrol.night_number)
	var made: Array = _patrol.call("active_dumpers")
	_check(made.size() == 1, "NIGHT harus spawn 1 NPC saja, dapat %d" % made.size())
	_check(_count_map(made, 1) == 1, "NPC pertama harus peta 1, dapat %s" % [made])
	_check(_count_map(made, 2) == 0,
		"peta 2 harus masih kosong di awal malam, dapat %d" % _count_map(made, 2))


func _test_duplicate_night() -> void:
	_make_main()
	_patrol = _make_patrol()
	_tm = _make_time_manager()
	# Patrol dibuat sebelum TM, jadi ia attach lewat watcher node_added yang
	# call_deferred. Satu frame belum tentu cukup untuk deferred itu berjalan.
	await process_frame
	_patrol.call("rebind")
	_emit_phase(P_NIGHT)
	var n: int = _patrol.night_number
	_emit_phase(P_NIGHT)
	_check(_patrol.night_number == n,
		"NIGHT kedua di fase yang sama tidak boleh menaikkan malam, dapat %d" % _patrol.night_number)
	_check(_patrol.active_count() == 1,
		"NIGHT ganda tidak boleh spawn dua NPC, dapat %d" % _patrol.active_count())


func _test_day_clears() -> void:
	_make_main()
	_patrol = _make_patrol()
	_tm = _make_time_manager()
	await process_frame
	await process_frame
	_patrol.call("rebind")
	var cleared: Array = []
	_patrol.connect("patrol_cleared", func(n: int) -> void: cleared.append(n))
	_emit_phase(P_NIGHT)
	_emit_phase(P_DAY)
	await process_frame
	_check(_patrol.active_count() == 0, "DAY harus membuang semua NPC")
	_check(not cleared.is_empty(), "patrol_cleared harus keluar saat fajar")
	if not cleared.is_empty():
		_check(int(cleared[0]) == 1, "patrol_cleared harus membawa malam 1, dapat %s" % [cleared[0]])


func _test_late_attach() -> void:
	_make_main()
	_patrol = _make_patrol()
	# TimeManager sengaja dibuat SETELAH NightPatrol siap. Patrol harus
	# menangkapnya lewat watcher node_added, bukan karena ada TM saat _ready().
	# auto_spawn sengaja dibiarkan true: purpose test ini attach, bukan
	# mematikan fase.
	_tm = _make_time_manager()
	await process_frame
	await process_frame
	_patrol.call("rebind")
	_emit_phase(P_NIGHT)
	_check(_patrol.night_number >= 1,
		"TimeManager yang telat harus tetap memicu spawn, malam %d" % _patrol.night_number)


func _test_rebind_idempotent() -> void:
	_make_main()
	_patrol = _make_patrol()
	_tm = _make_time_manager()
	await process_frame
	_patrol.call("rebind")
	_patrol.call("rebind")
	_patrol.call("rebind")
	_emit_phase(P_NIGHT)
	_check(_patrol.night_number == 1,
		"rebind berulang tidak boleh menggandakan spawn, malam %d" % _patrol.night_number)
	_check(_patrol.active_count() == 1,
		"rebind berulang tidak boleh spawn NPC ganda, dapat %d" % _patrol.active_count())


# ----------------------------------------------------------------- ekonomi
## Tangkapan tidak boleh membayar per NPC. Kalau iya, 2/2 akan jadi +200 dan
## "menang = 100" jadi bohong. Yang dibayar adalah klaim, di akhir malam.
func _test_catch_no_per_npc_payout() -> void:
	var gm := _real_game_manager()
	_silence_autoload_patrol()
	_make_main()
	_patrol = _make_patrol()
	gm.call("set_coins", 0)
	_patrol.call("begin_night", 1)
	var made: Array = _patrol.call("active_dumpers")
	if made.is_empty():
		_check(false, "tidak ada NPC untuk diuji")
		return
	made[0].emit_signal("intercepted", "Kurir Pasar", Vector2.ZERO)
	var after: Array = _patrol.call("active_dumpers")
	if after.size() > 1:
		after[1].emit_signal("intercepted", "Petani Sawah", Vector2.ZERO)
	_check(int(gm.coins) == 0,
		"tangkapan tidak boleh membayar sebelum klaim, dapat %d" % int(gm.coins))
	_check(_patrol.can_claim(), "2/2 harus bisa diklaim")


## Klaim membayar +100 sekali. Klik kedua harus ditolak supaya 2/2 = 200
## tidak mungkin terjadi hanya karena player buru-buru dua kali.
func _test_claim_pays_once() -> void:
	_silence_autoload_patrol()
	var gm := _real_game_manager()
	_make_main()
	_patrol = _make_patrol()
	gm.call("set_coins", 0)
	_patrol.call("begin_night", 1)
	_catch_both()
	_check(_patrol.can_claim(), "prasyarat: 2/2 harus bisa diklaim")
	_check(_patrol.call("claim_reward"), "klaim pertama harus berhasil")
	_check(int(gm.coins) == WIN, "klaim harus +%d, dapat %d" % [WIN, int(gm.coins)])
	_check(not _patrol.call("claim_reward"), "klaim kedua harus ditolak")
	_check(int(gm.coins) == WIN,
		"klaim kedua tidak boleh membayar lagi, dapat %d" % int(gm.coins))
	_check(not _patrol.can_claim(), "setelah diklaim, can_claim harus false")


## Klaim ditolak kalau belum 2/2, dan kalau sudah pernah diklaim.
func _test_claim_rejects() -> void:
	_silence_autoload_patrol()
	var gm := _real_game_manager()
	_make_main()
	_patrol = _make_patrol()
	gm.call("set_coins", 0)
	_patrol.call("begin_night", 1)
	_check(not _patrol.can_claim(), "0/2 tidak boleh bisa diklaim")
	_check(not _patrol.call("claim_reward"), "klaim di 0/2 harus ditolak")
	_check(int(gm.coins) == 0, "klaim gagal tidak boleh membayar, dapat %d" % int(gm.coins))
	# Tanpa malam sama sekali juga ditolak.
	_patrol.call("clear")
	_check(not _patrol.call("claim_reward"), "klaim tanpa malam harus ditolak")
	# 1/2 juga belum.
	_patrol.call("begin_night", 2)
	var made: Array = _patrol.call("active_dumpers")
	if not made.is_empty():
		made[0].emit_signal("intercepted", "Kurir Pasar", Vector2.ZERO)
	_check(not _patrol.can_claim(), "1/2 tidak boleh bisa diklaim")
	_check(not _patrol.call("claim_reward"), "klaim di 1/2 harus ditolak")


## Tangkap keduanya lalu klaim, lalu fajar. Hasil akhir harus +100, bukan
## +100 lalu -50: malam yang sudah dibayar tidak boleh penalti.
func _test_resolve_win() -> void:
	_silence_autoload_patrol()
	var gm := _real_game_manager()
	_make_main()
	_patrol = _make_patrol()
	_tm = _make_time_manager()
	gm.call("set_coins", 0)
	await process_frame
	_patrol.call("rebind")
	_emit_phase(P_NIGHT)
	_catch_both()
	_patrol.call("claim_reward")
	_emit_phase(P_DAY)
	await process_frame
	_check(int(gm.coins) == WIN,
		"2/2 + klaim harus berakhir di +%d, dapat %d" % [WIN, int(gm.coins)])


## 2/2 tapi player tidak pernah menekan tombol. Malam ini NEUTRAL: tidak dapat
## hadiah, tapi juga tidak kena penalti. "Tidak sempat klik" bukan gagal.
func _test_resolve_win_unclaimed() -> void:
	_silence_autoload_patrol()
	var gm := _real_game_manager()
	_make_main()
	_patrol = _make_patrol()
	_tm = _make_time_manager()
	gm.call("set_coins", 40)
	await process_frame
	_patrol.call("rebind")
	_emit_phase(P_NIGHT)
	_catch_both()
	# sengaja tidak claim
	_emit_phase(P_DAY)
	await process_frame
	_check(int(gm.coins) == 40,
		"2/2 tanpa klaim harus netral (tetap %d), dapat %d" % [40, int(gm.coins)])


## Penalti -50 jatuh SEKALI di fajar, bukan per NPC yang lolos. Dua pembuang
## yang kabur tidak boleh berarti -100.
func _test_resolve_loss_once() -> void:
	_silence_autoload_patrol()
	var gm := _real_game_manager()
	_make_main()
	_patrol = _make_patrol()
	_tm = _make_time_manager()
	gm.call("set_coins", 200)
	await process_frame
	_patrol.call("rebind")
	_emit_phase(P_NIGHT)
	# Kedua NPC lolos, tanpa tertangkap sama sekali.
	var made: Array = _patrol.call("active_dumpers")
	if not made.is_empty():
		made[0].emit_signal("escaped", "Kurir Pasar", Vector2.ZERO)
	var after: Array = _patrol.call("active_dumpers")
	if not after.is_empty():
		# NPC kedua yang lolos; cari yang peta 2.
		for d in after:
			if is_instance_valid(d) and _dumper_map(d) == 2:
				d.emit_signal("escaped", "Petani Sawah", Vector2.ZERO)
	_check(int(gm.coins) == 200,
		"selama malam berjalan koin tidak boleh bergerak, dapat %d" % int(gm.coins))
	_emit_phase(P_DAY)
	await process_frame
	_check(int(gm.coins) == 200 + LOSS,
		"dua NPC lolos harus penalti %d SEKALI, dapat %d" % [LOSS, int(gm.coins)])


## Tangkap NPC pertama lewat signal, lalu tangkap yang kedua. Helper
## karena pola "tangkap keduanya" dipakai beberapa test.
func _catch_both() -> void:
	var made: Array = _patrol.call("active_dumpers")
	for d in made:
		if is_instance_valid(d) and _dumper_map(d) == 1:
			d.emit_signal("intercepted", "Kurir Pasar", Vector2.ZERO)
			break
	var after: Array = _patrol.call("active_dumpers")
	for d in after:
		if is_instance_valid(d) and _dumper_map(d) == 2:
			d.emit_signal("intercepted", "Petani Sawah", Vector2.ZERO)
			break


func _test_economy_without_game_manager() -> void:
	_make_main()
	_patrol = _make_patrol()
	_tm = _make_time_manager()
	var real := root.get_node_or_null(^"GameManager")
	if real == null:
		_check(false, "autoload GameManager harus ada untuk test ini")
		return
	# Sembunyikan GameManager supaya _game_manager() mengembalikan null.
	real.name = &"GameManagerHidden"
	_emit_phase(P_NIGHT)
	var made: Array = _patrol.call("active_dumpers")
	var ok := true
	if not made.is_empty():
		made[0].emit_signal("intercepted", "Kurir Pasar", Vector2.ZERO)
	_emit_phase(P_DAY)
	real.name = &"GameManager"
	await process_frame
	_check(ok, "resolusi malam tanpa GameManager tidak boleh crash")
	_check(root.get_node_or_null(^"GameManager") != null,
		"GameManager harus kembali bernama GameManager setelah test")
