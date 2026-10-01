extends Area2D
class_name ShopNPC

## NPC penjaga toko.
## Buka/tutup mengikuti jam TimeManager (default 08:00-16:00), interaksi E,
## dan upgrade kapasitas inventori lewat ShopUI.
## Struktur node mengikuti Machine.tscn: Area2D(root) -> CollisionShape2D(sensor)
## + visual + SolidBody StaticBody2D -> Block CollisionShape2D.

const SHOP_UI := preload("res://scenes/ShopUI.tscn")
const IDLE_FPS := 4.0

## Prompt "[E] Beli" — kotak selebar ini dipusatkan di atas NPC, dan jarak
## PROMPT_HEAD_GAP dari puncak sprite mengatur seberapa tinggi badge nempel.
const PROMPT_WIDTH := 160.0
const PROMPT_HEIGHT := 26.0
const PROMPT_HEAD_GAP := 18.0

@export var shop_open_hour: float = 6.0
@export var shop_close_hour: float = 16.0

@onready var _sensor_shape: CollisionShape2D = $CollisionShape2D
@onready var _solid_shape: CollisionShape2D = $SolidBody/Block
@onready var _sprite: AnimatedSprite2D = $AnimatedSprite

var _player: CharacterBody2D = null
var _ui_open := false
var _ui: CanvasLayer = null
var _prompt_label: Label = null
var _hours_open := true

func _ready() -> void:
	add_to_group("shops")
	_setup_idle_animation()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_set_prompt_visible(false)
	_hours_open = _is_shop_open()
	_apply_hours(_hours_open)

func _process(_delta: float) -> void:
	var open := _is_shop_open()
	if open == _hours_open:
		return
	_hours_open = open
	_apply_hours(open)

## --- Jam buka/tutup ---

func _is_shop_open() -> bool:
	var tm := get_tree().get_first_node_in_group("time_manager") as TimeManager
	if tm == null:
		return true
	var hour := tm.game_hour()
	return hour >= shop_open_hour and hour < shop_close_hour

## NPC "hilang" di luar jam: visual dimatikan, solid body dinonaktifkan
## (bisa dilewati), sensor dimatikan, prompt & UI ditutup.
func _apply_hours(open: bool) -> void:
	visible = open
	_sprite.visible = open
	_solid_shape.set_deferred("disabled", not open)
	_sensor_shape.set_deferred("disabled", not open)
	set_deferred("monitoring", open)
	set_deferred("monitorable", open)
	if not open:
		_player = null
		_set_prompt_visible(false)
		_close_ui()

## --- Idle animation ---

func _setup_idle_animation() -> void:
	var frames := SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_speed("idle", IDLE_FPS)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", preload("res://assets/shop_npc/1.png"))
	frames.add_frame("idle", preload("res://assets/shop_npc/2.png"))
	frames.add_frame("idle", preload("res://assets/shop_npc/3.png"))
	_sprite.sprite_frames = frames
	_sprite.play("idle")
	_snap_depth()

## Kunci depth = dasar sprite, sejajar machine.gd / player.gd / map_depth.gd
## supaya NPC gak ketimpa layer player.
func _snap_depth() -> void:
	z_as_relative = false
	z_index = clampi(int(_sprite.global_position.y + _sprite_half_height()), -4096, 4096)

## Setengah tinggi sprite dalam pixel world. Dipakai depth sort sama prompt,
## jadi ikut otomatis kalo skala NPC diubah.
func _sprite_half_height() -> float:
	if _sprite and _sprite.sprite_frames:
		var tex := _sprite.sprite_frames.get_frame_texture("idle", 0)
		if tex:
			return tex.get_size().y * 0.5 * _sprite.global_scale.y
	return 0.0

## --- Proximity ---

func _on_body_entered(body: Node2D) -> void:
	if not _hours_open:
		return
	if body.is_in_group("player"):
		_player = body
		_set_prompt_visible(true)

func _on_body_exited(body: Node2D) -> void:
	if body == _player:
		_player = null
		_set_prompt_visible(false)
		_close_ui()

func get_player() -> CharacterBody2D:
	return _player

## Dipakai mesin (dan UI lain) buat cek apakah ada interaksi yang lagi aktif,
## supaya E tidak membuka dua UI sekaligus di titik yang berdekatan.
func is_ui_open() -> bool:
	return _ui_open

func _other_interaction_active() -> bool:
	for node in get_tree().get_nodes_in_group("machines"):
		if node != self and node.has_method("is_ui_open") and node.is_ui_open():
			return true
	return false

## --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(_player):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and _ui_open:
			_close_ui()
			get_viewport().set_input_as_handled()
		elif not _ui_open and event.keycode == KEY_E and not _other_interaction_active():
			_open_ui()
			get_viewport().set_input_as_handled()

## --- UI ---

func _open_ui() -> void:
	if _ui_open:
		return
	_ui_open = true
	if not _ui or not is_instance_valid(_ui):
		_instantiate_ui()
	if _ui and _ui.has_method("setup"):
		_ui.setup(self)
	_ui.visible = true

func _close_ui() -> void:
	if not _ui_open:
		return
	_ui_open = false
	if is_instance_valid(_ui):
		_ui.visible = false

func _instantiate_ui() -> void:
	_ui = SHOP_UI.instantiate()
	add_child(_ui)
	if _ui.has_signal("close_requested"):
		_ui.close_requested.connect(_close_ui)
	_ui.visible = false

## --- Prompt badge di atas NPC (Node2D, jadi ikut gerak di world) ---

func _set_prompt_visible(vis: bool) -> void:
	if not vis:
		if _prompt_label:
			_prompt_label.visible = false
		return
	if not _prompt_label:
		_build_prompt()
	_prompt_label.text = "[E] Beli"
	_prompt_label.visible = true

func _build_prompt() -> void:
	var label := Label.new()
	label.name = "PromptLabel"
	label.z_index = 4096
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_constant_override("outline_size", 4)
	# Lebar tetap + align center supaya teksnya Centered di atas NPC, bukan
	# nempel ke kiri sprite. Set setelah font override karena Label meng-clamp
	# size ke minimum yang dihitung dari font.
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(PROMPT_WIDTH, PROMPT_HEIGHT)
	# Jarak dari puncak sprite dihitung runtime, jadi tetap nempel di atas
	# kepala walau skala NPC diganti.
	label.position = Vector2(
		-PROMPT_WIDTH * 0.5,
		-_sprite_half_height() - PROMPT_HEAD_GAP
	)
	label.visible = false
	add_child(label)
	_prompt_label = label
