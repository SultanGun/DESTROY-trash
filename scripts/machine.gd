extends Area2D
class_name Machine

## Mesin interaksi untuk mekanik setor-pilah-olah:
## E = Mesin Pilah  (buka UI uipilah, mindahin sampah player -> GameData.sorted)
## F = Mesin Olah   (buka UI uiolah, ngolah GameData.sorted -> Koin GameManager)
## UI yang muncul = scene visual (res://scenes/uipilah.tscn / uiolah.tscn).

enum Kind { PILAH, RECYCLE }

const PILAH_UI := preload("res://scenes/uipilah.tscn")
const OLAH_UI := preload("res://scenes/uiolah.tscn")
const PromptBadge := preload("res://scripts/prompt_badge.gd")

@export var kind: Kind = Kind.PILAH

var _player: CharacterBody2D = null
var _ui_open := false
var _ui: CanvasLayer = null

func _ready() -> void:
	add_to_group("machines")
	_snap_depth()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_set_prompt_visible(false)


## Kunci depth = dasar Sprite2D (bukan origin root yang jauh dari visual),
## sejajar dengan player.gd (global.y + FOOT_Y) dan map_depth.gd.
func _snap_depth() -> void:
	if has_node("Sprite2D"):
		var sprite := $Sprite2D as Sprite2D
		var half := 0.0
		if sprite.texture:
			half = sprite.texture.get_size().y * 0.5 * sprite.scale.y
		z_index = int(sprite.global_position.y + half)

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
	_set_prompt_visible(false)

func _close_ui() -> void:
	if not _ui_open:
		return
	_ui_open = false
	if is_instance_valid(_ui):
		_ui.visible = false
	_set_inventory_visible(true)
	if is_instance_valid(_player):
		_set_prompt_visible(true)

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

var _prompt: CanvasLayer = null

func _set_prompt_visible(vis: bool) -> void:
	if _prompt == null:
		_build_prompt()
	if vis and _ui_open:
		vis = false
	_prompt.visible = vis

func _build_prompt() -> void:
	_prompt = PromptBadge.new()
	_prompt.name = "PromptBadge"
	add_child(_prompt)
	var spr := get_node_or_null("Sprite2D")
	var target: Node2D = spr if spr is Node2D else self
	var key: String = "[E]" if kind == Kind.PILAH else "[F]"
	var txt: String = "Pilah" if kind == Kind.PILAH else "Olah"
	var off := Vector2(0, -95) if spr else Vector2(0, -55)
	_prompt.setup(target, key, txt, off)
	_prompt.visible = false
