extends CanvasLayer
signal close_requested

var _shop_npc: ShopNPC = null
var _coin_label: Label = null
var _upgrades_container: VBoxContainer = null
var _exit_button: Button = null

## Ukuran font GUI toko — sengaja kecil biar muat tanpa berdesakan.
## Tombol upgrade dibuat dari kode, jadi harus di-override manual.
const FONT_SIZE_UPGRADE := 14

## Shortcut testing toko: tekan P buat nambah 100 koin.
## Cuma aktif selama GUI toko kebuka, jadi nggak jadi cheat yang nyala terus.
const DEBUG_COIN_KEY := KEY_P
const DEBUG_COIN_AMOUNT := 100

func _ready() -> void:
	_coin_label = get_node_or_null("CoinLabel")
	_upgrades_container = get_node_or_null("Upgrades")
	_exit_button = get_node_or_null("ExitButton")

	if _exit_button:
		_exit_button.pressed.connect(_on_close_pressed)

func setup(shop: ShopNPC) -> void:
	_shop_npc = shop
	_update_coin_label()
	_populate_upgrades()

func _populate_upgrades() -> void:
	# Clear existing upgrade buttons
	if _upgrades_container == null:
		return
	for child in _upgrades_container.get_children():
		child.queue_free()

	# Get player's inventory
	var inv := _get_inventory()
	if inv == null:
		return

	# Upgrade 1: Inventory capacity expansion (max 20)
	if inv.capacity < 20:
		var btn := Button.new()
		btn.set_meta("am_no_click", true)
		btn.set_meta("am_click_hooked", true)
		var price := _price_for_capacity(inv.capacity)
		btn.text = "Tambah kapasitas %d -> %d  (%d koin)" % [inv.capacity, mini(inv.capacity + 5, 20), price]
		btn.add_theme_font_size_override("font_size", FONT_SIZE_UPGRADE)
		btn.pressed.connect(_on_buy_capacity.bind(price, inv))
		_upgrades_container.add_child(btn)

## Player di-cari lewat group "player" (lihat player.gd), lalu ambil node
## Inventory-nya. Pakai get() supaya aman dari static typing CharacterBody2D.
func _get_inventory() -> Inventory:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player):
		return null
	return player.get("inventory") as Inventory

## GameManager autoload tidak punya class_name, jadi diambil untyped.
func _get_game_manager() -> Node:
	return get_node_or_null("/root/GameManager")

func _get_audio_manager() -> Node:
	return get_node_or_null("/root/AudioManager")

func _price_for_capacity(current_capacity: int) -> int:
	# Base 100, +50 per extra slot beyond 10
	return 100 + (current_capacity - 10) * 50

func _on_buy_capacity(price: int, inventory: Inventory) -> void:
	var gm = _get_game_manager()
	if gm == null:
		return

	if gm.spend_coins(price):
		inventory.set_capacity(inventory.capacity + 5)
		var am = _get_audio_manager()
		if am and am.has_method("play_upgrade"):
			am.play_upgrade()
		_update_coin_label()
		_populate_upgrades()
		print("Kapasitas inventori ditingkatkan menjadi ", inventory.capacity)
	else:
		print("Koin tidak cukup untuk upgrade ini")

func _update_coin_label() -> void:
	if _coin_label == null:
		return
	var gm = _get_game_manager()
	if gm == null:
		_coin_label.text = "Koin: ?"
		return

	_coin_label.text = "Koin: %d" % gm.coins

func _on_close_pressed() -> void:
	close_requested.emit()

## Shortcut testing: tambah koin biar bisa nyoba beli upgrade.
func _add_debug_coins() -> void:
	var gm = _get_game_manager()
	if gm == null:
		return
	gm.add_coins(DEBUG_COIN_AMOUNT)
	# Label koin nyusul langsung, nggak nunggu signal.
	_update_coin_label()
	_populate_upgrades()
	print("DEBUG: +%d koin, total %d" % [DEBUG_COIN_AMOUNT, gm.coins])

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close_requested.emit()
			get_viewport().set_input_as_handled()
		elif event.keycode == DEBUG_COIN_KEY:
			_add_debug_coins()
			get_viewport().set_input_as_handled()
