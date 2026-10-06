extends SceneTree

## Uji TrashSpawner, fokus ke regresi Map 2: sampah nongkrong di tengah jalan.
##
## Latar: spawn_area Map 2 dulu TEPAT menutupi pelat jalan (Rect2(40, 1080,
## 3176, 240)), dan gate tanah cuma kenal ColorRect - yang di Map 2 isinya
## jalan + trotoar, bukan rumput (rumputnya tile). Akibatnya semua sampah
## Map 2 spawn di tengah jalan.
##
## Kontrak baru:
##   1. Pelat jalan Map 2 (group "road") masuk cache larangan, bukan tanah.
##   2. Sampling acak Map 2 tidak pernah mengembalikan titik di jalan.
##   3. Spawner Map 2 tetap terisi penuh (tidak fail-closed total).
##   4. Map 1 tidak berubah: tanpa road rect, tanpa tile bounds, tetap terisi.
##
## Harness headless tanpa framework test project:
##   godot --headless --path <project> --script res://tests/test_trash_spawner.gd

const Map1Scene := preload("res://scenes/Map1_City.tscn")
const Map2Scene := preload("res://scenes/Map2.tscn")

## Pelat jalan Map 2 dalam koordinat lokal map (lihat Ground_14 di Map2.tscn).
const ROAD_Y_MIN := 1080.0
const ROAD_Y_MAX := 1338.0
const ROAD_X_MAX := 3215.0

const SAMPLES := 200

var _pass := 0
var _fail := 0
var _total_fail := 0
var _failures: Array[String] = []


func _initialize() -> void:
	seed(12345)
	await process_frame
	await _run("map2: jalan masuk cache larangan, bukan tanah", _test_road_cached_as_ban)
	await _run("map2: 200 sampel acak tidak ada yang di jalan", _test_random_never_on_road)
	await _run("map2: spawner tetap terisi penuh", _test_map2_fills_up)
	await _run("map1: tanpa jalan, tanpa tile bounds, tetap terisi", _test_map1_unchanged)
	await process_frame
	_report()
	quit(0 if _total_fail == 0 else 1)


func _run(label: String, fn: Callable) -> void:
	_fail = 0
	await fn.call()
	if _fail == 0:
		_pass += 1
		print("  LULUS  ", label)
	else:
		_total_fail += _fail
		_failures.append(label)


func _check(cond: bool, msg: String) -> bool:
	if cond:
		return true
	_fail += 1
	_failures.append(msg)
	print("    -> GAGAL: ", msg)
	return false


func _report() -> void:
	print("")
	print("===================================================")
	print("  lulus=%d  gagal=%d" % [_pass, _total_fail])
	if _total_fail > 0:
		print("  --- kegagalan ---")
		for f in _failures:
			print("  * ", f)
	print("===================================================")


## Map 2 standalone di origin: lokal == global. Setelah tiap test, map di-free
## supaya run berikutnya mulai dari spawner kosong.
func _load_map2() -> Node:
	var m: Node = Map2Scene.instantiate()
	root.add_child(m)
	for _i in 3:
		await physics_frame
	return m


func _load_map1() -> Node:
	var m: Node = Map1Scene.instantiate()
	root.add_child(m)
	for _i in 3:
		await physics_frame
	return m


func _spawner(m: Node) -> Node:
	return m.get_node_or_null("TrashSpawner")


## Titik (lokal map) jatuh di pelat jalan?
func _on_road(local_pos: Vector2) -> bool:
	return (local_pos.y >= ROAD_Y_MIN and local_pos.y <= ROAD_Y_MAX
		and local_pos.x >= 0.0 and local_pos.x <= ROAD_X_MAX)


func _test_road_cached_as_ban() -> void:
	var m := await _load_map2()
	var sp := _spawner(m)
	if not _check(sp != null, "Map2 harus punya TrashSpawner"):
		m.free()
		return
	var roads: Array = sp.get("_road_rects")
	_check(not roads.is_empty(),
		"Map2 harus punya road rect (Ground_14 groups=[road]), dapat %d" % roads.size())
	# Tengah jalan (lokal 1600,1209) harus ditolak walau di dalam bounds.
	var mid_road := Vector2(1600.0, 1209.0)
	_check(not bool(sp.call("_on_ground", mid_road)),
		"tengah jalan harus DITOLAK _on_ground")
	# Rumput di atas jalan harus diterima (physics gate urusan lain).
	var grass := Vector2(500.0, 500.0)
	_check(bool(sp.call("_on_ground", grass)),
		"rumput (500,500) harus DITERIMA _on_ground")
	m.free()
	await process_frame


func _test_random_never_on_road() -> void:
	var m := await _load_map2()
	var sp := _spawner(m)
	if not _check(sp != null, "Map2 harus punya TrashSpawner"):
		m.free()
		return
	var on_road := 0
	var failed := 0
	for _i in SAMPLES:
		var pos: Vector2 = sp.call("_find_free_position")
		if pos == Vector2.INF:
			failed += 1
			continue
		if _on_road(pos):
			on_road += 1
	_check(failed == 0,
		"sampling harus produktif, %d/%d gagal total" % [failed, SAMPLES])
	_check(on_road == 0,
		"%d/%d sampel jatuh DI JALAN - regresi!" % [on_road, SAMPLES])
	m.free()
	await process_frame


func _test_map2_fills_up() -> void:
	var m := await _load_map2()
	var sp := _spawner(m)
	if not _check(sp != null, "Map2 harus punya TrashSpawner"):
		m.free()
		return
	var want := int(sp.get("max_trash"))
	for _i in 30:
		await physics_frame
		if (sp.get("_trash") as Array).size() >= want:
			break
	var got: int = (sp.get("_trash") as Array).size()
	_check(got >= want,
		"spawner Map2 harus terisi %d, cuma dapat %d" % [want, got])
	# Dan yang sudah spawn pun tidak ada yang di jalan.
	var on_road := 0
	for t in (sp.get("_trash") as Array):
		if is_instance_valid(t) and _on_road((t as Node2D).position):
			on_road += 1
	_check(on_road == 0,
		"%d sampah hasil spawn ada DI JALAN" % on_road)
	m.free()
	await process_frame


func _test_map1_unchanged() -> void:
	var m := await _load_map1()
	var sp := _spawner(m)
	if not _check(sp != null, "Map1 harus punya TrashSpawner"):
		m.free()
		return
	# Map1 tidak punya group road dan tidak punya TileMap: gate lama yang jalan.
	var roads: Array = sp.get("_road_rects")
	_check(roads.is_empty(),
		"Map1 tidak boleh punya road rect, dapat %d" % roads.size())
	_check(not (sp.get("_map_bounds") as Rect2).has_area(),
		"Map1 tidak boleh punya tile bounds")
	_check(not (sp.get("_ground_rects") as Array).is_empty(),
		"Map1 harus tetap punya ColorRect tanah")
	var failed := 0
	for _i in 100:
		var pos: Vector2 = sp.call("_find_free_position")
		if pos == Vector2.INF:
			failed += 1
	_check(failed == 0,
		"sampling Map1 harus produktif, %d/100 gagal" % failed)
	var want := int(sp.get("max_trash"))
	for _i in 30:
		await physics_frame
		if (sp.get("_trash") as Array).size() >= want:
			break
	var got: int = (sp.get("_trash") as Array).size()
	_check(got >= want,
		"spawner Map1 harus terisi %d, cuma dapat %d" % [want, got])
	m.free()
	await process_frame
