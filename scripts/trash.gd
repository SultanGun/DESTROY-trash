extends Area2D
class_name Trash

## Dummy trash item buat test loop "ambil -> sortir -> olah".
## Logic di bawah ini gak perlu diubah sama sekali.

enum TrashType { ORGANIC, ANORGANIC }

const ORGANIC_TEXTURES := [
	preload("res://assets/sampah/koran.png"),
	preload("res://assets/sampah/tulang_ikan.png"),
	preload("res://assets/sampah_organic/eco_enzyme.png"),
	preload("res://assets/sampah_organic/kulit_kacang.png"),
	preload("res://assets/sampah_organic/pisang.png"),
	preload("res://assets/sampah_organic/ranting.png"),
	preload("res://assets/sampah_organic/roti.png"),
	preload("res://assets/sampah_organic/teh.png"),
]
const ANORGANIC_TEXTURES := [
	preload("res://assets/sampah/kemasan.png"),
	preload("res://assets/sampah/sedotan.png"),
]

## Id jenis per tipe (nyambung ke GameData.ITEM_NAMES / ITEM_PRICES).
const ORGANIC_KINDS := [
	"koran", "tulang_ikan", "eco_enzyme", "kulit_kacang",
	"pisang", "ranting", "roti", "teh",
]
const ANORGANIC_KINDS := ["kemasan", "sedotan"]

## Ukuran tampilan target (px) buat lebar/tinggi terpanjang sprite sampah,
## biar asset yang gede (organic sering 1000px+) tetap kelihatan seragam.
const DISPLAY_SIZE := 64.0

@export var trash_type: TrashType = TrashType.ORGANIC
@export var move_speed: float = 300.0

## Id jenis sampah instance ini (dipakai buat harga jual di GameData).
var kind: String = ""

var _target: Node2D = null
var _being_collected: bool = false

func _ready() -> void:
	add_to_group("trash")
	_update_depth()
	# Kasih visual beda per tipe: organic = bahan alami, anorganic = kemasan/plastik
	if has_node("Sprite2D"):
		var textures: Array = ORGANIC_TEXTURES if trash_type == TrashType.ORGANIC else ANORGANIC_TEXTURES
		var kinds: Array = ORGANIC_KINDS if trash_type == TrashType.ORGANIC else ANORGANIC_KINDS
		var i := randi() % textures.size()
		kind = kinds[i]
		var tex: Texture2D = textures[i]
		$Sprite2D.texture = tex
		var s := DISPLAY_SIZE / maxf(tex.get_width(), tex.get_height())
		$Sprite2D.scale = Vector2(s, s)

func _physics_process(delta: float) -> void:
	_update_depth()
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
	var ok := true
	if _target.has_method("collect_trash"):
		ok = _target.collect_trash(trash_type, kind)
	if ok:
		queue_free()
	else:
		# Inventory penuh: sampah gak ikut kecandu, balik ke lantai
		# biar bisa diambil lagi nanti (gak ilang).
		_being_collected = false
		_target = null
		set_deferred("monitoring", true)

func get_trash_type_name() -> String:
	return "Organic" if trash_type == TrashType.ORGANIC else "Anorganic"


## Sampah kecil di lantai: depth = posisi Y, update tiap frame karena
## sampah bisa terbang ke arah player saat dikoleksi.
func _update_depth() -> void:
	z_as_relative = false
	z_index = clampi(int(global_position.y), -4096, 4096)

func get_kind() -> String:
	return kind
