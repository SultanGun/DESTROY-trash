extends SceneTree

## Smoke test 600 frame pada scene Main sungguhan.
##
## Tujuannya bukan mengulang assertion unit: unit suite sudah-cover logika
## dumper, ekonomi, dan HUD. Yang di sini adalah "dunia tetap berdiri" -
## setelah 600 frame (~10 detik waktu game) tidak ada NPC yang tersesat di luar
## area main, tidak ada dumper yang menumpuk di titik yang sama, dan HUD tetap
## ter-mount. Smoke catch crash yang tidak punya assertion, yang biasanya baru
## muncul saat semua sistem jalan bersamaan.

const MainScene := preload("res://main.tscn")
const FRAMES := 600

const AUTOLOADS := [
	["GameData", "res://scripts/game_data.gd"],
	["GameManager", "res://scripts/game_manager.gd"],
	["SaveLoad", "res://scripts/save_load.gd"],
	["AudioManager", "res://scripts/audio_manager.gd"],
]

var _pass := 0
var _fail := 0


func _initialize() -> void:
	var root := get_root()
	for pair in AUTOLOADS:
		var n: String = pair[0]
		if root.has_node(n):
			continue
		var node := Node.new()
		node.name = n
		node.set_script(load(pair[1]))
		root.add_child(node)
	await process_frame

	var main := MainScene.instantiate()
	root.add_child(main)
	main.name = "Main"
	await process_frame

	var patrol := root.get_node_or_null("NightPatrol")
	if patrol != null:
		patrol.set("auto_spawn", false)
	_check(patrol != null, "autoload NightPatrol harus ada")

	# Malam pertama sungguhan: SATU NPC (peta 1), lalu NPC peta 2 menyusul begitu
	# yang pertama selesai. Smoke ikut mengikuti urutan itu supaya yang diuji
	# memang alur yang dimainkan player, bukan spawn massal.
	var made: Array = []
	if patrol != null:
		patrol.call("clear")
		patrol.call("begin_night", 1)
		made.append_array(patrol.call("active_dumpers"))
	_check(made.size() == 1, "malam pertama harus mulai dengan 1 NPC, dapat %d" % made.size())
	# Lepaskan giliran supaya NPC kedua ikut berjalan selama 600 frame.
	if not made.is_empty():
		made[0].emit_signal("intercepted", "Kurir Pasar", Vector2.ZERO)
		made = patrol.call("active_dumpers")
	_check(made.size() == 2, "setelah NPC pertama selesai harus ada 2 NPC, dapat %d" % made.size())

	for _i in FRAMES:
		await physics_frame

	# --- NPC yang masih hidup harus masih di dalam area main -------------
	var escaped := 0
	for d in made:
		if not is_instance_valid(d):
			continue
		if int(d.call("current_state")) == 5:  # ESCAPED
			escaped += 1
	_check(escaped == 0,
		"%d NPC keluar dari area main dalam %d frame - rute atau WORLD_RECT salah"
			% [escaped, FRAMES])

	# Tidak boleh ada dua NPC di tempat yang sama: tabrakan visual dan
	# interpolation akan terlihat, dan ini symmetry yang mudah patah.
	var overlap := 0
	for i in made.size():
		if not is_instance_valid(made[i]):
			continue
		for j in range(i + 1, made.size()):
			if not is_instance_valid(made[j]):
				continue
			var d0: float = made[i].global_position.distance_to(made[j].global_position)
			if d0 < 8.0:
				overlap += 1
	_check(overlap == 0, "%d pasangan NPC menumpuk (<8px)" % overlap)

	# --- HUD masih hidup dan ter-mount ---------------------------------
	var player := main.get_node_or_null("Player")
	_check(player != null, "Player harus ada setelah 600 frame")
	if player != null:
		var hud: Node = null
		for c in player.get_children():
			if c.name == "PatrolHUD":
				hud = c
				break
		_check(hud != null, "PatrolHUD harus tetap ter-mount")

	# --- Tidak ada dumper yatim di luar subtree Main -------------------
	var orphans := 0
	for d in made:
		if is_instance_valid(d):
			orphans += 1
	_check(orphans == 2,
		"semua 2 NPC harus masih hidup setelah %d frame, tersisa %d" % [FRAMES, orphans])

	print("===================================================")
	print("  smoke 600 frame: lulus=%d gagal=%d" % [_pass, _fail])
	print("===================================================")
	main.free()
	quit(0 if _fail == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  LULUS  ", msg)
	else:
		_fail += 1
		print("  GAGAL  ", msg)
