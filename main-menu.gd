extends Control

const BOUNCE := 1.15
var _tweens: Dictionary = {}
var _base_scales: Dictionary = {}

var _slot_picker: Control = null

func _ready() -> void:
	for button in [get_node("Button"), get_node("Button2"), get_node("Button3"), get_node("Button4")]:
		button.pivot_offset = button.size / 2.0
		_base_scales[button] = button.scale
		button.mouse_entered.connect(_on_hover.bind(button))
		button.mouse_exited.connect(_on_unhover.bind(button))
	_slot_picker = get_node_or_null("LoadSlots")
	if _slot_picker:
		_slot_picker.visible = false

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

func _on_button_pressed() -> void:
	get_tree().change_scene_to_file("res://main.tscn")

## Tombol LOAD (Button2): buka picker slot.
func _on_button_2_pressed() -> void:
	if _slot_picker == null:
		return
	if _slot_picker.has_method("refresh"):
		_slot_picker.call("refresh")
	_slot_picker.visible = true

func _on_button_4_pressed() -> void:
	get_tree().quit() # Replace with function body.
