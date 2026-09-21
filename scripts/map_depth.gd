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


## Dasar sprite = dasar CollisionShape2D jika ada, fallback ke setengah tinggi texture.
static func foot_of(sprite: Sprite2D) -> float:
	var col_shape := _find_collision_shape(sprite)
	if col_shape:
		var shape_bottom := 0.0
		if col_shape.shape is RectangleShape2D:
			shape_bottom = (col_shape.shape as RectangleShape2D).size.y * 0.5 * col_shape.scale.y
		elif col_shape.shape is CircleShape2D:
			shape_bottom = (col_shape.shape as CircleShape2D).radius * col_shape.scale.y
		elif col_shape.shape is CapsuleShape2D:
			shape_bottom = (col_shape.shape as CapsuleShape2D).height * 0.5 * col_shape.scale.y
		return col_shape.global_position.y + shape_bottom

	var half := 0.0
	var tex := sprite.texture
	if tex:
		half = tex.get_size().y * 0.5 * sprite.scale.y
	return sprite.global_position.y + half


static func _find_collision_shape(node: Node) -> CollisionShape2D:
	for child in node.get_children():
		if child is CollisionShape2D:
			return child as CollisionShape2D
		if child is StaticBody2D or child is Area2D:
			for subchild in child.get_children():
				if subchild is CollisionShape2D:
					return subchild as CollisionShape2D
	return null


func _snap_sprite(sprite: Sprite2D) -> void:
	sprite.z_index = int(foot_of(sprite))


## Visual mesin tidak di origin root-nya (sprite di koordinat absolut scene),
## jadi kunci depth diambil dari Sprite2D-nya lalu dipasang di root.
func _snap_machine(machine: Node) -> void:
	if machine is CanvasItem and machine.has_node("Sprite2D"):
		var sprite := (machine as Node).get_node("Sprite2D") as Sprite2D
		(machine as CanvasItem).z_index = int(foot_of(sprite))
