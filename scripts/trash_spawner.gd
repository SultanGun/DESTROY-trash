extends Node2D

## Nge-spawn sampah random di seluruh map, hindari area yang ketutup collision
## (bangunan/pohon/batu/fence/mesin). Kalau sampah ked amb il/di-recycle habis,
## otomatis respawn di tempat random lain — looping terus selama game jalan.

const TRASH_SCENE := preload("res://scenes/Trash.tscn")

## Berapa banyak sampah yang harus ada di map setiap saat.
@export var max_trash: int = 20

## Area spawn (koordinat map). Disesuaikan biar gak masuk sungai (y>3550)
## dan di dalem pagar/batas map.
@export var spawn_area: Rect2 = Rect2(90, 100, 3020, 3300)

## Jarak minimal antar sampah biar gak numpuk.
@export var min_gap := 90.0

## Jarak minimal dari player biar gak spawn di atas kepala player.
@export var player_clearance := 260.0

@export var spawn_mask := 1

var _trash: Array[Trash] = []

func _physics_process(_delta: float) -> void:
	_prune()
	var guard := 0
	while _trash.size() < max_trash and guard < max_trash * 10:
		guard += 1
		var pos := _find_free_position()
		if pos == Vector2.INF:
			break
		_spawn_trash(pos)

func _spawn_trash(pos: Vector2) -> void:
	var t: Trash = TRASH_SCENE.instantiate() as Trash
	t.trash_type = Trash.TrashType.ORGANIC if randi() % 2 == 0 else Trash.TrashType.ANORGANIC
	t.position = pos
	add_child(t)
	_trash.append(t)

func _prune() -> void:
	var alive: Array[Trash] = []
	for t in _trash:
		if is_instance_valid(t):
			alive.append(t)
	_trash = alive

func _find_free_position() -> Vector2:
	for i in 60:
		var pos := Vector2(
			randf_range(spawn_area.position.x, spawn_area.end.x),
			randf_range(spawn_area.position.y, spawn_area.end.y)
		)
		if _blocked(pos):
			continue
		if not _clear_of_trash(pos):
			continue
		if not _clear_of_player(pos):
			continue
		return pos
	return Vector2.INF

## Gak boleh nyampah di dalem object (bangunan/pohon/batu/fence/mesin).
## Semua object map itu StaticBody2D di layer 1.
func _blocked(pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = pos
	query.collision_mask = spawn_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return not space.intersect_point(query, 16).is_empty()

func _clear_of_trash(pos: Vector2) -> bool:
	for t in _trash:
		if is_instance_valid(t) and t.global_position.distance_to(global_position + pos) < min_gap:
			return false
	return true

func _clear_of_player(pos: Vector2) -> bool:
	var world_pos := global_position + pos
	for player in get_tree().get_nodes_in_group("player"):
		if player.global_position.distance_to(world_pos) < player_clearance:
			return false
	return true