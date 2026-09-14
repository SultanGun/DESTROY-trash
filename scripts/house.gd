extends Area2D

## Pintu rumah pemain (dipasang di depan pintu Map1_City_Perumahan#HouseA).
## Player deket -> muncul badge "[E] Tidur"; tekan E -> buka menu SAVE/LOAD.
## Posisi trigger di set dari editor (CollisionShape2D di depan pintu).

const SAVE_MENU := preload("res://scenes/save_menu.tscn")

var _player: CharacterBody2D = null
var _menu_open := false
var _menu: CanvasLayer = null

func _ready() -> void:
	add_to_group("houses")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_set_prompt_visible(false)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player = body
		_set_prompt_visible(true)

func _on_body_exited(body: Node2D) -> void:
	if body == _player:
		_player = null
		_set_prompt_visible(false)
		_close_menu()

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(_player):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and _menu_open:
			_close_menu()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_E and not _menu_open:
			_open_menu()
			get_viewport().set_input_as_handled()

## --- Menu SAVE/LOAD ---

func _open_menu() -> void:
	if _menu_open:
		return
	_menu_open = true
	if not _menu or not is_instance_valid(_menu):
		_menu = SAVE_MENU.instantiate()
		add_child(_menu)
		_menu.close_requested.connect(_close_menu)
	_menu.visible = true
	for p in get_tree().get_nodes_in_group("player"):
		if p.has_node("InventoryToggle"):
			p.get_node("InventoryToggle").visible = false
		if p.has_node("InventoryUI"):
			p.get_node("InventoryUI").visible = false

func _close_menu() -> void:
	if not _menu_open:
		return
	_menu_open = false
	if is_instance_valid(_menu):
		_menu.visible = false
	for p in get_tree().get_nodes_in_group("player"):
		if p.has_node("InventoryToggle"):
			p.get_node("InventoryToggle").visible = true
		if p.has_node("InventoryUI"):
			p.get_node("InventoryUI").visible = true

## --- Prompt badge di atas pintu ---

var _prompt_label: Label = null

func _set_prompt_visible(vis: bool) -> void:
	if not vis:
		if _prompt_label:
			_prompt_label.visible = false
		return
	if not _prompt_label:
		_build_prompt()
	_prompt_label.text = "[E] Tidur"
	_prompt_label.visible = true

func _build_prompt() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PromptLayer"
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(-55, -80)
	var f := label.get_theme_font("font")
	label.text = "[E] Tidur"
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_constant_override("outline_size", 4)
	layer.add_child(label)
	_prompt_label = label