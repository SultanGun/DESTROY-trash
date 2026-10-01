extends Node

## STEP 6: Sistem Ekonomi, Koin.
## Autoload "GameManager" -> bisa diakses dari mana aja (HUD, Mesin Olah, nanti Shop)
## tanpa get_node path yang rapuh. Data koin dipegang di sini, bukan di Player.
##
## Pollution SUDAH DIHAPUS. Dulu ada meter 0..100 yang naik setiap NPC lolos;
## sekarang kegagalan tidak digolongkan lewat meter, tapi langsung jadi penalti
## koin di akhir malam (lihat `settle_night_loss()`). Meternya dihapus dari
## game_manager, dari save (naik ke v3), dan dari HUD, karena ketiganya satu
## mekanisme dan membiarkan sebagiannya hidup pasti bikin drift.
##
## Aturan yang ditegakkan modul ini:
##   1. Koin selalu punya lantai 0. Tidak ada jalur (akrual, settlement, atau
##      load save) yang boleh membuatnya negatif.
##   2. Settlement malam adalah SATU transaksi yang jatuh di satu malam, bukan
##      per-NPC: 2/2 tertangkap = +100 sekali, selain itu -50 sekali.

signal coins_changed(new_amount: int)

## Settlement hasil satu malam patrol (kontrak balancing).
## Win  = kedua pembuang tertangkap, sekali +, bukan per NPC.
## Loss = ada yang lolos, dan penaltinya jatuh sekali di akhir malam.
const NIGHT_WIN_COINS := 100
const NIGHT_LOSS_COINS := -50

var coins: int = 0


func add_coins(amount: int) -> void:
	coins = maxi(0, coins + amount)
	coins_changed.emit(coins)


## Jalur SETEL (load save) memakai ini, bukan assignment langsung, supaya
## save yang rusak / diedit tangan tidak bisa membawa koin ke angka negatif.
##
## Koin TIDAK punya batas atas. Dulu ada COIN_MAX := 100, dan itu menabrak
## gameplay: satu malam berisi 6 NPC yang semuanya tertangkap memberi 600 koin,
## tapi mentok di 100 membuat sisa malam terasa sia-sia dan angka di HUD tidak
## pernah sama dengan yang benar-benar terkumpul. Yang dijaga hanya lantai 0.
func set_coins(value: int) -> void:
	var clamped := maxi(0, value)
	if clamped == coins:
		return
	coins = clamped
	coins_changed.emit(coins)


func spend_coins(amount: int) -> bool:
	if coins < amount:
		return false
	coins -= amount
	coins_changed.emit(coins)
	return true


## Malam menang: kedua pembuang sudah tertangkap, player menekan tombol klaim
## di HUD. Satu kali saja per malam; NightPatrol yang menjaga supaya tidak bisa
## diklaim berulang, jadi fungsi ini sendiri tidak perlu tahu.
func settle_night_win() -> void:
	add_coins(NIGHT_WIN_COINS)


## Malam kalah: minimal satu pembuang lolos, atau belum sempat diklaim. Dikenakan
## penalti SEKALI, saat malam selesai — bukan tiap NPC yang lolos, supaya dua
## NPC kabur tidak berarti -100 dan supaya angkanya tidak bergerak di tengah
## malam yang masih bisa diselamatkan.
func settle_night_loss() -> void:
	add_coins(NIGHT_LOSS_COINS)
