extends Node2D
## Snap depth global untuk semua prop statis di map.
##
## z_index = posisi kaki (dasar sprite / dasar collision).
## z_as_relative = false supaya z_index bersifat mutlak (global canvas),
## tidak terpengaruh nesting scene atau z_index parent (seperti Map2 yang ada di -49,
## atau prop di dalam TileMapLayer yang z-nya negatif).
## Player mengupdate z tiap frame di player.gd (global.y + FOOT_Y).

const GROUND_NODE := "Ground"


func _ready() -> void:
	var ground := get_node_or_null(GROUND_NODE)
	if ground is CanvasItem:
		(ground as CanvasItem).y_sort_enabled = false
	_snap_recursive(self)


func _snap_recursive(node: Node) -> void:
	if node != self:
		# Jangan sortir isi node Ground lantai
		if node.name == GROUND_NODE:
			if node is CanvasItem:
				(node as CanvasItem).y_sort_enabled = false
			return

		# Mesin: snap via root Area2D
		if node is Area2D and (node.name.begins_with("Machine") or node.is_in_group("machines")):
			_snap_machine(node)
			return

		# Prop Sprite2D:
		if node is Sprite2D:
			var n_low := node.name.to_lower()
			# Abaikan tile lantai / lapangan / jembatan jalan / background z negatif
			var is_ground := n_low.contains("ground") or n_low.contains("lapangan") or n_low.contains("bridge") or n_low.contains("stroke")
			if not is_ground and node.z_index > -10:
				_snap_sprite(node as Sprite2D)

	for child in node.get_children():
		_snap_recursive(child)


## Dasar sprite = titik terendah (max Y) dari shape tabrakan utama (lebar >= 50% max),
## fallback ke dasar texture. Semua dihitung dalam koordinat global canvas.
static func foot_of(sprite: Sprite2D) -> float:
	var shapes := _find_all_collision_nodes(sprite)
	if not shapes.is_empty():
		var max_width := 0.0
		for shape_node in shapes:
			var w := _shape_width_global(shape_node)
			if w > max_width:
				max_width = w

		# Cari dasar terendah dari shape utama (lebar >= 50% dari shape terlebar)
		# Menghindari tiang/sayap samping sempit (seperti di Gedung DPR) menaikkan z-index tembok tengah.
		var width_threshold := max_width * 0.5
		var max_bottom_y := -INF
		for shape_node in shapes:
			var w := _shape_width_global(shape_node)
			if w >= width_threshold:
				var bottom_y := _shape_bottom_global(shape_node)
				if bottom_y > max_bottom_y:
					max_bottom_y = bottom_y

		if max_bottom_y != -INF:
			return max_bottom_y

	# Fallback: dasar texture sprite dalam koordinat global
	var tex := sprite.texture
	if tex:
		var h := tex.get_size().y
		var local_bottom_y := (h * 0.5) if sprite.centered else h
		return sprite.to_global(Vector2(0.0, local_bottom_y + sprite.offset.y)).y

	return sprite.global_position.y


static func _shape_width_global(shape_node: Node2D) -> float:
	if shape_node is CollisionShape2D:
		var cs := shape_node as CollisionShape2D
		if cs.shape is RectangleShape2D:
			return (cs.shape as RectangleShape2D).size.x * cs.global_scale.x
		elif cs.shape is CircleShape2D:
			return (cs.shape as CircleShape2D).radius * 2.0 * cs.global_scale.x
		elif cs.shape is CapsuleShape2D:
			return (cs.shape as CapsuleShape2D).radius * 2.0 * cs.global_scale.x
	elif shape_node is CollisionPolygon2D:
		var poly := shape_node as CollisionPolygon2D
		var min_x := INF
		var max_x := -INF
		for pt in poly.polygon:
			var px := poly.to_global(pt).x
			if px < min_x: min_x = px
			if px > max_x: max_x = px
		if min_x != INF and max_x != -INF:
			return max_x - min_x
	return 0.0


static func _find_all_collision_nodes(node: Node) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for child in node.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			result.append(child as Node2D)
		elif child is StaticBody2D or child is Area2D:
			for subchild in child.get_children():
				if subchild is CollisionShape2D or subchild is CollisionPolygon2D:
					result.append(subchild as Node2D)
	return result


static func _shape_bottom_global(shape_node: Node2D) -> float:
	if shape_node is CollisionShape2D:
		var cs := shape_node as CollisionShape2D
		if cs.shape is RectangleShape2D:
			var rect := cs.shape as RectangleShape2D
			var hx := rect.size.x * 0.5
			var hy := rect.size.y * 0.5
			var c1 := cs.to_global(Vector2(-hx, hy)).y
			var c2 := cs.to_global(Vector2(hx, hy)).y
			var c3 := cs.to_global(Vector2(hx, -hy)).y
			var c4 := cs.to_global(Vector2(-hx, -hy)).y
			return maxf(maxf(c1, c2), maxf(c3, c4))
		elif cs.shape is CircleShape2D:
			var circle := cs.shape as CircleShape2D
			return cs.to_global(Vector2(0.0, circle.radius)).y
		elif cs.shape is CapsuleShape2D:
			var cap := cs.shape as CapsuleShape2D
			return cs.to_global(Vector2(0.0, cap.height * 0.5)).y
	elif shape_node is CollisionPolygon2D:
		var poly := shape_node as CollisionPolygon2D
		var max_y := -INF
		for pt in poly.polygon:
			var py := poly.to_global(pt).y
			if py > max_y:
				max_y = py
		if max_y != -INF:
			return max_y
	return shape_node.global_position.y


func _snap_sprite(sprite: Sprite2D) -> void:
	sprite.z_as_relative = false
	sprite.z_index = clampi(int(foot_of(sprite)), -4096, 4096)


## Visual mesin tidak di origin root-nya (sprite di koordinat absolut scene),
## jadi kunci depth diambil dari Sprite2D-nya lalu dipasang di root.
func _snap_machine(machine: Node) -> void:
	if machine is CanvasItem and machine.has_node("Sprite2D"):
		var sprite := (machine as Node).get_node("Sprite2D") as Sprite2D
		var half := 0.0
		if sprite.texture:
			half = sprite.texture.get_size().y * 0.5 * sprite.global_scale.y
		var canvas_item := machine as CanvasItem
		canvas_item.z_as_relative = false
		canvas_item.z_index = clampi(int(sprite.global_position.y + half), -4096, 4096)
