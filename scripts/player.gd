extends CharacterBody2D

@export var walk_speed: float = 240.0
@export var run_speed: float = 380.0

var facing: Vector2 = Vector2.DOWN

@onready var anim: AnimatedSprite2D = $Visual/Anim
@onready var debug_label: Label = $DebugHUD/Label
@onready var inventory: Inventory = $Inventory
@onready var organic_count_label: Label = $InventoryHUD/Panel/VBox/HBox/OrganicCount
@onready var anorganic_count_label: Label = $InventoryHUD/Panel/VBox/HBox/AnorganicCount


func _ready() -> void:
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
