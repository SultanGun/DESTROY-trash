extends CharacterBody2D

@export var walk_speed: float = 240.0
@export var run_speed: float = 380.0

## Transparansi object (bangunan/pohon/batu) waktu player lewat di depannya
## ala Stardew Valley, biar character tetap kelihatan.
@export var occlusion_alpha: float = 0.4

const OCCLUSION_PROBE_SIZE := Vector2(160, 360)
const OCCLUSION_MASK := 1

var facing: Vector2 = Vector2.DOWN

## body (StaticBody2D) -> { sprite, alpha }
var _occluded: Dictionary = {}

var _probe_shape: RectangleShape2D
var _slot_style: StyleBoxFlat = null
var _inv_vbox: VBoxContainer = null

@onready var anim: AnimatedSprite2D = $Visual/Anim
@onready var debug_label: Label = $DebugHUD/Label
@onready var inventory: Inventory = $Inventory
@onready var coin_label: Label = $CoinHUD/Margin/HBox/CoinLabel

func _ready() -> void:
	_probe_shape = RectangleShape2D.new()
	_probe_shape.size = OCCLUSION_PROBE_SIZE
	_inv_vbox = $InventoryHUD/Panel/VBox
	# panel inventory diresize biar cukup muat grid 2 baris (defaultnya tinggi 58px)
	$InventoryHUD/Panel.offset_top = -132.0
	$InventoryHUD/Panel.offset_bottom = -6.0
	_slot_style = StyleBoxFlat.new()
	_slot_style.bg_color = Color(0.09, 0.09, 0.1, 0.55)
	_slot_style.set_corner_radius_all(6)
	_slot_style.set_border_width_all(2)
	_slot_style.border_color = Color(0.9, 0.85, 0.6, 0.7)
	inventory.inventory_changed.connect(_on_inventory_changed)
	_on_inventory_changed(inventory.organic_count, inventory.anorganic_count, inventory.capacity)
	_build_coin_hud()


## HUD inventory: tampilin isi ransel sebagai GAMBAR sampah (bukan label
## organik/anorganik) — di mesin pilah player-lah yang belajar memilah.
func _on_inventory_changed(_organic: int, _anorganic: int, _capacity: int) -> void:
	if not is_instance_valid(_inv_vbox):
		return
	for c in _inv_vbox.get_children():
		if c.name != "Title":
			c.queue_free()

	_inv_vbox.get_node("Title").text = "RANGSEL  %d/%d" % [inventory.total_count(), inventory.capacity]

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	var kinds := inventory.stocks.keys()
	for i in inventory.capacity:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(40, 40)
		slot.add_theme_stylebox_override("panel", _slot_style)
		if i < kinds.size():
			var kind: String = kinds[i]
			var icon := TextureRect.new()
			icon.name = "icon"
			icon.texture = GameData.ITEM_TEXTURES.get(kind)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.custom_minimum_size = Vector2(36, 36)
			slot.add_child(icon)
			var qty := Label.new()
			qty.text = "x%d" % inventory.stocks[kind]
			qty.add_theme_font_size_override("font_size", 12)
			qty.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			qty.position = Vector2(-30, -2)
			slot.add_child(qty)
		grid.add_child(slot)
	_inv_vbox.add_child(grid)


func _physics_process(_delta: float) -> void:
	var input_dir := _read_input()
	if input_dir != Vector2.ZERO:
		facing = input_dir.normalized()

	var target_speed := walk_speed
	if Input.is_physical_key_pressed(KEY_SHIFT):
		target_speed = run_speed

	velocity = input_dir * target_speed
	move_and_slide()
	_update_animation(input_dir)
	_update_occlusion()

	if debug_label:
		debug_label.text = "frame=%d\npos=%s\ninput=%s\nanim=%s" % [
			Engine.get_process_frames(),
			position.round(),
			Vector2i(input_dir),
			anim.animation,
		]


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
##    CoinHUD/Margin  -> geser utk posisi panil & ukuran kotak (offset)
##    CoinHUD/Margin/BG  -> gambar latar kotak
##    CoinHUD/Margin/HBox/Icon  -> ikon koin
##    CoinHUD/Margin/HBox/CoinLabel  -> angka koin
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
		area.start_collect(self)


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
		# Hanya objek yang "di depan" player (pivot lebih bawah di layar).
		if body.global_position.y < global_position.y - 8.0:
			continue
		var sprite := _find_visual(body)
		if sprite == null:
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
	var size := texture.get_size() * sprite.scale
	return Rect2(sprite.global_position - size / 2.0, size)
