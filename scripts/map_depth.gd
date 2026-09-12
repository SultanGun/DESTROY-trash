extends Node2D
## Snap depth global untuk semua prop statis di map.
##
## Masalah: Player (child Main) dan prop (child Map1_City/StaticBody2D) beda
## parent Y-sort, jadi Y-sort bawaan tidak bisa menyilangkan urutan gambar
## mereka — player selalu di atas atap rumah (lihat screenshot bug).
## Solusi: z_index = posisi kaki (dasar sprite). Player mengupdate z tiap
## frame di player.gd dengan kunci yang sama (global.y + FOOT_Y).
## Ground/dekor jalan tidak disentuh (tetap di z negatif).

const MACHINE_ROOTS := ["MachinePilah", "MachineRecycle"]
const PROPS_CONTAINER := "StaticBody2D"
const GROUND_NODE := "Ground"


func _ready() -> void:
	var ground := get_node_or_null(GROUND_NODE)
	if ground is CanvasItem:
		# Decor lantai tidak ikut sortir kaki; z negatifnya yang menang.
		(ground as Node2D).y_sort_enabled = false
	var props := get_node_or_null(PROPS_CONTAINER)
	if props:
		for child in props.get_children():
			if child is Sprite2D:
				_snap_sprite(child)
	for mname in MACHINE_ROOTS:
		var machine := get_node_or_null(mname)
		if machine:
			_snap_machine(machine)


## Dasar sprite = tengah + setengah tinggi texture (asumsi centered).
static func foot_of(sprite: Sprite2D) -> float:
	var half := 0.0
	var tex := sprite.texture
	if tex:
		half = tex.get_size().y * 0.5 * sprite.scale.y
	return sprite.global_position.y + half


func _snap_sprite(sprite: Sprite2D) -> void:
	sprite.z_index = int(foot_of(sprite))


## Visual mesin tidak di origin root-nya (sprite di koordinat absolut scene),
## jadi kunci depth diambil dari Sprite2D-nya lalu dipasang di root.
func _snap_machine(machine: Node) -> void:
	if machine is CanvasItem and machine.has_node("Sprite2D"):
		var sprite := (machine as Node).get_node("Sprite2D") as Sprite2D
		(machine as CanvasItem).z_index = int(foot_of(sprite))
