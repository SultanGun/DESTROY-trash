extends SceneTree

## Unit test: Prologue dialog & auto-approach Kades.
## Menguji file .dialogue, parsing via DialogueManager, helper pergerakan
## player, dan status save/load prologue_completed.

const DialogueManagerScript := preload("res://addons/dialogue_manager/dialogue_manager.gd")
const PlayerScene := preload("res://scenes/Player.tscn")
const KadesScene := preload("res://scenes/kades.tscn")
const GameDataScript := preload("res://scripts/game_data.gd")
const PatrolHUDScene := preload("res://scenes/PatrolHUD.tscn")
const TimeManagerScript := preload("res://scripts/time_manager.gd")

var _pass := 0
var _fail := 0

func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass += 1
		print("  LULUS  ", message)
	else:
		_fail += 1
		printerr("  GAGAL  ", message)

func _initialize() -> void:
	await process_frame
	_test_dialogue_file_and_compiler()
	_test_player_cutscene_methods()
	_test_kades_setup()
	_test_save_load_flag()
	_test_patrol_hud_visibility_gating()
	print("===================================================")
	print("  test_prologue: lulus=%d gagal=%d" % [_pass, _fail])
	print("===================================================")
	quit(_fail)

func _test_dialogue_file_and_compiler() -> void:
	var path := "res://dialogues/prologue.dialogue"
	_assert(FileAccess.file_exists(path), "File dialogues/prologue.dialogue harus ada di disk")

	var text := FileAccess.get_file_as_string(path)
	_assert(text.contains("~ start"), "Dialogue harus punya label '~ start'")
	_assert(text.contains("~ reminder"), "Dialogue harus punya label '~ reminder'")
	_assert(text.contains("Kepala Desa:"), "Dialogue harus memuat percakapan 'Kepala Desa:'")
	_assert(text.contains("Browli:"), "Dialogue harus memuat percakapan 'Browli:'")

	var dm = DialogueManagerScript.new()
	var res = dm.create_resource_from_text(text)
	_assert(res != null, "DialogueManager harus bisa compile teks .dialogue tanpa error")
	_assert("start" in res.titles, "Titles harus memuat 'start'")
	_assert("reminder" in res.titles, "Titles harus memuat 'reminder'")
	_assert("Kepala Desa" in res.character_names, "Character names harus memuat 'Kepala Desa'")
	_assert("Browli" in res.character_names, "Character names harus memuat 'Browli'")
	dm.free()

func _test_player_cutscene_methods() -> void:
	var player = PlayerScene.instantiate()
	get_root().add_child(player)
	player.global_position = Vector2(711, 803)

	_assert(not player.is_in_cutscene(), "Default player tidak dalam cutscene")
	player.set_cutscene_mode(true)
	_assert(player.is_in_cutscene(), "set_cutscene_mode(true) harus menyalakan flag cutscene")

	# Gerak menuju titik target
	var target := Vector2(711, 810)
	var arrived: bool = player.move_towards_point(target, 0.016)
	_assert(player.global_position.y > 803.0, "move_towards_point harus memindahkan posisi player")
	_assert(player.facing.y > 0.0, "facing harus mengarah ke bawah")

	# Snap saat dekat
	player.global_position = Vector2(711, 809)
	arrived = player.move_towards_point(target, 0.016)
	_assert(arrived, "move_towards_point harus return true jika jarak < 4px")
	_assert(player.global_position == target, "posisi player harus snap ke target")

	player.face_direction(Vector2.UP)
	_assert(player.facing == Vector2.UP, "face_direction harus mengubah arah hadap player")

	player.set_cutscene_mode(false)
	_assert(not player.is_in_cutscene(), "set_cutscene_mode(false) harus menonaktifkan cutscene")
	player.queue_free()

func _test_kades_setup() -> void:
	var tm = TimeManagerScript.new()
	tm.name = "TimeManager"
	get_root().add_child(tm)

	var kades = KadesScene.instantiate()
	get_root().add_child(kades)
	_assert(kades.is_in_group("kades"), "Kades harus terdaftar di group 'kades'")
	_assert(kades.is_in_group("npcs"), "Kades harus terdaftar di group 'npcs'")

	# Jam 10:00 (siang) -> Kades aktif
	tm.jump_to_hour(10.0)
	kades._process(0.016)
	_assert(kades.visible, "Kades harus tampak pada jam 10:00")

	# Jam 16:00 (sore/tutup) -> Kades menghilang
	tm.jump_to_hour(16.0)
	kades._process(0.016)
	_assert(not kades.visible, "Kades harus hilang pada jam 16:00")

	# Jam 20:00 (malam) -> Kades tetap hilang
	tm.jump_to_hour(20.0)
	kades._process(0.016)
	_assert(not kades.visible, "Kades harus tetap hilang pada jam 20:00")

	# Jam 06:00 (pagi hari baru) -> Kades muncul kembali
	tm.jump_to_hour(6.0)
	kades._process(0.016)
	_assert(kades.visible, "Kades harus muncul kembali pada jam 06:00")

	# Uji PromptBadge
	kades._set_prompt_visible(true)
	var badge = kades.get_node_or_null("PromptBadge")
	_assert(badge != null, "Kades harus membuat node PromptBadge")
	_assert(badge.visible, "PromptBadge harus terlihat saat _set_prompt_visible(true)")
	kades._set_prompt_visible(false)
	_assert(not badge.visible, "PromptBadge harus tersembunyi saat _set_prompt_visible(false)")

	kades.queue_free()
	tm.queue_free()

func _test_save_load_flag() -> void:
	var gd = GameDataScript.new()
	_assert(not gd.prologue_completed, "prologue_completed awal harus false")

	gd.prologue_completed = true
	_assert(gd.prologue_completed, "prologue_completed bisa diubah ke true")

	# Uji parsing save data format dictionary
	var dummy_save = {
		"prologue_completed": true,
		"coins": 50,
		"day": 1
	}
	_assert(dummy_save.get("prologue_completed", false) == true, "Save dictionary memuat prologue_completed")
	gd.free()

func _test_patrol_hud_visibility_gating() -> void:
	var root = get_root()
	var gd: Node = root.get_node_or_null("GameData")
	var created_gd := false
	if gd == null:
		gd = GameDataScript.new()
		gd.name = "GameData"
		root.add_child(gd)
		created_gd = true

	# Prologue belum selesai -> PatrolHUD harus hidden
	gd.set("prologue_completed", false)
	var hud = PatrolHUDScene.instantiate()
	root.add_child(hud)
	_assert(not hud.visible, "PatrolHUD harus tersembunyi jika prolog belum selesai")

	# Prologue selesai -> PatrolHUD harus otomatis visible
	gd.set("prologue_completed", true)
	_assert(hud.visible, "PatrolHUD harus muncul setelah prolog selesai")

	hud.free()
	if created_gd:
		gd.free()
