extends CanvasLayer

## HUD jam/day ala Stardew: "HARI 1  09:30". Konek ke TimeManager via group,
## isi text & warna ikut fase siang/malam. Semua node NODE ASLI di
## scenes/TimeHUD.tscn biar gampang digeser/diatur di editor Godot.

@onready var box: Control = $Box
@onready var day_label: Label = $Box/DayLabel
@onready var clock_label: Label = $Box/ClockLabel
@onready var icon: TextureRect = $Box/Icon

var _time_manager: TimeManager = null

func _ready() -> void:
	_time_manager = get_tree().get_first_node_in_group("time_manager")
	if _time_manager == null:
		return
	_time_manager.time_updated.connect(_on_time_updated)
	_time_manager.phase_changed.connect(_on_phase_changed)
	_on_phase_changed(_time_manager.is_day)
	_on_time_updated(_time_manager.current_time, _time_manager.day_length)

func _on_time_updated(current_time: float, day_length: float) -> void:
	if _time_manager == null:
		return
	day_label.text = "HARI %d" % _time_manager.day
	clock_label.text = _time_manager.clock_text()

func _on_phase_changed(is_day: bool) -> void:
	var sun_color := Color(1.0, 0.92, 0.55, 1.0)
	var moon_color := Color(0.55, 0.65, 1.0, 1.0)
	clock_label.add_theme_color_override("font_color", sun_color if is_day else moon_color)