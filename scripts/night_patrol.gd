extends Node

## Autoload "NightPatrol": pemilik tunggal siklus hidup NPC pembuang sampah.
##
## NPC tidak pernah ada di main.tscn. Node ini yang spawn saat malam dan
## membuang saat pagi, jadi "siapa yang spawn NPC" punya satu jawaban.
##
## Malam sekarang punya dua pembuang, bukan enam, dan mereka berurutan:
## pembuang Map 1 muncul lebih dulu, dan pembuang Map 2 TIDAK muncul sampai
## yang pertama sudah tertangkap atau lolos. Jadi player cuma punya satu
## obin pada satu waktu, dan "2/2" di HUD adalah dua orang, bukan enam rute.
##
## Yang ditangani di sini juga: ekonomi per malam lewat `patrol_claimed`, dan
## angka untuk HUD lewat `patrol_progress`.

const DUMPER_SCENE := preload("res://scenes/IllegalDumper.tscn")
const DUMPER_ROUTES := preload("res://scripts/dumper_routes.gd")
const TIME_MANAGER := preload("res://scripts/time_manager.gd")

## TimeManager bukan autoload; ia mendaftarkan diri lewat grup ini.
const TIME_MANAGER_GROUP := &"time_manager"

const MAP_IDS := [1, 2]

## Dua pembuang saja per malam, satu di tiap peta, dan mereka berurutan.
##
## Rute dipin, bukan dipilih bergantian seperti sebelumnya. Alasannya: malam ini
## selalu soal dua orang yang sama, jadi player bisa belajar rute dan tidak
## ikut mengingat rute mana yang keluar. "Kurir Pasar" di Map 1 selalu pertama,
## "Petani Sawah" di Map 2 selalu kedua.
const ROGUE_ROUTES := {1: 0, 2: 3}

## Berapa pembuang yang harus tertangkap untuk menang. Menentukan juga penyebut
## HUD ("0/2") dan ambang klaim.
const NIGHT_TARGET := 2

## Rute memakai koordinat global `Main`, jadi NPC dipasangkan ke root Main
## (bukan ke Map1/Map2) agar tidak ada transform yang perlu dikompensasi.
const HOST_PATH := ^"/root/Main"

signal patrol_spawned(dumper: Node2D, route_id: int)
signal patrol_cleared(night_number: int)

## Dipancarkan setiap kali angka tangkapan berubah: (tertangkap, total target).
## `total` = NIGHT_TARGET sepanjang malam, sejak NPC kedua belum spawn. HUD
## harus menulis "0/2" dari detik pertama, bukan "0/1" lalu melompat ke "0/2".
signal patrol_progress(caught: int, total: int)

## Dipancarkan sekali saat player benar-benar meng klaim hadiah malam. HUD
## memakai ini untuk mengunci tombol klaim supaya tidak bisa diklik dua kali.
signal patrol_claimed()

var _active: Array[Node2D] = []

## Berapa NPC yang sudah ditutup player malam ini. Reset tiap malam baru.
var _caught := 0

## True kalau hadiah malam sudah diklaim. Satu kali per malam; toggle ini yang
## mencegah +100 dibayar dua kali.
var _claimed := false

## Malam yang sedang dihitung. -1 = belum ada malam, jadi spawn berikutnya
## selalu dianggap malam baru dan angka lama dibuang.
var _night_id := -1

## Peta yang masih menunggu giliran spawn, dalam urutan. Setelah Map 1
## di-spawn, isinya [2]; setelah Map 2, kosong. Intro malam diisi [1, 2] lalu
## Map 1 langsung keluar, jadi tidak ada antrean panjang.
var _pending_maps: Array[int] = []

## Diisi map_seam.gd saat player benar-benar menyeberang.
var current_map: int = 1

var night_number: int = 0

## Test mematikan ini supaya fase tidak memicu spawn tanpa TimeManager sungguhan.
var auto_spawn := true

var _time_manager: Node = null

## Fase terakhir yang sudah dilayani. -1 = belum ada. Satu fase hanya boleh
## dilayani sekali; sinyal ganda akan menambah NPC dan menaikkan night_number.
var _last_phase := -1

## true selama NightPatrol menunggu TimeManager muncul di tree.
var _watching := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _attach_time_manager():
		# TimeManager hidup di Main, bukan autoload, jadi saat autoload siap
		# scene utama belum dimuat. Tunggu lewat sinyal node_added.
		_start_watching()


## -------------------------------------------------- pemilihan rute per malam
## Semua index rute milik satu peta, sesuai urutan DumperRoutes.ALL.
func routes_for_map(map_id: int) -> Array[int]:
	var out: Array[int] = []
	for i in DUMPER_ROUTES.ALL.size():
		if int(DUMPER_ROUTES.ALL[i].get("map", 0)) == map_id:
			out.append(i)
	return out


## Rute yang dipakai satu peta malam ini. Dipin lewat ROGUE_ROUTES; peta yang
## tidak punya pin mengembalikan -1 supaya caller tidak pernah spawn tanpa rute.
func rogue_route_id(map_id: int) -> int:
	if not ROGUE_ROUTES.has(map_id):
		return -1
	return int(ROGUE_ROUTES[map_id])


## ------------------------------------------------------------------ spawning
## Mulai satu malam: reset angka, spawn pembuang Map 1, antrekan pembuang
## Map 2. Panggilannya tidak fatally terkait TimeManager, jadi test bisa
## memanggilnya langsung.
func begin_night(night: int) -> void:
	_night_id = night
	_caught = 0
	_claimed = false
	_active.clear()
	_pending_maps = [1, 2]
	# Angka HUD ditulis SEBELUM NPC pertama spawn, supaya "0/2" muncul di layar
	# bahkan kalau host Main belum ada. Kalau emit ini ditunda sampai sesudah
	# spawn, malam yang gagal spawn tampil sebagai "TERTANGKAP -".
	_emit_progress()
	_spawn_next_pending()


## Spawn pembuang berikutnya yang sudah gilir. Dipanggil saat malam dimulai
## dan lagi setiap kali pembuang sebelumnya selesai (tertangkap atau lolos).
func _spawn_next_pending() -> void:
	if _pending_maps.is_empty():
		return
	var map_id: int = _pending_maps.pop_front()
	spawn_rogue(map_id)


## Spawn satu pembuang untuk satu peta. Mengembalikan NPC-nya, atau null kalau
## host belum ada atau peta tidak punya rute.
func spawn_rogue(map_id: int) -> Node2D:
	var rid := rogue_route_id(map_id)
	if rid < 0:
		push_warning("NightPatrol: peta %d tidak punya rute pembuang" % map_id)
		return null
	var host := _host()
	if host == null:
		push_warning("NightPatrol: host %s belum ada, spawn dilewati" % HOST_PATH)
		return null
	var dumper := DUMPER_SCENE.instantiate() as Node2D
	# route_id dan tint diset sebelum add_child: _ready() membaca route_id
	# untuk memasang rute, dan tint harus siap sebelum sprite pertama tampil.
	var route: Dictionary = DUMPER_ROUTES.ALL[rid]
	dumper.set("route_id", rid)
	dumper.set("tint", route.get("tint", Color(0.78, 0.72, 0.60)))
	host.add_child(dumper)
	# add_child sudah menjalankan _ready() dengan physics mati; activate()
	# menyalakannya setelah rute terpasang.
	dumper.call("activate")
	_wire_economy(dumper)
	_wire_release(dumper)
	_active.append(dumper)
	patrol_spawned.emit(dumper, rid)
	return dumper


# ------------------------------------------------------- ekonomi + pelepasan
## Hubungkan satu NPC ke ekonomi. Dipanggil tepat sekali per NPC, di
## spawn_rogue(), jadi tidak ada NPC yang bisa lolos tanpa ikut dihitung.
##
## intercepted = tangkapan berhasil -> angka "n/2" naik. TIDAK ada koin di sini:
## ekonomi dihitung per malam, bukan per NPC (lihat _resolve_night/claim_reward).
func _wire_economy(dumper: Node2D) -> void:
	if dumper.has_signal(&"intercepted"):
		dumper.connect(&"intercepted", _on_dumper_intercepted)


## Hubungkan NPC ke antrean spawn. Begitu NPC ini selesai - tertangkap ATAU
## lolos - giliran berikutnya boleh jalan, dan itu yang membuat "satu obin di satu
## waktu" jadi aturan yang ditegakkan, bukan sekadar urutan angka.
func _wire_release(dumper: Node2D) -> void:
	for s in [&"intercepted", &"escaped"]:
		if dumper.has_signal(s):
			dumper.connect(s, _on_dumper_resolved)


func _on_dumper_intercepted(_route: String, _at: Vector2) -> void:
	_caught += 1
	_emit_progress()


## Pembuang pertama sudah selesai, apa pun hasilnya.-now giliran pembuang kedua.
func _on_dumper_resolved(_route: String, _at: Vector2) -> void:
	_spawn_next_pending()


## True kalau player boleh menekan tombol klaim: malam sedang berjalan, kedua
## pembuang sudah tertangkap, dan hadiah belum diambil.
func can_claim() -> bool:
	return _night_id >= 0 and _caught >= NIGHT_TARGET and not _claimed


## Player menekan tombol klaim. Membayar +100 sekali per malam.
##
## Sengaja TIDAK otomatis: GUI punya tombol karena momen "2/2" itu achievement,
## dan membayarnya diam-diam spendek player's reward. Kalau player tidak pernah
## menekan, malam ini netral - bukan Bonus, bukan penalti.
func claim_reward() -> bool:
	if not can_claim():
		return false
	_claimed = true
	var gm := _game_manager()
	if gm != null:
		gm.call("settle_night_win")
	patrol_claimed.emit()
	return true


## Selesaikan ekonomi satu malam. Dipanggil tepat sekali saat fase bergeser ke
## DAY, sebelum clear()().
##
## Tiga aturan, dan ketiganya disengaja:
##   - 2/2 tertangkap: klaim player yang membayar, jadi di sini tidak ada apa-apa.
##   - 2/2 tapi tidak diklaim: netral. Tidak dapat hadiah, tapi juga tidak kena
##     penalti harus jelas, dan "tidak sempat klik" bukan gagal.
##   - ada yang lolos: -50, SEKALI, bukan per NPC.
func _resolve_night() -> void:
	if _night_id < 0:
		return
	if _caught >= NIGHT_TARGET:
		return
	var gm := _game_manager()
	if gm != null:
		gm.call("settle_night_loss")


## Pancarkan ulang angka tangkapan ke HUD.
##
## Penyebut memakai NIGHT_TARGET HANYA selama malam sedang berjalan. Setelah
## clear() malam selesai, penyebut jadi 0 supaya HUD menulis "TERTANGKAP -",
## bukan "TERTANGKAP 0/2" di siang hari yang tenang - angka 0/2 di siang hari
## terbaca seperti malam yang belum selesai dan masih bisa diklaim.
func _emit_progress() -> void:
	patrol_progress.emit(_caught, NIGHT_TARGET if _night_id >= 0 else 0)


## GameManager dicari lewat /root, bukan identifier global, supaya skrip ini
## tetap bisa diuji headless tanpa autoload -- pola yang sama dengan
## MapSeam._report_map(). Kalau autoload belum ada, settlement dilewati
## diam-diam, bukan error.
func _game_manager() -> Node:
	return get_tree().root.get_node_or_null(^"GameManager")


func active_count() -> int:
	_prune()
	return _active.size()


func active_dumpers() -> Array[Node2D]:
	_prune()
	return _active.duplicate()


## Buang semua NPC. Aman dipanggil saat memang tidak ada NPC.
func clear() -> void:
	_prune()
	for d in _active:
		if is_instance_valid(d):
			# Mati dulu supaya tidak jalan satu frame selama node dilepas.
			d.call("deactivate")
			d.queue_free()
	_active.clear()
	_pending_maps.clear()
	# Malam juga selesai: -1 membuat malam berikutnya dihitung sebagai malam
	# baru. Tanpa ini, malam berikutnya akan mewarisi angka malam ini dan HUD
	# masih menampilkan "TERTANGKAP 2/2" di siang hari yang tenang.
	_night_id = -1
	_caught = 0
	_claimed = false
	_emit_progress()


## Buang entri yang sudah tidak valid. NPC bisa hilang tanpa lewat clear(),
## mis. dikejar player lalu keluar peta atau scene dimuat ulang.
func _prune() -> void:
	if _active.is_empty():
		return
	var kept: Array[Node2D] = []
	for d in _active:
		if is_instance_valid(d):
			kept.append(d)
	if kept.size() != _active.size():
		_active = kept


## ------------------------------------------------------------------ peta
## Dipanggil map_seam.gd setelah teleport selesai.
func set_current_map(map_id: int) -> void:
	if not MAP_IDS.has(map_id):
		push_warning("NightPatrol: map_id %d tidak dikenal" % map_id)
		return
	current_map = map_id


## ------------------------------------------------------------------ fase
## Malam = spawn. Phase berikutnya yang DAY = btuntaskan malam lalu buang semua.
## Pakai phase_changed, bukan signal midnight: yang perlu tahu "sekarang malam"
## setiap kali fase bergeser, bukan cuma sekali tengah malam.
func _on_phase_changed(phase: int) -> void:
	if not auto_spawn:
		return
	# Fase yang sama bukan transisi baru. Tanpa penjaga ini NIGHT yang datang
	# dua kali akan spawn 12 NPC dan menaikkan night_number dua kali.
	if phase == _last_phase:
		return
	_last_phase = phase
	if phase == TIME_MANAGER.Phase.NIGHT:
		night_number += 1
		begin_night(night_number)
	elif phase == TIME_MANAGER.Phase.DAY:
		# Resolve dulu: clear()() mengosongkan _caught, jadi urutan di sini yang
		# menentukan apakah malam ini masih bisa dihakimi.
		_resolve_night()
		clear()
		patrol_cleared.emit(night_number)


## Cari TimeManager lewat grup lalu sambung signal-nya. Idempoten: sambungan
## lama dicabut dulu supaya main.tscn yang dimuat ulang tidak doublespawn.
## Mengembalikan true kalau ada TimeManager yang jadi dipasang.
func _attach_time_manager() -> bool:
	_disconnect_time_manager()
	for node in get_tree().get_nodes_in_group(TIME_MANAGER_GROUP):
		if node.has_signal(&"phase_changed"):
			_time_manager = node
			break
	if _time_manager == null:
		return false
	_time_manager.connect(&"phase_changed", _on_phase_changed)
	_time_manager.tree_exiting.connect(_on_time_manager_leaving)
	# Sumber waktu baru: fase-nya belum pernah dilayani, jadi jangan andalkan
	# nilai _last_phase dari TimeManager sebelumnya.
	_last_phase = -1
	_stop_watching()
	return true


func _disconnect_time_manager() -> void:
	if is_instance_valid(_time_manager):
		if _time_manager.is_connected(&"phase_changed", Callable(self, "_on_phase_changed")):
			_time_manager.disconnect(&"phase_changed", Callable(self, "_on_phase_changed"))
		if _time_manager.tree_exiting.is_connected(Callable(self, "_on_time_manager_leaving")):
			_time_manager.tree_exiting.disconnect(Callable(self, "_on_time_manager_leaving"))
	_time_manager = null


## Scene dimuat ulang: TimeManager lama ikut hilang, yang baru menyusul.
func _on_time_manager_leaving() -> void:
	_time_manager = null
	_start_watching()


## Dengarkan node baru hanya selama TimeManager belum ditemukan, lalu
## berhenti supaya tidak ikut memproses tiap node yang di-add setelahnya.
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
	# node_added terpancar SEBELUM _ready() node itu jalan, sedangkan
	# TimeManager baru masuk grup di dalam _ready() (add_to_group). Cek grup
	# harus ditunda ke akhir frame, sama seperti audio_manager.gd.
	call_deferred("_retry_attach")


func _retry_attach() -> void:
	if _time_manager != null and is_instance_valid(_time_manager):
		_stop_watching()
		return
	if _attach_time_manager():
		_stop_watching()


## Dipanggil kalau TimeManager masuk tree setelah autoload (mis. ganti scene).
func rebind() -> void:
	if not _attach_time_manager():
		_start_watching()


func _host() -> Node:
	return get_tree().root.get_node_or_null(HOST_PATH)
