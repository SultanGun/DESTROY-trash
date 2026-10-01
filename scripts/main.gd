extends Node2D

## Main scene handler.
## Menangani startup game:
## 1. Jika ada slot pending dari menu Load (SaveLoad.pending_slot >= 1), muat save.
## 2. Jika game baru (SaveLoad.pending_slot < 1 dan belum prolog), jalankan
##    cutscene jalan kaki ke depan Kades lalu munculkan dialog pembuka.

const PROLOGUE_DIALOGUE_PATH := "res://dialogues/prologue.dialogue"

func _ready() -> void:
	call_deferred("_setup_game_start")

## Autoload SaveLoad diambil lewat /root, bukan identifier global, supaya
## skrip ini tetap bisa dikompilasi pada mode --script headless.
func _save_load() -> Node:
	return get_node_or_null("/root/SaveLoad")

func _setup_game_start() -> void:
	var sl := _save_load()
	var slot: int = sl.pending_slot if sl else -1
	if slot >= 1:
		_apply_pending_load()
	else:
		_check_prologue()

func _apply_pending_load() -> void:
	var sl := _save_load()
	if sl == null:
		return
	var slot: int = sl.pending_slot
	if slot < 1:
		return
	sl.pending_slot = -1
	if sl.apply_slot(slot):
		print("Main: slot ", slot, " di-load.")
	else:
		print("Main: slot ", slot, " kosong/tidak ada.")

func _check_prologue() -> void:
	var gd := get_node_or_null("/root/GameData")
	if gd and gd.prologue_completed:
		return
	# Headless mode skip otomatis untuk smoke/integration test existing
	if DisplayServer.get_name() == "headless":
		if gd and not gd.has_meta("force_prologue_test"):
			if gd:
				gd.prologue_completed = true
			return
	_run_prologue()

## Cutscene gerak otomatis ke depan Kades lalu buka dialog
func _run_prologue() -> void:
	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	var kades := get_tree().get_first_node_in_group("kades")
	if not player or not kades:
		_finish_prologue()
		return

	if player.has_method("set_cutscene_mode"):
		player.call("set_cutscene_mode", true)

	# Titik jalan kaki dari spawn depan rumah (711, 803) menuju depan Kades (900, 937)
	# Jalur L-turn yang rapi dan bebas obstacle:
	# 1. Turun ke y=1010
	# 2. Geser kanan ke x=900 (tepat sejajar Kades)
	# 3. Maju ke atas ke y=995 (tepat di depan muka Kades)
	var kades_pos: Vector2 = kades.global_position
	var p1 := Vector2(player.global_position.x, 1010.0)
	var p2 := Vector2(kades_pos.x, 1010.0)
	var p3 := Vector2(kades_pos.x, kades_pos.y + 58.0)

	await _walk_player_to(player, p1)
	await _walk_player_to(player, p2)
	await _walk_player_to(player, p3)

	# Berhenti dan tatap muka Pak Kades (arah atas / back)
	if player.has_method("face_direction"):
		player.call("face_direction", Vector2.UP)

	# Jeda sejenak untuk timing dramatis
	await get_tree().create_timer(0.35).timeout

	# Tahan waktu dunia selama dialog agar jam siang tidak berkurang
	var tm := get_tree().get_first_node_in_group("time_manager") as TimeManager
	if tm:
		tm.set_process(false)

	_start_prologue_dialogue()

func _walk_player_to(player: CharacterBody2D, target_pos: Vector2) -> void:
	if not player.has_method("move_towards_point"):
		player.global_position = target_pos
		return
	while not player.call("move_towards_point", target_pos, get_physics_process_delta_time()):
		await get_tree().physics_frame

func _start_prologue_dialogue() -> void:
	var dm = get_node_or_null("/root/DialogueManager")
	var dialogue_res = _load_prologue_dialogue()
	if dm and dialogue_res:
		dm.dialogue_ended.connect(_on_prologue_dialogue_ended, CONNECT_ONE_SHOT)
		dm.call("show_dialogue_balloon", dialogue_res, "start")
	else:
		_finish_prologue()

func _on_prologue_dialogue_ended(_resource: Resource) -> void:
	_finish_prologue()

func _finish_prologue() -> void:
	var gd := get_node_or_null("/root/GameData")
	if gd:
		gd.prologue_completed = true

	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player and player.has_method("set_cutscene_mode"):
		player.call("set_cutscene_mode", false)

	var tm := get_tree().get_first_node_in_group("time_manager") as TimeManager
	if tm:
		tm.set_process(true)

	print("Main: Prologue Kades selesai.")

func _load_prologue_dialogue() -> Resource:
	if ResourceLoader.exists(PROLOGUE_DIALOGUE_PATH):
		var res = load(PROLOGUE_DIALOGUE_PATH)
		if res:
			return res
	var dm = get_node_or_null("/root/DialogueManager")
	if dm and dm.has_method("create_resource_from_text"):
		var text := FileAccess.get_file_as_string(PROLOGUE_DIALOGUE_PATH)
		if not text.is_empty():
			return dm.call("create_resource_from_text", text)
	return null
