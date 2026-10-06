extends SceneTree

## Uji integrasi: NPC pembuang sampah harus dibuat NightPatrol saat malam,
## terpasang sebagai anak /root/Main, dan berjalan di rute masing-masing.
##
##   godot --headless --path <project> --script res://tests/test_main_integration.gd
##
## Berbeda dengan test_illegal_dumper.gd yang menguji satu NPC terisolasi, file
## ini memuat scene Main sungguhan supaya ownership spawn (bukan lagi instance
## statis di main.tscn) dan perilaku NPC di dunia nyata ikut terbukti.

const DumperRoutes := preload("res://scripts/dumper_routes.gd")
const MainScene := preload("res://main.tscn")
const TimeManagerScript := preload("res://scripts/time_manager.gd")
const IllegalDumperScript := preload("res://scripts/illegal_dumper.gd")
const PlayerScript := preload("res://scripts/player.gd")
const GameManagerScript := preload("res://scripts/game_manager.gd")

## Kontrak yang diuji diambil dari sumbernya, bukan ditulis ulang di sini.
## Kalau script produksi berubah angkanya, test ikut berubah dan tidak diam-diam
## menguji angka basi.
const CATCH_RANGE_PX: float = PlayerScript.CATCH_RANGE_PX
const S_FLEEING: int = IllegalDumperScript.State.FLEEING
const S_ESCAPED: int = IllegalDumperScript.State.ESCAPED
const S_CAUGHT: int = IllegalDumperScript.State.CAUGHT
const CATCH_ZONE_CENTER: float = 0.5

## Autoload project. Saat main loop dijalankan sebagai --script, autoload
## tidak didaftarkan sebagai global constant GDScript, sehingga skrip yang
## menulis "GameData"/"SaveLoad" telanjang akan gagal compile dengan
## "Identifier not found". Semua skrip produksi kini mengambil autoload
## lewat get_node("/root/<nama>") (pola yang sama dengan
## NightPatrol._game_manager()), jadi file ini bisa instantiate main.tscn
## dengan script root-nya benar-benar terpasang dan ikut jalan.
##
## Catatan cakupan: file ini membuktikan wiring NPC + bahwa skrip produksi
## itu bisa dikompilasi dan dimuat di harness headless. Perilaku UI
## (uipilah/uiolah/save_menu) belum punya assertion fungsional di sini --
## "0 SCRIPT ERROR" berarti skrip-nya valid, bukan bahwa logikanya diuji.
const AUTOLOADS := [
	["GameData", "res://scripts/game_data.gd"],
	["GameManager", "res://scripts/game_manager.gd"],
	["SaveLoad", "res://scripts/save_load.gd"],
	["AudioManager", "res://scripts/audio_manager.gd"],
]

## Rute yang dipakai pada malam pertama. Dua pembuang, satu per peta, dan rute
## DIPIN: peta 1 = rute 0 (Kurir Pasar), peta 2 = rute 3 (Petani Sawah).
## NPC peta 2 baru muncul setelah NPC peta 1 selesai.
const NIGHT_ONE_ROUTE_1 := 0
const NIGHT_ONE_ROUTE_2 := 3

var _pass := 0
var _fail := 0
var _failures: Array[String] = []
var _main: Node2D = null


func _initialize() -> void:
	await process_frame
	await _run("autoload: terdaftar", _test_autoloads)
	await _run("main: tidak ada dumper statis", _test_no_static_dumpers)
	await _run("main: malam spawn dari NightPatrol", _test_night_spawns)
	await _run("main: tiap dumper aktif di rute sendiri", _test_each_on_own_route)
	await _run("main: semua tetap dekat jalur", _test_all_stay_on_route)
	await _run("main: tidak saling menabrak", _test_no_overlap_at_spawn)
	await _run("main: pagi membuang semua NPC", _test_dawn_clears)
	await _run("E: menangkap NPC yang membawa (lewat minigame)", _test_e_catch_takes_carrying)
	await _run("E: tiga tekan meleset = NPC kabur", _test_e_miss_three_times_flees)
	await _run("E: menangkap NPC yang belum membawa (E langsung)", _test_e_catch_empty_dumper)
	await _run("E: menghormati jangkauan tangkapan", _test_e_respects_range)
	await _run("E: ditahan saat UI toko terbuka", _test_e_blocked_by_shop_ui)
	await _run("E: ditahan saat UI mesin terbuka", _test_e_blocked_by_machine_ui)
	await _run("prompt: badge [E] muncul saat dekat NPC", _test_catch_prompt_appears)
	await _run("prompt: badge hilang saat jauh dari NPC", _test_catch_prompt_hidden)
	await _run("marker: RogueMarker ter-mount di Player", _test_rogue_marker_mounted)
	await _run("marker: peta 2 = NPC kedua benar-benar spawn", _test_map2_rogue_spawns)
	await _run("marker: panah tepi diarahkan ke peta 2", _test_marker_edge_hint)
	await _run("HUD patrol ter-mount di Player", _test_patrol_hud_mounted)
	await process_frame
	await process_frame
	_free_main()
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


## Bandingkan isi dua array berurutan. Dipakai untuk array integer hasil
## panggilan ke kode produksi, yang tipenya tidak bisa disimpulkan di sini.
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


# ------------------------------------------------------------------- fixture
func _register_autoloads() -> void:
	for pair in AUTOLOADS:
		var n: String = pair[0]
		if root.has_node(n):
			continue
		var scr: Script = load(pair[1])
		var node := Node.new()
		node.name = n
		node.set_script(scr)
		root.add_child(node)


## Menambah scene Main ke tree TANPA menunggu frame, supaya snap posisi
## waypoint 0 milik NPC bisa diperiksa sebelum mereka sempat jalan.
func _load_main() -> Node2D:
	_free_main()
	_main = MainScene.instantiate()
	root.add_child(_main)
	# NightPatrol mencari host lewat /root/Main, jadi nama harus persis itu.
	_main.name = "Main"
	return _main as Node2D


## free() langsung, bukan queue_free(): nama node harus benar-benar lepas
## sebelum instantiate berikutnya, kalau tidak node kedua akan diberefi nama
## Main2 dan /root/Main tidak ditemukan.
func _free_main() -> void:
	if is_instance_valid(_main):
		_main.free()
	_main = null


func _dumpers(m: Node2D) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for c in m.get_children():
		if c is CharacterBody2D and c.is_in_group("illegal_dumpers"):
			out.append(c as Node2D)
	return out


func _off_route(d: Node2D, idx: int) -> float:
	var titik: Array = DumperRoutes.by_index(idx)["titik"]
	var best := INF
	for t in titik:
		best = min(best, d.global_position.distance_to(t))
	return best


func _tick(n: int) -> void:
	for _i in n:
		await physics_frame


# ----------------------------------------------------------------------- tests
## Semua autoload yang dipakai kode produksi harus terdaftar di /root saat mode
## --script. Kode produksi mengambilnya lewat get_node("/root/<nama>"), bukan
## sebagai global GDScript, jadi test ini cukup memverifikasi node-nya ada.
func _test_autoloads() -> void:
	_register_autoloads()
	for pair in AUTOLOADS:
		var n: String = pair[0]
		_check(root.has_node(NodePath(n)),
			"autoload /root/%s harus ada" % n)


## NPC tidak boleh lagi jadi instance statis di main.tscn. Ownership spawn
## milik NightPatrol: kalau ada dumper yang tertanam di scene, malam akan
## punya NPC yang tidak ikut dihitung 2/2 dan tidak bisa dilepas pagi.
func _test_no_static_dumpers() -> void:
	var m := _load_main()
	await process_frame
	_check(_dumpers(m).is_empty(),
		"main.tscn tidak boleh lagi memuat dumper statis, dapat %d" % _dumpers(m).size())
	_free_main()


## Malam pertama sekarang hanya spawn SATU NPC (peta 1). NPC peta 2 menyusul
## setelah yang pertama selesai, jadi test ini harus memancing lewat sinyal
## `intercepted` untuk mendapat NPC kedua - persis seperti gameplay.
func _test_night_spawns() -> void:
	var m := _load_main()
	await process_frame
	var made: Array = _spawn_night_one()
	if not _check(made.size() == 1,
			"malam pertama harus spawn 1 NPC (peta 1 saja), dapat %d" % made.size()):
		_free_main()
		return
	var d: Node2D = made[0]
	_check(int(d.get("route_id")) == NIGHT_ONE_ROUTE_1,
		"NPC peta 1 harus rute %d, dapat %d" % [NIGHT_ONE_ROUTE_1, int(d.get("route_id"))])
	_check(d.get_parent() == m, "NPC harus anak /root/Main")
	_check(d.is_physics_processing(), "NPC harus aktif sejak malam")
	_check(_dumpers(m).size() == 1,
		"Main harus punya 1 NPC di awal malam, dapat %d" % _dumpers(m).size())
	# NPC kedua baru muncul setelah yang pertama tertangkap.
	d.emit_signal("intercepted", "Kurir Pasar", Vector2.ZERO)
	var after: Array = _dumpers(m)
	_check(after.size() == 2,
		"setelah NPC pertama tertangkap harus ada 2 NPC, dapat %d" % after.size())
	if after.size() == 2:
		var d2: Node2D = after[1]
		_check(int(d2.get("route_id")) == NIGHT_ONE_ROUTE_2,
			"NPC kedua harus rute %d, dapat %d" % [NIGHT_ONE_ROUTE_2, int(d2.get("route_id"))])
	_free_main()


## Dua NPC harus memakai dua rute BERBEDA, di peta berbeda - kalau tidak,
## "satu di peta 1, satu di peta 2" jadi tidak lebih dari dua instance rute sama.
func _test_each_on_own_route() -> void:
	var m := _load_main()
	await process_frame
	var made: Array = _spawn_night_one()
	if not _check(made.size() == 1, "butuh NPC peta 1, dapat %d" % made.size()):
		_free_main()
		return
	# Diperiksa tanpa menunggu frame: NPC harus snap persis ke waypoint 0.
	var d: Node2D = made[0]
	_check(_near_waypoint(d, int(d.get("route_id")), 0) < 1.0,
		"NPC harus snap ke waypoint 0 di awal")
	var wp0: Vector2 = DumperRoutes.by_index(int(d.get("route_id")))["titik"][0]
	_check(d.global_position.distance_to(wp0) < 1.0,
		"NPC harus persis di waypoint 0, dapat %s" % d.global_position)
	d.emit_signal("intercepted", "Kurir Pasar", Vector2.ZERO)
	var after: Array = _dumpers(m)
	if not _check(after.size() == 2, "butuh 2 NPC untuk cek rute, dapat %d" % after.size()):
		_free_main()
		return
	var rid1 := int(after[0].get("route_id"))
	var rid2 := int(after[1].get("route_id"))
	_check(rid1 != rid2, "dua NPC harus beda rute, keduanya %d" % rid1)
	var map1 := int(DumperRoutes.by_index(rid1).get("map", 0))
	var map2 := int(DumperRoutes.by_index(rid2).get("map", 0))
	_check(map1 != map2,
		"dua NPC harus di peta berbeda, keduanya peta %d" % map1)
	_free_main()


func _near_waypoint(d: Node2D, route_idx: int, wp: int) -> float:
	var titik: Array = DumperRoutes.by_index(route_idx)["titik"]
	var p: Vector2 = titik[wp % titik.size()]
	return d.global_position.distance_to(p)


## Setelah 600 frame NPC tidak boleh tersesat: hanya ada DUA NPC, dan keduanya
## harus masih di dekat jalur masing-masing. Ini yang menangkap regresi rute.
func _test_all_stay_on_route() -> void:
	var m := _load_main()
	await process_frame
	var made: Array = _spawn_night_one()
	if made.is_empty():
		_check(false, "tidak ada NPC untuk diuji")
		_free_main()
		return
	# Pancing NPC kedua supaya keduanya berjalan bersamaan.
	made[0].emit_signal("intercepted", "Kurir Pasar", Vector2.ZERO)
	var both: Array = _dumpers(m)
	if not _check(both.size() == 2, "butuh 2 NPC, dapat %d" % both.size()):
		_free_main()
		return
	await _tick(200)
	for d in both:
		if not is_instance_valid(d):
			continue
		var rid := int(d.get("route_id"))
		var off := _off_route(d, rid)
		# Toleransi longgar: yang dicek NPC tidakandar liar jauh dari rutenya,
		# bukan presisi piksel. 400px lebih dari lebar jalan.
		_check(off < 400.0,
			"NPC rute %d jauh dari jalur (%d px) di %s" % [rid, int(off), d.global_position])
	_free_main()


## Dua NPC pada malam yang sama tidak boleh mulai di titik yang sama. Satu per
## peta jadi ini harus otomatis terpenuhi, tapi assertion ini menjaga kalau
## suatu saat "spawn keduanya" ditambahkan tanpa lihat-lik radius.
func _test_no_overlap_at_spawn() -> void:
	var m := _load_main()
	await process_frame
	_spawn_night_one()
	var ds: Array = _dumpers(m)
	if not _check(ds.size() == 1, "butuh minimal 1 dumper, dapat %d" % ds.size()):
		_free_main()
		return
	ds[0].emit_signal("intercepted", "Kurir Pasar", Vector2.ZERO)
	var both: Array = _dumpers(m)
	if both.size() < 2:
		_check(false, "butuh 2 NPC setelah pancing, dapat %d" % both.size())
		_free_main()
		return
	var d0: Node2D = both[0]
	var d1: Node2D = both[1]
	var gap := d0.global_position.distance_to(d1.global_position)
	_check(gap > 8.0,
		"dua NPC tidak boleh mulai menumpuk (jarak %d px)" % int(gap))
	_free_main()


func _test_dawn_clears() -> void:
	var m := _load_main()
	await process_frame
	var tm := _time_manager(m)
	if tm == null:
		_check(false, "Main harus punya TimeManager")
		_free_main()
		return
	var p := root.get_node_or_null("NightPatrol")
	if p == null:
		_check(false, "autoload NightPatrol harus ada")
		_free_main()
		return
	# auto_spawn harus true di test ini: justru fase NIGHT/DAY yang diuji, bukan
	# pemanggilan begin_night() manual seperti di test lain.
	p.set("auto_spawn", true)
	p.call("clear")
	tm.emit_signal("phase_changed", TimeManagerScript.Phase.NIGHT)
	await process_frame
	if not _check(_dumpers(m).size() == 1,
		"NIGHT harus spawn 1 NPC, dapat %d" % _dumpers(m).size()):
		_free_main()
		return
	tm.emit_signal("phase_changed", TimeManagerScript.Phase.DAY)
	await process_frame
	await process_frame
	_check(_dumpers(m).is_empty(),
		"pagi harus membuang semua NPC, masih %d" % _dumpers(m).size())
	_free_main()


func _time_manager(m: Node2D) -> Node:
	for c in m.get_children():
		if c.is_in_group("time_manager"):
			return c
	return null


# ------------------------------------------------------- tangkapan pakai tombol E
## Tangkapan sekarang lewat MINIGAME: E pertama membuka bar, E kedua di zona
## yang benar yang menutup NPC. Semua test di sini menekan E lewat jalur input
## sungguhan (`_unhandled_input`), lalu lalu mengatur posisi bar
## lewat handle minigame yang sama - supaya wiring tombol -> buka minigame ->
## nilai timing -> try_catch ikut teruji, bukan try_catch() langsung.
class StubMachine extends Node2D:
	func _ready() -> void:
		add_to_group("machines")

	func is_ui_open() -> bool:
		return true


## Handle minigame milik player, untuk mengatur posisi bar supaya tekan E
## jatuh DI dalam atau DI luar zona.
func _minigame(player: Node) -> Node:
	for c in player.get_children():
		if c.name == "CatchMinigame":
			return c
	return null


func _open_minigame_on(player: Node, carrier: Node2D) -> Node:
	player.global_position = carrier.global_position
	player.velocity = Vector2.ZERO
	_press_e(player)  # E pertama: buka minigame
	var mg := _minigame(player)
	if mg == null:
		return null
	# Tahan bar tepat di tengah zona supaya tekan E berikutnya = sukses.
	mg.set("_pos", CATCH_ZONE_CENTER)
	return mg


## E pertama membuka minigame dan MENAHAN NPC; E kedua di zona = tertangkap.
## Koin TIDAK berubah di sini: ekonomi per malam, dibayar lewat klaim.
func _test_e_catch_takes_carrying() -> void:
	_load_main()
	var made := _spawn_night_one()
	if not _check(made.size() == 1, "butuh NPC, dapat %d" % made.size()):
		_free_main()
		return
	var carrier: Node2D = made[0]
	await _make_carrying(carrier)
	_check(bool(carrier.call("is_carrying")),
		"NPC harus sudah membawa sebelum diuji")

	var player := _player()
	var before := _coins()
	var mg := _open_minigame_on(player, carrier)
	if not _check(mg != null, "Player harus punya anak CatchMinigame"):
		_free_main()
		return
	_check(bool(mg.call("is_active")), "E pertama harus membuka minigame")
	_check(bool(carrier.call("is_frozen")),
		"NPC harus dibekukan selama minigame, bukan jalangement")
	# Tekan E kedua saat bar di zona: tangkapan sukses = NPC langsung hilang.
	_press_e(player)
	_check(int(carrier.call("current_state")) == S_CAUGHT,
		"NPC harus langsung CAUGHT setelah tekan E tepat, dapat %d"
			% int(carrier.call("current_state")))
	_check(not carrier.visible,
		"NPC tertangkap harus langsung hilang")
	_check(not bool(carrier.call("is_frozen")),
		"NPC harus thawed setelah minigame selesai")
	_check(_coins() == before,
		"tangkapan tidak boleh membayar per NPC, dari %d jadi %d" % [before, _coins()])
	_free_main()


## Tekan E tiga kali di luar zona = NPC lolos dan jalan pulang ke respawn.
## Dulu tiga gagal berarti NPC langsung ESCAPED di tempat; sekarang dia
## FLEEING pulang dulu dan jadi ESCAPED saat tiba di respawn.
func _test_e_miss_three_times_flees() -> void:
	_load_main()
	var made := _spawn_night_one()
	if made.is_empty():
		_check(false, "tidak ada NPC")
		_free_main()
		return
	var carrier: Node2D = made[0]
	await _make_carrying(carrier)
	var player := _player()
	var mg := _open_minigame_on(player, carrier)
	if mg == null:
		_check(false, "minigame tidak terbuka")
		_free_main()
		return
	# Tiga tekan meleset: bar di ujung jauh dari zona.
	for i in 3:
		mg.set("_pos", 0.0)
		_press_e(player)
	_check(int(carrier.call("current_state")) == S_FLEEING,
		"tiga gagal harus membuat NPC FLEEING pulang, dapat %d"
			% int(carrier.call("current_state")))
	_check(carrier.visible,
		"NPC yang lolos harus tetap terlihat saat jalan pulang")
	_check(not bool(mg.call("is_active")), "minigame harus tertutup setelah gagal 3x")
	_free_main()


## NPC yang belum mengambil sampah TETAP bisa ditutup. Dulu E di dekat NPC
## kosong diam-diam tidak terjadi apa-apa dan player harus menunggu NPC
## berjalan ke waypoint ambil - inilah yang dikeluhkan user. Sekarang
## begitu NPC muncul, E langsung membuka minigame.
func _test_e_catch_empty_dumper() -> void:
	_load_main()
	var made := _spawn_night_one()
	if made.is_empty():
		_check(false, "tidak ada NPC")
		_free_main()
		return
	var carrier: Node2D = made[0]
	# Sengaja TIDAK _make_carrying: NPC masih kosong, baru spawn.
	_check(not bool(carrier.call("is_carrying")),
		"prasyarat: NPC harus belum membawa")
	var player := _player()
	player.global_position = carrier.global_position
	player.velocity = Vector2.ZERO
	_press_e(player)
	var mg := _minigame(player)
	_check(mg != null and bool(mg.call("is_active")),
		"E harus membuka minigame bahkan kalau NPC belum membawa")
	# Dan tekan yang benar harus tetap menutupnya: langsung CAUGHT + hilang.
	if mg != null:
		mg.set("_pos", CATCH_ZONE_CENTER)
		_press_e(player)
		_check(int(carrier.call("current_state")) == S_CAUGHT,
			"NPC kosong yang ditekan tepat harus langsung CAUGHT, state %d"
				% int(carrier.call("current_state")))
		_check(not carrier.visible,
			"NPC tertangkap harus langsung hilang")
	_free_main()


## Jangkauan tangkapan tetap dijaga: NPC di luar CATCH_RANGE_PX tidak bisa
## memulai minigame meski dia membawa.
func _test_e_respects_range() -> void:
	_load_main()
	var made := _spawn_night_one()
	if made.is_empty():
		_check(false, "tidak ada NPC")
		_free_main()
		return
	var carrier: Node2D = made[0]
	await _make_carrying(carrier)
	var player := _player()
	# Jauh di luar CATCH_RANGE_PX tapi masih di dalam peta.
	player.global_position = carrier.global_position + Vector2(CATCH_RANGE_PX + 150.0, 0)
	player.velocity = Vector2.ZERO
	_press_e(player)
	var mg := _minigame(player)
	_check(mg == null or not bool(mg.call("is_active")),
		"NPC di luar jangkauan tidak boleh memulai minigame")
	_free_main()


## UI toko terbuka = E dipakai untuk belanja, bukan untuk tangkapan.
func _test_e_blocked_by_shop_ui() -> void:
	_load_main()
	var made := _spawn_night_one()
	if made.is_empty():
		_check(false, "tidak ada NPC")
		_free_main()
		return
	var carrier: Node2D = made[0]
	await _make_carrying(carrier)
	var stub := _make_shop_stub()
	var player := _player()
	player.global_position = carrier.global_position
	player.velocity = Vector2.ZERO
	_press_e(player)
	var mg := _minigame(player)
	_check(mg == null or not bool(mg.call("is_active")),
		"E di belakang UI toko tidak boleh membuka minigame tangkapan")
	stub.free()
	_free_main()


## UI mesin terbuka juga memakai E-nya, sama seperti toko.
func _test_e_blocked_by_machine_ui() -> void:
	_load_main()
	var made := _spawn_night_one()
	if made.is_empty():
		_check(false, "tidak ada NPC")
		_free_main()
		return
	var carrier: Node2D = made[0]
	await _make_carrying(carrier)
	var stub := StubMachine.new()
	stub.position = Vector2(50, 50)
	root.add_child(stub)
	var player := _player()
	player.global_position = carrier.global_position
	player.velocity = Vector2.ZERO
	_press_e(player)
	var mg := _minigame(player)
	_check(mg == null or not bool(mg.call("is_active")),
		"E di belakang UI mesin tidak boleh membuka minigame tangkapan")
	stub.free()
	_free_main()


## Prompt badge harus muncul selama player dekat NPC hidup, karena inilah yang
## memberi tahu tombol mana yang dipakai. Tanpa ini, E adalah tombol misterius.
func _test_catch_prompt_appears() -> void:
	_load_main()
	var made := _spawn_night_one()
	if made.is_empty():
		_check(false, "tidak ada NPC")
		_free_main()
		return
	var carrier: Node2D = made[0]
	var player := _player()
	player.global_position = carrier.global_position
	player.velocity = Vector2.ZERO
	# _update_catch_prompt() dipanggil dari _physics_process, jadi satu frame.
	await physics_frame
	await physics_frame
	var badge: Node = null
	for c in player.get_children():
		if c.name == "CatchPrompt":
			badge = c
			break
	_check(badge != null, "harus ada anak CatchPrompt di Player")
	if badge != null:
		_check(badge.visible, "badge harus terlihat saat player dekat NPC")
	_free_main()


func _test_catch_prompt_hidden() -> void:
	_load_main()
	var made := _spawn_night_one()
	if made.is_empty():
		_check(false, "tidak ada NPC")
		_free_main()
		return
	var carrier: Node2D = made[0]
	var player := _player()
	# Jauh dari NPC: tidak ada yang bisa ditangkap, jadi tidak ada prompt.
	player.global_position = carrier.global_position + Vector2(CATCH_RANGE_PX + 400.0, 0)
	player.velocity = Vector2.ZERO
	await physics_frame
	await physics_frame
	var badge: Node = null
	for c in player.get_children():
		if c.name == "CatchPrompt":
			badge = c
			break
	if badge != null:
		_check(not badge.visible, "badge harus hilang saat player jauh dari NPC")
	_free_main()


## Penunjuk pembuang liar harus ter-mount: tanpa itu, tidak ada cara memastikan
## NPC benar-benar spawn (ini keluhan user: "tidak pernah lihat di Map 2").
func _test_rogue_marker_mounted() -> void:
	_load_main()
	var player := _player()
	_check(player != null, "Main harus punya Player")
	if player == null:
		return
	var marker := player.get_node_or_null("RogueMarker")
	_check(marker != null, "Player scene harus punya anak RogueMarker")
	if marker != null:
		_check(marker.has_method("setup"),
			"RogueMarker harus punya setup()")
		# Punya kedua mode tampilan: on-screen chevron dan edge arrow.
		_check(marker.get_node_or_null("OnScreenMarker") != null,
			"RogueMarker harus punya node OnScreenMarker")
		_check(marker.get_node_or_null("EdgeMarker") != null,
			"RogueMarker harus punya node EdgeMarker")
	# Dengan NPC aktif, marker harus terlihat (menandakan ada target).
	var made := _spawn_night_one()
	if not made.is_empty() and marker != null:
		# Marker menggambar di _process(), jadi harus menunggu frame idle -
		# hanya await physics_frame bisa resolve sebelum _process jalan.
		await process_frame
		await physics_frame
		_check(marker.visible,
			"marker harus terlihat saat ada NPC aktif, supaya player tahu dia benar-benar spawn")
	_free_main()


## Keluhan user: "tidak pernah lihat pembuang di Map 2". Ini yang membuktikannya
## NPC kedua benar-benar spawn di peta 2 setelah NPC pertama tertangkap, dan
## rutenya peta 2 - bukan sekadar "tidak error".
func _test_map2_rogue_spawns() -> void:
	_load_main()
	var made := _spawn_night_one()
	if not _check(made.size() == 1, "mulai harus 1 NPC, dapat %d" % made.size()):
		_free_main()
		return
	# Tangkap NPC pertama lewat jalur gameplay: E + minigame.
	var player := _player()
	player.global_position = made[0].global_position
	player.velocity = Vector2.ZERO
	var mg := _open_minigame_on(player, made[0])
	if mg != null:
		_press_e(player)  # tekan tepat -> tertangkap -> peta 2 muncul
	var after: Array = _dumpers(_main)
	if not _check(after.size() == 2,
			"harus ada 2 NPC setelah yang pertama tertangkap, dapat %d" % after.size()):
		_free_main()
		return
	# NPC baru harus di peta 2.
	var new_rid := int(after[1].get("route_id"))
	var new_map := int(DumperRoutes.by_index(new_rid).get("map", 0))
	_check(new_map == 2, "NPC kedua harus di peta 2, dapat peta %d" % new_map)
	_free_main()


## Panel tepi harus menyebut peta tujuan. Diuji langsung lewat _map_hint()
## supaya logika label ikut teruji, bukan hanya node-nya ada.
func _test_marker_edge_hint() -> void:
	_load_main()
	var made := _spawn_night_one()
	if made.is_empty():
		_check(false, "tidak ada NPC")
		_free_main()
		return
	# NPC pertama berokurid peta 1.
	var player := _player()
	var marker = player.get_node_or_null("RogueMarker")
	if not _check(marker != null, "harus ada RogueMarker"):
		_free_main()
		return
	var hint1: String = marker.call("_map_hint", made[0])
	_check(hint1 == "Map 1", "NPC peta 1 harus berlabel 'Map 1', dapat '%s'" % hint1)
	# Pancing NPC peta 2, lalu cek labelnya berubah.
	made[0].emit_signal("intercepted", "Kurir Pasar", Vector2.ZERO)
	var after: Array = _dumpers(_main)
	if after.size() >= 2:
		var hint2: String = marker.call("_map_hint", after[1])
		_check(hint2 == "Map 2", "NPC peta 2 harus berlabel 'Map 2', dapat '%s'" % hint2)
	else:
		_check(false, "NPC peta 2 tidak muncul untuk diuji label")
	_free_main()


func _make_shop_stub() -> Node:
	var s := Node2D.new()
	s.add_to_group("shops")
	s.set_script(load("res://tests/_shop_stub.gd"))
	root.add_child(s)
	return s


# ------------------------------------------------------------------ HUD di Player
## HUD patrol harus benar-benar anak dari Player scene, DAN punya tombol klaim
## (bukan bar pollution / bar MEMBUANG yang lama).
func _test_patrol_hud_mounted() -> void:
	_load_main()
	var player := _player()
	_check(player != null, "Main harus punya Player")
	if player == null:
		return
	var hud: Node = null
	for c in player.get_children():
		if c.name == "PatrolHUD":
			hud = c
			break
	_check(hud != null, "Player scene harus punya anak PatrolHUD")
	if hud == null:
		return
	var labels := hud.find_children("*", "Label", true, false)
	_check(labels.size() >= 2,
		"PatrolHUD harus punya minimal 2 label (judul + TERTANGKAP), dapat %d"
			% labels.size())
	var btn := hud.find_child("ClaimButton", true, false) as Button
	_check(btn != null, "PatrolHUD harus punya tombol ClaimButton")
	if btn != null:
		_check(btn.disabled, "tombol klaim harus mati di awal malam")


# ----------------------------------------------------------------------- helpers
func _player() -> Node2D:
	if _main == null:
		return null
	return _main.get_node_or_null("Player") as Node2D


func _coins() -> int:
	var gm := root.get_node_or_null("GameManager")
	if gm == null:
		return -1
	return int(gm.get("coins"))


## Tekan E lewat jalur input sungguhan. Hasilnya dinilai dari state NPC dan
## status minigame, bukan dari flag "input handled": flag itu bisa sudah
## terpasang oleh input lain di frame yang sama, jadi membacanya bikin test rapuh.
func _press_e(player: Node) -> void:
	if player == null:
		return
	var ev := InputEventKey.new()
	ev.keycode = KEY_E
	ev.pressed = true
	ev.echo = false
	player.call("_unhandled_input", ev)


## Bikin satu NPC benar-benar membawa, lewat jalur nyata: activate(), lalu
## teleport ke waypoint ambil dan biarkan `_arrive()` memicunya.
##
## Tidak menunggu jalan kaki. NPC bergerak ~95 px/s, jadi dari posisi spawn ke
## waypoint ambil bisa memakan 800+ frame; itu membuat test lambat tanpa
## menambah cakupan apa pun, karena yang diuji adalah kontrak E bukan hopeless
## waktu tempuh rute.
func _make_carrying(d: Node2D) -> void:
	if d == null or not is_instance_valid(d):
		return
	d.call("activate")
	var route: Dictionary = d.get("_route")
	if route.is_empty():
		_check(false, "NPC tidak punya rute, jadi tidak bisa dibuat membawa")
		return
	d.call("teleport_to_waypoint", int(route["pickup"]))
	# Dua frame: satu untuk mendeteksi tiba, satu untuk efek `_arrive()`.
	await physics_frame
	await physics_frame


## Spawn lewat autoload NightPatrol sungguhan, fase dikendalikan manual supaya
## hasil tes tidak bergantung jam. `begin_night` menghasilkan SATU NPC (peta 1);
## NPC peta 2 menyusul setelah yang pertama selesai.
func _spawn_night_one() -> Array:
	var p := root.get_node_or_null("NightPatrol")
	if p == null:
		return []
	# auto_spawn dimatikan supaya jam dunia tidak memicu malamnya sendiri;
	# malam di sini dibuat eksplisit lewat begin_night(1).
	p.set("auto_spawn", false)
	p.call("clear")
	p.call("begin_night", 1)
	var made: Array = p.call("active_dumpers")
	return made
