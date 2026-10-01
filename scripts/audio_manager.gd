extends Node

## AudioManager (Autoload) — Godot 4.4.1 compatible.
## - Music: Dolphin Shores OGG, loop, selalu bunyi, volume rendah.
## - Ambience: burung (siang) vs jangkrik (malam), crossfade ikut TimeManager.phase.
## - SFX: vacuum suck, one-shot per sampah mulai kesedot, pool anti-kepotong.

const MUSIC_STREAM := preload("res://assets/audio/music_main_dolphin_shores.ogg")
const MUSIC_NIGHT_STREAM := preload("res://assets/audio/music_night_clouds.mp3")
const DAY_STREAM := preload("res://assets/audio/ambience_day_birds.mp3")
const NIGHT_STREAM := preload("res://assets/audio/ambience_night_crickets.mp3")
const VACUUM_STREAM := preload("res://assets/audio/sfx_vacuum_suck.mp3")
const CLICK_STREAM := preload("res://assets/audio/sfx_ui_click.mp3")
const COIN_STREAM := preload("res://assets/audio/sfx_coin_reward.mp3")
const UPGRADE_STREAM := preload("res://assets/audio/sfx_upgrade.mp3")

const MENU_MUSIC_VOL_DB := -12.0
const GAME_MUSIC_VOL_DB := -14.0
const NIGHT_MUSIC_VOL_DB := -5.0
const MUSIC_FADE_SECS := 1.5
const DAY_ON_DB := -18.0
const NIGHT_ON_DB := -12.0
const AMBI_SUNSET_DB := -20.0
const AMBI_OFF_DB := -80.0
const FADE_SECS := 2.5
const SFX_POOL_SIZE := 6
const UI_POOL_SIZE := 6
const CLICK_VOL_DB := -6.0
const COIN_VOL_DB := -3.0
const UPGRADE_VOL_DB := 0.0

var _music: AudioStreamPlayer
var _music_night: AudioStreamPlayer
var _day: AudioStreamPlayer
var _night: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_idx := 0
var _ui_pool: Array[AudioStreamPlayer] = []
var _ui_idx := 0
var _fade_tween: Tween = null
var _music_fade: Tween = null
var _tm: Node = null
var _last_scene_path := ""
var _ambience_off := true
var _current_phase := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music = _make_player(MUSIC_STREAM, MENU_MUSIC_VOL_DB)
	_music_night = _make_player(MUSIC_NIGHT_STREAM, AMBI_OFF_DB)
	_day = _make_player(DAY_STREAM, AMBI_OFF_DB)
	_night = _make_player(NIGHT_STREAM, AMBI_OFF_DB)
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.stream = VACUUM_STREAM
		p.volume_db = 0.0
		add_child(p)
		_sfx_pool.append(p)
	for i in UI_POOL_SIZE:
		var u := AudioStreamPlayer.new()
		u.volume_db = CLICK_VOL_DB
		add_child(u)
		_ui_pool.append(u)
	_music.play()
	_music_night.play()
	_day.play()
	_night.play()
	# TimeManager adalah node di Main (bukan autoload) dan siap SETELAH
	# autoload — jadi coba connect deferred + dengarkan node baru.
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_late_connect")


## Musik normal di menu, turun sedikit saat di game (main.tscn).
## Saat malam (phase 2), bgm berganti ke music_night_clouds.
## Dicek tiap frame tapi cuma bereaksi saat scene berganti (murah).
func _process(_delta: float) -> void:
	var path := ""
	var cs := get_tree().current_scene
	if cs != null:
		path = cs.scene_file_path
	if path == _last_scene_path:
		return
	_last_scene_path = path
	_update_music(false)
	_update_ambience_presence()


## Ambience hanya boleh bunyi selama ada TimeManager di scene aktif.
## Saat kembali ke menu (TM di-free), senyapkan keduanya; tanpa ini,
## volume terakhir "bocor" dan ikut terdengar di menu.
func _update_ambience_presence() -> void:
	if _tm != null and not is_instance_valid(_tm):
		_tm = null
	if _tm != null:
		return
	# TM tidak ada: kalau scene baru ternyata sudah punya TM (ganti
	# scene game->game), attach langsung daripada menyenyapkan.
	if get_tree().get_first_node_in_group("time_manager") != null:
		_late_connect()
		return
	if not _ambience_off:
		_silence_ambience()


func _silence_ambience() -> void:
	_current_phase = 0
	_update_music(false)
	if _day == null or _night == null:
		return
	_kill_fade()
	_ambience_off = true
	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.tween_property(_day, "volume_db", AMBI_OFF_DB, 1.5)
	_fade_tween.tween_property(_night, "volume_db", AMBI_OFF_DB, 1.5)


func _update_music(instant: bool) -> void:
	if _music == null or _music_night == null:
		return
	var is_game := (_tm != null and is_instance_valid(_tm)) or (_last_scene_path.get_file() == "main.tscn")
	var day_music_target := AMBI_OFF_DB
	var night_music_target := AMBI_OFF_DB

	if not is_game:
		day_music_target = MENU_MUSIC_VOL_DB
		night_music_target = AMBI_OFF_DB
	else:
		if _current_phase == 2:
			day_music_target = AMBI_OFF_DB
			night_music_target = NIGHT_MUSIC_VOL_DB
		else:
			day_music_target = GAME_MUSIC_VOL_DB
			night_music_target = AMBI_OFF_DB

	if instant:
		if _music_fade != null and _music_fade.is_valid():
			_music_fade.kill()
		_music.volume_db = day_music_target
		_music_night.volume_db = night_music_target
		return

	if is_equal_approx(_music.volume_db, day_music_target) and is_equal_approx(_music_night.volume_db, night_music_target):
		return

	if _music_fade != null and _music_fade.is_valid():
		_music_fade.kill()
	_music_fade = create_tween().set_parallel(true)
	_music_fade.tween_property(_music, "volume_db", day_music_target, MUSIC_FADE_SECS)
	_music_fade.tween_property(_music_night, "volume_db", night_music_target, MUSIC_FADE_SECS)


func _make_player(stream: AudioStream, vol_db: float) -> AudioStreamPlayer:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol_db
	add_child(p)
	return p


## SFX vacuum: dipanggil Player tiap 1 sampah mulai kesedot.
func play_vacuum() -> void:
	if _sfx_pool.is_empty():
		return
	# Cari player yang lagi nganggur dulu biar overlap tidak kepotong.
	for p in _sfx_pool:
		if not p.playing:
			p.pitch_scale = randf_range(0.95, 1.05)
			p.play()
			return
	# Semua sibuk: pakai round-robin (restart yang terlama).
	var p2: AudioStreamPlayer = _sfx_pool[_sfx_idx]
	_sfx_idx = (_sfx_idx + 1) % _sfx_pool.size()
	p2.pitch_scale = randf_range(0.95, 1.05)
	p2.play()


## SFX UI: click tiap tombol ditekan, coin saat koin benar-benar masuk.
func play_click() -> void:
	_play_ui(CLICK_STREAM, CLICK_VOL_DB, randf_range(0.97, 1.03))


func play_coin() -> void:
	_play_ui(COIN_STREAM, COIN_VOL_DB, 1.0)


func play_upgrade() -> void:
	_play_ui(UPGRADE_STREAM, UPGRADE_VOL_DB, 1.0)


func _play_ui(stream: AudioStream, vol_db: float, pitch: float) -> void:
	if _ui_pool.is_empty():
		return
	for u in _ui_pool:
		if not u.playing:
			u.stream = stream
			u.volume_db = vol_db
			u.pitch_scale = pitch
			u.play()
			return
	var u2: AudioStreamPlayer = _ui_pool[_ui_idx]
	_ui_idx = (_ui_idx + 1) % _ui_pool.size()
	u2.stream = stream
	u2.volume_db = vol_db
	u2.pitch_scale = pitch
	u2.play()


func _late_connect() -> void:
	var tm := get_tree().get_first_node_in_group("time_manager")
	if tm != null:
		_attach_tm(tm)


func _on_node_added(node: Node) -> void:
	# node_added terpancar SEBELUM _ready() node tersebut jalan, sedangkan
	# TimeManager baru masuk grup di dalam _ready() (add_to_group) — jadi
	# cek grup harus ditunda ke akhir frame via deferred.
	#
	# Yang dikirim ke deferred adalah INSTANCE ID, bukan objeknya. Kalau objeknya
	# di-free sebelum frame berakhir, konversi argumen akan gagal ("Cannot convert
	# argument 1 from Object to Object") dan guard is_instance_valid() di dalam
	# fungsi tidak pernah sempat jalan. ID integer aman; nodanya di-resolve ulang
	# dengan instance_from_id().
	var id := node.get_instance_id()
	call_deferred("_check_node_tm", id)
	# Hook click sound ke semua tombol (termasuk yang dibuat saat runtime,
	# misal panah/bin mesin pilah) — deferred dengan alasan yang sama.
	call_deferred("_hook_buttons_deep", id)


func _check_node_tm(node_id: int) -> void:
	var node := instance_from_id(node_id) as Node
	if node != null and node.is_in_group("time_manager"):
		_attach_tm(node)


## Pasang click sound ke node + seluruh turunannya. Guard meta cegah
## koneksi ganda saat scene di-reload. Tombol disabled tidak memancarkan
## pressed, jadi tidak ada bunyi palsu.
func _hook_buttons_deep(node_id: int) -> void:
	var node := instance_from_id(node_id) as Node
	if node == null:
		return
	_hook_one_button(node)
	for c in node.get_children():
		_hook_buttons_deep(c.get_instance_id())


func _hook_one_button(node: Node) -> void:
	if not (node is BaseButton):
		return
	if node.has_meta("am_no_click") or node.has_meta("am_click_hooked"):
		return
	node.set_meta("am_click_hooked", true)
	(node as BaseButton).pressed.connect(play_click)


func _attach_tm(tm: Node) -> void:
	if tm == _tm:
		return
	if is_instance_valid(_tm) and _tm.has_signal("phase_changed"):
		if _tm.is_connected("phase_changed", _on_phase_changed):
			_tm.disconnect("phase_changed", _on_phase_changed)
	_tm = tm
	if _tm != null and _tm.has_signal("phase_changed"):
		_tm.connect("phase_changed", _on_phase_changed)
		var start_phase := 0
		if _tm.has_method("phase"):
			start_phase = int(_tm.call("phase"))
		print("AudioManager: TimeManager attached, phase awal = ", start_phase)
		_apply_phase(start_phase, true)


func _on_phase_changed(phase: int) -> void:
	_apply_phase(phase, false)


## Phase TimeManager: 0 DAY, 1 SUNSET, 2 NIGHT.
func _apply_phase(phase: int, instant: bool) -> void:
	_current_phase = phase
	_update_music(instant)
	if _day == null or _night == null:
		return
	_ambience_off = false
	var day_target := AMBI_OFF_DB
	var night_target := AMBI_OFF_DB
	match phase:
		0:
			day_target = DAY_ON_DB
		2:
			night_target = NIGHT_ON_DB
		_:
			day_target = AMBI_SUNSET_DB
			night_target = AMBI_SUNSET_DB
	if instant:
		_kill_fade()
		_day.volume_db = day_target
		_night.volume_db = night_target
		return
	_kill_fade()
	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.tween_property(_day, "volume_db", day_target, FADE_SECS)
	_fade_tween.tween_property(_night, "volume_db", night_target, FADE_SECS)


func _kill_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null


## Berhentiin semua player sebelum autoload di-free.
##
## Tanpa ini, playback object (AudioStreamPlaybackOggVorbis / MP3) masih
## dipegang thread audio saat ObjectDB dibersihkan, dan engine mencetak
## "4 resources still in use at exit" + "ObjectDB instances leaked" di SETIAP
## test headless. Semua player di-stop supaya playback-nya dilepas duluan.
func _exit_tree() -> void:
	_kill_fade()
	if _music_fade != null and _music_fade.is_valid():
		_music_fade.kill()
	_music_fade = null
	_stop_all([_music, _day, _night])
	_stop_all(_sfx_pool)
	_stop_all(_ui_pool)


func _stop_all(players: Array) -> void:
	for p in players:
		if p is AudioStreamPlayer and is_instance_valid(p):
			(p as AudioStreamPlayer).stop()
