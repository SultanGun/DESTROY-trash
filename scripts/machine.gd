extends Area2D
class_name Machine

## Mesin interaksi untuk mekanik setor-pilah-recycle.
## E = Mesin Pilah (mindahin sampah player -> sorted di GameData)
## F = Mesin Recycle (ngolah sorted -> poin daur ulang)
## UI dibangun real-time via code (Godot 4.4.1 compatible).

enum Kind { PILAH, RECYCLE }

@export var kind: Kind = Kind.PILAH

var _player: CharacterBody2D = null
var _ui_open := false
var _ui: Control = null
var _stats_label: Label = null
var _action_label: Label = null

func _ready() -> void:
	add_to_group("machines")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_set_prompt_visible(false)

func _process(_delta: float) -> void:
	if _ui_open and _stats_label:
		_refresh_stats()

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

## --- UI ---

func _open_ui() -> void:
	if _ui_open:
		return
	_ui_open = true
	if not _ui:
		_build_ui()
	_refresh_stats()
	_ui.visible = true

func _close_ui() -> void:
	if not _ui_open:
		return
	_ui_open = false
	if _ui:
		_ui.visible = false

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MachineUI"
	add_child(layer)

	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_ui)
	_ui.visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_ui.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Mesin Pilah & Sortir" if kind == Kind.PILAH else "Mesin Daur Ulang"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_stats_label = Label.new()
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_stats_label)

	_action_label = Label.new()
	_action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_action_label)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	vbox.add_child(actions)

	actions.add_child(_make_button("Aksi Utama", _on_action_pressed))
	actions.add_child(_make_button("Tutup (Esc)", Callable(self, "_close_ui")))

func _make_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 44)
	btn.pressed.connect(callback)
	return btn

func _refresh_stats() -> void:
	if not is_instance_valid(_player):
		return
	var inv: Inventory = _player.get_node("Inventory")
	if kind == Kind.PILAH:
		_stats_label.text = "Inventory Player\nOrganic: %d | Anorganic: %d | Total: %d/%d\n\nSudah dipilah di mesin ini:\nOrganic: %d | Anorganic: %d" % [
			inv.organic_count, inv.anorganic_count, inv.total_count(), inv.capacity,
			GameData.sorted_organic, GameData.sorted_anorganic,
		]
		_action_label.text = "Aksi: pindahkan semua sampah ke temp penampung"
	else:
		_stats_label.text = "Terkumpul utk didaur ulang\nOrganic: %d | Anorganic: %d\n\nTotal sampah yg sudah didaur ulang: %d\nPoin: %d" % [
			GameData.sorted_organic, GameData.sorted_anorganic,
			GameData.recycled_total, GameData.recycle_points,
		]
		_action_label.text = "Aksi: proses semua sampah -> poin"

func _on_action_pressed() -> void:
	if not is_instance_valid(_player):
		return
	var inv: Inventory = _player.get_node("Inventory")
	if kind == Kind.PILAH:
		var o := inv.organic_count
		var a := inv.anorganic_count
		if o + a == 0:
			_action_label.text = "Tidak ada sampah utk dipilah. Ambil sampah dulu (E dibuka lewat pickup radius)."
			return
		inv.clear()
		GameData.add_sorted(o, a)
		_action_label.text = "Sampah dipilah & dipindah ke penampung. Lanjutkan ke Mesin Daur Ulang (F)."
	else:
		var processed := GameData.recycle_all()
		if processed == 0:
			_action_label.text = "Belum ada sampah terpilah. Pilah di mesin lain dulu (E)."
			return
		_action_label.text = "Daur ulang %d sampah -> %d poin." % [processed, GameData.recycle_points]

## --- Prompt badge di atas mesin ---

var _prompt_label: Label = null

func _set_prompt_visible(vis: bool) -> void:
	if not vis:
		if _prompt_label:
			_prompt_label.visible = false
		return
	if not _prompt_label:
		_build_prompt()
	_prompt_label.text = "[E] Pilah" if kind == Kind.PILAH else "[F] Recycle"
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