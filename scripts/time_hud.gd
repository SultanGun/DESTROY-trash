extends CanvasLayer

## HUD jam/day ala Stardew: "HARI 1  09:30". Konek ke TimeManager via group.
## Warna teks ikut fase: kuning cerah (siang), oranye (senja), biru (malam).
## Semua node NODE ASLI di scenes/TimeHUD.tscn biar gampang digeser/diatur.

@onready var box: Control = $Box
@onready var day_label: Label = $Box/DayLabel
@onready var clock_label: Label = $Box/ClockLabel
@onready var icon: TextureRect = $Box/Icon
@onready var midnight_banner: Label = $MidnightBanner

var _time_manager: TimeManager = null

const COLORS := {
	TimeManager.Phase.DAY: Color(1.0, 0.92, 0.55, 1.0),
	TimeManager.Phase.SUNSET: Color(1.0, 0.62, 0.35, 1.0),
	TimeManager.Phase.NIGHT: Color(0.55, 0.65, 1.0, 1.0),
}

func _ready() -> void:
	_time_manager = get_tree().get_first_node_in_group("time_manager")
	if _time_manager == null:
		return
	_time_manager.time_updated.connect(_on_time_updated)
	_time_manager.phase_changed.connect(_on_phase_changed)
	_time_manager.midnight.connect(_on_midnight)
	_on_phase_changed(_time_manager.phase())
	_on_time_updated(_time_manager.current_time, _time_manager.day_length)

func _on_midnight() -> void:
	if midnight_banner == null:
		return
	midnight_banner.visible = true
	var tween := create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(midnight_banner, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func() -> void:
		midnight_banner.visible = false
		midnight_banner.modulate.a = 1.0
	)

func _on_time_updated(_current_time: float, _day_length: float) -> void:
	if _time_manager == null:
		return
	day_label.text = "HARI %d" % _time_manager.day
	clock_label.text = _time_manager.clock_text()

func _on_phase_changed(phase: int) -> void:
	if COLORS.has(phase):
		clock_label.add_theme_color_override("font_color", COLORS[phase])
		day_label.add_theme_color_override(
			"font_color",
			Color(1.0, 0.98, 0.9, 1.0) if phase == TimeManager.Phase.DAY else COLORS[phase]
		)