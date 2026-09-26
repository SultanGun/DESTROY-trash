extends CanvasLayer

var _target: Node2D = null
var _world_offset: Vector2 = Vector2(0, -90)
var _panel: PanelContainer = null
var _key_label: Label = null
var _text_label: Label = null
var _bob_t: float = 0.0
var _base_key: String = "[E]"
var _base_text: String = "Pilah"

func setup(target: Node2D, key: String, text: String, world_offset: Vector2) -> void:
	_target = target
	_base_key = key
	_base_text = text
	_world_offset = world_offset
	if _panel == null:
		_build()
	else:
		_refresh_text()

func _ready() -> void:
	layer = 20
	if _panel == null:
		_build()
	visible = false

func _build() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Badge"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.66)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	_panel.add_theme_stylebox_override("panel", sb)
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 6)
	var key_bg := PanelContainer.new()
	var ksb := StyleBoxFlat.new()
	ksb.bg_color = Color(0.22, 0.85, 0.38, 1)
	ksb.corner_radius_top_left = 6
	ksb.corner_radius_top_right = 6
	ksb.corner_radius_bottom_left = 6
	ksb.corner_radius_bottom_right = 6
	ksb.content_margin_left = 6
	ksb.content_margin_right = 6
	ksb.content_margin_top = 2
	ksb.content_margin_bottom = 2
	key_bg.add_theme_stylebox_override("panel", ksb)
	_key_label = Label.new()
	_key_label.add_theme_font_size_override("font_size", 15)
	_key_label.add_theme_color_override("font_color", Color.WHITE)
	_key_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_key_label.add_theme_constant_override("outline_size", 4)
	_key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_bg.add_child(_key_label)
	_text_label = Label.new()
	_text_label.add_theme_font_size_override("font_size", 14)
	_text_label.add_theme_color_override("font_color", Color.WHITE)
	_text_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_text_label.add_theme_constant_override("outline_size", 4)
	hbox.add_child(key_bg)
	hbox.add_child(_text_label)
	_panel.add_child(hbox)
	add_child(_panel)
	_refresh_text()

func _refresh_text() -> void:
	if _key_label:
		_key_label.text = _base_key
	if _text_label:
		_text_label.text = _base_text

func _process(delta: float) -> void:
	if not is_instance_valid(_target) or _panel == null:
		return
	if not visible:
		return
	_bob_t += delta * 2.2
	var bob := sin(_bob_t) * 4.0
	var world_pos: Vector2 = _target.global_position + _world_offset + Vector2(0, bob)
	var vp := get_viewport()
	if vp == null:
		return
	var ct: Transform2D = vp.get_canvas_transform()
	var screen_pos: Vector2 = ct * world_pos
	_panel.position = screen_pos - _panel.size * 0.5
