extends SceneTree

## Uji runtime untuk IllegalDumper (scripts/illegal_dumper.gd).
##
## Harness headless tanpa framework test project:
##   godot --headless --path <project> --script res://tests/test_illegal_dumper.gd
##
## Yang diuji (kontrak gameplay, bukan detail visual):
##   1. Data rute: 7 rute (3 Map 1 + 4 Map 2), schema lengkap, index/pickup/dump
##      konsisten dan dalam jangkauan.
##   2. Spawn: NPC masuk IDLE dengan physics mati; activate() menyalakan dan
##      menempatkan NPC di waypoint 0, state PATROL.
##   3. Jalan: NPC bergerak dan tetap dekat jalur.
##   4. Siklus: ambil muatan di pickup -> membawa -> DUMPING -> kosong, sinyal
##      dumped keluar 1x. Setelah buang, NPC kembali ke respawn (RETURNING),
##      bukan mengulang circuit tanpa akhir.
##   5. Tangkap E-KEY eksplisit lewat try_catch(); tidak ada tangkap otomatis
##      dari area: badan yang menabrak NPC tidak memicu apa pun.
##   6. NPC menembus dunia (collision_mask = 0), tidak lagi tersangkut.
##   7. Hanya animasi kiri/kanan yang dipakai, termasuk untuk gerak vertikal
##      dan saat diam.
##   8. Tertangkap -> FLEEING -> kembali ke respawn -> CAUGHT terminal.
##   9. Berhasil buang -> RETURNING -> kembali ke respawn -> ESCAPED terminal.
##  10. State terminal melepas NPC (despawn), bukan cuma berhenti.
##  11. Keluar peta tetap jadi ESCAPED (jaring pengaman).
##  12. route_id ngawur, rute kosong, deactivate(), teleport di terminal.

const DumperRoutes := preload("res://scripts/dumper_routes.gd")
const DumperScene := preload("res://scenes/IllegalDumper.tscn")

## Angka state WAJIB sama dengan enum State di scripts/illegal_dumper.gd.
## CAUGHT/ESCAPED mempertahankan nilai lamanya (4/5) supaya tidak ada angka
## state lama yang berubah artinya; RETURNING/FLEEING ditambahkan di belakang.
const S_IDLE := 0
const S_PATROL := 1
const S_APPROACH_DUMP := 2
const S_DUMPING := 3
const S_CAUGHT := 4
const S_ESCAPED := 5
const S_RETURNING := 6
const S_FLEEING := 7

## State terminal: NPC melepas diri (queue_free) dan tidak bisa dihidupkan lagi.
const S_TERMINAL := [S_CAUGHT, S_ESCAPED]

## Batas toleransi "masih dekat jalur", dalam pixel. Leg terpanjang sengaja
## punya backtrack, jadi ini longgar; tujuannya hanya menangkap NPC yang
## benar-benar keluar koridor.
const OFF_ROUTE_TOL_PX := 400.0

## Jarak tangkap yang dipakai player.gd saat menekan E. Test memakai angka yang
## sama supaya "dekat" dan "jauh" punya arti yang sama di kode dan di test.
const CATCH_RANGE_PX := 50.0

var _pass := 0
var _fail := 0
var _failures: Array[String] = []


func _initialize() -> void:
	# Root Window baru "di dalam tree" setelah satu frame. Tanpa ini, add_child
	# tidak memicu _ready dan semua pemeriksaan spawn ikut gagal.
	await process_frame
	await _run("data: 7 rute terdaftar (3 Map 1 + 4 Map 2)", _test_route_inventory)
	await _run("data: index/pickup/dump konsisten", _test_route_data)
	await _run("spawn: snap waypoint 0, IDLE sampai activate", _test_spawn)
	await _run("jalan: bergerak dan tetap dekat jalur", _test_walks_route)
	await _run("siklus: ambil -> bawa -> buang -> kosong", _test_carry_dump_cycle)
	await _run("tangkap: E eksplisit, hanya saat membawa", _test_try_catch)
	await _run("tangkap: menabrak NPC tidak memicu apa pun", _test_no_automatic_catch)
	await _run("tangkap: tidak bisa dua kali", _test_try_catch_once)
	await _run("kabur: NPC di respawn tetap terlihat kabur", _test_flee_leg_visible)
	await _run("kabur: NPC jauh dari respawn langsung pulang", _test_flee_leg_not_used_when_far)
	await _run("tabrakan: NPC menembus dunia (mask 0)", _test_passes_through_world)
	await _run("tabrakan: player tidak lagi tertahan NPC", _test_player_no_longer_blocks)
	await _run("animasi: hanya kiri/kanan, vertikal tahan facing", _test_left_right_only_animation)
	await _run("terminal: tertangkap -> FLEEING -> respawn -> despawn", _test_caught_flees_and_despawns)
	await _run("terminal: buang -> RETURNING -> respawn -> despawn", _test_dump_returns_and_despawns)
	await _run("keluar peta: ESCAPED dan muatan hilang", _test_escape_out_of_bounds)
	await _run("terminal: tidak bisa dihidupkan lagi", _test_terminal_is_final)
	await _run("route_id ngawur: jatuh ke rute 0", _test_route_id_out_of_range)
	await _run("rute kosong: NPC dimatikan", _test_empty_route_disables)
	await _run("deactivate: NPC berhenti di tempat", _test_deactivate_pauses_movement)
	# Beri frame supaya queue_free() selesai; kalau tidak, quit() keluar dengan
	# ObjectDB leak yang menutupi leak yang forthcoming.
	await process_frame
	await process_frame
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


## Menambah NPC ke tree dan mengembalikan node-nya TANPA menunggu frame, supaya
## pemanggil bisa memeriksa hasil _ready (snap ke waypoint 0) sebelum NPC sempat
## jalan. `route_id` diteruskan apa adanya supaya nilai ngawur bisa diuji.
##
## Node hasil fungsi ini IDLE: belum jalan. Yang butuh NPC hidup memanggil
## `activate()` lebih dulu.
func _add_dumper(route_id: int) -> Node2D:
	var d := DumperScene.instantiate()
	d.set("route_id", route_id)
	root.add_child(d)
	return d as Node2D


## Menambah NPC, menyalakannya, lalu menunggu satu frame.
func _spawn_dumper(idx: int) -> Node2D:
	var d := _add_dumper(idx)
	d.call("activate")
	await process_frame
	return d


func _tick(n: int) -> void:
	for _i in n:
		await physics_frame


## Sentinel state untuk NPC yang sudah dibebaskan. Nilai -1 tidak pernah dipakai
## enum State mana pun, jadi "sampel -1" selalu berarti node hilang, bukan state.
const S_FREED := -1


func _state(d: Node2D) -> int:
	# Pesan kegagalan di _check dievaluasi SELALU, bahkan saat kondisi lulus.
	# Karena itu accessor di sini wajib aman terhadap node yang sudah
	# queue_free() di tengah test, kalau tidak akan muncul SCRIPT ERROR yang
	# menutupi penyebab kegagalan sebenarnya.
	if not is_instance_valid(d):
		return S_FREED
	return int(d.call("current_state"))


func _carrying(d: Node2D) -> bool:
	if not is_instance_valid(d):
		return false
	return bool(d.call("is_carrying"))


func _waypoint(d: Node2D) -> Vector2:
	if not is_instance_valid(d):
		return Vector2.ZERO
	return d.call("target_waypoint") as Vector2


func _goto_wp(d: Node2D, i: int) -> void:
	if not is_instance_valid(d):
		return
	d.call("teleport_to_waypoint", i)


## Jarak ke waypoint terdekat, untuk mendeteksi keluar jalur.
func _off_route(d: Node2D, idx: int) -> float:
	var titik: Array = DumperRoutes.by_index(idx)["titik"]
	var best := INF
	for t in titik:
		best = min(best, d.global_position.distance_to(t))
	return best


func _make_body(at: Vector2, in_player_group: bool) -> Node2D:
	var b := CharacterBody2D.new()
	if in_player_group:
		b.add_to_group("player")
	var cs := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 18.0
	cap.height = 51.5
	cs.shape = cap
	b.add_child(cs)
	b.position = at
	root.add_child(b)
	return b as Node2D


## Namai animasi yang sedang diputar NPC, untuk memeriksa kontrak
## "hanya kiri/kanan".
func _anim_name(d: Node2D) -> String:
	var anim := d.get_node_or_null(^"Visual/Anim") as AnimatedSprite2D
	return "" if anim == null else String(anim.animation)


## True kalau animasi yang diputar adalah salah satu dari yang diizinkan.
func _anim_is_lr(name: String) -> bool:
	return name == "left" or name == "right"


## Tunggu sampai node benar-benar dibebaskan oleh queue_free() plus satu frame
## pemrosesan. Ini kontrak "state terminal melepas NPC", bukan "NPC diam".
func _wait_freed(d: Node2D, max_frames: int) -> bool:
	for _i in max_frames:
		if not is_instance_valid(d):
			return true
		await process_frame
	return not is_instance_valid(d)


func _wait_state(d: Node2D, want: int, max_frames: int) -> bool:
	for _i in max_frames:
		# NPC bisa sudah queue_free() di tengah menunggu; memanggil method
		# pada object yang sudah dibebaskan menghasilkan SCRIPT ERROR dan
		# ikut menggagalkan test lain.
		if not is_instance_valid(d):
			return false
		if _state(d) == want:
			return true
		await physics_frame
	return false


## Tunggu sampai status muatan mencapai `want`. Mengambil barang bersifat
## instan, jadi pengujian "sudah mengambil" tidak bisa memakai _wait_state.
func _wait_carrying(d: Node2D, want: bool, max_frames: int) -> bool:
	for _i in max_frames:
		if not is_instance_valid(d):
			return false
		if _carrying(d) == want:
			return true
		await physics_frame
	return false


# ----------------------------------------------------------------------- tests
## Inventaris rute: jumlah, sebaran per peta, nama unik, dan skema wajib.
## Ini kontrak yang dijaga analyzer dan seam Night Patrol nanti, jadi
## dijaga di sini sebagai satu-satunya sumber kebenaran.
func _test_route_inventory() -> void:
	var n := DumperRoutes.ALL.size()
	_check(n == 7, "harus ada 7 rute, dapat %d" % n)
	if n == 0:
		return

	var per_map := {1: 0, 2: 0}
	var seen_names := {}
	for i in n:
		var r: Dictionary = DumperRoutes.by_index(i)
		if not _check(not r.is_empty(), "by_index(%d) kosong" % i):
			continue

		# Skema wajib: tanpa kunci ini seam pemanggil akan crash jauh dari
		# penyebabnya, jadi gagal di sini lebih murah.
		for key in ["nama", "map", "pickup", "dump", "titik"]:
			_check(r.has(key), "rute %d: kunci '%s' hilang" % [i, key])

		var nama := str(r.get("nama", ""))
		_check(nama != "", "rute %d: nama kosong" % i)
		_check(not seen_names.has(nama),
			"nama rute duplikat: %s" % nama)
		seen_names[nama] = true

		var map_id := int(r.get("map", 0))
		_check(per_map.has(map_id),
			"rute %d: map %d di luar {1,2}" % [i, map_id])
		if per_map.has(map_id):
			per_map[map_id] += 1

		var titik: Array = r.get("titik", [])
		_check(titik.size() >= 3,
			"rute %d: butuh minimal 3 waypoint, dapat %d" % [i, titik.size()])
		for j in titik.size():
			_check(titik[j] is Vector2 and (titik[j] as Vector2).is_finite(),
				"rute %d titik %d: bukan Vector2 finite" % [i, j])

	_check(per_map[1] == 3, "harus ada 3 rute Map 1, dapat %d" % per_map[1])
	_check(per_map[2] == 4, "harus ada 4 rute Map 2, dapat %d" % per_map[2])


func _test_route_data() -> void:
	var n := DumperRoutes.ALL.size()
	for i in n:
		var r := DumperRoutes.by_index(i)
		if not _check(not r.is_empty(), "by_index(%d) kosong" % i):
			continue
		var titik: Array = r["titik"]
		var pi := int(r["pickup"])
		var di := int(r["dump"])
		_check(titik.size() >= 3,
			"rute %d: butuh minimal 3 waypoint, dapat %d" % [i, titik.size()])
		_check(pi >= 0 and pi < titik.size(),
			"rute %d: pickup %d di luar jangkauan" % [i, pi])
		_check(di >= 0 and di < titik.size(),
			"rute %d: dump %d di luar jangkauan" % [i, di])
		_check(pi != di, "rute %d: pickup == dump (%d)" % [i, pi])
		_check(DumperRoutes.pickup_point(r).is_finite(),
			"rute %d: pickup_point tidak valid" % i)
		_check(DumperRoutes.dump_point(r).is_finite(),
			"rute %d: dump_point tidak valid" % i)
	# Akses di luar jangkauan harus menolak, bukan crash.
	_check(DumperRoutes.by_index(n).is_empty(),
		"by_index(%d) harus kosong" % n)
	_check(DumperRoutes.by_index(-1).is_empty(), "by_index(-1) harus kosong")


func _test_spawn() -> void:
	var d := _add_dumper(0)
	var route: Dictionary = DumperRoutes.by_index(0)
	var titik: Array = route["titik"]
	# Diperiksa tanpa menunggu frame: NPC harus snap persis ke waypoint 0.
	_check(d.global_position.distance_to(titik[0]) < 0.01,
		"NPC harus snap ke waypoint 0 (harap %s, dapat %s)" % [titik[0], d.global_position])
	# Kursor harus sudah maju ke waypoint 1 supaya langsung jalan, bukan diam.
	_check(_waypoint(d).distance_to(titik[1]) < 0.01,
		"kursor harus di waypoint 1, dapat %s" % _waypoint(d))
	# Lahir IDLE: belum jalan, physics mati. Ini yang membuat "siapa yang spawn
	# NPC" bisa menentukan hidup/mati, bukan ikut melekat di scene.
	_check(_state(d) == S_IDLE, "state awal harus IDLE, dapat %d" % _state(d))
	_check(not d.is_physics_processing(), "NPC IDLE tidak boleh jalan sebelum activate")
	_check(not _carrying(d), "NPC harus mulai tanpa muatan")
	_check(d.is_in_group("illegal_dumpers"), "NPC harus masuk grup illegal_dumpers")
	_check(d.visible, "NPC harus terlihat walau IDLE, bukan disembunyikan")

	# activate() menyalakan: PATROL + physics hidup.
	d.call("activate")
	_check(_state(d) == S_PATROL, "activate harus masuk PATROL, dapat %d" % _state(d))
	_check(d.is_physics_processing(), "activate harus menyalakan physics")

	# deactivate() mematikan lagi tanpa menggeser posisi.
	var pos := d.global_position
	d.call("deactivate")
	_check(_state(d) == S_IDLE, "deactivate harus kembali IDLE, dapat %d" % _state(d))
	_check(not d.is_physics_processing(), "deactivate harus mematikan physics")
	_check(d.global_position.distance_to(pos) < 0.01, "deactivate tidak boleh menggeser NPC")
	d.queue_free()


func _test_walks_route() -> void:
	var d := await _spawn_dumper(0)
	var start := d.global_position
	await _tick(45)
	_check(d.global_position.distance_to(start) > 5.0,
		"NPC harus bergerak, tapi tetap di %s" % start)
	var drift := _off_route(d, 0)
	_check(drift < OFF_ROUTE_TOL_PX,
		"NPC keluar jalur: %.1f px dari waypoint terdekat" % drift)
	d.queue_free()


func _test_carry_dump_cycle() -> void:
	var d := await _spawn_dumper(0)
	var dumps: Array[Vector2] = []
	d.connect("dumped", func(_n, at): dumps.append(at))
	var route: Dictionary = DumperRoutes.by_index(0)
	var pi := int(route["pickup"])
	var di := int(route["dump"])

	# Kursor dipindah ke titik ambil supaya test cepat dan determinis.
	# Ambil barang bersifat instan: tidak ada state PICKUP, jadi yang dicari
	# adalah "sudah membawa" + APPROACH_DUMP dalam frame yang sama.
	_goto_wp(d, pi)
	_check(await _wait_carrying(d, true, 240),
		"harus membawa setelah tiba di titik ambil, state %d carrying %s"
		% [_state(d), _carrying(d)])
	_check(_state(d) == S_APPROACH_DUMP,
		"harus langsung APPROACH_DUMP setelah ambil, state %d" % _state(d))

	# Kursor dipindah ke titik dump. Membawa muatan harus tetap mengantar ke
	# APPROACH_DUMP, bukan kembali PATROL, atau NPC lewat tanpa membuang.
	_goto_wp(d, di)
	_check(_state(d) == S_APPROACH_DUMP,
		"teleport saat membawa harus tetap APPROACH_DUMP, state %d" % _state(d))
	_check(await _wait_state(d, S_DUMPING, 240),
		"harus masuk state DUMPING, state %d" % _state(d))
	_check(dumps.size() == 1,
		"sinyal dumped harus keluar saat tiba, dapat %d" % dumps.size())
	if dumps.size() == 1:
		_check(dumps[0].distance_to(DumperRoutes.dump_point(route)) < 0.01,
			"posisi dumped harus persis di titik dump, dapat %s" % dumps[0])

	# Setelah jeda DUMPING, muatan harus hilang dan NPC mulai pulang.
	# Ini perubahan kontrak inti: dulu NPC balik PATROL dan circuit berjalan
	# selamanya. Sekarang satu siklus = satu trip, lalu selesai.
	_check(await _wait_carrying(d, false, 400),
		"NPC harus kosong setelah DUMPING selesai")
	_check(_state(d) == S_RETURNING or _state(d) == S_ESCAPED,
		"harus pulang (RETURNING) atau selesai (ESCAPED) setelah DUMPING, state %d"
		% _state(d))
	_check(dumps.size() == 1,
		"sinyal dumped tidak boleh keluar lagi, total %d" % dumps.size())
	if is_instance_valid(d):
		d.queue_free()


func _test_try_catch() -> void:
	var d := await _spawn_dumper(0)
	var hits: Array[String] = []
	d.connect("intercepted", func(n, _at): hits.append(n))
	var route: Dictionary = DumperRoutes.by_index(0)

	# Tanpa muatan pun HARUS bisa ditutup. Dulu try_catch() menolak di sini,
	# yang memaksa player menunggu NPC berjalan ke waypoint ambil lebih dulu -
	# bisa ratusan frame sebelum E melakukan apa pun. Sekarang begitu NPC
	# muncul, E langsung membuka minigame dan tekan yang tepat langsung
	# menutupnya.
	var ok_empty := bool(d.call("try_catch"))
	_check(ok_empty, "NPC tanpa muatan pun harus bisa ditutup (E langsung)")
	_check(hits.size() == 1,
		"menutup NPC kosong harus memicu intercepted 1x, dapat %d" % hits.size())
	if hits.size() == 1:
		_check(hits[0] == "Kurir Pasar", "nama rute pada sinyal salah: %s" % hits[0])
	_check(not _carrying(d), "setelah tertangkap muatan harus hilang")
	_check(_state(d) == S_FLEEING,
		"setelah tertangkap harus FLEEING dulu, state %d" % _state(d))
	if is_instance_valid(d):
		d.queue_free()
		return

	# Tangkap eksplisit saat NPC MEMBAWA muatan: jalur yang sama harus bekerja,
	# jadi kontrak ini tidak berubah hanya karena syarat carrying dilonggarkan.
	var d2 := await _spawn_dumper(1)
	d2.connect("intercepted", func(n, _at): hits.append(n))
	var route2: Dictionary = DumperRoutes.by_index(1)
	_goto_wp(d2, int(route2["pickup"]))
	_check(await _wait_carrying(d2, true, 240),
		"harus membawa sebelum uji tangkap, state %d" % _state(d2))
	var ok := bool(d2.call("try_catch"))
	_check(ok, "try_catch() harus berhasil saat NPC membawa muatan")
	_check(hits.size() == 2,
		"try_catch() harus memicu intercepted tepat 1x lagi, total %d" % hits.size())
	_check(not _carrying(d2), "setelah tertangkap muatan harus hilang")
	_check(_state(d2) == S_FLEEING,
		"setelah tertangkap harus FLEEING dulu, state %d" % _state(d2))
	# Menutup NPC yang sama dua kali harus ditolak: dia sudah terminal.
	var again := bool(d2.call("try_catch"))
	_check(not again, "tangkap kedua NPC yang sama harus ditolak")
	_check(hits.size() == 2,
		"tekan E dua kali tidak boleh menambah sinyal, dapat %d" % hits.size())
	if is_instance_valid(d2):
		d2.queue_free()


func _test_no_automatic_catch() -> void:
	# Area tangkap dihapus. Badan player yang menabrak NPC tidak boleh
	# memicu apa pun -- hanya try_catch() (tombol E) yang capturing.
	var d := await _spawn_dumper(0)
	var hits: Array[String] = []
	d.connect("intercepted", func(n, _at): hits.append(n))
	d.call("_set_carrying", true)
	_check(_carrying(d), "muatan harus aktif sebelum uji tabrakan")

	# Player menabrak NPC dan tetap di sana beberapa frame. Tidak ada sinyal
	# area lagi, jadi tidak boleh ada tangkap.
	var p := _make_body(d.global_position + Vector2(20.0, 0.0), true)
	for _i in 12:
		p.global_position = d.global_position
		await physics_frame
	_check(hits.is_empty(),
		"tabrakan tidak boleh memicu intercept tanpa tekan E, dapat %d" % hits.size())
	_check(_carrying(d), "tabrakan tidak boleh menghilangkan muatan")
	_check(_state(d) != S_FLEEING and _state(d) != S_CAUGHT,
		"tabrakan tidak boleh mengubah state ke FLEEING/CAUGHT, state %d" % _state(d))
	p.queue_free()
	if is_instance_valid(d):
		d.queue_free()


func _test_try_catch_once() -> void:
	# try_catch() harus idempoten. Begitu tertangkap NPC masuk FLEEING, dan
	# FLEEING BUKAN terminal - jadi penjaga eksplisit di try_catch() yang
	# mencegah tangkap kedua, bukan state terminal. Regression ini menjaga
	# penjaga itu tetap ada setelah syarat "harus membawa" dilonggarkan.
	var d := await _spawn_dumper(0)
	var hits: Array[String] = []
	d.connect("intercepted", func(n, _at): hits.append(n))
	d.call("_set_carrying", true)
	_check(bool(d.call("try_catch")), "tangkap pertama harus berhasil")
	_check(_state(d) == S_FLEEING,
		"sesudah tertangkap harus FLEEING (bukan terminal), state %d" % _state(d))
	var again := bool(d.call("try_catch"))
	_check(not again, "tangkap kedua harus ditolak walau FLEEING belum terminal")
	_check(hits.size() == 1,
		"tekan E dua kali tidak boleh menambah sinyal, dapat %d" % hits.size())
	# NPC yang sudah terminal (selesai malam) juga tetap ditolak.
	if is_instance_valid(d):
		d.queue_free()


## NPC yang ditutup TEPAT DI TITIK RESPAWN harus terlihat kabur dulu.
##
## Ini kondisi yang muncul setelah E bisa dipakai begitu NPC spawn: player bisa
## menekan E saat NPC masih berdiri di waypoint 0. Tanpa penjaga, `try_catch()`
## menetapkan `_wp = 0` dan NPC sudah ada di sana, jadi ia "tiba" seketika,
## terminal, dan hilang 0.6 detik kemudian - player tidak pernah melihatnya
## bergerak, dan terbaca sebagai NPC lenyap begitu tertangkap.
func _test_flee_leg_visible() -> void:
	var d := await _spawn_dumper(0)
	var route: Dictionary = DumperRoutes.by_index(0)
	var respawn: Vector2 = route["titik"][0]
	# Taruh tepat di respawn.
	d.global_position = respawn
	await process_frame
	var before: Vector2 = d.global_position
	_check(d.call("try_catch"), "tangkap di respawn harus berhasil")
	_check(_state(d) == S_FLEEING,
		"harus FLEEING, bukan langsung terminal, state %d" % _state(d))
	# Tidak boleh jadi terminal dalam beberapa frame pertama.
	for _i in 30:
		await physics_frame
		if not is_instance_valid(d):
			break
	_check(is_instance_valid(d) and _state(d) == S_FLEEING,
		"NPC tidak boleh lenyap seketika; state %d" % _state(d))
	if not is_instance_valid(d):
		return
	# Dan dia harus benar-benar bergerak, bukan diam di tempat.
	var moved: float = before.distance_to(d.global_position)
	_check(moved > 20.0,
		"NPC harus terlihat bergerak saat kabur, baru jalan %.0f px" % moved)
	if is_instance_valid(d):
		d.queue_free()


## Kebalikannya: NPC yang ditutup JAUH dari respawn (mis. sedang membawa di
## titik buang, ~1900px dari rumah) harus langsung pulang, tanpa kaki tambahan.
## Kaki kabur hanya untuk NPC yang sudah berdiri di respawn; kalau tidak, tiap
## tangkapan akan berputar jauh dulu sebelum pulang.
func _test_flee_leg_not_used_when_far() -> void:
	var d := await _spawn_dumper(0)
	var route: Dictionary = DumperRoutes.by_index(0)
	var respawn: Vector2 = route["titik"][0]
	# Taruh di titik yang jauh dari respawn (titik dump).
	d.global_position = route["titik"][int(route["dump"])]
	await process_frame
	_check(d.global_position.distance_to(respawn) > 500.0,
		"prasyarat: NPC harus jauh dari respawn")
	_check(d.call("try_catch"), "tangkap harus berhasil")
	# `_flee_via` harus 0 dan target langsung respawn.
	_check(int(d.get("_flee_via")) == 0,
		"NPC jauh dari respawn tidak boleh memakai kaki kabur, dapat %d"
			% int(d.get("_flee_via")))
	var d0: Vector2 = d.global_position
	for _i in 30:
		await physics_frame
		if not is_instance_valid(d):
			break
	if is_instance_valid(d):
		# Geraknya harus menuju respawn, bukan ke kaki kabur.
		var to_home: Vector2 = (respawn - d.global_position).normalized()
		var actual: Vector2 = (d.global_position - d0).normalized()
		_check(to_home.dot(actual) > 0.5,
			"NPC harus langsung menuju respawn, arahnya %s" % actual)
	if is_instance_valid(d):
		d.queue_free()


func _test_passes_through_world() -> void:
	# collision_mask = 0: NPC menembus StaticBody2D, jadi tidak ada lagi
	# penghitung stuck / is_blocked untuk（＝）menolong.
	var d := await _spawn_dumper(0)
	var route: Dictionary = DumperRoutes.by_index(0)
	var target: Vector2 = route["titik"][1]

	# Dinding tepat di tengah jalur menuju waypoint 1.
	var wall := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(400, 40)
	cs.shape = rect
	wall.add_child(cs)
	wall.position = target - (target - d.global_position).normalized() * 40.0
	root.add_child(wall)
	await physics_frame

	_check(int(d.collision_mask) == 0,
		"collision_mask harus 0 supaya NPC menembus dunia, dapat %d"
		% int(d.collision_mask))
	_check(not d.has_method("is_blocked"),
		"is_blocked() harus dihapus: tidak ada lagi penghalang yang dihormati")

	var pos_before := d.global_position
	await _tick(120)
	# NPC harus menembus dinding dan mendekati waypoint, bukan freeze.
	_check(d.global_position.distance_to(pos_before) > 10.0,
		"NPC harus tetap bergerak menembus penghalang")
	_check(_state(d) == S_PATROL,
		"NPC harus tetap PATROL, state %d" % _state(d))
	wall.queue_free()
	if is_instance_valid(d):
		d.queue_free()


func _test_player_no_longer_blocks() -> void:
	# Player menaruh badan tepat di jalur NPC. Karena collision_mask = 0,
	# player tidak lagi menahan NPC maupun membakar counter apa pun.
	var d := _add_dumper(0)
	d.call("activate")
	var start := d.global_position
	var route: Dictionary = DumperRoutes.by_index(0)
	var target: Vector2 = route["titik"][1]
	var dir := (target - start).normalized()
	var p := _make_body(start + dir * 45.0, true)
	await process_frame

	await _tick(180)
	_check(not d.has_method("is_blocked"),
		"is_blocked() harus dihapus")
	_check(not d.has_method("is_stuck"),
		"is_stuck() harus dihapus: tidak ada lagi counter nyangkut")
	# Yang diuji adalah kemajuan, bukan posisi akhir: dalam 180 tick NPC sudah
	# bisa melewati waypoint 1 dan lanjut ke waypoint berikutnya, jadi
	# "jarak ke waypoint 1" bukan lagi ukuran diam atau tidak.
	# Diverifikasi lewat proyeksi ke arah tujuan: NPC harus maju ke depan.
	var moved := d.global_position - start
	_check(moved.length() > 100.0,
		"NPC harus tetap jalan menembus player, baru bergerak %.1f px" % moved.length())
	_check(moved.dot(dir) > 0.0,
		"NPC harus maju searah rute, bukan terdorong balik")
	p.queue_free()
	if is_instance_valid(d):
		d.queue_free()


func _test_left_right_only_animation() -> void:
	# Hanya animasi kiri/kanan yang boleh diputar. Gerak vertikal menahan
	# facing horizontal terakhir; idle juga menahan, tidak kembali "idle".
	var d := await _spawn_dumper(0)
	# Idle setelah spawn harus sudah left/right, bukan "front"/"idle".
	_check(_anim_is_lr(_anim_name(d)),
		"animasi awal harus kiri/kanan, dapat '%s'" % _anim_name(d))

	# Gerak ke kanan.
	d.velocity = Vector2(100.0, 0.0)
	d.call("_update_animation")
	_check(_anim_name(d) == "right",
		"gerak kanan harus animasi right, dapat '%s'" % _anim_name(d))

	# Bergerak vertikal: harus menahan facing terakhir (right), bukan
	#Wm gimmick ke "front"/"back".
	d.velocity = Vector2(0.0, 100.0)
	d.call("_update_animation")
	_check(_anim_name(d) == "right",
		"gerak vertikal harus menahan facing right, dapat '%s'" % _anim_name(d))

	# Bergerak ke kiri: kiri.
	d.velocity = Vector2(-100.0, 0.0)
	d.call("_update_animation")
	_check(_anim_name(d) == "left",
		"gerak kiri harus animasi left, dapat '%s'" % _anim_name(d))

	# Diam: menahan facing terakhir (left), bukan kembali idle.
	d.velocity = Vector2.ZERO
	d.call("_update_animation")
	_check(_anim_name(d) == "left",
		"diam harus menahan facing left, dapat '%s'" % _anim_name(d))
	if is_instance_valid(d):
		d.queue_free()


func _test_caught_flees_and_despawns() -> void:
	# Kontrak terminal utama: tertangkap -> FLEEING -> jalan balik ke respawn
	# -> CAUGHT -> queue_free. Tidak boleh loop di CAUGHT atau jadi diam.
	var d := await _spawn_dumper(0)
	var hits: Array[String] = []
	d.connect("intercepted", func(n, _at): hits.append(n))
	d.call("_set_carrying", true)
	_check(bool(d.call("try_catch")), "try_catch() harus berhasil")
	_check(_state(d) == S_FLEEING, "harus FLEEING setelah try_catch, state %d" % _state(d))

	# NPC kabur lebih cepat dari walk_speed normal (dibuat FLEEING).
	_check(await _wait_state(d, S_CAUGHT, 3000),
		"NPC harus sampai CAUGHT di respawn, state %d" % _state(d))
	_check(hits.size() == 1, "sinyal intercepted tetap 1x, dapat %d" % hits.size())

	# CAUGHT terminal: NPC dilepas dari tree.
	_check(await _wait_freed(d, 120),
		"NPC harus queue_free() setelah CAUGHT (terminal)")
	if is_instance_valid(d):
		d.queue_free()


func _test_dump_returns_and_despawns() -> void:
	# Berhasil buang -> RETURNING -> respawn -> ESCAPED -> queue_free.
	var d := await _spawn_dumper(0)
	var dumps: Array[Vector2] = []
	d.connect("dumped", func(_n, at): dumps.append(at))
	var route: Dictionary = DumperRoutes.by_index(0)
	_goto_wp(d, int(route["pickup"]))
	_check(await _wait_carrying(d, true, 240), "harus membawa")
	_goto_wp(d, int(route["dump"]))
	_check(await _wait_state(d, S_DUMPING, 240), "harus DUMPING, state %d" % _state(d))
	_check(await _wait_state(d, S_ESCAPED, 4000),
		"setelah buang NPC harus selesai ESCAPED di respawn, state %d" % _state(d))
	_check(dumps.size() == 1, "sinyal dumped tetap 1x, dapat %d" % dumps.size())
	_check(not _carrying(d), "NPC selesai tidak boleh masih membawa muatan")
	_check(await _wait_freed(d, 120),
		"NPC harus queue_free() setelah ESCAPED (terminal)")
	if is_instance_valid(d):
		d.queue_free()


func _test_route_id_out_of_range() -> void:
	# route_id di luar jangkauan harus jatuh ke rute 0 dan tetap jalan normal,
	# bukan crash atau jadi NPC diam. Nilai 99 dipakai karena 0..6 itu valid
	# setelah Phase 2 menambah rute Map 2.
	var d := _add_dumper(99)
	var titik: Array = DumperRoutes.by_index(0)["titik"]
	_check(d.global_position.distance_to(titik[0]) < 0.01,
		"harus jatuh ke rute 0 (waypoint 0 %s), dapat %s" % [titik[0], d.global_position])
	_check(_waypoint(d).distance_to(titik[1]) < 0.01,
		"kursor harus di waypoint 1 rute 0, dapat %s" % _waypoint(d))
	_check(_state(d) == S_IDLE, "harus tetap IDLE sebelum activate, dapat %d" % _state(d))
	d.call("activate")
	_check(_state(d) == S_PATROL, "harus tetap PATROL, state %d" % _state(d))
	_check(d.is_physics_processing(), "harus tetap aktif, bukan dimatikan")
	_check(d.visible, "harus tetap terlihat, bukan disembunyikan")

	var start := d.global_position
	await _tick(45)
	_check(d.global_position.distance_to(start) > 5.0,
		"NPC harus tetap bisa jalan setelah fallback, tetap di %s" % start)
	d.queue_free()


func _test_escape_out_of_bounds() -> void:
	# NPC yang keluar dari area main harus jadi ESCAPED, berhenti, dan kehilangan
	# muatan supaya muatan hilang dari dunia (ekonomi Phase 3).
	var d := await _spawn_dumper(0)
	d.call("_set_carrying", true)
	var escapes: Array[String] = []
	d.connect("escaped", func(n, _at): escapes.append(n))
	# Ke kanan dari batas dunia: WORLD_RECT berakhir di x=6470.
	d.global_position = Vector2(6470.0 + 400.0, 100.0)
	_check(await _wait_state(d, S_ESCAPED, 60),
		"NPC di luar batas harus ESCAPED, state %d" % _state(d))
	_check(escapes.size() == 1,
		"sinyal escaped harus keluar tepat 1x, dapat %d" % escapes.size())
	var pos := d.global_position
	await _tick(30)
	_check(d.global_position.distance_to(pos) < 0.01,
		"NPC escaped tidak boleh bergerak lagi, bergeser ke %s" % d.global_position)
	_check(d.velocity == Vector2.ZERO,
		"NPC escaped harus bervelocity nol")
	_check(not _carrying(d), "NPC escaped tidak boleh masih membawa muatan")
	d.queue_free()


func _test_terminal_is_final() -> void:
	# Setelah CAUGHT atau ESCAPED, activate() dan teleport tidak boleh
	# menghidupkan lagi. Kalau tidak, NPC yang sudah selesai (dan muatan yang
	# sudah "dibuang dari dunia") akan balik dan ekonomi bisa dihitung dua kali.
	for label in ["ESCAPED", "CAUGHT"]:
		var d := await _spawn_dumper(0)
		if label == "ESCAPED":
			# Keluar peta adalah cara tercepat mencapai ESCAPED.
			d.global_position = Vector2(6470.0 + 400.0, 100.0)
			_check(await _wait_state(d, S_ESCAPED, 60),
				"[%s] harus sampai ESCAPED dulu, state %d" % [label, _state(d)])
		else:
			# carrying + try_catch() -> FLEEING, lalu tunggu sampai CAUGHT.
			d.call("_set_carrying", true)
			_check(bool(d.call("try_catch")), "[%s] try_catch() harus berhasil" % label)
			_check(await _wait_state(d, S_CAUGHT, 3000),
				"[%s] harus sampai CAUGHT dulu, state %d" % [label, _state(d)])

		var terminal := _state(d)
		_check(terminal in S_TERMINAL,
			"[%s] harus salah satu state terminal yang terdaftar" % label)
		var pos := d.global_position
		# Terminal tidak boleh BERGERAK, dan tidak ada jalan kembali.
		# Physics sengaja tetap menyala di state terminal: itu yang menghitung
		# mundur `despawn_hold` supaya sinyal sempat dibaca sebelum node hilang.
		# Karena itu yang diuji adalah diamnya NPC, bukan matinya physics.
		await _tick(30)
		_check(d.global_position.distance_to(pos) < 0.01,
			"[%s] terminal tidak boleh bergerak lagi, bergeser ke %s" % [label, d.global_position])
		_check(d.velocity == Vector2.ZERO,
			"[%s] terminal harus bervelocity nol" % label)
		d.call("activate")
		_check(_state(d) == terminal,
			"[%s] activate tidak boleh membangkitkan terminal, state %d"
			% [label, _state(d)])
		d.call("teleport_to_waypoint", 1)
		_check(d.global_position.distance_to(pos) < 0.01,
			"[%s] teleport harus diabaikan, NPC menggeser ke %s"
			% [label, d.global_position])
		# try_catch() juga tidak boleh mengubah apa pun dari terminal.
		_check(not bool(d.call("try_catch")),
			"[%s] try_catch() harus ditolak saat terminal" % label)
		d.queue_free()


func _test_deactivate_pauses_movement() -> void:
	# deactivate() dipakai saat pagi: NPC harus berhenti di tempat, bukan jalan
	# sampai queue_free() diproses satu frame kemudian.
	var d := await _spawn_dumper(0)
	await _tick(30)
	var at := d.global_position
	d.call("deactivate")
	await _tick(30)
	_check(d.global_position.distance_to(at) < 0.5,
		"NPC deactivated tidak boleh bergerak, geser %.1f px"
		% d.global_position.distance_to(at))
	d.queue_free()


func _test_empty_route_disables() -> void:
	# NPC dijalankan dulu supaya assertion "physics mati" berarti sesuatu: kalau
	# tidak, IDLE saja sudah membuatnya mati dan test ini lolos tanpa bukti.
	var d := await _spawn_dumper(0)
	_check(d.is_physics_processing(), "NPC harus aktif sebelum rute dikosongkan")
	# Pasang rute kosong lewat seam yang sama dipakai _ready.
	var ok: bool = d.call("_apply_route", {})
	_check(not ok, "rute kosong harus ditolak")
	_check(not d.is_physics_processing(), "NPC harus dimatikan saat rute kosong")
	_check(not d.visible, "NPC harus disembunyikan saat rute kosong")
	# Semua seam publik harus aman dipanggil tanpa rute: tidak crash, tidak
	# bergerak. Kalau tidak, NPC yang salah set bisa nyasar ke (0,0).
	var pos_before := d.global_position
	d.call("teleport_to_waypoint", 3)
	_check(d.global_position.distance_to(pos_before) < 0.01,
		"teleport_to_waypoint tanpa rute harus no-op, dapat %s" % d.global_position)
	_check(_waypoint(d) == Vector2.ZERO,
		"target_waypoint tanpa rute harus ZERO, dapat %s" % _waypoint(d))
	d.queue_free()


# ---------------------------------------------------------------------- report
func _report() -> void:
	print("")
	print("===================================================")
	print("  lulus=%d  gagal=%d" % [_pass, _fail])
	if _fail > 0:
		print("  --- kegagalan ---")
		for f in _failures:
			print("  * ", f)
	print("===================================================")
