extends CanvasLayer

const BOUNCE := 1.15
var _tweens: Dictionary = {}
var _base_scales: Dictionary = {}

func _ready() -> void:
	for button in [get_node("Control/BTMM"), get_node("Control/RSM"), get_node("Control/STTNG"), get_node("Control/EXT")]:
		button.pivot_offset = button.size / 2.0
		_base_scales[button] = button.scale
		button.mouse_entered.connect(_on_hover.bind(button))
		button.mouse_exited.connect(_on_unhover.bind(button))

func _on_hover(button: Button) -> void:
	if _tweens.has(button):
		_tweens[button].kill()
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", _base_scales[button] * BOUNCE, 0.15)
	_tweens[button] = tween

func _on_unhover(button: Button) -> void:
	if _tweens.has(button):
		_tweens[button].kill()
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", _base_scales[button], 0.12)
	_tweens[button] = tween

# Called when the node enters the scene tree for the first time.
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_button_4_pressed() -> void:
	get_tree().quit() # Replace with function body.


func _on_texture_button_pressed() -> void:
	$Control.visible = !$Control.visible # Replace with function body.


func _on_btmm_pressed() -> void:
	get_tree().change_scene_to_file("res://main-menu.tscn") # Replace with function body.
