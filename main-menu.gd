extends CanvasLayer

const BOUNCE := 1.15

var _tweens: Dictionary = {}

func _ready() -> void:
	for button in [get_node("Button"), get_node("Button2"), get_node("Button3")]:
		button.pivot_offset = button.size / 2.0
		button.mouse_entered.connect(_on_hover.bind(button))
		button.mouse_exited.connect(_on_unhover.bind(button))

func _on_hover(button: Button) -> void:
	if _tweens.has(button):
		_tweens[button].kill()
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", button.scale * BOUNCE, 0.15)
	_tweens[button] = tween

func _on_unhover(button: Button) -> void:
	if _tweens.has(button):
		_tweens[button].kill()
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", button.scale / BOUNCE, 0.12)
	_tweens[button] = tween

func _on_button_pressed() -> void:
	get_tree().change_scene_to_file("res://node_2d.tscn")
