extends Area2D

## Strip pemisah Map 1 (kiri) dan Map 2 (kanan) di world yang sama.
##
## Dua map di-load barengan di Main, jadi "nyebrang" di sini bukan pindah
## scene: player cuma di geser ke sisi seberang waktu lewat, dikasih fade
## hitam biar lompatnya gak kelihatan.
##
## DUA trigger, bukan satu strip di tengah. Alasannya geometri: dengan satu
## strip di x=3268, kepicuinnya cuma bisa pas waktu player sudah "di dalam"
## gap, dan memaksa teleport ke sisi yang DEKAT.
##
## Survei kolom (`zz_survey.gd`, memakai `_stand()` yang sama persis dengan
## teleport) menunjukkan peta ini BUKAN daratan penuh, tapi platform sempit
## yang bersusun. Contoh hasil di x=3155 (titik masuk forward): tanah
## standable cuma di y 1084-1340, 2648-3068, dan 3748-4004.
##
## Dari situ muncul bug yang dilaporkan: trigger di scene.ukurannya cuma
## 84x351 di (3172, 1144.5), jadi hanya menutup y 969..1320 — persis satu
## koridor yang kebetulan jalan. Di luar pita itu TIDAK ADA area teleport
## sama sekali, dan satu-satunya hal yang menahan player adalah dinding
## `EdgeBlocker`. Efeknya persis yang dikeluhkan: bisa nyebrang di satu
## tinggi, tapi di tinggi lain menabrak tembok.
##
## Perbaikannya trigger jadi PITA PENUH setinggi area main, dan dinding
## dihapus total:
##   ForwardTrigger (Map1, x=3110..3200) -> arrival Map2 x=3420
##   ReverseTrigger (Map2, x=3280..3360) -> arrival Map1 x=3020
## Player yang masuk trigger langsung diseberangkan, dari tinggi APAPUN.
##
## Karena tidak ada dinding, crossing tidak bisa "ditolak": player tidak punya
## gravity, jadi kalau tidak diseberangkan dia tetap berjalan ke depan sampai
## masuk celah antar-map. Jadi tinggi tujuan TIDAK lagi ikut tinggi player.
## `_resolve_arrival_y()` mencari pita standable terdekat di sisi seberang dan
## player mendarat di situ. Lompatan Y-nya tidak terlihat karena terjadi di
## tengah layar hitam.
##
## Kolom arrival dipilih dari survei, bukan tebakan: yang dipakai adalah kolom
## dengan jarak ke pita standable terdekat PALING KECIL, supaya pergeseran Y
## sekecil mungkin.
##   Map1  x=3020 -> jarak terjauh 1032px  (x=3040 lebih buruk: 1952px)
##   Map2  x=3420 -> jarak terjauh  312px
##
## Trigger dicek manual tiap frame, BUKAN lewat `body_entered`. Alasannya
## `collision_mask` Area lama (4) tidak cocok dengan layer Player (1), jadi
## `body_entered` praktis tidak pernah kepicu untuk player. Sekarang mask=0 +
## monitoring=false, dan deteksi masuk trigger manual dari posisi player.

## Garis tengah tiap trigger (dipakai buat fallback kalau shape belum ada).
## Harus sama dengan CollisionShape2D di MapSeam.tscn.
const FWD_TRIGGER_X := 3155.0
const FWD_TRIGGER_HALF_W := 45.0
const REV_TRIGGER_X := 3320.0
const REV_TRIGGER_HALF_W := 40.0
const TRIGGER_Y := 2050.0
const TRIGGER_HALF_H := 2050.0

## X tujuan tiap arah. WAJIB berada DI LUAR trigger seberang (setelah di-grow
## setengah lebar player), kalau tidak player mendarat di dalam trigger
## seberang lalu langsung ter-trigger balik (bounce).
##   arrival Map1 3020 < 3110-16.5 = 3093.5  (jarak 73.5px)
##   arrival Map2 3420 > 3360+16.5 = 3376.5  (jarak 43.5px)
const ARRIVE_MAP2_X := 3420.0
const ARRIVE_MAP1_X := 3020.0

## Jarak maksimal yang masih dianggap "ada tanah" di bawah tujuan. Kalau
## lebih jauh dari ini, dianggap void → titik itu tidak dipakai sebagai
## tempat mendarat.
const MAX_DROP := 260.0

## Cara `_resolve_arrival_y()` mencari tempat mendarat: melangkah keluar dari
## tinggi player naik DAN turun selebar `ARRIVAL_SCAN_STEP` sampai ketemu
## pita standable. `ARRIVAL_SCAN_MAX` adalah batas radius pencarian; dari
## survei, jarak terjauh ke pita terdekat adalah 1032px (Map1 x=3020), jadi
## 1400 memberi ruang aman tanpa pernah gagal.
const ARRIVAL_SCAN_STEP := 8.0
const ARRIVAL_SCAN_MAX := 1400.0

## Durasi tiap arah fade (detik). Total satu transisi = 2x ini.
## Player sudah DIBEKU sebelum fade dimulai, jadi fade yang panjang di sini
## tidak terasa seperti lag — layar sudah gelap, tidak ada yang bisa
## dikendalikan. Yang penting fade-nya cukup jelas terbaca sebagai "pindah
## area", bukan blink sekejap.
const FADE_TIME := 0.5

## Jeda setelah transisi selesai, biar player gak langsung kepicu lagi.
const COOLDOWN_TIME := 0.6

## Batas Y global, sama dengan batas camera Map 1 — teleport gak pernah
## lempar player keluar area main.
const Y_MIN := 68.0
const Y_MAX := 4019.0

## Batas kamera per map (x kiri, x kanan) dalam koordinat GLOBAL.
##
## Ini yang bikin "camera cut" ala Stardew Valley. Karena kedua map berada di
## satu Node2D yang sama, kamera tanpa batas akan ikut menunjukkan Map 2
## padahal player masih di Map 1: Map 1 berakhiran di ~3200 dan Map 2 mulai
## di 3268, jaraknya cuma ~70px, jadi map sebelah terlihat sebelum player
## sempat menyeberang.
##
## Alih-alih menutup celah itu dengan dinding atau area blackout, batas
## kamera dipindah tiap kali pindah map. Efeknya: saat player mendekati
## trigger, layar berhenti di ujung map yang sedang dimasuki; map sebelah
## baru benar-benar terlihat setelah teleport.
const CAM_LIMIT_MAP1_X := Vector2(0.0, 3200.0)
const CAM_LIMIT_MAP2_X := Vector2(3268.0, 6470.0)
## Batas atas/bawah tidak diubah per map — tinggi kedua map sama.
const CAM_LIMIT_Y := Vector2(0.0, 4000.0)

const PLAYER_GROUP := &"player"

## Nama node Capsule player (lihat Player.tscn).
const PLAYER_COLLISION := ^"Collision"

## Nama node Camera2D player (lihat Player.tscn). Dipakai buat camera cut:
## batas kamera dipindah per map supaya map sebelah tidak kelihatan sebelum
## player menyeberang.
const PLAYER_CAMERA := ^"Camera2D"

## ---------------------------------------------------------------
## Edge blocker — DIHAPUS
## ---------------------------------------------------------------
## Sebelumnya ada `EdgeBlocker`: StaticBody2D yang menahan player di celah
## antar-map pada pita Y yang arrival-nya tidak standable. Alasannya waktu itu
## crossing bisa DITOLAK, dan player tidak punya gravity, jadi tanpa dinding
## dia akan terus berjalan masuk ke lubang.
##
## Sekarang filingnya dihapus karena dua alasan:
##   1. Player melaporkannya sebagai "tembok" — dan memang dia terasa seperti
##      itu: `_is_arrive_safe()` menolak pada hampir semua tinggi, jadi praktis
##      dinding penuh di x=3208..3292. Itu persis keluhan "di Map 1 aman, tapi
##      di Map 2 masih ada tembok, jadi tidak bisa teleport balik".
##   2. Dinding itu tidak dibutuhkan lagi. Crossing sekarang tidak pernah
##      ditolak: `_resolve_arrival_y()` selalu mencari pita standable terdekat
##      di sisi seberang, jadi selalu ada tempat mendarat yang aman. Player
##      tidak pernah punya kesempatan berjalan masuk ke celah.

@onready var _fwd_shape: CollisionShape2D = $ForwardTrigger
@onready var _rev_shape: CollisionShape2D = $ReverseTrigger
@onready var _fade: ColorRect = $FadeLayer/Fade

## Player yang lagi dibeku, plus nilai physics_process-nya sebelum dibeku.
## Disimpan di member (bukan lokal) supaya `_exit_tree()` tetep bisa ngeluarin
## dia walau scene ini dibuang di tengah fade.
var _frozen_player: CharacterBody2D = null
var _frozen_prev_physics := true

var _player: CharacterBody2D = null

## True kalau player sedang di dalam trigger (setelah di-grow setengah lebar
## player). Dipakai buat deteksi "baru masuk".
var _fwd_inside := false
var _rev_inside := false

## Posisi player waktu crossing terakhir kali DICOBANYA per arah.
##
## Ini yang memperbaiki deadlock yang pernah ada: `inside` tidak pernah
## berubah lagi kalau player terkurung DI DALAM trigger, jadi trigger yang
## hanya bereaksi pada transisi outside->inside tidak akan pernah menyala
## kedua kali. Menyimpan posisi percobaan terakhir membuat trigger dievaluasi
## ulang begitu player BERGERAK, bahkan kalau dia belum keluar trigger.
##
## `Vector2.INF` = belum pernah dicoba, jadi frame pertama selalu dievaluasi.
var _fwd_checked_at := Vector2.INF
var _rev_checked_at := Vector2.INF

var _transitioning := false

## Sisa cooldown dalam detik, dikurangi dari `delta` (lihat catatan di
## `_physics_process`) — bukan jam dinding.
var _cooldown_left := 0.0

func _ready() -> void:
	var player := _resolve_player()
	if player != null:
		var pos := player.global_position
		var hw := _player_half_width(player)
		_fwd_inside = _fwd_rect(hw).has_point(pos)
		_rev_inside = _rev_rect(hw).has_point(pos)

func _exit_tree() -> void:
	# Jaring pengaman: kalau scene ini di-free / dicabut dari tree saat fade
	# masih jalan, player harus tetep balik jalan. Tanpa ini physics_process
	# player Bakal mati selamanya dan game nyangkut.
	_release_player()
	# Fade yang nyangkut di alpha 1 juga dibersihin, biar gak jadi layar hitam
	# permanen kalau nodenya di-re-use.
	if is_instance_valid(_fade):
		_fade.color.a = 0.0

func _physics_process(delta: float) -> void:
	# Cooldown dihitung dari `delta`, BUKAN `Time.get_ticks_msec()`. Yang kedua
	# pakai jam dinding, jadi tidak konsisten dengan fade yang berbasis delta:
	# cooldown jadi ikut ngebut/nyusut bareng `Engine.time_scale`, dan tidak
	# bisa diuji headless (dengan `--fixed-fps` simulasi jalan jauh lebih cepat
	# dari waktu nyata, jadi cooldown 0.6s masih aktif ribuan frame kemudian).
	# Catatan: `delta` di sini sudah ikut memperhitungkan `time_scale`, jadi
	# scorch time masih memperlambat cooldown — itu perilaku yang wajar.
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	var player := _resolve_player()
	if player == null:
		return
	_track_triggers(player)

## Deteksi trigger tiap frame.
##
## Syaratnya player SEDANG DI DALAM trigger, bukan cuma perpindahan luar ke
## dalam. Alasannya historis, dan aturannya harus dipertahankan: dulu
## `EdgeBlocker` menahan player yang crossing-nya ditolak DI DALAM trigger.
## Kalau aturannya edge-only, player yang tertahan itu ikut ter-latch
## `_fwd_inside`/`_rev_inside` sebagai "sudah di dalam", tidak ada lagi
## transisi luar-ke-dalam, dan crossing-nya tidak akan pernah dicoba ulang.
## `_fwd_checked_at`/`_rev_checked_at` sudah menutup kasus itu, tapi aturan
## "di dalam = masih boleh mencoba" tetap benar dan biayanya nol.
##
## Anti-bounce tetap aman tanpa aturan edge-only: teleport selalu mendarat di
## LUAR trigger seberang (3420 dan 3020, lihat konstanta arrival), dan selama
## transisi berjalan `_transitioning` menahan percobaan baru, lalu cooldown
## menahan percobaan sesudahnya.
##
## Biaya pencarian tidak nol (`_resolve_arrival_y()` = satu ray + satu shape
## query per kandidat, dan bisa sampai ~175 kandidat untuk kasus terburuk),
## jadi percobaan diulang hanya kalau player BERGERAK sejak cek terakhir.
## Karena hasilnya fungsi murni dari posisi, diam di titik yang sama pasti
## menghasilkan jawaban yang sama — tidak ada yang terlewat.
func _track_triggers(player: CharacterBody2D) -> void:
	var pos := player.global_position
	var hw := _player_half_width(player)
	var fwd_in := _fwd_rect(hw).has_point(pos)
	var rev_in := _rev_rect(hw).has_point(pos)

	if not _transitioning and not _is_on_cooldown():
		if fwd_in and (not _fwd_inside or pos != _fwd_checked_at):
			_fwd_checked_at = pos
			_try_cross(player, true)
		elif rev_in and (not _rev_inside or pos != _rev_checked_at):
			_rev_checked_at = pos
			_try_cross(player, false)

	_fwd_inside = fwd_in
	_rev_inside = rev_in

func _is_on_cooldown() -> bool:
	return _cooldown_left > 0.0

## Rect trigger dalam koordinat GLOBAL, dihitung dari CollisionShape2D biar
## ikut geser kalau node ini di-drag di editor. `grow` dilewatkan setengah
## lebar player: trigger dianggap "tersentuh" saat TEPI player menyentuh
## strip, bukan saat titik tengahnya masuk.
func _fwd_rect(grow: float) -> Rect2:
	return _shape_rect(_fwd_shape, FWD_TRIGGER_X, FWD_TRIGGER_HALF_W, grow)

func _rev_rect(grow: float) -> Rect2:
	return _shape_rect(_rev_shape, REV_TRIGGER_X, REV_TRIGGER_HALF_W, grow)

func _shape_rect(shape_node: CollisionShape2D, fallback_x: float, half_w: float,
		grow: float) -> Rect2:
	var rect_shape := shape_node.shape as RectangleShape2D
	if rect_shape == null:
		return Rect2(fallback_x - half_w - grow, TRIGGER_Y - TRIGGER_HALF_H,
				half_w * 2.0 + grow * 2.0, TRIGGER_HALF_H * 2.0)
	var local := rect_shape.get_rect()
	var rect := Rect2(shape_node.global_position + local.position, local.size)
	if grow > 0.0:
		rect = rect.grow(grow)
	return rect

## Setengah lebar Capsule player dalam koordinat GLOBAL, dihitung dari shape
## asli (bukan angka hardcode) supaya ikut benar kalau Player.tscn diutak-atik.
func _player_half_width(player: CharacterBody2D) -> float:
	var col := player.get_node_or_null(PLAYER_COLLISION) as CollisionShape2D
	if col == null:
		return 18.0
	var capsule := col.shape as CapsuleShape2D
	if capsule == null:
		return 18.0
	return maxf(capsule.radius * absf(col.scale.x), 1.0)

## Freeze -> fade hitam -> geser + ganti kamera -> fade terang -> unfreeze.
##
## Urutannya penting, dan BUKAN "fade dulu baru freeze":
##   - Player dibekukan di frame PERSAMA trigger tersentuh, sebelum fade
##     dimulai. Kalau penundaan baru berlaku setelah fade selesai, player
##     masih jalan 0.5s (sekitar 120px di walk speed 240) dan bisa keluar
##     lagi dari trigger — itu yang bikin transisi terasa "nempel" dan tidak
##     mulus.
##   - Teleport terjadi saat layar benar-benar hitam, jadi pergeseran
##     3000+px tidak pernah kelihatan.
##   - Player dilepas setelah fade balik selesai, supaya tidak ada frame di
##     mana player terlihat diam tapi sudah bisa digerakkan.
func _try_cross(player: CharacterBody2D, to_map2: bool) -> void:
	if _transitioning:
		return
	# Tentukan tinggi mendarat SEBELUM beku, lalu pakai hasil yang sama untuk
	# fading dan penempatan. Kalau Searching dilakukan setelah freeze, dan
	# ternyata tidak ketemu, player sudah beku tanpa tujuan — dan tidak ada
	# dinding anymore, jadi dia akan tetap berjalan ke depan sampai masuk
	# celah antar-map. `_resolve_arrival_y()` tidak pernah gagal di peta ini
	# (lihat catatan ARRIVAL_SCAN_MAX), tapi return -1 tetap dijaga sebagai
	# jaring pengaman: kalau suatu saat peta berubah dan tidak ada satu pun
	# pita standable di kolom arrival, crossing di-skip dari frame ini.
	var arrival_y := _resolve_arrival_y(player, to_map2)
	if arrival_y < 0.0:
		return
	_transitioning = true
	# Beku SEBELUM fade: inilah yang bikin teleport terasa instan begitu
	# player menyentuh trigger.
	_freeze_player(player)
	await _fade_to(1.0)
	_place_player(player, to_map2, arrival_y)
	_apply_camera_cut(to_map2)
	_report_map(to_map2)
	await _fade_to(0.0)
	# Dilepas SESUDAH fade balik selesai, bukan sebelumnya. Kalau dilepas
	# duluan, player dilepas saat layar masih ~100% hitam (alpha 1.0), jadi
	# begitu layar mulai terang player sudah bisa digerakkan dan
	# pergerakannya langsung kelihatan — hasilnya transisi terasa "nempel".
	# Melepas di sini berarti player mulai bergerak persis saat layar bersih.
	_release_player()
	_cooldown_left = COOLDOWN_TIME
	_transitioning = false

## Kabari `NightPatrol` peta tujuan. Dipanggil di tengah fade (player sudah
## dipindah, layar masih hitam) supaya NPC yang akan muncul malam itu tahu
## peta yang sedang dimasuki.
##
## Dicari lewat `/root` dan tidak diesensuaikan ke compile artifact test
## headless (`--script` tidak memuat autoload), jadi_scene ini tetap bisa
## diuji tanpa `NightPatrol` di tree.
func _report_map(to_map2: bool) -> void:
	var np := get_tree().root.get_node_or_null(^"NightPatrol")
	if np == null:
		return
	np.call("set_current_map", 2 if to_map2 else 1)


## Pindahkan batas kamera ke map tujuan.
##
## Dipanggil di tengah fade (layar sudah hitam penuh), jadi perpindahan map
## tidak pernah terlihat dan kamera tidak sempat "mengejar" posisi baru dari
## sisi seberang.
func _apply_camera_cut(to_map2: bool) -> void:
	var cam := _camera()
	if cam == null:
		return
	var x_limits := CAM_LIMIT_MAP2_X if to_map2 else CAM_LIMIT_MAP1_X
	cam.limit_left = int(x_limits.x)
	cam.limit_right = int(x_limits.y)
	cam.limit_top = int(CAM_LIMIT_Y.x)
	cam.limit_bottom = int(CAM_LIMIT_Y.y)
	# Kalau `position_smoothing` / `limit_smoothed` pernah dinyalakan, kamera
	# akan meluncur pelan ke batas baru dan terlihat "menyapu" seluruh dunia.
	# `reset_smoothing()` memaksa kamera langsung patuh ke batas baru — itu
	# yang bikin hasilnya cut, bukan pan.
	cam.reset_smoothing()

func _camera() -> Camera2D:
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
	if _player == null:
		return null
	return _player.get_node_or_null(PLAYER_CAMERA) as Camera2D

## Tentukan tinggi Y tempat player akan mendarat di sisi seberang.
##
## Ini menggantikan `_is_arrive_safe()` yang dulu mengembalikan bool. Dulu
## arriving yang tidak ada tanahnya berarti crossing DITOLAK, dan `EdgeBlocker`
## menahan player di tempat. Sekarang tidak ada dinding, jadi ditolak berarti
## player berjalan terus ke celah antar-map — lebih buruk dari dinding. Jadi
## pertanyaannya bukan "apakah tinggi ini aman", tapi "tinggi standable mana
## yang paling dekat".
##
## Pencarian bolak-balik (naik DAN turun, selebar `ARRIVAL_SCAN_STEP`) dari
## tinggi player, jadi pergeseran Y sekecil mungkin dan tetap simetris: player
## di y=2500 yang pitsa sedikit di bawah deck tidak terlempar ke puncak peta.
## `_stand()` di sini SAMA PERSIS dengan yang dipakai `zz_survey.gd` untuk
## memetakan kolom, jadi hasil survei dan hasil teleport selalu sepakat.
## Kalau diagnostic bilang "x=3020, y=3800 standable", teleport juga akan
## mendarat di sana. Kalau dua-duanya berubah, harus diubah dua file.
##
## Return -1 kalau tidak ada pita standable dalam `ARRIVAL_SCAN_MAX`. Di peta
## ini tidak terjadi (jarak terjauh 1032px), tapi return-nya tetap dijaga
## supaya perubahan peta di masa depan tidak diam-diam teleport ke lubang.
func _resolve_arrival_y(player: CharacterBody2D, to_map2: bool) -> float:
	var arrival_x := ARRIVE_MAP2_X if to_map2 else ARRIVE_MAP1_X
	var origin_y := clampf(player.global_position.y, Y_MIN, Y_MAX)
	var col := player.get_node_or_null(PLAYER_COLLISION) as CollisionShape2D
	if col == null or col.shape == null:
		return -1.0
	var space := player.get_world_2d().direct_space_state
	var foot := _player_foot(col)

	# Tinggi sekarang dulu: kasus paling umum, tidak ada Y yang perlu digeser.
	if _stand(space, col.shape, col.global_transform, arrival_x, origin_y,
			foot, player) >= 0.0:
		return origin_y

	# Lalu melangkah keluar selebar ARRIVAL_SCAN_STEP, naik dulu lalu turun
	# pada tiap langkah supaya jarak yang sama dianggap setara.
	var offset := ARRIVAL_SCAN_STEP
	while offset <= ARRIVAL_SCAN_MAX:
		var below := clampf(origin_y + offset, Y_MIN, Y_MAX)
		if _stand(space, col.shape, col.global_transform, arrival_x, below,
				foot, player) >= 0.0:
			return below
		var above := clampf(origin_y - offset, Y_MIN, Y_MAX)
		if _stand(space, col.shape, col.global_transform, arrival_x, above,
				foot, player) >= 0.0:
			return above
		offset += ARRIVAL_SCAN_STEP
	return -1.0

## Ground y player bisa bertumpu di column ini, atau -1 kalau tidak bisa berdiri.
func _stand(space: PhysicsDirectSpaceState2D, shape: Shape2D, base_xf: Transform2D,
		x: float, y: float, foot: float, player: CharacterBody2D) -> float:
	var q := PhysicsRayQueryParameters2D.create(Vector2(x, y), Vector2(x, y + MAX_DROP))
	q.collide_with_areas = false
	q.collision_mask = 0xFFFFFFFF
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return -1.0
	var gy: float = (hit["position"] as Vector2).y

	var q2 := PhysicsShapeQueryParameters2D.new()
	q2.shape = shape
	var xf := base_xf
	xf.origin = base_xf.origin + (Vector2(x, gy - foot) - base_xf.get_origin())
	q2.transform = xf
	q2.collision_mask = 0xFFFFFFFF
	q2.collide_with_areas = false
	q2.collide_with_bodies = true
	q2.exclude = [player.get_rid(), hit["rid"]]
	if not space.intersect_shape(q2, 1).is_empty():
		return -1.0
	return gy

## Jarak dari origin player ke dasar capsule (titik tumpu), dalam koordinat
## GLOBAL. Capsule di Player.tscn di-offset (1,37) dan di-scale, jadi angka
## hardcode seperti 37 atau 60 salah kalau scene-nya berubah.
func _player_foot(col: CollisionShape2D) -> float:
	var half_h := 18.0
	var capsule := col.shape as CapsuleShape2D
	if capsule != null:
		half_h = capsule.height * 0.5
	return col.position.y + half_h * absf(col.scale.y)

## Geser ke kolom arrival, dan ke tinggi hasil `_resolve_arrival_y()`.
## Y TIDAK lagi ikut tinggi player: itu justru bug yang bikin pemindahan
## tersendat. Tinggi arrival sudah dipastikan standable sebelum teleport, jadi
## tinggal menerapkannya di sini.
func _place_player(player: CharacterBody2D, to_map2: bool, arrival_y: float) -> void:
	var x := ARRIVE_MAP2_X if to_map2 else ARRIVE_MAP1_X
	player.global_position = Vector2(x, clampf(arrival_y, Y_MIN, Y_MAX))
	# Velocity direset supaya player tidak meluncur melewati arrival point
	# karena sisa momentum waktu freeze.
	player.velocity = Vector2.ZERO

func _freeze_player(player: CharacterBody2D) -> void:
	_frozen_player = player
	_frozen_prev_physics = player.is_physics_processing()
	player.set_physics_process(false)

## Dipanggil baik di akhir transisi normal maupun dari `_exit_tree()`.
## Idempoten: aman dipanggil dua kali.
func _release_player() -> void:
	if is_instance_valid(_frozen_player):
		_frozen_player.set_physics_process(_frozen_prev_physics)
	_frozen_player = null

func _fade_to(alpha: float) -> void:
	# Tween sengaja dibuat lewat `self`, bukan `get_tree()`: kalau node ini
	# dibuang, tween-nya ikut mati dan coroutine-nya ikut berhenti, bukan
	# nyesel-half-resume lalu nulis ke object yang udah free. Sisa player
	# yang masih beku ditangani `_exit_tree()`.
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", alpha, FADE_TIME)
	await tween.finished

func _resolve_player() -> CharacterBody2D:
	if is_instance_valid(_player):
		return _player
	_player = _find_player()
	return _player

func _find_player() -> CharacterBody2D:
	for node in get_tree().get_nodes_in_group(PLAYER_GROUP):
		if node is CharacterBody2D:
			return node as CharacterBody2D
	return null
