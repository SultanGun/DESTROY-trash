extends Area2D
class_name KadesNPC

## NPC Kepala Desa.
## Berdiri di depan balai warga/desa (Map 1). Terlibat langsung di awal game
## untuk prolog/dialog perkenalan dengan Browli via Dialogue Manager.
## Setelah prolog selesai, player bisa berinteraksi (E) untuk dialog pengingat.

const PromptBadge := preload("res://scripts/prompt_badge.gd")

@export var kades_open_hour: float = 6.0
@export var kades_close_hour: float = 16.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _sensor_shape: CollisionShape2D = $CollisionShape2D
@onready var _solid_shape: CollisionShape2D = get_node_or_null("AnimatedSprite2D/Area2D/CollisionShape2D")

var _player: CharacterBody2D = null
var _prompt: CanvasLayer = null
var _is_talking := false
var _hours_open := true

func _ready() -> void:
	add_to_group("kades")
	add_to_group("npcs")
	_snap_depth()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_set_prompt_visible(false)
	_hours_open = _is_kades_open()
	_apply_hours(_hours_open)

func _process(_delta: float) -> void:
	var open := _is_kades_open()
	if open == _hours_open:
		return
	_hours_open = open
	_apply_hours(open)

func _is_kades_open() -> bool:
	var tm := get_tree().get_first_node_in_group("time_manager") as TimeManager
	if tm == null:
		return true
	var hour := tm.game_hour()
	return hour >= kades_open_hour and hour < kades_close_hour

func _apply_hours(open: bool) -> void:
	visible = open
	if _sprite:
		_sprite.visible = open
	if _solid_shape:
		_solid_shape.set_deferred("disabled", not open)
	if _sensor_shape:
		_sensor_shape.set_deferred("disabled", not open)
	set_deferred("monitoring", open)
	set_deferred("monitorable", open)
	if not open:
		_player = null
		_set_prompt_visible(false)

func _snap_depth() -> void:
	z_as_relative = false
	z_index = clampi(int(global_position.y + _sprite_half_height()), -4096, 4096)

func _sprite_half_height() -> float:
	if _sprite and _sprite.sprite_frames:
		var tex := _sprite.sprite_frames.get_frame_texture("idlekades", 0)
		if tex:
			return tex.get_size().y * 0.5 * global_scale.y
	return 30.0

func _game_data() -> Node:
	return get_node_or_null("/root/GameData")

func _is_prologue_done() -> bool:
	var gd := _game_data()
	return bool(gd.prologue_completed) if gd else false

func _on_body_entered(body: Node2D) -> void:
	if not _hours_open:
		return
	if body.is_in_group("player"):
		_player = body as CharacterBody2D
		# Hanya tampilkan prompt bicara jika prolog sudah selesai dan tidak sedang dialog
		if _is_prologue_done() and not _is_talking:
			_set_prompt_visible(true)

func _on_body_exited(body: Node2D) -> void:
	if body == _player:
		_player = null
		_set_prompt_visible(false)

func _unhandled_input(event: InputEvent) -> void:
	if not _hours_open:
		return
	if not is_instance_valid(_player):
		return
	if not _is_prologue_done() or _is_talking:
		return
	if _player.has_method("is_in_cutscene") and _player.call("is_in_cutscene"):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			_talk()
			get_viewport().set_input_as_handled()

func _talk() -> void:
	_is_talking = true
	_set_prompt_visible(false)
	if _player and _player.has_method("set_cutscene_mode"):
		_player.call("set_cutscene_mode", true)
	
	var dm = get_node_or_null("/root/DialogueManager")
	var dialogue_res = _load_dialogue()
	if dm and dialogue_res:
		dm.dialogue_ended.connect(_on_dialogue_ended, CONNECT_ONE_SHOT)
		dm.call("show_dialogue_balloon", dialogue_res, "reminder")
	else:
		_on_dialogue_ended(null)

func _on_dialogue_ended(_res) -> void:
	_is_talking = false
	if _player and _player.has_method("set_cutscene_mode"):
		_player.call("set_cutscene_mode", false)
	if is_instance_valid(_player):
		_set_prompt_visible(true)

func _load_dialogue() -> Resource:
	var path := "res://dialogues/prologue.dialogue"
	if ResourceLoader.exists(path):
		var res = load(path)
		if res:
			return res
	var dm = get_node_or_null("/root/DialogueManager")
	if dm and dm.has_method("create_resource_from_text"):
		var text := FileAccess.get_file_as_string(path)
		if not text.is_empty():
			return dm.call("create_resource_from_text", text)
	return null

func _set_prompt_visible(vis: bool) -> void:
	if _prompt == null:
		_build_prompt()
	if vis and _is_talking:
		vis = false
	_prompt.visible = vis

func _build_prompt() -> void:
	_prompt = PromptBadge.new()
	_prompt.name = "PromptBadge"
	add_child(_prompt)
	_prompt.setup(self, "[E]", "Bicara", Vector2(0, -78))
	_prompt.visible = false
