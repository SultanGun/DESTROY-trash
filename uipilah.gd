extends CanvasLayer

## UI Mesin Pilah (E): player memilah sampah SATU-PER-SATU.
## Panah kiri/kanan buat muter isi ransel, klik bin ORGANIK (kiri) / ANORGANIK
## (kanan). Salah = dikasih tau, tapi tetep masuk buffer sesuai jenis aslinya.
## Semua fungsi nempel DI tombol/gambar yang udah ada, bukan teks nampang.

signal close_requested

const CONTENT_SCALE := 0.62

var _machine: Node = null
var _index: int = 0
var _kinds: Array = []
var _status := ""

var _scaler: Node2D = null
var _item_view: TextureRect = null
var _item_name: Label = null
var _status_label: Label = null
var _esc_hint: Label = null

@onready var _item_container: Sprite2D = $Rectangle6
@onready var _close_button: Button = $Button

func _ready() -> void:
	_build_dim()
	_wrap_and_center()
	if _close_button:
		_close_button.text = ""
		_close_button.pressed.connect(func() -> void: close_requested.emit())
	_build_item_view()
	_build_arrows()
	_build_bins()
	_build_status()
	_build_esc_hint()
	_refresh()

func setup(machine: Node) -> void:
	_machine = machine
	_refresh()

func _process(_delta: float) -> void:
	if visible:
		_refresh()

## ---------- Aksi ----------

func _on_arrow(delta: int) -> void:
	_index = posmod(_index + delta, maxi(_kinds.size(), 1))
	_status = ""
	_refresh()

func _on_bin_pressed(zone: String) -> void:
	var inv := _player_inventory()
	if inv == null:
		return
	if inv.stocks.is_empty():
		_status = "Ransel kosong, cari sampah di sekitar dulu."
		_refresh()
		return
	if _kinds.is_empty():
		_refresh()
		return
	var kind: String = _kinds[_index]
	if inv.take_one(kind):
		var actual: String = "ORGANIK" if GameData.ITEM_TYPE.get(kind, Trash.TrashType.ORGANIC) == Trash.TrashType.ORGANIC else "ANORGANIK"
		GameData.add_sorted({kind: 1})
		if zone == actual:
			_status = "Benar! %s = %s. Masuk mesin olah." % [GameData.ITEM_NAMES.get(kind, kind), actual]
		else:
			_status = "Aduh, %s itu %s, bukan %s." % [GameData.ITEM_NAMES.get(kind, kind), actual, zone]
	_index = clampi(_index, 0, maxi(_kinds.size() - 1, 0))
	_refresh()

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

## Gambar sampah terpilih di dalam frame Rectangle6 (tengah), DI-GEDEIN.
func _build_item_view() -> void:
	if _item_container == null:
		return
	_item_view = TextureRect.new()
	_item_view.name = "ItemView"
	_item_view.position = Vector2(-265, -205)
	_item_view.size = Vector2(530, 410)
	_item_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_item_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_item_container.add_child(_item_view)

	# Nama item: di luar frame (anak Scaler) biar font-nya gak ikut scale kecil
	# Rectangle6; dipasang tepat di bawah frame tengah.
	_item_name = Label.new()
	_item_name.name = "ItemName"
	_item_name.position = Vector2(399, 420)
	_item_name.size = Vector2(320, 40)
	_item_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_item_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_item_name.add_theme_font_size_override("font_size", 26)
	_item_name.add_theme_color_override("font_color", Color(1, 0.96, 0.7))
	_item_name.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.02))
	_item_name.add_theme_constant_override("outline_size", 6)
	_ensure_scaler().add_child(_item_name)

func _build_arrows() -> void:
	_add_flat_button("ArrowR", Rect2(905, 280, 128, 128), func() -> void: _on_arrow(1))
	_add_flat_button("ArrowL", Rect2(94, 281, 128, 128), func() -> void: _on_arrow(-1))

func _build_bins() -> void:
	_add_flat_button("BinL", Rect2(53, 143, 228, 94), func() -> void: _on_bin_pressed("ORGANIK"))
	_add_flat_button("BinR", Rect2(865, 140, 200, 94), func() -> void: _on_bin_pressed("ANORGANIK"))

func _add_flat_button(bname: String, rect: Rect2, handler: Callable) -> void:
	var b := Button.new()
	b.name = bname
	b.position = rect.position
	b.size = rect.size
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(handler)
	_ensure_scaler().add_child(b)

func _build_status() -> void:
	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.position = Vector2(400, 486)
	_status_label.size = Vector2(318, 36)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", Color.WHITE)
	_status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_status_label.add_theme_constant_override("outline_size", 5)
	_ensure_scaler().add_child(_status_label)

func _build_esc_hint() -> void:
	_esc_hint = Label.new()
	_esc_hint.name = "EscHint"
	_esc_hint.text = "[ESC] Tutup"
	_esc_hint.position = Vector2(500, 560)
	_esc_hint.size = Vector2(160, 24)
	_esc_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_esc_hint.add_theme_font_size_override("font_size", 14)
	_esc_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_esc_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_esc_hint.add_theme_constant_override("outline_size", 4)
	_ensure_scaler().add_child(_esc_hint)

## ---------- Refresh ----------

func _refresh() -> void:
	var inv := _player_inventory()
	if inv == null:
		return
	_kinds = inv.stocks.keys()
	_kinds.sort_custom(func(a, b) -> bool:
		return inv.stocks[a] > inv.stocks[b]
	)
	if _kinds.is_empty():
		_index = 0
		if _item_view:
			_item_view.texture = null
		if _item_name:
			_item_name.text = ""
		if _status_label:
			_status_label.text = _status if not _status.is_empty() else "Ransel kosong, cari sampah dulu."
		return

	_index = clampi(_index, 0, _kinds.size() - 1)
	var kind: String = _kinds[_index]
	if _item_view:
		_item_view.texture = GameData.ITEM_TEXTURES.get(kind)
	if _item_name:
		_item_name.text = "%s  x%d" % [GameData.ITEM_NAMES.get(kind, kind), inv.stocks[kind]]
	if _status_label:
		_status_label.text = _status

func _player_inventory() -> Inventory:
	if not is_instance_valid(_machine):
		return null
	if not _machine.has_method("get_player"):
		return null
	var player: CharacterBody2D = _machine.get_player()
	if not is_instance_valid(player):
		return null
	return player.get_node_or_null("Inventory")
