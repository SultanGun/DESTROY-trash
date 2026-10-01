extends SceneTree

## Uji runtime untuk GameManager: koin dan settlement per malam.
##
## Harness headless tanpa framework test project:
##   godot --headless --path <project> --script res://tests/test_game_manager.gd
##
## Yang diuji (kontrak gameplay, bukan detail visual):
##   1. Koin: add_coins menumpuk, spend_coins menolak kalau kurang.
##   2. Koin punya lantai 0, tidak punya batas atas.
##   3. set_coins clamp ke >= 0 dan tidak spam sinyal.
##   4. Settlement malam menang: +100 sekali.
##   5. Settlement malam kalah: -50 sekali, lantai 0.
##   6. Pollution sudah tidak ada sama sekali (API-nya hilang).
##
## Autoload TIDAK bisa diakses sebagai identifier global saat --script, jadi
## GameManager di-instansikan manual lewat preload.

const GameManagerScript := preload("res://scripts/game_manager.gd")

## Settlement sesuai kontrak per malam: 2/2 tertangkap = +100 sekali,
## selain itu = -50 sekali.
const WIN_COINS := 100
const LOSS_COINS := -50

var _pass := 0
var _fail := 0
var _failures: Array[String] = []

## Noise dari autoload NightPatrol/AudioManager yang tetap hidup di tree.
var _gm: Node = null


func _initialize() -> void:
	await process_frame
	_gm = GameManagerScript.new()
	_gm.name = "GameManagerUji"
	root.add_child(_gm)

	await _run("koin: add menumpuk, spend menolak kalau kurang", _test_coins_basic)
	await _run("koin: lantai 0, tanpa batas atas", _test_coins_no_cap)
	await _run("koin: set_coins clamp + tidak spam sinyal", _test_set_coins)
	await _run("settlement malam menang: +100 koin", _test_settle_night_win)
	await _run("settlement malam kalah: -50 koin", _test_settle_night_loss)
	await _run("settlement malam kalah: koin 0 tidak jadi negatif", _test_settle_night_loss_floor)
	await _run("pollution API sudah dihapus", _test_pollution_gone)

	_gm.queue_free()
	# Beri frame supaya queue_free() selesai; kalau tidak, quit() keluar dengan
	# ObjectDB leak yang menutupi leak yang forthcoming.
	await process_frame
	await process_frame
	_report()
	quit(0 if _fail == 0 else 1)


## --- helper ---------------------------------------------------------------

func _fresh(coins: int) -> void:
	_gm.coins = coins


func _test_coins_basic() -> void:
	_fresh(0)
	_gm.add_coins(30)
	_check(_gm.coins == 30, "setelah +30 harus 30, dapat %d" % _gm.coins)
	_gm.add_coins(20)
	_check(_gm.coins == 50, "setelah +20 harus 50, dapat %d" % _gm.coins)
	_check(_gm.spend_coins(40), "spend 40 dari 50 harus berhasil")
	_check(_gm.coins == 10, "setelah spend 40 harus 10, dapat %d" % _gm.coins)
	_check(not _gm.spend_coins(40), "spend 40 dari 10 harus DITOLAK")


## Koin tidak punya batas atas, tapi tetap punya lantai 0. Dulu ada
## COIN_MAX := 100 dan itu membuat satu malam berisi 6 NPC yang semuanya
## tertangkap (600 koin) terlihat identik dengan satu tangkapan saja.
func _test_coins_no_cap() -> void:
	_fresh(0)
	_gm.add_coins(999)
	_check(_gm.coins == 999, "koin tidak boleh mentok, dapat %d" % _gm.coins)
	# Dua malam menang berturut-turut harus terakumulasi, bukan mentok.
	_gm.add_coins(WIN_COINS)
	_gm.add_coins(WIN_COINS)
	_check(_gm.coins == 999 + WIN_COINS * 2,
		"akumulasi kemenangan tidak boleh dipotong, dapat %d" % _gm.coins)
	_fresh(10)
	_gm.add_coins(-999)
	_check(_gm.coins == 0, "koin harus lantai 0, dapat %d" % _gm.coins)


func _test_set_coins() -> void:
	var seen: Array[int] = []
	_gm.coins_changed.connect(func(v: int) -> void: seen.append(v))
	_fresh(500)
	_gm.set_coins(500)
	_check(seen.is_empty(), "set_coins dengan nilai sama tidak boleh memancarkan, dapat %s" % [seen])
	_gm.set_coins(9999)
	_check(_gm.coins == 9999, "set_coins(9999) harus 9999, dapat %d" % _gm.coins)
	_check(seen == [9999], "hanya nilai baru yang memancarkan, dapat %s" % [seen])
	# Save yang rusak / diedit tangan tidak boleh membawa koin ke negatif.
	_gm.set_coins(-50)
	_check(_gm.coins == 0, "set_coins(-50) harus lantai 0, dapat %d" % _gm.coins)


func _test_settle_night_win() -> void:
	_fresh(0)
	_gm.settle_night_win()
	_check(_gm.coins == WIN_COINS, "menang harus +%d, dapat %d" % [WIN_COINS, _gm.coins])
	# Settlement per malam, bukan per NPC: menumpuk dua malam harus dua kali.
	_gm.settle_night_win()
	_check(_gm.coins == WIN_COINS * 2,
		"dua malam menang harus +%d, dapat %d" % [WIN_COINS * 2, _gm.coins])


func _test_settle_night_loss() -> void:
	_fresh(200)
	_gm.settle_night_loss()
	_check(_gm.coins == 200 + LOSS_COINS,
		"kalah harus %d, dapat %d" % [200 + LOSS_COINS, _gm.coins])
	# Penalti jatuh SEKALI di akhir malam, bukan per NPC yang lolos. Dua
	# pembuang yang lolos tidak boleh berarti -100.
	_gm.settle_night_loss()
	_check(_gm.coins == 200 + LOSS_COINS * 2,
		"dua malam kalah harus dua kali penalti, dapat %d" % _gm.coins)


func _test_settle_night_loss_floor() -> void:
	_fresh(10)
	_gm.settle_night_loss()
	_check(_gm.coins == 0, "kalah dari koin 10 harus lantai 0, dapat %d" % _gm.coins)
	_fresh(0)
	_gm.settle_night_loss()
	_check(_gm.coins == 0, "kalah dari koin 0 harus tetap 0, dapat %d" % _gm.coins)


## Pollution dicabut dari game. API-nya harus benar-benar hilang, bukan sekadar
## disembunyikan: kalau masih ada, save masih akan menyimpannya dan meter bisa
## muncul lagi tanpa ada yang sengaja memanggilnya.
func _test_pollution_gone() -> void:
	for gone in ["pollution", "set_pollution", "add_pollution", "remove_pollution",
			"get_pollution", "settle_catch", "settle_escape", "POLLUTION_MAX"]:
		_check(not _gm.has_method(String(gone)),
			"GameManager tidak boleh punya %s lagi" % gone)
	_check(not ("pollution_changed" in _gm.get_signal_list()),
		"sinyal pollution_changed harus hilang")
	_check(_gm.coins >= 0, "koin harus selalu >= 0, dapat %d" % _gm.coins)


## --- runner ---------------------------------------------------------------

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
	print("    -> GAGAL: ", msg)
	return false


func _report() -> void:
	print("===================================================")
	for f in _failures:
		print("  GAGAL: ", f)
	print("  lulus=%d gagal=%d" % [_pass, _fail])
	print("===================================================")
