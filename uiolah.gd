extends CanvasLayer

## UI Mesin Olah (F): bahan olahan (GameData.sorted) -> Koin (GameManager).
## Alur A (MVP): langsung jadi koin, harga per jenis beda.
## Preview GAMBAR sampah tampil di satu frame; koin udah ada di HUD luar,
## jadi gak dibikin lagi di dalam UI. Fungsi nempel di tombol.

signal close_requested

const CONTENT_SCALE := 0.62
const MAX_ROWS := 5

var _machine: Node = null
var _selected: String = ""
var _index: int = 0
var _status := ""

var _scaler: Node2D = null
var _status_label: Label = null
var _esc_hint: Label = null

@onready var _olah_button: Button = $Button6
@onready var _tutup_button: Button = $Button7
@onready var _row_buttons: Array = [$Button, $Button2, $Button3, $Button4, $Button5]
@onready var _count_organic: Label = get_node_or_null("Group18(1)/Label")
@onready var _count_anorganic: Label = get_node_or_null("Group20/Label")
@onready var _frame: Sprite2D = get_node_or_null("FrameNoBgStretched(1)")
@onready var _frame_icon: TextureRect = _frame.get_node_or_null("TextureRect") if _frame else null
@onready var _preview: TextureRect = _frame.get_node_or_null("Preview") if _frame else null
@onready var _preview_value: Label = _frame.get_node_or_null("PreviewValue") if _frame else null

func _ready() -> void:
	_build_dim()
	_wrap_and_center()
	if _olah_button:
		_restyle(_olah_button)
		_olah_button.pressed.connect(_on_olah_pressed)
	if _tutup_button:
		# Exit: pakai art asli scene (Group 30, font bawaan game).
		_restyle(_tutup_button)
		_tutup_button.pressed.connect(func() -> void: close_requested.emit())
	for i in MAX_ROWS:
		_row_buttons[i].pressed.connect(_on_row_pressed.bind(i))
		_row_buttons[i].focus_mode = Control.FOCUS_NONE
	_build_preview()
	_build_status()
	_build_esc_hint()
	_refresh()

func setup(machine: Node) -> void:
	_machine = machine
	_refresh()

func _process(_delta: float) -> void:
	if visible:
		_refresh()

func _on_row_pressed(i: int) -> void:
	var kinds := _sorted_list()
	if i < kinds.size():
		_selected = kinds[i]
		_status = ""
	_refresh()

func _on_olah_pressed() -> void:
	if GameData.sorted.is_empty():
		_status = "Belum ada bahan olahan. Pilah di Mesin Pilah dulu."
		_refresh()
		return
	var coins := GameData.sell_sorted()
	get_node("/root/GameManager").add_coins(coins)
	if coins > 0:
		var am := get_node_or_null("/root/AudioManager")
		if am != null and am.has_method("play_coin"):
			am.play_coin()
	_selected = ""
	_index = 0
	_status = "+%d koin!" % coins
	_refresh()

## Button6 (OLah) & Button7 (KELUAR) pakai art ASLI scene (font bawaan game,
## udah ke-bake di gambar). Gak mengubah stylebox scene sama sekali;
## cuma teks label dikosongin + efek "pop" pas ditekan biar responsif.
func _restyle(btn: Button) -> void:
	btn.text = ""
	btn.pivot_offset = btn.size * 0.5
	btn.button_down.connect(_pop_bubble.bind(btn, true))
	btn.button_up.connect(_pop_bubble.bind(btn, false))

func _pop_bubble(btn: Button, pressed: bool) -> void:
	var tween := create_tween()
	tween.tween_property(btn, "scale", Vector2.ONE * (1.08 if pressed else 1.0), 0.1) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## ---------- Bangun UI ----------

func _build_dim() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

func _wrap_and_center() -> void:
	var s := _ensure_scaler()
	s.position = _center_offset()
	for c in get_children():
		if c == s or c.name == "Dim":
			continue
		remove_child(c)
		s.add_child(c)

func _ensure_scaler() -> Node2D:
	if _scaler == null:
		_scaler = Node2D.new()
		_scaler.name = "Scaler"
		add_child(_scaler)
		_scaler.scale = Vector2.ONE * CONTENT_SCALE
	return _scaler

func _center_offset() -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	return vp * 0.5 * (1.0 - CONTENT_SCALE)

func _build_preview() -> void:
	if _frame == null:
		return
	if _frame_icon:
		_frame_icon.visible = false
	var cb: CheckBox = _frame.get_node_or_null("TextureRect/CheckBox")
	if cb:
		cb.visible = false
	# Node "Preview" (gambar) & "PreviewValue" (teks emas) sekarang NODE ASLI di
	# scenes/uiolah.tscn -> bisa digeser-geser langsung di editor Godot.

func _build_status() -> void:
	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.position = Vector2(120, 545)
	_status_label.size = Vector2(560, 36)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 17)
	_status_label.add_theme_color_override("font_color", Color.WHITE)
	_status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_status_label.add_theme_constant_override("outline_size", 5)
	_ensure_scaler().add_child(_status_label)

func _build_esc_hint() -> void:
	_esc_hint = Label.new()
	_esc_hint.name = "EscHint"
	_esc_hint.text = "[ESC] Tutup"
	_esc_hint.position = Vector2(620, 575)
	_esc_hint.size = Vector2(160, 24)
	_esc_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_esc_hint.add_theme_font_size_override("font_size", 14)
	_esc_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_esc_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_esc_hint.add_theme_constant_override("outline_size", 4)
	_ensure_scaler().add_child(_esc_hint)

## ---------- Refresh ----------

func _sorted_list() -> Array:
	var kinds := GameData.sorted.keys()
	kinds.sort_custom(func(a, b) -> bool:
		return GameData.sorted[a] > GameData.sorted[b]
	)
	return kinds

func _refresh() -> void:
	if not is_instance_valid(_count_organic):
		return
	if _count_organic:
		_count_organic.text = str(GameData.sorted_organic)
	if _count_anorganic:
		_count_anorganic.text = str(GameData.sorted_anorganic)
	if _status_label:
		_status_label.text = _status

	_render_rows()
	_sync_row_selection()
	_render_preview()

## Highlit baris terpilih tanpa rebuild (biar node baris gak ke-churn).
func _sync_row_selection() -> void:
	var kinds := _sorted_list()
	for i in MAX_ROWS:
		var k: String = kinds[i] if i < kinds.size() else ""
		_row_buttons[i].set_pressed_no_signal(k != "" and k == _selected)

func _render_preview() -> void:
	if not _selected.is_empty() and GameData.sorted.has(_selected):
		_index = _sorted_list().find(_selected)
	if _selected.is_empty() or not GameData.sorted.has(_selected):
		var kinds := _sorted_list()
		_selected = kinds[_index] if not kinds.is_empty() else ""
	if _preview:
		_preview.texture = GameData.ITEM_TEXTURES.get(_selected)
	if _preview_value:
		if _selected.is_empty():
			_preview_value.text = "Pilih bahan olahan"
		else:
			_preview_value.text = "x%d (+%d)" % [
				GameData.sorted[_selected],
				GameData.sorted[_selected] * GameData.ITEM_PRICES.get(_selected, 1),
			]

## Baris = tombol pilih; teks nama & xN = Label ANAK node scene (RowName/RowQty)
## yang bisa digeser-geser langsung di editor Godot. Kode cuma isi text & visible.
var _last_rows: Array = []

func _render_rows() -> void:
	var kinds := _sorted_list()
	var sig: Array = []
	for i in MAX_ROWS:
		var k: String = kinds[i] if i < kinds.size() else ""
		sig.append("%s|%s" % [k, "e" if i >= kinds.size() else "d"])
	if sig == _last_rows:
		return
	_last_rows = sig
	for i in MAX_ROWS:
		var btn: Button = _row_buttons[i]
		var name_lbl: Label = btn.get_node_or_null("RowName")
		var qty_lbl: Label = btn.get_node_or_null("RowQty")
		if i < kinds.size():
			var k: String = kinds[i]
			btn.disabled = false
			if name_lbl:
				name_lbl.text = GameData.ITEM_NAMES.get(k, k)
				name_lbl.visible = true
			if qty_lbl:
				qty_lbl.text = "x%d" % GameData.sorted[k]
				qty_lbl.visible = true
		else:
			btn.text = ""
			btn.disabled = true
			if name_lbl:
				name_lbl.text = ""
				name_lbl.visible = false
			if qty_lbl:
				qty_lbl.visible = false
