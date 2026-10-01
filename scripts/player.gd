extends CharacterBody2D

## Player: gerak WASD, sprint Shift, inventaris B, koordinat B, tangkapan E.
##
## Tangkapan tidak lagi "tekan E = langsung tertangkap". E membuka minigame bar
## + zona target (lihat catch_minigame.gd); tekan E kedua kalinya saat bar pas
## di zona yang benar-benar menutup NPC.
##
## Ringkasan: bar bolak-balik, tiga percobaan, gagal tiga kali = NPC kabur.
## Selama minigame aktif player dikunci di tempat dan NPC-nya dibekukan, supaya
## tantangannya timing, bukan mengejar.

@export var walk_speed: float = 240.0
@export var run_speed: float = 380.0

## Transparansi object (bangunan/pohon/batu) waktu player lewat di depannya
## ala Stardew Valley, biar character tetap kelihatan.
@export var occlusion_alpha: float = 0.4

const OCCLUSION_PROBE_SIZE := Vector2(160, 360)
const OCCLUSION_MASK := 1

## Offset kaki dari origin (Collision ada di y=37): dipakai sebagai kunci
## depth sort global biar sejajar dengan dasar sprite prop.
const FOOT_Y := 40.0

## Jarak tangkap maksimum, diukur dari titik tengah player. 50px kira-kira
## satu langkah ditambah lengan: dekat tanpa menempel, longgak tanpa jauh.
const CATCH_RANGE_PX := 50.0

var facing: Vector2 = Vector2.DOWN

## body (StaticBody2D) -> { sprite, alpha }
var _occluded: Dictionary = {}

var _probe_shape: RectangleShape2D

const INVENTORY_UI := preload("res://iventory.tscn")
var _inv_ui: CanvasLayer = null

## Minigame tangkapan (bar + zona target). Dibuat sekali di _ready, bukan
## tiap kali E ditekan, supaya tidak ada alokasi node di tengah gameplay.
const CATCH_MINIGAME := preload("res://scenes/CatchMinigame.tscn")
var _minigame: CanvasLayer = null

## NPC yang sedang dinilai minigame. null = tidak ada tangkapan yang berjalan.
var _minigame_target: Node2D = null

## Prompt badge di atas NPC yang bisa ditutup. Mengikuti pola yang sama dengan
## shop ("[E] Beli") supaya player sudah tahu cara pakainya tanpa ditebak.
const PROMPT_BADGE := preload("res://scenes/PromptBadge.tscn")
const CATCH_PROMPT_OFFSET := Vector2(0, -84)
var _prompt_badge: CanvasLayer = null

## HUD koordinat (toggle Tombol B) — dibuat saat _ready biar kelihatan
## & nggak perlu nambah node manual di Player.tscn.
## Nempel di kiri-bawah layar (anchor pojok kiri-bawah, jadi tetap di sana
## walau ukuran jendela/resolusi berubah).
const COORD_HUD_OFFSET := Vector2(14, 14)
const COORD_HUD_FONT_SIZE := 12
var _coord_layer: CanvasLayer = null
var _coord_label: Label = null
var _show_coords := false

@onready var anim: AnimatedSprite2D = $Visual/Anim
@onready var inventory: Inventory = $Inventory
@onready var coin_label: Label = $CoinHUD/Box/CoinLabel
@onready var inv_toggle: Button = $InventoryToggle/Button
@onready var rogue_marker: CanvasLayer = $RogueMarker

func _ready() -> void:
	_probe_shape = RectangleShape2D.new()
	_probe_shape.size = OCCLUSION_PROBE_SIZE
	_update_depth()
	_instantiate_inventory_ui()
	_instantiate_catch_minigame()
	inv_toggle.pressed.connect(_toggle_inventory)
	_build_coin_hud()
	_build_coord_hud()
	# Penunjuk pembuang liar butuh tahu posisinya di mana supaya bisa
	# menggambar chevron / panah tepi relatif terhadap player.
	if rogue_marker != null and rogue_marker.has_method("setup"):
		rogue_marker.call("setup", self)

func _instantiate_inventory_ui() -> void:
	_inv_ui = INVENTORY_UI.instantiate()
	_inv_ui.name = "InventoryUI"
	add_child(_inv_ui)
	_inv_ui.visible = false
	_inv_ui.setup(self)
	_inv_ui.close_requested.connect(_close_inventory)

func _instantiate_catch_minigame() -> void:
	_minigame = CATCH_MINIGAME.instantiate()
	_minigame.name = "CatchMinigame"
	add_child(_minigame)
	_minigame.connect("succeeded", _on_minigame_succeeded)
	_minigame.connect("failed", _on_minigame_failed)
	_minigame.connect("dismissed", _on_minigame_dismissed)

func _toggle_inventory() -> void:
	if _inv_ui == null:
		return
	_inv_ui.visible = not _inv_ui.visible
	if _inv_ui.visible:
		_inv_ui.refresh()

func _close_inventory() -> void:
	if _inv_ui:
		_inv_ui.visible = false


## ---------- HUD KOORDINAT (tombol B) ----------
func _build_coord_hud() -> void:
	_coord_layer = CanvasLayer.new()
	_coord_layer.name = "CoordHUD"
	add_child(_coord_layer)
	_coord_label = Label.new()
	_coord_label.name = "CoordLabel"
	# Anchor ke pojok kiri-bawah layar (bukan position absolut) supaya tetap
	# di kiri-bawah walau resolusi jendela berubah.
	_coord_label.anchor_left = 0.0
	_coord_label.anchor_top = 1.0
	_coord_label.anchor_right = 0.0
	_coord_label.anchor_bottom = 1.0
	_coord_label.offset_left = COORD_HUD_OFFSET.x
	_coord_label.offset_top = -COORD_HUD_OFFSET.y - 20.0
	_coord_label.offset_right = COORD_HUD_OFFSET.x
	_coord_label.offset_bottom = -COORD_HUD_OFFSET.y
	_coord_label.grow_horizontal = Control.GROW_DIRECTION_END
	_coord_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_coord_label.add_theme_font_size_override("font_size", COORD_HUD_FONT_SIZE)
	# Outline gelap biar teks tetap kebaca di atas map terang/gelap.
	_coord_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.4))
	_coord_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_coord_label.add_theme_constant_override("outline_size", 4)
	_coord_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_coord_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coord_label.text = "X: 0   Y: 0"
	_coord_label.visible = false
	_coord_layer.add_child(_coord_label)


func _toggle_coords() -> void:
	_show_coords = not _show_coords
	_coord_label.visible = _show_coords
	if _show_coords:
		_update_coord_label()


## Isi label dengan posisi dunia player. Dipanggil tiap frame selama HUD
## tampil, jadi koordinat ikut bergerak.
func _update_coord_label() -> void:
	if _coord_label == null:
		return
	var p := global_position
	_coord_label.text = "X: %d   Y: %d" % [roundi(p.x), roundi(p.y)]


func _process(_delta: float) -> void:
	# Murah: cuma jalan kalau HUD koordinat sedang tampil.
	if _show_coords:
		_update_coord_label()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not event.pressed:
		return
	match event.keycode:
		KEY_TAB:
			_toggle_inventory()
			get_viewport().set_input_as_handled()
		KEY_B:
			_toggle_coords()
			get_viewport().set_input_as_handled()
		KEY_E:
			if _press_e():
				get_viewport().set_input_as_handled()


## Satu pintu untuk semua yang dipicu E, supaya tidak ada dua tempat yang
## sama-sama memutuskan "apakah E dipakai untuk apa".
##
## Dua mode:
##   1. Minigame sedang jalan -> E ditekan sebagai jawaban timing.
##   2. Tidak ada minigame     -> E mencoba membuka tangkapan.
func _press_e() -> bool:
	if _minigame != null and _minigame.call("is_active"):
		return bool(_minigame.call("press"))
	# Guard UI lain: player berdiri di antara mesin dan NPC masih harus bisa
	# buka mesin dengan E, dan UI toko yang terbuka tidak boleh ketemu catcher.
	if _machine_ui_open() or _shop_ui_open():
		return false
	var target := _nearest_catchable_dumper()
	if target == null:
		return false
	_open_minigame(target)
	return true


## NPC pembuang yang SEDINGINYA bisa ditutup, dalam jangkauan tangkap.
##
## Syarat "harus membawa" DIHAPUS. Dulu E hanya jalan kalau NPC sudah ambil
## sampah di waypoint pickup, dan itu memaksa player menunggu NPC berjalan
## ~800 frame lebih dulu - thud, E dipencet berkali-kali dan tidak terjadi
## apa-apa. Sekarang begitu NPC muncul, E langsung membuka minigame.
##
## Yang tetap dijaga: NPC harus HIDUP. Yang terminal (CAUGHT/ESCAPED) sudah
## selesai malam ini dan tidak boleh bisa ditangkap dua kali, dan NPC yang
## sedang ditahan minigame tidak boleh jadi target baru.
func _nearest_catchable_dumper() -> Node2D:
	var best: Node2D = null
	var best_d := CATCH_RANGE_PX
	# NPC yang paling dekat: satu tekan E hanya menutup satu NPC, jadi pilih
	# yang terdekat supaya tidak perlu menekan E berulang kali.
	for d in get_tree().get_nodes_in_group("illegal_dumpers"):
		if not is_instance_valid(d):
			continue
		if not d.has_method("try_catch"):
			continue
		# NPC yang sedang dinilai minigame lain tidak jadi kandidat; tanpa ini
		# satu NPC bisa jadi target dua kali kalau ada dua player-ish di scene.
		if d == _minigame_target:
			continue
		var state := int(d.call("current_state")) if d.has_method("current_state") else 0
		# CAUGHT(4), ESCAPED(5), dan FLEEING(7) berarti NPC sudah ditutup atau
		# sedang kabur. Semuanya tidak boleh jadi target: FLEEING belum terminal
		# tapi sudah "selesai" dari sisi player, dan try_catch() akan menolaknya
		# juga - menyaring di sini biar prompt tidak muncul untuk NPC yang
		# Sebenarnya sudah ditangani.
		if state == 4 or state == 5 or state == 7:
			continue
		var dist := global_position.distance_to(d.global_position)
		if dist <= best_d:
			best_d = dist
			best = d
	return best


## Prompt badge "[E] Tangkap" yang muncul di atas NPC selama dia bisa
## ditutup. Dibuat lazy supaya tidak ada alokasi node kalau tidak dipakai.
func _catch_prompt_badge(target: Node2D) -> CanvasLayer:
	if _prompt_badge == null or not is_instance_valid(_prompt_badge):
		_prompt_badge = PROMPT_BADGE.instantiate() as CanvasLayer
		_prompt_badge.name = "CatchPrompt"
		add_child(_prompt_badge)
	_prompt_badge.call("setup", target, "[E]", "Tangkap", CATCH_PROMPT_OFFSET)
	# `prompt_badge.gd`::_ready() sengaja mulai tersembunyi, jadi badge harus
	# dinyalakan eksplisit di sini. Tanpa baris ini, setup() jalan tapi badge
	# tetap tidak terlihat - persis bug yang bikin prompt terasa tidak ada.
	_prompt_badge.set("visible", true)
	return _prompt_badge


func _clear_catch_prompt() -> void:
	if _prompt_badge != null and is_instance_valid(_prompt_badge):
		_prompt_badge.set("visible", false)


## Tampilkan atau sembunyikan badge tangkapan sesuai NPC terdekat.
##
## disembunyikan kalau: sedang ada minigame terbuka, ada UI lain yang aktif
## (toko/mesin - E milik mereka), atau tidak ada NPC dalam jangkauan.
func _update_catch_prompt() -> void:
	if _minigame != null and _minigame.call("is_active"):
		_clear_catch_prompt()
		return
	if _machine_ui_open() or _shop_ui_open():
		_clear_catch_prompt()
		return
	var target := _nearest_catchable_dumper()
	if target == null:
		_clear_catch_prompt()
		return
	_catch_prompt_badge(target)


## Buka minigame untuk satu NPC, dan tahan NPC itu diam selama penilaian.
func _open_minigame(target: Node2D) -> void:
	if _minigame == null:
		return
	_minigame_target = target
	# NPC beku dulu, baru minigame dibuka. Urutannya penting: kalau minigame
	# lebih dulu, NPC masih bergerak dan bisa keluar jangkauan di frame yang sama.
	if target.has_method("set_frozen"):
		target.call("set_frozen", true)
	_minigame.call("open")


## Tutup minigame dan lepaskan NPC-nya. Dipanggil oleh semua jalur keluar,
## supaya tidak pernah ada NPC yang tertinggal beku kalau minigame ditutup
## karena alasan apa pun.
func _close_minigame() -> void:
	if _minigame_target != null and is_instance_valid(_minigame_target):
		if _minigame_target.has_method("set_frozen"):
			_minigame_target.call("set_frozen", false)
	_minigame_target = null


func _on_minigame_succeeded() -> void:
	var target := _minigame_target
	_close_minigame()
	# try_catch() menolak kalau NPC sudah tidak membawa apa-apa (mis. NPC menyelesaikan
	# buang dan mulai pulang di antara E ditekan dan tekanannya dinilai), dan itu
	# benar: capturing NPC yang sudah selesai berarti produksi sia-sia.
	if target != null and is_instance_valid(target):
		target.call("try_catch")


func _on_minigame_failed() -> void:
	var target := _minigame_target
	_close_minigame()
	# Tiga gagal: NPC menyerah dan kabur. Tangkapan malam ini jadi mustahil, dan
	# penalti -50 dijatuhkan sekali saat fajar oleh NightPatrol.
	if target != null and is_instance_valid(target):
		target.call("force_escape")


func _on_minigame_dismissed() -> void:
	_close_minigame()


## NPC yang sedang dinilai bisa berhenti jadi target tanpa kesalahan player
## Kalau itu terjadi, menahannya beku di layar cuma membekukan NPC yang sudah
## selesai - dan player menekan E ke bar yang tidak lagi mewakili apa pun.
## Jadi setiap frame dicek: masih hidup, masih membawa, masih dalam jangkauan.
func _guard_minigame_target() -> void:
	if _minigame_target == null:
		return
	if not is_instance_valid(_minigame_target):
		_minigame.call("dismiss")
		return
	# Syarat "masih membawa" TIDAK lagi dipakai di sini: minigame boleh dimulai
	# kapan saja NPC hidup dan dekat, jadi selama berjalan NPC boleh menganggur
	# di titik buang. Yang tetap diperiksa: masih hidup dan masih dalam
	# jangkauan. Kalau NPC lepas, minigame ditutup tanpa memakai percobaan.
	var still_ok := global_position.distance_to(_minigame_target.global_position) <= CATCH_RANGE_PX
	if not still_ok:
		_minigame.call("dismiss")


## True kalau ada mesin dengan UI yang sedang terbuka. Memakai pola yang sama
## dengan machine.gd: satu-satunya sumber kebenaran UI adalah machine itu sendiri.
func _machine_ui_open() -> bool:
	for node in get_tree().get_nodes_in_group("machines"):
		if is_instance_valid(node) and node.has_method("is_ui_open") and node.is_ui_open():
			return true
	return false


## Toko punya UI juga, tapi tidak punya `is_ui_open()`; yang dijaga lewat group
## yang sama supaya pemeriksaan ini tetap satu arah.
func _shop_ui_open() -> bool:
	for node in get_tree().get_nodes_in_group("shops"):
		if is_instance_valid(node) and node.has_method("is_ui_open") and node.is_ui_open():
			return true
	return false


func _physics_process(_delta: float) -> void:
	# Prompt TERCANGKAP dihitung lebih dulu, sebelum cabang minigame. Kalau
	# urutannya dibalik, cabang minigame akan return sebelum badge disembunyikan
	# - dan badge itu tetap menempel di atas panel minigame, menutupi teks
	# "TEKAN E SAAT BAR DI ZONA". Badge dan minigame satu layer, jadi badge
	# yang belakangan di-tree tetap menggambar paling atas.
	_update_catch_prompt()
	# Minigame tangkapan sedang berjalan: player dikunci di tempat. Kalau player
	# bebas bergerak, dia bisa menjauh dari NPC yang sedang dinilai, membuat
	# tangkapan terasa seperti dikejar bukan seperti ditebak.
	if _minigame != null and _minigame.call("is_active"):
		_guard_minigame_target()
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var input_dir := _read_input()
	if input_dir != Vector2.ZERO:
		facing = input_dir.normalized()

	var target_speed := walk_speed
	if Input.is_physical_key_pressed(KEY_SHIFT):
		target_speed = run_speed

	velocity = input_dir * target_speed
	move_and_slide()
	_update_depth()
	_update_animation(input_dir)
	_update_occlusion()


func _read_input() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_W):
		dir.y -= 1.0
	if dir != Vector2.ZERO:
		return dir.normalized()

	return Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")


func _update_animation(input_dir: Vector2) -> void:
	var target := "idle"
	if input_dir != Vector2.ZERO:
		if abs(facing.x) > abs(facing.y):
			target = "right" if facing.x > 0.0 else "left"
		else:
			target = "front" if facing.y > 0.0 else "back"
	if anim.animation != target:
		anim.play(target)


func collect_trash(trash_type: int, kind: String) -> bool:
	if inventory.is_full():
		return false
	inventory.add_trash(trash_type, kind)
	print("Collected: ", trash_type, " (", kind, ") | Total: ", inventory.total_count(), "/", inventory.capacity)
	return true


## ---------- HUD Koin (STEP 6) ----------
## Node CoinHUD sekarang NODE ASLI di scenes/Player.tscn (CanvasLayer):
##    CoinHUD/Box  -> geser utk posisi panil & ukuran kotak (offset)
##    CoinHUD/Box/BG  -> gambar latar kotak
##    CoinHUD/Box/Icon  -> ikon koin
##    CoinHUD/Box/CoinLabel  -> angka koin
## Di sini cuma sambungin sinyal GameManager.coins_changed -> update angka.
func _build_coin_hud() -> void:
	var gm := get_node("/root/GameManager")
	gm.coins_changed.connect(_on_coins_changed)
	_on_coins_changed(gm.coins)

func _on_coins_changed(new_amount: int) -> void:
	if coin_label:
		coin_label.text = str(new_amount)


func _on_pickup_radius_area_entered(area: Area2D) -> void:
	if area.is_in_group("trash") and not inventory.is_full():
		var am := get_node_or_null("/root/AudioManager")
		if am != null and am.has_method("play_vacuum"):
			am.play_vacuum()
		area.start_collect(self)


## ---------- Depth sort global ----------
## z_index = posisi kaki, supaya bisa saling menutupi dengan prop yang
## parent-nya beda (Player di Main, prop di Map1_City). Prop statis di-snap
## sekali di map_depth.gd dengan kunci yang sama (dasar sprite).
func _update_depth() -> void:
	z_as_relative = false
	z_index = clampi(int(global_position.y + FOOT_Y), -4096, 4096)


## ---------- Occlusion ala Stardew Valley ----------
## Query objek statis yang pivot-nya di bawah player (posisi "depan") dan
## sprite-nya beneran nutupin player. Yang ketutup di-fade tipis biar player
## tetap kelihatan, lalu balik normal pas player udah pindah.
func _update_occlusion() -> void:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _probe_shape
	query.transform = Transform2D(0.0, global_position + Vector2(0, 70))
	query.collision_mask = OCCLUSION_MASK
	query.collide_with_areas = false

	var keep := {}
	for hit in space_state.intersect_shape(query, 64):
		var body: Object = hit.collider
		if body == self or not body is StaticBody2D:
			continue
		var sprite := _find_visual(body)
		if sprite == null:
			continue
		# Dasar objek dalam koordinat global: pakai sprite.z_index jika sudah di-snap absolut,
		# atau dasar texture
		var foot_y: float = float(sprite.z_index) if (not sprite.z_as_relative and sprite.z_index > 0) else (sprite.global_position.y + (sprite.texture.get_size().y * 0.5 * sprite.global_scale.y if sprite.texture else 0.0))
		# Hanya fade jika kaki player berada di belakang dasar objek (di area atap/kanopi).
		# Jika kaki player di depan/sejajar dasar objek, player berada di depan, jangan fade.
		var player_foot_y: float = global_position.y + FOOT_Y
		if player_foot_y >= foot_y:
			continue
		# Sprite-nya harus beneran nutupin posisi player, biar fence pendek
		# & objek yang jauh gak ikut nge-fade.
		if not _sprite_aabb(sprite).has_point(global_position):
			continue
		keep[body] = sprite

	for body in keep:
		if _occluded.has(body):
			_occluded[body]["sprite"] = keep[body]
			continue
		var sprite: Sprite2D = keep[body]
		_occluded[body] = { "sprite": sprite, "alpha": sprite.modulate.a }
		sprite.modulate.a = occlusion_alpha

	for body in _occluded.keys():
		if not keep.has(body):
			var entry: Dictionary = _occluded[body]
			if is_instance_valid(entry["sprite"]):
				entry["sprite"].modulate.a = entry["alpha"]
			_occluded.erase(body)


func _exit_tree() -> void:
	for entry in _occluded.values():
		if is_instance_valid(entry["sprite"]):
			entry["sprite"].modulate.a = entry["alpha"]
	_occluded.clear()


## Cari Sprite2D yang harus di-fade: map props punya pola
## Sprite(parent) -> StaticBody2D "_Collision" (anak), mesin punya
## Area2D(root) -> StaticBody2D SolidBody + Sprite2D.
func _find_visual(body: StaticBody2D) -> Sprite2D:
	var parent := body.get_parent()
	if parent is Sprite2D:
		return parent
	if parent:
		for child in parent.get_children():
			if child is Sprite2D:
				return child
	return null


func _sprite_aabb(sprite: Sprite2D) -> Rect2:
	var texture := sprite.texture
	if texture == null:
		return Rect2()
	var size := texture.get_size() * sprite.global_scale
	return Rect2(sprite.global_position - size / 2.0, size)
