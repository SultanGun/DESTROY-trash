extends CharacterBody2D

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

var facing: Vector2 = Vector2.DOWN

## body (StaticBody2D) -> { sprite, alpha }
var _occluded: Dictionary = {}

var _probe_shape: RectangleShape2D

const INVENTORY_UI := preload("res://iventory.tscn")
var _inv_ui: CanvasLayer = null

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

func _ready() -> void:
	_probe_shape = RectangleShape2D.new()
	_probe_shape.size = OCCLUSION_PROBE_SIZE
	_update_depth()
	_instantiate_inventory_ui()
	inv_toggle.pressed.connect(_toggle_inventory)
	_build_coin_hud()
	_build_coord_hud()

func _instantiate_inventory_ui() -> void:
	_inv_ui = INVENTORY_UI.instantiate()
	_inv_ui.name = "InventoryUI"
	add_child(_inv_ui)
	_inv_ui.visible = false
	_inv_ui.setup(self)
	_inv_ui.close_requested.connect(_close_inventory)

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


func _physics_process(_delta: float) -> void:
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
