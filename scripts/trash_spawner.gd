extends Node2D

## Nge-spawn sampah random di seluruh map, hindari area yang ketutup collision
## (bangunan/pohon/batu/fence/mesin). Kalau sampah ked amb il/di-recycle habis,
## otomatis respawn di tempat random lain — looping terus selama game jalan.

const TRASH_SCENE := preload("res://scenes/Trash.tscn")

## Berapa banyak percobaan cari slot kosong per frame sebelum menyerah.
const MAX_ATTEMPTS := 60

## Berapa banyak sampah yang harus ada di map setiap saat.
@export var max_trash: int = 20

## Area spawn (koordinat lokal map). Disesuaikan biar gak masuk sungai (y>3550)
## dan di dalem pagar/batas map.
@export var spawn_area: Rect2 = Rect2(90, 100, 5460, 3300)

## Jarak minimal antar sampah biar gak numpuk.
@export var min_gap := 90.0

## Jarak minimal dari player biar gak spawn di atas kepala player.
@export var player_clearance := 260.0

@export var spawn_mask := 1

## Margin aman dari tepi `spawn_area`, diterapkan saat runtime lewat grow()
## supaya rect hasil save tetap persis seperti yang desainer isi di inspector.
@export var border_margin := 40.0

var _trash: Array[Trash] = []

## Rect tanah hasil cache, sudah dikonversi ke koordinat GLOBAL. Diisi sekali
## di _ready() supaya cek per frame ga perlu crawl scene tree.
var _ground_rects: Array[Rect2] = []

## Rect larangan (jalan raya) hasil cache, koordinat GLOBAL. Diisi dari
## ColorRect yang masuk group "road" (mis. pelat jalan Map 2). Sampah tidak
## boleh spawn di tengah jalan, walau titiknya lolos gate lain.
var _road_rects: Array[Rect2] = []

## Bounding box gabungan TileMapLayer di bawah map root, koordinat GLOBAL.
## Map yang tanahnya digambar pakai tile (Map 2) tidak punya ColorRect rumput,
## jadi tanpa ini gate tanah buta dan spawn_area jadi satu-satunya penentu -
## yang dulu tepat menutupi jalan. Map tanpa TileMap (Map 1) tidak terpengaruh:
## rect ini tetap kosong dan gate ColorRect lama yang dipakai.
var _map_bounds := Rect2()

## Bounding box gabungan _ground_rects. Efisien buat early-out titik yang
## jelas-jelas di luar map sebelum scan semua rect.
var _ground_bounds := Rect2()

func _ready() -> void:
	refresh_ground_rects()

## Cache ulang rect tanah map.
##
## Map 1 punya node `Ground` yang anak-anaknya ColorRect, tapi Map 2 gak punya
## node dengan nama itu — karpet tanahnya ada sebagai ColorRect langsung di root
## map. Daripada menebak nama node, ambil SEMUA ColorRect di bawah map root:
## itu mencakup `Ground` Map 1 maupun layout Map 2.
func refresh_ground_rects() -> void:
	_ground_rects.clear()
	_road_rects.clear()
	_map_bounds = Rect2()
	var map_root := get_parent()
	if map_root == null:
		push_warning("TrashSpawner: gak ada parent map, ground gate dilewati.")
		return
	_collect_ground_rects(map_root)
	_collect_road_rects(map_root)
	_collect_tile_bounds(map_root)
	# Jalan boleh menutupi tanah (pelat jalan di atas tile rumput), tapi tidak
	# boleh dipakai spawn: tidak perlu dihapus dari _ground_rects karena veto
	# jalan di _on_ground selalu menang.
	if _ground_rects.is_empty() and not _map_bounds.has_area():
		# Fail-closed: tanpa data tanah, lebih baik gak spawn daripada nge-spawn
		# sampah di void. Panggil refresh_ground_rects() manual kalau map baru
		# sempat diganti transform-nya.
		push_warning("TrashSpawner: gak nemu ColorRect tanah, spawn diblokir total.")
		return
	if not _ground_rects.is_empty():
		_ground_bounds = _ground_rects[0]
		for rect in _ground_rects:
			_ground_bounds = _ground_bounds.merge(rect)

func _collect_ground_rects(node: Node) -> void:
	# Subtree jalan dilewati total: pelat jalan + marka yang jadi anaknya
	# bukan tanah dan tidak boleh masuk cache tanah.
	if node.is_in_group(&"road"):
		return
	if node is ColorRect:
		var rect := node as ColorRect
		_ground_rects.append(rect.get_global_rect())
	for child in node.get_children():
		_collect_ground_rects(child)


## Kumpulkan rect larangan dari ColorRect yang masuk group "road", termasuk
## seluruh subtree-nya (mis. marka jalan yang jadi anak pelat jalan).
func _collect_road_rects(node: Node) -> void:
	if node.is_in_group(&"road"):
		_collect_road_subtree(node)
		return
	for child in node.get_children():
		_collect_road_rects(child)


func _collect_road_subtree(node: Node) -> void:
	if node is ColorRect:
		_road_rects.append((node as ColorRect).get_global_rect())
	for child in node.get_children():
		_collect_road_subtree(child)


## Kumpulkan bounds TileMapLayer sebagai area tanah. Satu layer penuh
## (mis. Layer1 Map 2 yang mengisi seluruh map) cukup diwakili satu Rect2
## gabungan, jadi cek per titik tetap O(1) walau cell-nya puluhan ribu.
func _collect_tile_bounds(node: Node) -> void:
	if node is TileMapLayer:
		var layer := node as TileMapLayer
		var used: Rect2i = layer.get_used_rect()
		if used.has_area():
			var top_left: Vector2 = layer.to_global(layer.map_to_local(used.position))
			var bottom_right: Vector2 = layer.to_global(
				layer.map_to_local(used.end - Vector2i(1, 1)))
			var cell := Rect2(top_left, Vector2.ZERO)
			cell = cell.expand(bottom_right)
			# map_to_local mengembalikan TITIK TENGAH cell, jadi lebarkan
			# setengah tile ke semua sisi supaya tepi map ikut kehitung.
			var half := Vector2(layer.tile_set.tile_size) * 0.5
			cell = cell.grow_individual(half.x, half.y, half.x, half.y)
			if _map_bounds.has_area():
				_map_bounds = _map_bounds.merge(cell)
			else:
				_map_bounds = cell
	for child in node.get_children():
		_collect_tile_bounds(child)

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
	t.position = pos # pos lokal spawner == lokal map (spawner child langsung map root)
	add_child(t)
	_trash.append(t)

func _prune() -> void:
	var alive: Array[Trash] = []
	for t in _trash:
		if is_instance_valid(t):
			alive.append(t)
	_trash = alive

## Cari satu slot spawn yang lolos semua gate. Balikin posisi LOKAL spawner
## (dipakai langsung buat `Trash.position`), atau Vector2.INF kalau gagal.
func _find_free_position() -> Vector2:
	# Menjauh dari tepi spawn_area. Kalau margin kegedean sampai area habis,
	# jatuh ke rect mentah daripada langsung gagal.
	var area := spawn_area.grow(-border_margin)
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		area = spawn_area
	for _i in MAX_ATTEMPTS:
		var pos := Vector2(
			randf_range(area.position.x, area.end.x),
			randf_range(area.position.y, area.end.y)
		)
		# Semua gate di bawah bekerja di koordinat GLOBAL, karena:
		# - map di-instance di Main dengan position/scale sendiri,
		# - rect tanah di-cache dalam global space,
		# - physics query & posisi player juga global.
		var world_pos := to_global(pos)
		if not _on_ground(world_pos):
			continue
		if _blocked(world_pos):
			continue
		if not _clear_of_trash(world_pos):
			continue
		if not _clear_of_player(world_pos):
			continue
		return pos
	return Vector2.INF

## True kalau `global_point` boleh ditandai sampah.
##
## Urutannya: veto jalan dulu (menang atas segalanya), lalu area tanah.
## Map bertile (Map 2) memakai bounds tile; map ColorRect (Map 1) memakai
## rect tanah seperti sebelumnya. Fail-closed: tanpa data tanah, tolak.
func _on_ground(global_point: Vector2) -> bool:
	for road in _road_rects:
		if road.has_point(global_point):
			return false
	if _map_bounds.has_area():
		return _map_bounds.has_point(global_point)
	if _ground_rects.is_empty():
		return false
	if not _ground_bounds.has_point(global_point):
		return false
	for rect in _ground_rects:
		if rect.has_point(global_point):
			return true
	return false

## Gak boleh nyampah di dalem object (bangunan/pohon/batu/fence/mesin).
## Semua object map itu StaticBody2D di layer 1. `global_point` = koordinat global.
func _blocked(global_point: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = global_point
	query.collision_mask = spawn_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return not space.intersect_point(query, 16).is_empty()

## `global_point` = koordinat global; `_trash` isinya node global juga.
func _clear_of_trash(global_point: Vector2) -> bool:
	for t in _trash:
		if is_instance_valid(t) and t.global_position.distance_to(global_point) < min_gap:
			return false
	return true

## `global_point` = koordinat global, dan posisi player juga global.
func _clear_of_player(global_point: Vector2) -> bool:
	for player in get_tree().get_nodes_in_group("player"):
		if player.global_position.distance_to(global_point) < player_clearance:
			return false
	return true
