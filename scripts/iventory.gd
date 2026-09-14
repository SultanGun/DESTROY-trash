extends CanvasLayer
## Layar inventory layar penuh (iventory.tscn).
## Dibuka lewat tombol tengah layar; slot-slot visualnya (Sprite2D
## "Erasebg-transformed(10)1..18" di TextureRect/Rectangle7) diisi icon sampah
## + qty dari Inventory player.

signal close_requested

var _inventory: Inventory = null
var _slots: Array[Sprite2D] = []

func _ready() -> void:
	var close_btn := get_node_or_null("TextureRect/Button")
	if close_btn is Button:
		(close_btn as Button).pressed.connect(func() -> void: close_requested.emit())

## Panggil sekali dari Player pas scene ke-instantiate.
func setup(player: CharacterBody2D) -> void:
	if _inventory:
		return
	_inventory = player.inventory
	_build_slots()
	_inventory.inventory_changed.connect(_refresh)
	_refresh()

func _build_slots() -> void:
	_slots.clear()
	for i in 18:
		var slot := get_node_or_null(
			"TextureRect/Rectangle7/Erasebg-transformed(10)%d" % (i + 1)
		) as Sprite2D
		if slot == null:
			continue
		var icon := TextureRect.new()
		icon.name = "Icon"
		# Kotak slot 750px * scale 0.3 = ~225px; ikon full-isi kotak.
		icon.size = Vector2(750, 750)
		icon.position = Vector2(-375, -375)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)

		var qty := Label.new()
		qty.name = "Qty"
		qty.size = Vector2(160, 70)
		qty.position = Vector2(140, 250)
		qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		qty.add_theme_font_size_override("font_size", 50)
		qty.add_theme_color_override("font_color", Color(1, 0.92, 0.55, 1))
		qty.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.01, 1))
		qty.add_theme_constant_override("outline_size", 10)
		qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(qty)

		_slots.append(slot)

func refresh() -> void:
	_refresh()

func _refresh(_organic: int = 0, _anorganic: int = 0, _capacity: int = 0) -> void:
	if _inventory == null:
		return
	var kinds := _inventory.stocks.keys()
	for i in _slots.size():
		var icon := _slots[i].get_node_or_null("Icon") as TextureRect
		var qty := _slots[i].get_node_or_null("Qty") as Label
		if icon == null or qty == null:
			continue
		if i < kinds.size():
			var kind: String = kinds[i]
			icon.texture = GameData.ITEM_TEXTURES.get(kind)
			icon.visible = true
			qty.text = "x%d" % _inventory.stocks[kind]
			qty.visible = true
		else:
			icon.texture = null
			icon.visible = false
			qty.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		close_requested.emit()
		get_viewport().set_input_as_handled()