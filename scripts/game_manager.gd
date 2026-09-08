extends Node

## STEP 6: Sistem Ekonomi & Koin.
## Autoload "GameManager" -> bisa diakses dari mana aja (HUD, Mesin Olah, nanti Shop)
## tanpa get_node path yang rapuh. Data koin dipegang di sini, bukan di Player.

signal coins_changed(new_amount: int)

var coins: int = 0

func add_coins(amount: int) -> void:
	coins += amount
	coins_changed.emit(coins)

func spend_coins(amount: int) -> bool:
	if coins < amount:
		return false
	coins -= amount
	coins_changed.emit(coins)
	return true