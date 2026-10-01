extends Node2D

## Stub toko untuk test_main_integration.gd.
##
## Satu-satunya yang penting: masuk group "shops" dan `is_ui_open()` true.
## Yang diuji adalah guard E di player.gd, bukan perilaku toko sungguhan.
## File terpisah karena GDScript class dalam (`class X:`) tidak bisa
## sekaligus jadi node yang di-add_child dengan script-nya sendiri.

func _ready() -> void:
	add_to_group("shops")


func is_ui_open() -> bool:
	return true
