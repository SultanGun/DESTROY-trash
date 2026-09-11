extends Area2D
class_name Machine

## Mesin interaksi untuk mekanik setor-pilah-olah:
## E = Mesin Pilah  (buka UI uipilah, mindahin sampah player -> GameData.sorted)
## F = Mesin Olah   (buka UI uiolah, ngolah GameData.sorted -> Koin GameManager)
## UI yang muncul = scene visual (res://scenes/uipilah.tscn / uiolah.tscn).

enum Kind { PILAH, RECYCLE }

const PILAH_UI := preload("res://scenes/uipilah.tscn")
const OLAH_UI := preload("res://scenes/uiolah.tscn")

@export var kind: Kind = Kind.PILAH

var _player: CharacterBody2D = null
var _ui_open := false
var _ui: CanvasLayer = null

func _ready() -> void:
	add_to_group("machines")
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
		_close_ui()

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(_player):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and _ui_open:
			_close_ui()
			get_viewport().set_input_as_handled()
		elif not _ui_open:
			var open: bool = (kind == Kind.PILAH and event.keycode == KEY_E) \
				or (kind == Kind.RECYCLE and event.keycode == KEY_F)
			if open:
				_open_ui()
				get_viewport().set_input_as_handled()

func get_player() -> CharacterBody2D:
	return _player

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
	_set_inventory_visible(false)

func _close_ui() -> void:
	if not _ui_open:
		return
	_ui_open = false
	if is_instance_valid(_ui):
		_ui.visible = false
	_set_inventory_visible(true)

## Sembunyikan tombol & overlay inventory player selama UI mesin kebuka,
## biar layar fokus ke mesin.
func _set_inventory_visible(vis: bool) -> void:
	for p in get_tree().get_nodes_in_group("player"):
		if p.has_node("InventoryToggle"):
			p.get_node("InventoryToggle").visible = vis
		if p.has_node("InventoryUI"):
			p.get_node("InventoryUI").visible = vis

func _instantiate_ui() -> void:
	_ui = (PILAH_UI if kind == Kind.PILAH else OLAH_UI).instantiate()
	add_child(_ui)
	if _ui.has_signal("close_requested"):
		_ui.close_requested.connect(_close_ui)
	_ui.visible = false

## --- Prompt badge di atas mesin ---

var _prompt_label: Label = null

func _set_prompt_visible(vis: bool) -> void:
	if not vis:
		if _prompt_label:
			_prompt_label.visible = false
		return
	if not _prompt_label:
		_build_prompt()
	_prompt_label.text = "[E] Pilah" if kind == Kind.PILAH else "[F] Olah"
	_prompt_label.visible = true

func _build_prompt() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PromptLayer"
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(-60, -70)
	label.text = "[E] Pilah"
	add_theme_override(label)
	layer.add_child(label)
	_prompt_label = label

func add_theme_override(lbl: Label) -> void:
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	var f := lbl.get_theme_font("font")
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_constant_override("outline_size", 4)
