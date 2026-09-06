extends Area2D
class_name Trash

## Dummy trash item buat test loop "ambil -> sortir -> olah".
## Ganti ColorRect/Sprite2D placeholder ini dengan asset asli nanti —
## logic di bawah ini gak perlu diubah sama sekali.

enum TrashType { ORGANIC, ANORGANIC }

const ORGANIC_TEXTURES := [
	preload("res://assets/sampah/tulang_ikan.png"),
	preload("res://assets/sampah/koran.png"),
]
const ANORGANIC_TEXTURES := [
	preload("res://assets/sampah/kemasan.png"),
	preload("res://assets/sampah/sedotan.png"),
]

@export var trash_type: TrashType = TrashType.ORGANIC
@export var move_speed: float = 300.0

var _target: Node2D = null
var _being_collected: bool = false

func _ready() -> void:
	add_to_group("trash")
	# Kasih visual beda per tipe: organic = bahan alami, anorganic = kemasan/plastik
	if has_node("Sprite2D"):
		var textures: Array = ORGANIC_TEXTURES if trash_type == TrashType.ORGANIC else ANORGANIC_TEXTURES
		$Sprite2D.texture = textures[randi() % textures.size()]

func _physics_process(delta: float) -> void:
	if _being_collected and is_instance_valid(_target):
		global_position = global_position.move_toward(_target.global_position, move_speed * delta)
		if global_position.distance_to(_target.global_position) < 6.0:
			_finish_collect()

## Dipanggil dari Player waktu trash masuk ke pickup radius —
## trash mulai "kesedot" otomatis ke arah player.
func start_collect(target: Node2D) -> void:
	if _being_collected:
		return
	_being_collected = true
	_target = target
	set_deferred("monitoring", false) # biar gak ke-detect dobel selagi terbang

func _finish_collect() -> void:
	if not is_instance_valid(_target):
		queue_free()
		return
	if _target.has_method("collect_trash"):
		_target.collect_trash(trash_type)
	queue_free()

func get_trash_type_name() -> String:
	return "Organic" if trash_type == TrashType.ORGANIC else "Anorganic"
