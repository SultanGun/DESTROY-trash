extends SceneTree

## Uji balance audio: BGM harus jadi alas, ambience duduk di bawahnya.
##
## Latar: burung pagi terdengar LEBIH KERAS dari BGM padahal gain-nya -18 dB
## vs BGM -14 dB. Penyebabnya: angka dB itu relatif terhadap file-nya
## masing-masing, dan file burung jauh lebih panas (-14.7 LUFS, spiky LRA 12.1)
## dibanding file musik (-16.5 LUFS, halus LRA 2.5). Test ini mengunci HUBUNGAN
## antar gain (beda minimal 6 dB antara bed dan ambience), bukan angka mutlak,
## supaya penyeimbang berikutnya tidak mengulanginya.
##
## Pengukuran sumber (ffmpeg loudnorm, EBU R128) saat balance ini dibuat:
##   music_main_dolphin_shores.ogg  I=-16.47  LRA=2.5
##   music_night_clouds.mp3         I=-27.02  LRA=1.5
##   ambience_day_birds.mp3         I=-14.65  LRA=12.1
##   ambience_night_crickets.mp3    I=-23.89  LRA=3.4
##   ambience_rain.mp3              I=-25.51  LRA=1.7
##
## Harness headless tanpa framework test project:
##   godot --headless --path <project> --script res://tests/test_audio_balance.gd

const AudioManagerScript := preload("res://scripts/audio_manager.gd")
const RainScript := preload("res://scripts/rain_system.gd")

## Jarak minimal (dB) antara bed musik dan ambience-nya. 6 dB = ambience
## jelas di bawah bed walau file ambience-nya panas dan spiky.
const MIN_BED_GAP_DB := 6.0

var _pass := 0
var _fail := 0
var _total_fail := 0
var _failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	await _run("siang: burung jauh di bawah BGM", _test_day_balance)
	await _run("malam: jangkrik jauh di bawah BGM malam", _test_night_balance)
	await _run("hujan duduk di bawah BGM, bukan di atasnya", _test_rain_sits_under_music)
	await _run("semua gain ambience/musik dalam batas aman", _test_gains_in_safe_bounds)
	await process_frame
	_report()
	quit(0 if _total_fail == 0 else 1)


func _run(label: String, fn: Callable) -> void:
	_fail = 0
	await fn.call()
	if _fail == 0:
		_pass += 1
		print("  LULUS  ", label)
	else:
		_total_fail += _fail
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
	print("  lulus=%d  gagal=%d" % [_pass, _total_fail])
	if _total_fail > 0:
		print("  --- kegagalan ---")
		for f in _failures:
			print("  * ", f)
	print("===================================================")


func _test_day_balance() -> void:
	var music: float = AudioManagerScript.GAME_MUSIC_VOL_DB
	var birds: float = AudioManagerScript.DAY_ON_DB
	_check(birds < music,
		"burung (%.1f dB) harus DI BAWAH BGM siang (%.1f dB)" % [birds, music])
	_check(music - birds >= MIN_BED_GAP_DB,
		"jarak BGM-burung %.1f dB kurang dari %.1f dB - burung akan menutupi musik"
		% [music - birds, MIN_BED_GAP_DB])


func _test_night_balance() -> void:
	var music: float = AudioManagerScript.NIGHT_MUSIC_VOL_DB
	var crickets: float = AudioManagerScript.NIGHT_ON_DB
	_check(crickets < music,
		"jangkrik (%.1f dB) harus DI BAWAH BGM malam (%.1f dB)" % [crickets, music])
	_check(music - crickets >= MIN_BED_GAP_DB,
		"jarak BGM-jangkrik %.1f dB kurang dari %.1f dB" % [music - crickets, MIN_BED_GAP_DB])


func _test_rain_sits_under_music() -> void:
	var music: float = AudioManagerScript.GAME_MUSIC_VOL_DB
	var rain: float = RainScript.RAIN_VOL_DB
	_check(rain < music,
		"hujan (%.1f dB) harus di bawah BGM siang (%.1f dB)" % [rain, music])


func _test_gains_in_safe_bounds() -> void:
	# Gain staging tidak boleh positif (risiko clipping dari gain) dan tidak
	# boleh lebih sunyi dari -80 dB (batas bisu engine di file ini).
	var gains := {
		"GAME_MUSIC": AudioManagerScript.GAME_MUSIC_VOL_DB,
		"MENU_MUSIC": AudioManagerScript.MENU_MUSIC_VOL_DB,
		"NIGHT_MUSIC": AudioManagerScript.NIGHT_MUSIC_VOL_DB,
		"DAY_BIRDS": AudioManagerScript.DAY_ON_DB,
		"NIGHT_CRICKETS": AudioManagerScript.NIGHT_ON_DB,
		"RAIN": RainScript.RAIN_VOL_DB,
	}
	for name in gains:
		var v: float = gains[name]
		_check(v <= 0.0 and v >= -80.0,
			"gain %s = %.1f dB di luar batas aman [-80, 0]" % [name, v])
	# Musik menu harus terdengar (bukan bisu).
	_check(float(gains["MENU_MUSIC"]) > AudioManagerScript.AMBI_OFF_DB,
		"musik menu tidak boleh bisu")
