extends Node

## STEP 8+ — Save/Load 2 slot (autoload "SaveLoad").
## File: user://save_slot1.json & save_slot2.json.
## Proses: rumah (E) -> SIMPAN/TIDUR -> tulis slot. Main menu -> LOAD ->
## pilih slot -> set slot ini -> masuk main.tscn -> main.gd auto-terapkan.

const SLOT_COUNT := 2
const SAVE_PATHS := {
	1: "user://save_slot1.json",
	2: "user://save_slot2.json",
}

## Slot yang lagi aktif (menyesuaikan slot yang dipilih/terakhir di-load).
static var current_slot: int = 1

## Slot yang diminta dimuat oleh main menu (-1 = tidak ada).
static var pending_slot: int = -1

func slot_path(slot: int) -> String:
	return SAVE_PATHS.get(slot, "user://save_slot1.json")

func has_save(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))

## Tulis kondisi game sekarang ke slot (SIMPAN & TIDUR di save_menu).
func save_slot(slot: int) -> bool:
	var data := gather_data()
	if data.is_empty():
		return false
	var file := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	current_slot = slot
	print("SAVE slot ", slot, " -> ", slot_path(slot), " | coins=", data.coins, " hari=", data.day)
	return true

## Baca JSON slot terpilih (dipakai main menu buat preview & main.gd buat apply).
func read_slot(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var file := FileAccess.open(slot_path(slot), FileAccess.READ)
	if file == null:
		return {}
	var raw: Variant = JSON.parse_string(file.get_as_text())
	return raw if raw is Dictionary else {}

## Terapkan data save ke dunia (dipanggil SaveLoad.request_load -> main.gd).
func apply_slot(slot: int) -> bool:
	var data := read_slot(slot)
	if data.is_empty():
		return false
	_apply_data(data)
	current_slot = slot
	print("LOAD slot ", slot, " applied | coins=", GameManager.coins, " hari=", data.get("day", 1))
	return true

## Ambil kondisi game sekarang buat ditulis ke save.
func gather_data() -> Dictionary:
	var player := get_tree().get_first_node_in_group("player")
	var tm := get_tree().get_first_node_in_group("time_manager")
	var inv: Inventory = player.inventory if player else null
	var pos: Vector2 = player.global_position if player else Vector2(711, 803)
	return {
		"version": 1,
		"coins": GameManager.coins,
		"day": tm.day if tm else 1,
		"current_time": tm.current_time if tm else 0.0,
		"seconds_per_game_hour": tm.seconds_per_game_hour if tm else 60.0,
		"player_pos": [pos.x, pos.y],
		"inventory_stocks": inv.stocks.duplicate() if inv else {},
		"inventory_capacity": inv.capacity if inv else 10,
		"sorted": GameData.sorted.duplicate(),
	}

func _apply_data(data: Dictionary) -> void:
	var player := get_tree().get_first_node_in_group("player")
	var tm := get_tree().get_first_node_in_group("time_manager")
	if not player or not tm:
		return
	GameManager.coins = int(data.get("coins", 0))
	GameManager.coins_changed.emit(GameManager.coins)
	tm.day = int(data.get("day", 1))
	tm.current_time = float(data.get("current_time", 0.0))
	tm.seconds_per_game_hour = float(data.get("seconds_per_game_hour", 60.0))
	tm.day_length = 24.0 * tm.seconds_per_game_hour
	tm._prev_hour = tm.game_hour()
	var pos: Array = data.get("player_pos", [711, 803])
	player.global_position = Vector2(pos[0], pos[1])
	var inv: Inventory = player.inventory
	inv.set_capacity(int(data.get("inventory_capacity", 10)))
	inv.stocks = (data.get("inventory_stocks", {}) as Dictionary).duplicate()
	inv.organic_count = 0
	inv.anorganic_count = 0
	for kind in inv.stocks:
		if GameData.ITEM_TYPE.get(kind, Trash.TrashType.ORGANIC) == Trash.TrashType.ORGANIC:
			inv.organic_count += inv.stocks[kind]
		else:
			inv.anorganic_count += inv.stocks[kind]
	inv.inventory_changed.emit(inv.organic_count, inv.anorganic_count, inv.capacity)
	GameData.sorted = (data.get("sorted", {}) as Dictionary).duplicate()
	GameData.stats_changed.emit()
