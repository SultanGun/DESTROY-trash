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

@onready var anim: AnimatedSprite2D = $Visual/Anim
@onready var debug_label: Label = $DebugHUD/Label
@onready var inventory: Inventory = $Inventory
@onready var organic_count_label: Label = $InventoryHUD/Panel/VBox/HBox/OrganicCount
@onready var anorganic_count_label: Label = $InventoryHUD/Panel/VBox/HBox/AnorganicCount


func _ready() -> void:
	_probe_shape = RectangleShape2D.new()
	_probe_shape.size = OCCLUSION_PROBE_SIZE
	inventory.inventory_changed.connect(_on_inventory_changed)
	_on_inventory_changed(inventory.organic_count, inventory.anorganic_count, inventory.capacity)


func _on_inventory_changed(organic: int, anorganic: int, _capacity: int) -> void:
	organic_count_label.text = str(organic)
	anorganic_count_label.text = str(anorganic)


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


func collect_trash(trash_type: int) -> void:
	inventory.add_trash(trash_type)
	print("Collected: ", trash_type, " | Total: ", inventory.total_count(), "/", inventory.capacity)


func _on_pickup_radius_area_entered(area: Area2D) -> void:
	if area.is_in_group("trash"):
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
