extends CharacterBody2D
class_name IllegalDumper

## NPC pembuang sampah ilegal.
##
## Satu malam = satu perjalanan. NPC menyusuri circuit tertutup dari
## scripts/dumper_routes.gd tepat satu kali, lalu selesai:
##   ambil sampah (titik `pickup`, instan) -> membawa -> buang (titik `dump`)
##   -> pulang ke respawn -> selesai
##
## During transit player bisa menekan E untuk menangkap NPC yang sedang
## membawa. Tangkapan itu eksplisit (bukan otomatis dari tabrakan): muatan
## hilang, lalu NPC melarikan diri ke respawn dan selesai sebagai CAUGHT.
##
## Tidak ada state PATROL yang berputar selamanya. Begitu satu siklus selesai
## (dilewati atau tertangkap) NPC queue_free(), jadi tidak ada NPC yang menumpuk
## di scene sampai pagi.
##
## NPC tidak pernah jalan sendiri. `NightPatrol` yang memanggil `activate()`
## saat malam datang dan `deactivate()` saat pagi, jadi siklus hidup NPC terikat
## ke jam duties dan bukan ke `main.tscn`.
##
## Data rute di-hardcode dengan sengaja. A* hanya dipakai design-time di
## tools/route_analyze.gd, dan file data itu dibaca analyzer yang sama, sehingga
## yang divalidasi persis angka yang dipakai runtime.
##
## Struktur node mengikuti Player.tscn:
##   CharacterBody2D(root) -> Visual/Anim + Visual/Carry + Visual/StateIcon,
##   Collision.
##
## `collision_mask` sengaja 0 (lihat tscn): NPC menembus dunia, jadi tidak ada
## lagi penghitung stuck / penghalang player yang perlu ditangani. Jalur rute
## sudah divalidasi design-time terhadap collision bake, jadi tidak perlu
## sorting obstacle saat runtime.

const DumperRoutes := preload("res://scripts/dumper_routes.gd")

## Dumper sengaja lebih lambat dari player (240) supaya bisa disusul dan
## ditangkap tanpa movement-nya terasa teleport saat wrap rute.
@export_range(40.0, 240.0, 1.0) var walk_speed: float = 95.0

## Lama berhenti di titik dump sambil membuang muatan.
@export_range(0.1, 10.0, 0.1) var dump_hold: float = 1.4

## Pengali kecepatan saat pulang setelah lolos tangkapan. >1 supaya "lari" terasa
## lebih cepat daripada walk_speed biasa.
@export_range(1.0, 3.0, 0.05) var flee_speed_multiplier: float = 1.8

## Berapa lama NPC yang sudah terminal tetap terlihat sebelum dilepas dari
## tree. Bukan jeda gameplay (terminal sudah tidak bisa hidup lagi), hanya
## memberi ruang supaya sinyal sempat dibaca dan animasi terminal sempat
## terlihat sebelum node hilang.
@export_range(0.0, 3.0, 0.1) var despawn_hold: float = 0.6

## Radius dianggap "sampai" di sebuah waypoint.
@export_range(4.0, 40.0, 1.0) var arrive_radius: float = 10.0

## Berapa jauh (px) kaki kabur minimal harus bisa kelihatan. Dipakai saat NPC
## lolos tepat di titik respawn: tanpa kaki tambahan dia akan sampai seketika
## dan hilang tanpa pernah kelihatan bergerak.
const FLEE_LEG_MIN_DIST := 220.0

## Warna sprite, dipakai juga sebagai penanda sedang bawa muatan.
@export var tint: Color = Color(0.78, 0.72, 0.60)

## Index rute di DumperRoutes.ALL. 0..2 = Map 1 (Kurir Pasar, Karyawan Pabrik,
## Pemuda Taman), 3..6 = Map 2 (Petani Sawah, Pedagang Keliling, Pedagang Pasar,
## Petani Timur). Dipakai eksplisit supaya salah pilih rute tidak mungkin
## diam-diam hanya karena nama node berubah.
@export_range(0, 6, 1) var route_id: int = 0

## Kunci depth sort global, sama seperti player.gd (dasar sprite).
const FOOT_Y := 40.0

## Siklus hidup satu malam, dari spawn sampai terminal.
##
## IDLE sengaja jadi state PERTAMA dan `_ready()` TIDAK mengaktifkan NPC.
## `NightPatrol` yang memutuskan kapan NPC boleh jalan: spawn -> `activate()`,
## pagi -> `deactivate()` -> buang. Kalau `_ready()` langsung jalan, NPC akan
## berjalan di luar jam tugas dan tidak bisa dikunci pagi hari.
##
## Angka state di sini WAJIB sama dengan konstanta S_* di tests/test_illegal_dumper.gd.
enum State {
	IDLE,          ## 0 spawned, belum aktif (siang / sudah dikunci pagi)
	PATROL,        ## 1 kosong, menyusuri circuit menuju titik ambil
	APPROACH_DUMP, ## 2 membawa muatan, menuju titik dump
	DUMPING,       ## 3 berhenti di titik dump, sedang membuang
	CAUGHT,        ## 4 tertangkap: hilang di tempat, terminal
	ESCAPED,       ## 5 selesai tanpa tertangkap: buang berhasil lalu pulang,
	               ##    lolos dari tangkapan lalu pulang, atau keluar area
	RETURNING,     ## 6 buang selesai, berjalan pulang ke respawn
	FLEEING,       ## 7 lolos dari tangkapan, berjalan pulang ke respawn lebih cepat
}

## Terminal: NPC sudah selesai satu malam. Tidak bisa dihidupkan lagi dan
## di-`queue_free()` setelah `despawn_hold` supaya sinyal sempat dibaca.
const TERMINAL_STATES: Array[int] = [State.CAUGHT, State.ESCAPED]


## Sampah sudah dibuang di titik dump. `at` = posisi titik buangan.
signal dumped(route_name: String, at: Vector2)
## Player menangkap NPC yang sedang membawa (tombol E). `at` = posisi NPC saat
## tertangkap.
signal intercepted(route_name: String, at: Vector2)
## NPC keluar dari area main tanpa tertangkap.
signal escaped(route_name: String, at: Vector2)
## NPC selesai satu malam (CAUGHT atau ESCAPED) dan akan dilepas dari tree.
signal finished(route_name: String, outcome: String)
signal state_changed(state: int, carrying: bool)

## Batas area main yang memuat KEDUA map (Map 1 x 0..3200, Map 2 x 3268..6470,
## tinggi 0..4051). NPC yang keluar dari sini dianggap keluar dari area main.
## `grow` memberi toleransi supaya NPC tidak dianggap keluar tepat di tepi jalan
## yang sah — rute divalidasi terhadap collision bake, bukan terhadap rect ini.
const WORLD_RECT := Rect2(0.0, 0.0, 6470.0, 4051.0)
const WORLD_MARGIN_PX := 200.0

@onready var _anim: AnimatedSprite2D = $Visual/Anim
@onready var _carry: Polygon2D = $Visual/Carry
@onready var _icon: Polygon2D = $Visual/StateIcon

var _route: Dictionary = {}
var _titik: Array = []
var _wp := 0
## Benar selama minigame tangkapan menahan NPC diam. State dan muatan tetap
## seperti semula; cuma gerak yang ditunda. Dihapus di setiap terminal supaya
## NPC yang dilepas tidak pernah tersesat dalam keadaan beku.
var _frozen := false
## Dimulai IDLE, bukan PATROL: NPC tidak boleh jalan sebelum `activate()`.
## Waypoint yang harus dilalui dulu sebelum pulang ke respawn, 0 = tidak ada.
## Dipakai supaya NPC yang lolos tepat di titik respawn tetap terlihat pulang,
## alih-alih hilang seketika. Direset tiap kali state berubah.
var _flee_via := 0
var _state: State = State.IDLE
var _timer := 0.0
var _carrying := false
## Facing horizontal terakhir, dalam {-1, 0, +1}. 0 = belum bergerak. Animasi
## hanya kiri/kanan, jadi gerak vertikal cukup menahan nilai ini.
var _facing_x := 0.0
## Sisa waktu sebelum NPC terminal di-queue_free(). Dipakai supaya sinyal
## finished/terminal sempat dibaca dan animasi sempat terlihat.
var _despawn_left := 0.0
## Sudah pernah memancarkan `finished`? Mencegah penghitungan ganda kalau
## _finish() terpanggil dua kali untuk satu NPC.
var _announced := false


func _ready() -> void:
	add_to_group("illegal_dumpers")
	# Collision passthrough: NPC menembus dunia, jadi tidak ada lagi sorting
	# obstacle maupun penghitung stuck saat runtime. Rute sudah divalidasi
	# design-time terhadap collision bake.
	collision_mask = 0
	if not _apply_route(DumperRoutes.by_index(_route_index())):
		return
	_set_carrying(false)
	_update_icon()
	_update_animation()
	# Settled di IDLE sampai `activate()`. `NightPatrol` yang memanggilnya,
	# jadi NPC tidak pernah jalan di luar malam hanya karena di-spawn.
	set_physics_process(false)


## Menghidupkan NPC: mulai jalan dari waypoint yang sedang dituju.
## Idempoten. Tidak efek kalau rute tidak punya waypoint atau NPC sudah terminal.
func activate() -> void:
	if _titik.is_empty():
		return
	if _state == State.IDLE:
		_enter(State.PATROL)
	elif _is_terminal():
		# CAUGHT / ESCAPED terminal: NPC yang sudah selesai satu malam tidak
		# dihidupkan ulang, termasuk saat malam berikutnya.
		return
	set_physics_process(true)


## Mematikan NPC dan mengembalikannya ke IDLE. Muatan yang sedang dibawa tidak
## diubah, jadi state pagi bisa diperiksa sebelum node dibuang.
## Idempoten, dan tidak menghidupkan kembali NPC yang sudah terminal.
func deactivate() -> void:
	set_physics_process(false)
	velocity = Vector2.ZERO
	if not _is_terminal() and _state != State.IDLE:
		_enter(State.IDLE)


## Menahan NPC diam di tempat tanpa mengubah state-nya.
##
## Dipakai selama minigame tangkapan berjalan. Kalau NPC terus jalan, bar
## minigame jadi soal mengejar target yang ikut lari, bukan soal ketepatan
## menekan - dan player yang gagal akan merasa ditipu, bukan kalah skill.
## State, muatan, dan waypoint tidak berubah: cuma geraknya yang berhenti.
func set_frozen(value: bool) -> void:
	if value:
		velocity = Vector2.ZERO
	_frozen = value


func is_frozen() -> bool:
	return _frozen


## NPC menyerah dan kabur karena player gagal menelessly tangkapan.
##
## Lolos-dari-tangkapan berarti NPC masih di dalam peta dan terlihat: dia
## jalan pulang ke respawn, baru selesai. Ekonomi sama saja - malam ini tidak
## bisa 2/2 - tapi visualnya jujur: player melihat NPC-nya pergi, bukan lenyap
## mendadak. Sinyal `escaped` dipancarkan langsung (bukan saat tiba) supaya
## antrean spawn NightPatrol jalan seperti biasa; `finished("escaped")`
## menyusul saat NPC sampai respawn.
##
## Berbeda dari `escaped` biasa (NPC keluar area tanpa sengaja lalu hilang di
## tempat, lihat _escape): yang itu sudah di luar area main, jadi tidak ada
## gunanya disuruh jalan pulang.
func force_escape() -> bool:
	if _titik.is_empty() or _is_terminal() or _state == State.IDLE:
		return false
	velocity = Vector2.ZERO
	escaped.emit(_route_name(), global_position)
	# Jalan pulang ke respawn. Kaki kabur yang terlihat hanya kalau NPC
	# berdiri di respawn (mis. gagal tepat setelah spawn): tanpa itu dia
	# "tiba" seketika dan hilang tanpa pernah terlihat jalan.
	_wp = 0
	if global_position.distance_to(_titik[0]) <= arrive_radius:
		var flee_leg := _flee_leg_waypoint()
		if flee_leg > 0:
			_flee_via = flee_leg
		_wp = flee_leg
	_enter(State.FLEEING)
	return true


## Memasang satu rute dan mensnap NPC ke waypoint 0 supaya tidak perlu melintasi
## peta saat spawn. Mengembalikan false kalau rute tidak punya waypoint: NPC
## dimatikan supaya tidak berjalan lurus ke (0,0).
func _apply_route(route: Dictionary) -> bool:
	_route = route
	_titik = route.get("titik", [])
	if _titik.is_empty():
		push_error("IllegalDumper '%s': rute %d tidak punya waypoint"
			% [name, _route_index()])
		set_physics_process(false)
		visible = false
		return false
	global_position = _titik[0]
	_wp = 1 % _titik.size()
	return true


## Index rute tervalidasi. Nilai di luar jangkauan jatuh ke rute 0 dengan
## peringatan, supaya salah set [member route_id] kelihatan di log.
func _route_index() -> int:
	if route_id < 0 or route_id >= DumperRoutes.ALL.size():
		push_warning("IllegalDumper '%s': route_id %d di luar jangkauan, pakai rute 0"
			% [name, route_id])
		return 0
	return route_id


## Memindahkan NPC ke waypoint `i` dan menjadikan waypoint itu tujuan
## berikutnya. Dipakai test dan debugging; gameplay normal tidak memakainya.
## Dipisah dari [_apply_route] karena menggeser posisi badan saja tidak cukup:
## kursor waypoint harus ikut geser, kalau tidak NPC akan tetap pursuing
## waypoint yang lama.
##
## Waypoint 0 adalah respawn. Teleport ke situ membuat NPC "sampai di rumah",
## jadi harus menyelesaikan sisa perjalanan (selesai ESCAPED atau CAUGHT sesuai
## apakah muatan masih dibawa) — bukan membuat NPC berputar lagi dari awal.
func teleport_to_waypoint(i: int) -> void:
	if _titik.is_empty():
		return
	# Guard di paling atas, SEBELUM ada mutasi posisi. NPC terminal itu selesai
	# dan tidak boleh bergerak lagi sama sekali; NPC IDLE belum dijalankan jadi
	# tidak ada yang berhak memindahkannya.
	if _state == State.IDLE or _is_terminal():
		return
	_wp = posmod(i, _titik.size())
	global_position = _titik[_wp]
	# Invariant "membawa muatan -> APPROACH_DUMP" ikut dijaga, kalau tidak NPC
	# akan melewati titik dump tanpa membuang.
	_enter(State.APPROACH_DUMP if _carrying else State.PATROL)


## Diperluas untuk test: sedang bawa muatan atau tidak.
func is_carrying() -> bool:
	return _carrying


## Diperluas untuk test: state machine saat ini.
func current_state() -> int:
	return _state


## Diperluas untuk test: waypoint yang sedang dituju.
func target_waypoint() -> Vector2:
	if _titik.is_empty():
		return Vector2.ZERO
	return _titik[_wp]


## Progres membuang 0..1. 0 di luar state DUMPING supaya HUD bisa menjumlahkan
## semua NPC aktif tanpa masing-masing harus mengecek state-nya.
func dump_fraction() -> float:
	if _state != State.DUMPING or dump_hold <= 0.0:
		return 0.0
	return clampf(1.0 - _timer / dump_hold, 0.0, 1.0)


## True kalau NPC sudah menyelesaikan satu malam dan tidak bisa dihidupkan lagi.
func is_finished() -> bool:
	return _is_terminal()


## Player menekan E untuk menangkap NPC ini. Mengembalikan true kalau tangkapan
## benar-benar terjadi.
##
## Syaratnya sengaja ketat: hanya NPC yang SEDANG MEMBAWA dan belum terminal.
## NPC kosong di patroli tidak bisa ditangkap, jadi tidak ada sumber +100 koin
## gratis dari memencet E di NPC yang salah.
##
## Tidak ada radius di sini: proximity diperiksa player.gd (yang tahu posisi
## player dan modal UI aktif), jadi aturan "E hanya saat dekat" punya satu
## pemilik saja.
func try_catch() -> bool:
	if _titik.is_empty() or _is_terminal():
		return false
	# Penjaga idempotensi: CAUGHT terminal dan FLEEING (pulang setelah lolos)
	# sama-sama berarti "sudah ditutup player". Tanpa ini tekan E berulang
	# akan resurrect NPC dan menggandakan sinyal.
	#
	# CAUGHT(4) dan FLEEING(7) sama-sama berarti "sudah ditutup player".
	if _state == State.FLEEING or _state == State.CAUGHT:
		return false
	# NPC kosong pun bisa ditutup, supaya player tidak perlu menunggu NPC
	# berjalan ke waypoint ambil dulu.
	#
	# Tertangkap = langsung hilang di tempat. Tidak ada jalan pulang:
	# tangkapan yang sukses berarti NPC diamankan saat itu juga.
	_set_carrying(false)
	velocity = Vector2.ZERO
	intercepted.emit(_route_name(), global_position)
	visible = false
	_enter(State.CAUGHT)
	_finish("caught")
	return true


## Waypoint pertama yang cukup jauh dari respawn untuk jadi "kaki kabur" yang
## terlihat. Kalau tidak ada yang memenuhi, pakai waypoint 1.
func _flee_leg_waypoint() -> int:
	for i in range(1, _titik.size()):
		if _titik[0].distance_to(_titik[i]) >= FLEE_LEG_MIN_DIST:
			return i
	return 1


func _is_terminal() -> bool:
	return TERMINAL_STATES.has(_state)


func _physics_process(delta: float) -> void:
	_update_depth()
	# Terminal tidak pernah jalan lagi; satu-satunya yang tersisa adalah
	# menghitung mundur pelepasan node. Physics sengaja tetap menyala supaya
	# `_tick_despawn` tetap dijalankan.
	if _is_terminal():
		velocity = Vector2.ZERO
		_tick_despawn(delta)
		_update_animation()
		return
	# Minigame tangkapan sedang menilai player: NPC ditahan diam. State, muatan,
	# dan waypoint tetap utuh, jadi begitu minigame selesai NPC lanjut dari
	# tempat yang sama.
	if _frozen:
		velocity = Vector2.ZERO
		_update_animation()
		return
	if _left_main_area():
		_escape()
		return
	match _state:
		State.PATROL, State.APPROACH_DUMP, State.RETURNING, State.FLEEING:
			_step_travel()
		_:
			_hold(delta)
	_update_animation()


## True kalau NPC sudah keluar dari area main yang memuat kedua map.
## Toleransi WORLD_MARGIN_PX supaya waypoint sah yang persis di tepi tidak
## salah dihitung keluar.
func _left_main_area() -> bool:
	if _state == State.IDLE or _is_terminal():
		return false
	return not WORLD_RECT.grow(WORLD_MARGIN_PX).has_point(global_position)


## Terminal: NPC keluar dari area main dan berhenti selamanya.
## Muatan ikut dibuang karena sudah keluar dari area yang harus dibersihkan.
## Kalau tidak, muatan hilang dari dunia tapi NPC masih terlihat sambil membawa.
func _escape() -> void:
	velocity = Vector2.ZERO
	_set_carrying(false)
	_enter(State.ESCAPED)
	escaped.emit(_route_name(), global_position)
	_finish("escaped")


## Menghitung mundur jeda sebelum node dilepas dari tree, lalu queue_free().
## Physics sengaja tetap menyala di state terminal; `_physics_process` hanya
## memanggil fungsi ini, tidak pernah menjalankan gerak lagi.
func _tick_despawn(delta: float) -> void:
	_despawn_left -= delta
	if _despawn_left > 0.0:
		return
	queue_free()


## Menandai NPC selesai: memancarkan `finished` sekali saja lalu menjadwalkan
## pelepasan node. Dipanggil tepat saat masuk state terminal.
##
## `_announced` dipakai sebagai penanda, bukan `_despawn_left`: nilai latter
## mulai dari 0.0, jadi dipakai sebagai flag akan salah baca sebagai "sudah
## selesai" dan melepas node tanpa jeda sama sekali.
func _finish(outcome: String) -> void:
	if _announced:
		return
	_announced = true
	_despawn_left = despawn_hold
	finished.emit(_route_name(), outcome)


# -------------------------------------------------------------- state machine
## Bergerak satu langkah ke waypoint tujuan. Dipakai oleh keempat state yang
## sedang berjalan: PATROL (kosong), APPROACH_DUMP (membawa), RETURNING, dan
## FLEEING.
##
## Tidak ada logika stuck / penghalang di sini. `collision_mask = 0` membuat NPC
## menembus dunia, jadi tidak ada yang bisa menghentikannya; jalur rute sudah
## divalidasi design-time. Menghapus counters ini juga menghapus kasus "NPC diam
## di antara dua penghalang" yang dulu butuh recovery.
func _step_travel() -> void:
	var target: Vector2 = _titik[_wp]
	var to_target := target - global_position
	if to_target.length() <= arrive_radius:
		_arrive()
		return
	velocity = to_target.normalized() * _travel_speed()
	move_and_slide()


## Kecepatan langkah saat ini. FLEEING (pulang setelah lolos) memakai
## pengali supaya "lari" terasa lebih cepat daripada jalan biasa.
func _travel_speed() -> float:
	if _state == State.FLEEING:
		return walk_speed * flee_speed_multiplier
	return walk_speed


## Berhenti di tempat selama `secs`, lalu lanjut ke state berikutnya.
func _hold(delta: float) -> void:
	# Berdiri diam di titik ambil/buang itu disengaja, bukan tertahan.
	velocity = Vector2.ZERO
	_timer -= delta
	if _timer > 0.0:
		return
	match _state:
		State.DUMPING:
			# Muatan sudah keluar dari tangan. Bukan balik PATROL: satu siklus
			# sudah selesai, jadi NPC pulang ke respawn lalu terminal.
			_set_carrying(false)
			_begin_return(State.RETURNING)
		State.IDLE:
			# activate() yang menentukan state berikutnya.
			pass


## Mulai perjalanan pulang: kursor diarahkan ke respawn, lalu jalan. Setelah tiba
## di respawn NPC jadi ESCAPED terminal (lihat _reach_respawn).
func _begin_return(s: State) -> void:
	_wp = 0
	_enter(s)


## Sampai di waypoint saat ini. Titik 0 adalah respawn, jadi apa pun yang
## berjalan ke sana selesai; waypoint lain diproses sesuai state.
func _arrive() -> void:
	# Respawn: apa pun yang sampai ke sini selesai satu malam.
	if _wp == 0:
		_reach_respawn()
		return
	# FLEEING yang disuruh lewat satu kaki supaya kelihatan: begitu kaki itu
	# tercapai, langsung pulang. Kalau tidak, `_advance()` akan menyusuri seluruh
	# rute (61 titik, ~8600px, lebih dari semenit) sebelum sampai respawn.
	if _state == State.FLEEING and _flee_via > 0:
		_flee_via = 0
		_wp = 0
		return
	var dump := int(_route["dump"])
	var pickup := int(_route["pickup"])
	match _state:
		State.PATROL:
			if _wp == pickup:
				_set_carrying(true)
				_advance()
				_enter(State.APPROACH_DUMP)
			else:
				# Melewati titik dump tanpa muatan bukan membuang apa pun.
				_advance()
		State.APPROACH_DUMP:
			if _wp == dump:
				# Sampah menyentuh tanah tepat saat tiba, bukan setelah jeda.
				dumped.emit(_route_name(), _titik[_wp])
				_enter(State.DUMPING, dump_hold)
			else:
				_advance()
		_:
			# RETURNING / FLEEING cuma berjalan pulang; waypoint selain respawn
			# dilewati tanpa efek.
			_advance()


## Sampai di respawn: terminal dan dilepas dari tree setelah `despawn_hold`.
##
## Satu-satunya jalan yang masih berjalan sampai respawn adalah pulang normal
## (RETURNING, setelah buang) dan lolos-dari-tangkapan (FLEEING, lihat
## force_escape). Keduanya berarti malam ini selesai tanpa tangkapan: ESCAPED.
## Tertangkap langsung CAUGHT di tempat (lihat try_catch) dan tidak pernah
## lewat sini.
func _reach_respawn() -> void:
	velocity = Vector2.ZERO
	_set_carrying(false)
	_enter(State.ESCAPED)
	_finish("escaped")


func _enter(s: State, secs: float = 0.0) -> void:
	_state = s
	_timer = secs
	_update_icon()
	# Beku hanya berlaku selama NPC masih main. Kalau minigame menahan NPC
	# tepat saat NPC kabur, node yang dilepas akan menggambar idle selamanya
	# karena `_physics_process` yang memanggil `_hold()` tidak pernah jalan lagi.
	_frozen = false
	# Kaki kabur hanya berlaku untuk satu putaran FLEEING. Kalau tidak
	# dibersihkan di sini, NPC yang dibekukan minigame lalu diterminasi
	# bisa mewarisi `_flee_via` ke malam berikutnya.
	if s != State.FLEEING:
		_flee_via = 0
	state_changed.emit(_state, _carrying)


## Maju ke waypoint berikutnya; wrap di akhir karena circuit tertutup.
func _advance() -> void:
	_wp = (_wp + 1) % _titik.size()


func _set_carrying(v: bool) -> void:
	_carrying = v
	if _carry:
		_carry.visible = v
	if _anim:
		# Lebih gelap + kusam saat bawa muatan, biar terbaca dari jauh.
		_anim.modulate = tint if v else tint.lerp(Color.WHITE, 0.65)
	_update_icon()


# -------------------------------------------------------------------- visuals
## Penanda kecil di atas kepala memakai Polygon2D, bukan tekstur, supaya scene
## tetap ringan dan tidak perlu aset baru per NPC.
func _update_icon() -> void:
	if _icon == null:
		return
	var c := Color(0.55, 0.55, 0.55, 0.0)
	if _state == State.DUMPING:
		c = Color(0.95, 0.75, 0.20, 0.95)
	elif _state == State.CAUGHT:
		c = Color(0.40, 0.75, 0.95, 0.95)
	elif _state == State.ESCAPED:
		c = Color(0.85, 0.20, 0.85, 0.95)
	elif _state == State.FLEEING:
		# Lolos lalu pulang: biru muda.
		c = Color(0.55, 0.65, 0.95, 0.80)
	elif _state == State.RETURNING:
		# Pulang: ungu redup, versi kalem dari ESCAPED.
		c = Color(0.60, 0.45, 0.80, 0.70)
	elif _carrying:
		c = Color(0.95, 0.35, 0.30, 0.95)
	_icon.color = c


## Samakan dengan player.gd: z_index = posisi kaki.
func _update_depth() -> void:
	z_index = int(global_position.y + FOOT_Y)


## Hanya dua animasi: `left` dan `right`.
##
## `front`/`back`/`idle` di SpriteFrames tidak pernah dipilih di runtime —
## membakar siklus idle saat NPC diam hanya bikin dumper terlihat "hidup-mati".
## Gerak vertikal (naik/turun sesuai kedalaman peta) sengaja TIDAK mengubah
## facing: dumper yang sedang berjalan ke bawah harus tetap menampilkan sisi
## yang terakhir dilihat, bukan beralih ke `front`. Diam juga menahan facing
## terakhir.
func _update_animation() -> void:
	if _anim == null:
		return
	# Hanya sumbu X yang menentukan arah; threshold kecil menyaring drift float.
	if absf(velocity.x) > 1.0:
		_facing_x = 1.0 if velocity.x > 0.0 else -1.0
	# Sebelum bergerak sama sekali, default ke kanan supaya sprite tidak
	# `_anim.animation` kosong saat di-spawn.
	var target := "right" if _facing_x >= 0.0 else "left"
	if _anim.animation != target:
		_anim.play(target)


func _route_name() -> String:
	return String(_route.get("nama", name))
