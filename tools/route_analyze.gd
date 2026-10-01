extends SceneTree
## Analisis tata letak -> rute patroli NPC pembuang sampah ilegal.
##
## Alat baca-saja: TIDAK mengubah peta, TIDAK menulis scene. Hanya memuat
## main.tscn, membaca collision prop yang sudah dibake per map, membuat
## grid bisa jalan, lalu A* antar-anchor.
##
## Konteks penting: game ini top-down TANPA gravitasi (lihat scripts/player.gd
## `velocity = input_dir * speed`). Jadi tidak ada "lantai" - yang menghalangi
## hanya collision prop (pohon, batu, rumah, pagar, tenda, tong, Chest, sumur,
## menara, kincir angin). Warna jalan/lantai cuma ColorRect dekoratif.
## Maka "jalan" di sini = GUIDE COST, bukan benturan fisika.
##
## Multi-map: setiap map punya `MapSpec` sendiri di `_build_specs()` yang
## menyebut node, batas grid global, dan lapisan cost. Analisis diulang per map
## dengan grid di-reset penuh, sehingga obstacle satu map tidak pernah bocor ke
## map lain.
##
## Pemakaian:
##   godot --headless --path <project> --script res://tools/route_analyze.gd
##   godot --headless --path <project> --script res://tools/route_analyze.gd -- dump:2
##        (argumen opsional: peta occupancy ASCII untuk authoring rute)

const CELL := 20.0

## Radius kapsul NPC (21.6 di ShopNPC.tscn) + margin aman.
const NPC_R := 28.0

## Pita tepi yang dikunci supaya NPC tidak keluar peta.
const BORDER := 30.0

## Sawah/kebun: bisa dilewati secara fisik, tapi pricey supaya rute
## memilih jalan tanah, bukan memlekati tanaman.
const FIELD_COST := 5.0
const FLOOR_COST := 1.6
const OPEN_COST := 2.6
const ROAD_COST := 1.0

## Biaya terendah per sel yang bisa dimasuki (lihat _apply_blocked_cost).
## Dipakai sebagai skala heuristic A* supaya tetap admissible.
const MIN_COST := ROAD_COST

const BRIDGE_HALF := 95.0

const DumperRoutes := preload("res://scripts/dumper_routes.gd")


## Deskriptor satu peta: everything yang<Map1> punya dan Map2 tidak.
class MapSpec extends RefCounted:
	var id: int = 0
	var nama: String = ""
	var node_name: String = ""
	## Batas grid di ruang GLOBAL. Peta digeser/disesuaikan main.tscn, jadi
	## batas ini TIDAK bisa diasumsikan sama antar map.
	var grid_global := Rect2()
	var barriers: Array = []  # Array[Rect2] lokal - pagar luar / strip tepi
	var keepout: Array = []  # Array[Rect2] lokal - padat visual, tanpa collider
	var river := Rect2()  # lokal; end == position berarti "tidak ada sungai"
	var bridges: Array = []  # Array[float] - x lokal penyeberangan
	var floors: Array = []  # Array[Rect2] lokal - semen/plaza permeable
	var fields: Array = []  # Array[Rect2] lokal - sawah/kebun (pricey)
	var roads: Array = []  # Array[Rect2] lokal - jalan/trotoar (murah)


var _w := 0
var _h := 0
var _blocked := PackedByteArray()
var _cost := PackedFloat32Array()
var _map: Node2D = null
var _spec: MapSpec = null

## Batas grid GLOBAL peta aktif (dari _spec.grid_global).
var _gx0 := 0.0
var _gy0 := 0.0
var _gx1 := 0.0
var _gy1 := 0.0

## Binary min-heap (f, cell) buat A*;-array append + sift, bukan sort tiap pop.
var _heap_f := PackedFloat32Array()
var _heap_v := PackedInt32Array()
var _heap_n := 0

## Total gate yang harus hijau di akhir analyze.
var _routes_ok := 0
var _routes_total := 0


# ------------------------------------------------------------------ specs
func _build_specs() -> Array:
	var out: Array = []

	# ------------------------------------------------------------- Map 1
	# Pagar luar kota disebar tiap 220px; setelah di-inflate NPC_R=28 semua
	# celahnya tertutup, tapi grid masih menyisakan 1 kolom sel di luar pagar.
	# Strip di bawah menutup celah itu supaya NPC tidak pernah keluar kota.
	var m1 := MapSpec.new()
	m1.id = 1
	m1.nama = "Map1_City"
	m1.node_name = "Map1_City"
	# Nilai ini hasil tuning Map1 (pos 11,-49 / scale 1,1.00788) dan sudah
	# divalidasi oleh 3 rute existing - jangan diubah tanpa re-run analyzer.
	m1.grid_global = Rect2(-40.0, -80.0, 3280.0, 4080.0)
	m1.barriers = [
		Rect2(-200, -200, 3400, 240),   # strip atas (pagar y=60)
		Rect2(-200, -200, 240, 4400),   # strip kiri (pagar x=60)
		Rect2(3100, -200, 300, 4400),  # strip kanan (pagar x=3140)
	]
	m1.keepout = [
		Rect2(2100, 1600, 760, 560),   # Platform pabrik
		Rect2(2110, 1720, 260, 200),   # MesinPemilah
		Rect2(2590, 1720, 260, 200),   # MesinPengolah
		Rect2(2380, 1840, 200, 60),    # Conveyor
	]
	m1.river = Rect2(0, 3560, 3200, 100)
	m1.bridges = [900.0, 1600.0, 2550.0]  # tools/map1_city.gd
	m1.floors = [
		Rect2(40, 40, 1390, 990),       # Apartemen permeable
		Rect2(1790, 40, 1390, 990),     # Park
		Rect2(60, 1380, 1360, 960),     # Market
		Rect2(1770, 1360, 1410, 1000),  # Pabrik
		Rect2(0, 2400, 3200, 1600),     # Desa / Nowhere
	]
	m1.fields = [
		Rect2(120, 2560, 1280, 880),    # sawah barat x120..1400
		Rect2(1800, 2560, 1280, 880),   # sawah timur x1800..3080
	]
	m1.roads = [
		Rect2(0, 1080, 3200, 240),      # Aspal mendatar
		Rect2(1480, 0, 240, 4000),      # Aspal tegak
		Rect2(0, 1030, 3200, 50),       # Trotoar atas
		Rect2(0, 1320, 3200, 50),       # Trotoar bawah
		Rect2(1430, 0, 50, 4000),       # Trotoar kiri
		Rect2(1720, 0, 50, 4000),       # Trotoar kanan
		Rect2(2440, 40, 60, 990),       # Jalur taman tegak
		Rect2(1790, 520, 1390, 60),     # Jalur taman mendatar
		Rect2(2405, 470, 150, 140),     # Plaza taman
		Rect2(560, 1760, 360, 200),     # Plaza pasar
		Rect2(120, 3420, 1280, 60),     # Jalan tanah barat
		Rect2(1800, 3420, 1280, 60),    # Jalan tanah timur
		Rect2(1960, 3260, 400, 220),    # Plaza desa
		Rect2(60, 1380, 1360, 32),      # Ring pasar atas
		Rect2(60, 2308, 1360, 32),      # Ring pasar bawah
		Rect2(60, 1380, 32, 960),       # Ring pasar kiri
		Rect2(1388, 1380, 32, 960),     # Ring pasar kanan
	]
	out.append(m1)

	# ------------------------------------------------------------- Map 2
	# Desa: jauh lebih sederhana dari Map1. Tidak ada sungai/jembatan, tidak
	# ada aspal tegak - hanya SATU jalan mendatar (Ground_14, y1080..1338)
	# dengan dua trotoar. Sisanya ladang TierMap + 38 prop.
	var m2 := MapSpec.new()
	m2.id = 2
	m2.nama = "Map2"
	m2.node_name = "Map2"
	# pos (3268,-49) scale (1,1); batas lokal dipetakan ke global lewat _lg().
	# Bawah dibuat 4200 karena walkable Map2 murdering y=4057 (melewati 4000).
	m2.grid_global = Rect2(3228.0, -129.0, 3280.0, 4200.0)
	# Tanpa pagar luar di Map2, jadi strip tepi dibuat eksplisit supaya NPC
	# tidak keluar area playable. Lebar 300 = cukup untuk menutup inflate 28.
	m2.barriers = [
		Rect2(-200, -200, 3600, 240),   # strip atas
		Rect2(-200, -200, 240, 4600),   # strip kiri
		Rect2(3260, -200, 340, 4600),   # strip kanan
		Rect2(-200, 4180, 3600, 240),   # strip bawah
	]
	m2.river = Rect2()  # tidak ada sungai
	m2.bridges = []
	m2.floors = [
		Rect2(0, 0, 3200, 1046),        # lawn utara
		Rect2(0, 1370, 3200, 2830),     # ladang /qg south
	]
	m2.fields = [
		Rect2(60, 1400, 3080, 2740),    # petak ladang Navigate
	]
	m2.roads = [
		Rect2(0, 1080, 3200, 240),      # Aspal mendatar (Ground_14)
		Rect2(0, 1046, 3200, 34),       # Trotoar atas (Ground_10)
		Rect2(6, 1333, 3209, 37),       # Trotoar bawah (Ground_10 #2)
	]
	out.append(m2)

	return out


func _activate(spec: MapSpec, map_node: Node2D) -> void:
	_spec = spec
	_map = map_node
	_gx0 = spec.grid_global.position.x
	_gy0 = spec.grid_global.position.y
	_gx1 = spec.grid_global.end.x
	_gy1 = spec.grid_global.end.y


# ---------------------------------------------------------------- definisi
func _local(p: Vector2) -> Vector2:
	# koordinat lokal peta aktif -> global dunia
	return _map.position + p * _map.scale


func _to_local(g: Vector2) -> Vector2:
	# global dunia -> koordinat lokal peta aktif
	return Vector2((g.x - _map.position.x) / _map.scale.x, (g.y - _map.position.y) / _map.scale.y)


func _lg(r: Rect2) -> Rect2:
	var a := _local(r.position)
	var b := _local(r.end)
	return Rect2(a, b - a)


func _routes(map_id: int) -> Array:
	## Data rute production (scripts/dumper_routes.gd) dibaca apa adanya, supaya
	## analyzer memvalidasi PERSIS angka yang dipakai runtime — bukan salinan
	## anchor kasar yang bisa menyimpang dari data final.
	## Titik di data production Aleppo koordinat GLOBAL (ruang Main), sedangkan grid
	## dan A* bekerja di ruang GLOBAL juga, tapi dump/anchor dilaporkan dalam ruang
	## lokal peta supaya angkanya bisa dibandingkan dengan angka penulisan.
	## `map` opsional: route lama tanpa key -> map 1 (backward compatible).
	var out := []
	for r in DumperRoutes.ALL:
		if int(r.get("map", 1)) != map_id:
			continue
		out.append({
			"nama": r["nama"],
			"pickup": int(r.get("pickup", -1)),
			"dump": int(r["dump"]),
			"titik": r["titik"],  # GLOBAL
		})
	return out


# -------------------------------------------------------------------- main
func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	var dump_map := -1
	var dump_px := 160
	var lanes_map := -1
	var lanes_step := 60
	var vlanes := false
	for a in argv:
		if a.begins_with("dump:"):
			dump_map = int(a.substr(5))
		elif a.begins_with("zoom:"):
			dump_px = maxi(CELL, int(a.substr(5)))
		elif a.begins_with("lanes:"):
			lanes_map = int(a.substr(6))
		elif a.begins_with("lanestep:"):
			lanes_step = maxi(CELL, int(a.substr(9)))
		elif a.begins_with("vlane:"):
			lanes_map = int(a.substr(6))
			vlanes = true

	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	await process_frame
	await process_frame

	var specs := _build_specs()
	for spec in specs:
		var map_node := main.get_node_or_null(spec.node_name) as Node2D
		if map_node == null:
			push_error("%s tidak ditemukan di main.tscn" % spec.node_name)
			continue
		_activate(spec, map_node)
		print("")
		print("################ PETA %d: %s ################" % [spec.id, spec.nama])
		print("global: pos=%s scale=%s  (NPC_R=%.0f CELL=%.0f)"
			% [map_node.position, map_node.scale, NPC_R, CELL])
		_build_grid()

		var comp := _components()
		var label: PackedInt32Array = comp["label"]
		var sizes: Dictionary = comp["size"]
		print("komponen terhubung: %d" % comp["count"])
		var big := []
		for k in sizes:
			big.append([k, sizes[k]])
		big.sort_custom(func(a, b): return a[1] > b[1])
		for e in big.slice(0, 4):
			print("  komponen #%d: %d sel" % [e[0], e[1]])

		if spec.id == dump_map:
			_dump_ascii(dump_px)
		if spec.id == lanes_map:
			if vlanes:
				_dump_vlanes(lanes_step)
			else:
				_dump_lanes(lanes_step)

		for route in _routes(spec.id):
			_report(route, label, sizes)

	main.queue_free()

	print("")
	print("################ RINGKASAN ################")
	print("peta dianalisis: %d | rute: %d | siap pakai: %d"
		% [specs.size(), _routes_total, _routes_ok])
	if _routes_ok == _routes_total and _routes_total > 0:
		print("SEMUA RUTE LOLOS")
	else:
		print(">>> ADA RUTE YANG BELUM SIAP")
	quit(0 if (_routes_ok == _routes_total and _routes_total > 0) else 1)


# ------------------------------------------------------------------- grid
func _build_grid() -> void:
	_w = int(ceil((_gx1 - _gx0) / CELL))
	_h = int(ceil((_gy1 - _gy0) / CELL))
	_blocked.resize(_w * _h)
	_cost.resize(_w * _h)
	for k in _w * _h:
		_cost[k] = OPEN_COST

	_border()
	for r in _spec.floors:
		_fill(_lg(r), FLOOR_COST)
	for r in _spec.fields:
		_fill(_lg(r), FIELD_COST)
	for r in _spec.roads:
		_fill(_lg(r), ROAD_COST)

	# Sungai: taban, kecuali di jembatan. river.end == position berarti
	# "tidak ada sungai" dan seluruh blok dilewati.
	var rr := _lg(_spec.river)
	if rr.size.x > 0.0 and rr.size.y > 0.0:
		for j in _h:
			var cy := _gy0 + (j + 0.5) * CELL
			if cy < rr.position.y or cy > rr.end.y:
				continue
			for i in _w:
				var cx := _gx0 + (i + 0.5) * CELL
				if cx < rr.position.x or cx > rr.end.x:
					continue
				var lx := _to_local(Vector2(cx, cy)).x
				var on_bridge := false
				for bx in _spec.bridges:
					if absf(lx - bx) <= BRIDGE_HALF:
						on_bridge = true
				if not on_bridge:
					_blocked[j * _w + i] = 1

	# Machinery padat tanpa collider
	for r in _spec.keepout:
		_mark(_lg(r))

	# Prop collisions yang sudah dibake - hanya di bawah peta aktif, supaya
	# Player / ShopNPC / peta lain tidak ikut jadi halangan.
	# _mark() sudah inflate sendiri; JANGAN grow dua kali di sini.
	var rects := _collect_rects()
	for r in rects:
		_mark(r)

	# Strip luar peta
	for r in _spec.barriers:
		_mark(_lg(r))

	_apply_blocked_cost()
	var blocked_n := _count_blocked()
	print("grid %dx%d sel (%.0fpx) | collider %s: %d | tersumbat: %d sel (%.1f%%)"
		% [_w, _h, CELL, _spec.nama, rects.size(), blocked_n,
			100.0 * float(blocked_n) / float(_w * _h)])


func _components() -> Dictionary:
	## Flood fill 4-arah dari tiap sel bebas -> label komponen terhubung.
	## Mengembalikan { "count": int, "label": PackedInt32Array, "size": Dictionary }
	## supaya rute yang salah bisa didiagnosis sebagai anchor di komponen berbeda.
	var label := PackedInt32Array()
	label.resize(_w * _h)
	for k in _w * _h:
		label[k] = -1
	var sizes := {}
	var next := 0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for seed in _w * _h:
		if _blocked[seed] == 1 or label[seed] != -1:
			continue
		var stack := [seed]
		label[seed] = next
		var n := 0
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			n += 1
			var ci := cur % _w
			var cj := int(cur / _w)
			for d in dirs:
				var nq := Vector2i(ci + d.x, cj + d.y)
				if not _in_bounds(nq):
					continue
				var nk := _idx(nq.x, nq.y)
				if _blocked[nk] == 1 or label[nk] != -1:
					continue
				label[nk] = next
				stack.append(nk)
		sizes[next] = n
		next += 1
	return {"count": next, "label": label, "size": sizes}


func _component_of(label: PackedInt32Array, p: Vector2) -> int:
	var c := _cell(_snap(p))
	if not _in_bounds(c):
		return -1
	return label[_idx(c.x, c.y)]


func _count_blocked() -> int:
	var n := 0
	for k in _w * _h:
		if _blocked[k] == 1:
			n += 1
	return n


func _apply_blocked_cost() -> void:
	for k in _w * _h:
		if _blocked[k] == 1:
			_cost[k] = 0.0


func _border() -> void:
	for j in _h:
		var cy := _gy0 + (j + 0.5) * CELL
		if cy < _gy0 + BORDER or cy > _gy1 - BORDER:
			for i in _w:
				_blocked[j * _w + i] = 1
			continue
		for i in _w:
			var cx := _gx0 + (i + 0.5) * CELL
			if cx < _gx0 + BORDER or cx > _gx1 - BORDER:
				_blocked[j * _w + i] = 1


func _mark(r: Rect2) -> void:
	var grown := r.grow(NPC_R)
	for j in _h:
		var cy := _gy0 + (j + 0.5) * CELL
		if cy < grown.position.y or cy > grown.end.y:
			continue
		for i in _w:
			var cx := _gx0 + (i + 0.5) * CELL
			if cx < grown.position.x or cx > grown.end.x:
				continue
			_blocked[j * _w + i] = 1


func _fill(r: Rect2, value: float) -> void:
	for j in _h:
		var cy := _gy0 + (j + 0.5) * CELL
		if cy < r.position.y or cy > r.end.y:
			continue
		for i in _w:
			var cx := _gx0 + (i + 0.5) * CELL
			if cx < r.position.x or cx > r.end.x:
				continue
			var k := j * _w + i
			if _blocked[k] == 1:
				continue
			_cost[k] = value


func _collect_rects() -> Array:
	var out: Array = []
	_walk(_map, out)
	return out


func _walk(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is CollisionShape2D and _under_static(c):
			var r := _shape_rect(c as CollisionShape2D)
			if r.size.x > 0.0 and r.size.y > 0.0:
				out.append(r)
		_walk(c, out)


func _under_static(n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p is StaticBody2D:
			return true
		p = p.get_parent()
	return false


func _shape_rect(cs: CollisionShape2D) -> Rect2:
	## Bounding box dunia dari satu CollisionShape2D. Collider hasil bake
	## tidak berotasi, jadi kotak = posisi global digeser setengah ukuran.
	##
	## PENTING: `size` di shape TIDAK ikut scale Node2D - scale ada di
	## transform node. `global_position` sudah menerapkan seluruh rantai
	## scale, tapi `size` belum. Jadi bentuk dikali skala global node di
	## sini. Mengabaikan ini persis bug "collider 2170px" yang pernah muncul.
	var sh := cs.shape
	if sh == null:
		return Rect2()
	var size := Vector2.ZERO
	if sh is RectangleShape2D:
		size = (sh as RectangleShape2D).size
	elif sh is CircleShape2D:
		var rr := (sh as CircleShape2D).radius
		size = Vector2(rr * 2.0, rr * 2.0)
	elif sh is CapsuleShape2D:
		var c := (sh as CapsuleShape2D)
		size = Vector2(c.radius * 2.0, c.height)
	else:
		return Rect2()
	var gs := _global_scale(cs)
	size *= gs
	var half := size * 0.5
	return Rect2(cs.global_position - half, half * 2.0)


func _global_scale(n: Node2D) -> Vector2:
	## Akumulasi scale sepanjang rantai parent, untuk memperbesar shape.size.
	var s := Vector2.ONE
	var p: Node = n
	while p != null:
		if p is Node2D:
			s *= (p as Node2D).scale
		p = p.get_parent()
	return s


# ------------------------------------------------------------- A* (heap)
func _idx(i: int, j: int) -> int:
	return j * _w + i


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor((p.x - _gx0) / CELL)), int(floor((p.y - _gy0) / CELL)))


func _cell_center(i: int, j: int) -> Vector2:
	return Vector2(_gx0 + (i + 0.5) * CELL, _gy0 + (j + 0.5) * CELL)


func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _w and c.y < _h


func _is_blocked(c: Vector2i) -> bool:
	return _blocked[_idx(c.x, c.y)] == 1


func _snap(p: Vector2) -> Vector2:
	## Titik terdekat yang tidak tersumbat (spiral kecil)
	# Cari sel bebas terdekat. Kalau anchor awal tersumbat, snapped != anchor
	# dan NPC berarti TIDAK sampai di anchor itu - itu harus dianggap gagal,
	# bukan diam-diam dipindah.
	var c := _cell(p)
	if _in_bounds(c) and not _is_blocked(c):
		return p
	for radius in range(1, 80):
		for dj in range(-radius, radius + 1):
			for di in range(-radius, radius + 1):
				if absi(di) != radius and absi(dj) != radius:
					continue
				var q := c + Vector2i(di, dj)
				if not _in_bounds(q):
					continue
				if _blocked[_idx(q.x, q.y)] == 0:
					return _cell_center(q.x, q.y)
	return p


func _heap_push(f: float, v: int) -> void:
	_heap_f.append(f)
	_heap_v.append(v)
	var i := _heap_n
	_heap_n += 1
	while i > 0:
		var p := (i - 1) >> 1
		if _heap_f[p] <= _heap_f[i]:
			break
		_heap_swap(p, i)
		i = p


func _heap_pop() -> int:
	var top := _heap_v[0]
	_heap_n -= 1
	_heap_f[0] = _heap_f[_heap_n]
	_heap_v[0] = _heap_v[_heap_n]
	_heap_f.resize(_heap_n)
	_heap_v.resize(_heap_n)
	var i := 0
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var s := i
		if l < _heap_n and _heap_f[l] < _heap_f[s]:
			s = l
		if r < _heap_n and _heap_f[r] < _heap_f[s]:
			s = r
		if s == i:
			break
		_heap_swap(s, i)
		i = s
	return top


func _heap_swap(a: int, b: int) -> void:
	var tf := _heap_f[a]
	_heap_f[a] = _heap_f[b]
	_heap_f[b] = tf
	var tv := _heap_v[a]
	_heap_v[a] = _heap_v[b]
	_heap_v[b] = tv


func _octile(from: Vector2i, to: Vector2i) -> float:
	var dx := absi(from.x - to.x)
	var dy := absi(from.y - to.y)
	return float(maxi(dx, dy)) + 0.41421 * float(mini(dx, dy))


func _astar(from: Vector2, to: Vector2) -> PackedVector2Array:
	## Selalu mengembalikan DAFTAR PUSAT SEL. Titik eksak_from/to tidak
	## disertakan, sehingga setiap leg berujung di sel yang sama dengan awal
	## leg berikutnya dan penggabungan circuit tidak pernah melompat.
	var out := PackedVector2Array()
	var a := _cell(_snap(from))
	var b := _cell(_snap(to))
	if not _in_bounds(a) or not _in_bounds(b):
		return out
	if _is_blocked(a) or _is_blocked(b):
		return out
	if a == b:
		out.append(_cell_center(b.x, b.y))
		return out

	var n := _w * _h
	var g := PackedFloat32Array()
	g.resize(n)
	for k in n:
		g[k] = INF
	var came := PackedInt32Array()
	came.resize(n)
	for k in n:
		came[k] = -1
	var closed := PackedByteArray()
	closed.resize(n)

	var goal := _idx(b.x, b.y)
	var start := _idx(a.x, a.y)
	g[start] = 0.0
	# WAJIB kosongkan heap, bukan cuma _heap_n = 0. Leg sebelumnya bisa
	# keluar lebih awal (goal ketemu) dengan sisa heap terisi; tanpa
	# clear(), elemen lama jadi root dan A* berikutnya salah total.
	_heap_f.clear()
	_heap_v.clear()
	_heap_n = 0
	_heap_push(_octile(a, b) * MIN_COST, start)

	var dirs := _dirs()
	while _heap_n > 0:
		var cur := _heap_pop()
		if closed[cur] == 1:
			continue
		closed[cur] = 1
		if cur == goal:
			return _rebuild(cur, came)
		var ci := cur % _w
		var cj := int(cur / _w)
		for d in dirs:
			var nq := Vector2i(ci + d.x, cj + d.y)
			if not _in_bounds(nq) or _is_blocked(nq):
				continue
			if d.x != 0 and d.y != 0:
				# sudut keras: dua tetangga ortogonal harus terbuka
				if _is_blocked(Vector2i(ci + d.x, cj)):
					continue
				if _is_blocked(Vector2i(ci, cj + d.y)):
					continue
			var nk := _idx(nq.x, nq.y)
			var step := 1.0 if (d.x == 0 or d.y == 0) else 1.41421
			var ng: float = g[cur] + step * _cost[nk]
			if ng < g[nk]:
				g[nk] = ng
				came[nk] = cur
				_heap_push(ng + _octile(nq, b) * MIN_COST, nk)
	return out


func _dirs() -> Array:
	return [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]


func _rebuild(end_i: int, came: PackedInt32Array) -> PackedVector2Array:
	var rev := PackedVector2Array()
	var k := end_i
	while k != -1:
		rev.append(_cell_center(k % _w, k / _w))
		k = came[k]
	rev.reverse()
	return _simplify(rev)


func _clear_line(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var steps := int(ceil(d.length() / (CELL * 0.5)))
	for s in range(steps + 1):
		var p := a.lerp(b, float(s) / float(maxi(steps, 1)))
		var c := _cell(p)
		if not _in_bounds(c) or _is_blocked(c):
			return false
	return true


func _simplify(path: PackedVector2Array, keep: Dictionary = {}) -> PackedVector2Array:
	## Greedy line-of-sight: majukan probe sejauh mungkin selama ruas dari
	## anchor masih bebas tabrakan. Saat tersumbat, titik SEBELUM blocker
	## jadikan anchor baru.
	##
	## `keep` berisi indeks yang WAJIB ada di hasil (titik anchor yang
	## disusun manusia, terutama titik DUMP). Tanpa itu, line-of-sight
	## akan memotong belokan dan menghapus titik dump - rute jadi terlihat
	## valid padahal NPC tidak pernah sampai ke sana.
	if path.size() <= 2:
		return path
	var out := PackedVector2Array()
	out.append(path[0])
	var last := path.size() - 1
	var i := 1
	while i < last:
		var base := out[out.size() - 1]
		# Titik wajib yang terjangkau langsung dari titik sebelumnya.
		if keep.has(i) and _clear_line(base, path[i]):
			out.append(path[i])
			i += 1
			continue
		# Greedy line-of-sight dari `base`: cari titik terjauh yang masih
		# bebas tabrakan. Probe berhenti begitu menusuk titik wajib, supaya
		# anchor (terutama DUMP) tidak pernah dilompati.
		var j := i
		var best := -1
		while j <= last:
			if not _clear_line(base, path[j]):
				break
			best = j
			if keep.has(j) or j == last:
				break
			j += 1
		if best < 0:
			# Tidak ada titik yang terjangkau dari `base` (hanya mungkin
			# kalau A* memakai diagonal). Emit satu titik agar maju; ruas
			# ini akan divalidasi ulang oleh pemeriksa tabrakan di _report.
			out.append(path[i])
			i += 1
		else:
			out.append(path[best])
			i = best + 1
	if out[out.size() - 1].distance_to(path[last]) > 0.01:
		out.append(path[last])
	return out


# ----------------------------------------------------------------- report
func _report(route: Dictionary, label: PackedInt32Array, sizes: Dictionary) -> void:
	var nama: String = route["nama"]
	var titik: Array = route["titik"]  # GLOBAL
	var dump_i: int = route["dump"]
	var pickup_i: int = route["pickup"]
	var n := titik.size()
	_routes_total += 1

	print("")
	print("=== %s (%d anchor, pickup=%s dump=#%d) ===" % [nama, n, str(pickup_i), dump_i])

	# Diagnosis per anchor: sel anchor snapped, komponennya, dan apakah
	# anchor itu bisa dicapai dari anchor start.
	for k in n:
		var g: Vector2 = titik[k]
		var c := _cell(_snap(g))
		var comp := _component_of(label, g)
		var free := _is_blocked(c) == false if _in_bounds(c) else false
		print("  anchor %2d %v global / %v lokal -> sel %s | komponen #%d (%d sel) | sel bebas=%s"
			% [k, g, _to_local(g), str(c), comp, int(sizes.get(comp, 0)), str(free)])

	var full := PackedVector2Array()
	# Indeks di `full` yang WAJIB dipertahankan saat simplification:
	# setiap anchor yang disusun manusia. Tanpa ini, titik DUMP (yang
	# bentuknya belokan spur: masuk lalu balik lagi) akan dipotong oleh
	# line-of-sight dan NPC tidak pernah sampai ke titik buangnya.
	var keep := {}
	var keep_pts: Array = []
	var legs_ok := 0
	var failed: Array = []
	for k in n:
		var a: Vector2 = titik[k]
		var b: Vector2 = titik[(k + 1) % n]
		var ca := _component_of(label, a)
		var cb := _component_of(label, b)
		if ca != cb:
			failed.append(k)
			print("  [%d] GAGAL (komponen beda #%d vs #%d): %v -> %v"
				% [k, ca, cb, titik[k], titik[(k + 1) % n]])
			continue
		var leg := _astar(a, b)
		if leg.size() < 2:
			failed.append(k)
			print("  [%d] GAGAL (astar): %v -> %v" % [k, titik[k], titik[(k + 1) % n]])
			continue
		legs_ok += 1
		# Leg pertama menyumbang seluruhnya; leg berikutnya melompati
		# titik awal karena sama dengan titik akhir leg sebelumnya.
		var skip := 0 if full.is_empty() else 1
		for idx in range(skip, leg.size()):
			full.append(leg[idx])
		keep[full.size() - 1] = true
		# Posisi anchor ikut dikumpulkan supaya _drop_stubs (yang bekerja
		# pada indeks hasil simplify) tetap tahu mana titik yang tak boleh
		# dibuang - indeks di `keep` sudah tidak berlaku setelah simplify.
		keep_pts.append(full[full.size() - 1])

	if full.size() < 2:
		print("  RUTE GAGAL total")
		return

	var path := _drop_stubs(_simplify(full, keep), keep_pts)
	var total := 0.0
	for i in range(path.size() - 1):
		total += path[i].distance_to(path[i + 1])

	# Validasi: tiap ruas harus bebas tabrakan
	var clean := true
	for i in range(path.size() - 1):
		if not _clear_line(path[i], path[i + 1]):
			print("  RUSAK ruas %d: %v -> %v" % [i, path[i], path[i + 1]])
			clean = false

	print("  leg ok %d/%d | panjang %.0fpx | waypoint %d | bebas tabrakan %s"
		% [legs_ok, n, total, path.size(), str(clean)])
	if not failed.is_empty():
		print("  leg gagal: %s" % str(failed))

	# DUMP WAJIB berada di sel bebas. Kalau tersumbat, NPC akan di-snap ke
	# sel lain dan tidak pernah menyentuh titik dump yang dimaksud.
	# DAN rute harus benar-benar MEMBENTUKI titik dump - sel bebas saja
	# tidak cukup kalau path cuma lewat di blok yang sama.
	var dump_global: Vector2 = titik[dump_i]
	var dump_cell := _cell(dump_global)
	var dump_free := _in_bounds(dump_cell) and _is_blocked(dump_cell) == false
	var dump_hits := _nearest_on_path(path, dump_global)
	print("  dump #%d %v global / %v lokal | sel=%s | BEBAS=%s | DICAPAI=%s (%.0fpx, wp #%d)"
		% [dump_i, dump_global, _to_local(dump_global), str(dump_cell), str(dump_free),
			str(dump_hits["hit"]), dump_hits["dist"], dump_hits["index"]])
	if not dump_free:
		# Kandidat pengganti: sel bebas terdekat yang sampai 4 sel dari anchor.
		var dc := _cell(dump_global)
		var found: Array = []
		for radius in range(1, 6):
			for dj in range(-radius, radius + 1):
				for di in range(-radius, radius + 1):
					if absi(di) != radius and absi(dj) != radius:
						continue
					var q := dc + Vector2i(di, dj)
					if not _in_bounds(q) or _is_blocked(q):
						continue
					var lc := _to_local(_cell_center(q.x, q.y))
					found.append([lc, q])
			if not found.is_empty():
				break
		for f in found.slice(0, 6):
			print("    kandidat sel bebas: %v lokal  sel=%s" % [f[0], str(f[1])])

	# PICKUP punya gate yang sama dengan DUMP: kalau tersumbat, NPC tidak
	# pernah mengambil sampah sehingga seluruh ekonomi rute itu bohong.
	var pickup_free := true
	var pickup_hits := {"hit": true, "dist": 0.0, "index": -1}
	if pickup_i >= 0 and pickup_i < n:
		var pick_global: Vector2 = titik[pickup_i]
		var pick_cell := _cell(pick_global)
		pickup_free = _in_bounds(pick_cell) and _is_blocked(pick_cell) == false
		pickup_hits = _nearest_on_path(path, pick_global)
		print("  pickup #%d %v global / %v lokal | sel=%s | BEBAS=%s | DICAPAI=%s (%.0fpx, wp #%d)"
			% [pickup_i, pick_global, _to_local(pick_global), str(pick_cell),
				str(pickup_free), str(pickup_hits["hit"]),
				pickup_hits["dist"], pickup_hits["index"]])

	var ready: bool = clean and failed.is_empty() and dump_free and bool(dump_hits["hit"]) \
		and pickup_free and bool(pickup_hits["hit"])
	if ready:
		_routes_ok += 1
	else:
		print("  >>> RUTE BELUM SIAP DIPAKAI")

	_diagnose_shape(path)

	print("  --- waypoint (global | lokal) ---")
	for i in path.size():
		var g: Vector2 = path[i]
		print("    Vector2(%d, %d),  # %d  lokal %.0f, %.0f"
			% [int(round(g.x)), int(round(g.y)), i,
				_to_local(g).x, _to_local(g).y])


func _drop_stubs(path: PackedVector2Array, keep_pts: Array = []) -> PackedVector2Array:
	## Buang waypoint yang jaraknya ke tetangga terlalu pendek sehingga NPC
	## terlihat mandek-mandek (belok 20px lalu balik). Sebuah titik hanya
	## dibuang kalau ruas PINTASAN dari sebelum ke sesudahnya tetap bebas
	## tabrakan - jadi proses ini tidak pernah membuat NPC tembus halangan.
	## Titik anchor (lihat keep_pts) dan titik closure tidak pernah dibuang,
	## kalau tidak NPC bisa berhenti sebelum sampai ke titik dump.
	var out := PackedVector2Array()
	var min_d := CELL * 1.2
	for i in path.size():
		if i == 0 or i == path.size() - 1:
			out.append(path[i])
			continue
		var cur := path[i]
		var guarded := false
		for kp in keep_pts:
			if cur.distance_to(kp) < 0.01:
				guarded = true
				break
		if guarded:
			out.append(cur)
			continue
		var prev := out[out.size() - 1]
		var nxt := path[i + 1]
		if prev.distance_to(cur) < min_d and cur.distance_to(nxt) < min_d and _clear_line(prev, nxt):
			continue
		out.append(cur)
	return out


func _nearest_on_path(path: PackedVector2Array, target: Vector2) -> Dictionary:
	## Titik terdekat di POLYLINE rute (bukan cuma di waypoint), supaya
	## "rute melewati dump" diukur akurat walau dump jatuh di tengah ruas.
	var best := INF
	var bi := -1
	for i in path.size():
		var d := Geometry2D.get_closest_point_to_segment(target, path[i], path[mini(i + 1, path.size() - 1)]).distance_to(target)
		if d < best:
			best = d
			bi = i
	return {"dist": best, "hit": best <= CELL * 1.5, "index": bi}


func _diagnose_shape(path: PackedVector2Array) -> void:
	## Ukur kualitas bentuk rute, bukan cuma kelolosan collision.
	## Dua symptom yang bikin NPC terlihat "aneh" saat runtime:
	##   - backtrack: ruas yang kembali ke arah yang baru saja dilalui
	##   - stub: ruas jauh lebih pendek dari radius sel, bikin NPC
	##     berhenti-mulai di satu tempat
	## Rute boleh-weaving di gang sempit, jadi angka ini informatif:
	## yang penting rasio backtrack TIDAK mendekati 1.
	var n := path.size()
	if n < 4:
		return
	var span := 0.0
	for i in range(n - 1):
		span += path[i].distance_to(path[i + 1])
	if span <= 0.0:
		print("  bentuk: panjang 0")
		return

	# Backtrack: untuk tiap ruas, cari ruas SEBELUMNYA yang arahnya hampir
	# sama dan jaraknya pendek -> berarti keluar-masuk area yang sama.
	var back := 0
	var worst := 0.0
	var worst_pair := [-1, -1]
	for i in range(n - 1):
		var v := path[i + 1] - path[i]
		if v.length() < 0.01:
			continue
		for j in range(maxi(0, i - 6), i):
			var u := path[j + 1] - path[j]
			if u.length() < 0.01:
				continue
			if v.normalized().dot(u.normalized()) < -0.86:
				back += 1
				var score := minf(v.length(), u.length())
				if score > worst:
					worst = score
					worst_pair = [i, j]

	# Stub: ruas lebih pendek dari 1.5 sel.
	var stubs: Array = []
	for i in range(n - 1):
		var d := path[i].distance_to(path[i + 1])
		if d < CELL * 1.5:
			stubs.append(i)

	# Titik yang muncul lebih dari sekali = NPC akan melewati titik sama
	# beberapa kali per putaran. Titik penutup (sama dengan titik 0) DILEWATI:
	# itu closure circuit yang disengaja, bukan retrace.
	var closed := n - 1
	while closed > 0 and path[closed].distance_to(path[0]) < 0.01:
		closed -= 1
	var seen := {}
	var dup := []
	for i in range(closed + 1):
		var key := "%d,%d" % [int(round(path[i].x)), int(round(path[i].y))]
		if seen.has(key):
			dup.append([seen[key], i])
		else:
			seen[key] = i

	print("  bentuk: backtrack %d ruas, stub %d, titik kembar %d (closure #%d diabaikan)"
		% [back, stubs.size(), dup.size(), closed])
	if worst > 0.0:
		print("  bentuk: backtrack terpanjang %.0fpx antara ruas %d dan %d"
			% [worst, worst_pair[0], worst_pair[1]])
	for s in stubs.slice(0, 6):
		print("  bentuk: stub ruas %d -> %d  %.0fpx"
			% [s, s + 1, path[s].distance_to(path[s + 1])])
	for d in dup.slice(0, 6):
		print("  bentuk: titik kembar #%d dan #%d" % [d[0], d[1]])
	# Gate hanya untuk hal yang benar-benar salah: stub (NPC mandek-mandek)
	# dan kembar di tengah rute. Backtrack diurnal di gang sempit itu wajar.
	if dup.size() > 0 or stubs.size() > 0:
		print("  bentuk: >> perlu rapikan anchor (kembar %d, stub %d)" % [dup.size(), stubs.size()])


# --------------------------------------------------------------- ascii map
func _dump_ascii(dump_px := 160) -> void:
	## Peta occupancy kasar untuk authoring anchor: '#'=tersumbat,
	## '.'=bisa jalan mahal (open/field), ','=lantai, '='=jalan.
	## Dipakai interaktif, bukan gate.
	var step := maxi(1, int(dump_px / CELL))
	print("")
	print("--- occupancy %s (1 char = %dpx) ---" % [_spec.nama, int(step * CELL)])
	var header := "     "
	for i in range(0, _w, step * 4):
		header += str(int(round((_gx0 + i * CELL) / 100.0)))
	print(header)
	for j in range(0, _h, step):
		var cy := _gy0 + (j + 0.5) * CELL
		var row := "%4d " % int(round(cy))
		for i in range(0, _w, step):
			var c := _cell_center(i, j)
			var cc := _cell(c)
			if not _in_bounds(cc) or _is_blocked(cc):
				row += "#"
			elif _cost[_idx(cc.x, cc.y)] <= ROAD_COST + 0.01:
				row += "="
			elif _cost[_idx(cc.x, cc.y)] <= FLOOR_COST + 0.01:
				row += ","
			elif _cost[_idx(cc.x, cc.y)] <= FIELD_COST + 0.01:
				row += "."
			else:
				row += " "
		print(row)


func _dump_lanes(step: int) -> void:
	## Daftar rentang x yang BEBAS per baris, supaya anchor ditulis dari angka
	## nyata dan bukan dari tebakan kolom karakter ascii.
	var row_step := maxi(1, int(step / CELL))
	print("")
	print("--- lane %s (baris tiap %dpx, rentang x global) ---" % [_spec.nama, row_step * CELL])
	print("   y_global | rentang x_global bebas")
	for j in range(0, _h, row_step):
		var cy := _gy0 + (j + 0.5) * CELL
		var runs := []
		var start_x := -1.0
		for i in range(_w + 1):
			var free_here := false
			if i < _w:
				var cc := _cell(_cell_center(i, j))
				free_here = _in_bounds(cc) and not _is_blocked(cc)
			if free_here and start_x < 0.0:
				start_x = _gx0 + i * CELL
			elif not free_here and start_x >= 0.0:
				runs.append([start_x, _gx0 + i * CELL])
				start_x = -1.0
		if runs.is_empty():
			continue
		var parts := PackedStringArray()
		for r in runs:
			if r[1] - r[0] < 60.0:
				continue
			parts.append("%d-%d" % [int(r[0]), int(r[1])])
		if parts.is_empty():
			continue
		print("%4d | %s" % [int(round(cy)), ", ".join(parts)])


func _dump_vlanes(step: int) -> void:
	## Versi vertikal dari _dump_lanes: daftar rentang y yang bebas untuk tiap
	## kolom x. Dipakai untuk menyambung antar-anchor secara vertikal.
	var col_step := maxi(1, int(step / CELL))
	print("")
	print("--- vlanes %s (kolom tiap %dpx, rentang y global) ---" % [_spec.nama, col_step * CELL])
	print(" x_global | rentang y_global bebas")
	for i in range(0, _w, col_step):
		var cx := _gx0 + (i + 0.5) * CELL
		var runs := []
		var start_y := -1.0
		for j in range(_h + 1):
			var free_here := false
			if j < _h:
				var cc := _cell(_cell_center(i, j))
				free_here = _in_bounds(cc) and not _is_blocked(cc)
			if free_here and start_y < 0.0:
				start_y = _gy0 + j * CELL
			elif not free_here and start_y >= 0.0:
				runs.append([start_y, _gy0 + j * CELL])
				start_y = -1.0
		if runs.is_empty():
			continue
		var parts := PackedStringArray()
		for r in runs:
			if r[1] - r[0] < 60.0:
				continue
			parts.append("%d-%d" % [int(r[0]), int(r[1])])
		if parts.is_empty():
			continue
		print("%4d | %s" % [int(round(cx)), ", ".join(parts)])
