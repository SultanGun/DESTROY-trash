extends SceneTree


const MAP_W := 3200
const MAP_H := 4000
const OUT := "res://scenes/Map1_City.tscn"
const PROPS := "res://assets/sprites/props/"

var _l: PackedStringArray = PackedStringArray()
var _res: Array = []           # [id, path] urut
var _res_id: Dictionary = {}   # path -> id index

func _init() -> void:
	pass

func _initialize() -> void:
	_collect_resources()
	_build_header()
	_build_zones()
	_write_file()
	var ok := FileAccess.file_exists(OUT)
	print("Map1_City selesai: %d baris, resources=%d, tulisok=%s" % [_l.size(), _res.size(), str(ok)])
	quit()

func _res_of(path: String) -> String:
	if FileAccess.file_exists(path):
		if not _res_id.has(path):
			var idx := _res.size()
			_res.append([idx, path])
			_res_id[path] = idx
		return "\"" + str(_res_id[path]) + "_c\""
	return ""

func _res_line() -> String:
	return "ExtResource(" + str(_res_id.size()) + "_c)"

func _collect_resources() -> void:
	_res_of(PROPS + "Top-Down Simple Summer_Prop - House.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Tree Small.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Tree Medium.png")
	_res_of(PROPS + "Top-Down Simple Summer_prop - Tree Large.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Wooden Fence Horizontal.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Wooden Fence Vertical.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Bushes Small.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Bushes Medium.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Bushes Large.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Rock 01.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Rock 02.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Rock 03.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Rock 04.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Rock 05.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Well.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Tent.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Wooden Cart.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Wooden Barrel.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Treasure Chest.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Tree Stump Short.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Tree Stump Tall.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Campfire.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Blue Banner.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Red Banner.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Magic Stone Tower.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Castle Square.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Watchtower Short.png")
	_res_of(PROPS + "Top-Down Simple Summer_prop - Windmill.png")
	_res_of(PROPS + "Top-Down Simple Summer_Prop - Wooden Bridge Horizontal.png")

func _p(name: String, parent: String, type: String) -> void:
	_l.append("[node name=\"" + name + "\" type=\"" + type + "\" parent=\"" + parent + "\"]")

func _rectn(name: String, parent: String, tl: Vector2, br: Vector2, color: Color, z: int) -> void:
	_p(name, parent, "ColorRect")
	_l.append("offset_left = %d" % int(tl.x))
	_l.append("offset_top = %d" % int(tl.y))
	_l.append("offset_right = %d" % int(br.x))
	_l.append("offset_bottom = %d" % int(br.y))
	_l.append("color = Color(%f, %f, %f, 1)" % [color.r, color.g, color.b])
	_l.append("z_index = %d" % z)

func _spr(name: String, parent: String, path: String, pos: Vector2, z: int, scale_f: float = 1.0) -> void:
	if not FileAccess.file_exists(path):
		push_warning("SKIP texture hilang: " + path)
		return
	var rid := _res_of(path)
	_p(name, parent, "Sprite2D")
	_l.append("position = Vector2(%d, %d)" % [int(pos.x), int(pos.y)])
	if scale_f != 1.0:
		_l.append("scale = Vector2(%f, %f)" % [scale_f, scale_f])
	_l.append("texture = ExtResource(\"" + str(_res_id[path]) + "_c\")")

func _lbl(name: String, parent: String, tl: Vector2, br: Vector2, text: String, size: int) -> void:
	_p(name, parent, "Label")
	_l.append("offset_left = %d" % int(tl.x))
	_l.append("offset_top = %d" % int(tl.y))
	_l.append("offset_right = %d" % int(br.x))
	_l.append("offset_bottom = %d" % int(br.y))
	_l.append("text = \"%s\"" % text)
	_l.append("horizontal_alignment = 1")
	_l.append("vertical_alignment = 1")
	_l.append("theme_override_font_sizes/font_size = %d" % size)

func _build_header() -> void:
	var load_steps := _res.size() + 1
	var eh := "[gd_scene load_steps=%d format=3 uid=\"uid://dr6msqg3adjhk\"]" % load_steps
	_l.append(eh)
	_l.append("")
	for i in _res.size():
		_l.append("[ext_resource type=\"Texture2D\" path=\"%s\" id=\"%d_c\"]" % [_res[i][1], i])
	_l.append("")
	_l.append("[node name=\"Map1_City\" type=\"Node2D\"]")

func _build_zones() -> void:
	# palette
	var g_grass := Color(0.44, 0.66, 0.33)
	var g_grass2 := Color(0.40, 0.62, 0.30)
	var park_g := Color(0.37, 0.61, 0.29)
	var asphalt := Color(0.24, 0.24, 0.26)
	var sidewalk := Color(0.68, 0.68, 0.66)
	var curb := Color(0.17, 0.17, 0.19)
	var dash := Color(0.93, 0.93, 0.88)
	var zebra := Color(0.90, 0.90, 0.86)
	var path_c := Color(0.78, 0.73, 0.63)
	var plaza_c := Color(0.86, 0.81, 0.71)
	var market_c := Color(0.82, 0.75, 0.62)
	var market_ring := Color(0.76, 0.68, 0.55)
	var concrete := Color(0.56, 0.56, 0.53)
	var platform := Color(0.48, 0.48, 0.45)
	var sign_red := Color(0.78, 0.20, 0.18)
	var machine_a := Color(0.78, 0.48, 0.20)
	var machine_b := Color(0.25, 0.52, 0.85)
	var belt := Color(0.30, 0.30, 0.33)

	var tex_p := PROPS + "Top-Down Simple Summer_Prop - "
	var tex_p2 := PROPS + "Top-Down Simple Summer_prop - "

	# ---------- ZONA JALAN ----------
	_p("Jalan", "Map1_City", "Node2D")

	# trotoar (di bawah aspal biar putus di persimpangan)
	_rectn("SidewalkTop", "Map1_City/Jalan", Vector2(0, 1030), Vector2(MAP_W, 1080), sidewalk, -25)
	_rectn("SidewalkBottom", "Map1_City/Jalan", Vector2(0, 1320), Vector2(MAP_W, 1370), sidewalk, -25)
	_rectn("SidewalkLeft", "Map1_City/Jalan", Vector2(1430, 0), Vector2(1480, MAP_H), sidewalk, -25)
	_rectn("SidewalkRight", "Map1_City/Jalan", Vector2(1720, 0), Vector2(1770, MAP_H), sidewalk, -25)

	# aspal salib
	_rectn("AsphaltH", "Map1_City/Jalan", Vector2(0, 1080), Vector2(MAP_W, 1320), asphalt, -23)
	_rectn("AsphaltV", "Map1_City/Jalan", Vector2(1480, 0), Vector2(1720, MAP_H), asphalt, -23)

	# curb tepi aspal
	_rectn("CurbTop", "Map1_City/Jalan", Vector2(0, 1074), Vector2(MAP_W, 1080), curb, -22)
	_rectn("CurbBottom", "Map1_City/Jalan", Vector2(0, 1320), Vector2(MAP_W, 1326), curb, -22)
	_rectn("CurbLeft", "Map1_City/Jalan", Vector2(1480, 0), Vector2(1486, MAP_H), curb, -22)
	_rectn("CurbRight", "Map1_City/Jalan", Vector2(1720, 0), Vector2(1726, MAP_H), curb, -22)

	# marka putus-putus tengah jalan
	var i := 0
	var x := 16
	while x < MAP_W - 60:
		if not (x > 1380 and x < 1820):
			_rectn("MarkaH_%d" % i, "Map1_City/Jalan", Vector2(x, 1197), Vector2(x + 40, 1203), dash, -21)
			i += 1
		x += 100
	var j := 0
	var y := 16
	while y < MAP_H - 60:
		if not (y > 980 and y < 1420):
			_rectn("MarkaV_%d" % j, "Map1_City/Jalan", Vector2(1597, y), Vector2(1603, y + 40), dash, -21)
			j += 1
		y += 100

	# zebra crossing di 4 sisi persimpangan
	var zebra_groups := [
		["ZH1", "Map1_City/Jalan", Vector2(1180, 1090), true],
		["ZH2", "Map1_City/Jalan", Vector2(2040, 1090), true],
		["ZV1", "Map1_City/Jalan", Vector2(1486, 900), false],
		["ZV2", "Map1_City/Jalan", Vector2(1486, 1460), false],
	]
	for zg in zebra_groups:
		var zname: String = zg[0]
		var zparent: String = zg[1]
		var ztl: Vector2 = zg[2]
		var horizontal: bool = zg[3]
		for s in range(5):
			var zt: Vector2
			if horizontal:
				zt = ztl + Vector2(s * 20, 0)
				_rectn("%s_%d" % [zname, s], zparent, zt, zt + Vector2(14, 118), zebra, -21)
			else:
				zt = ztl + Vector2(0, s * 20)
				_rectn("%s_%d" % [zname, s], zparent, zt, zt + Vector2(118, 14), zebra, -21)

	# ---------- ZONA PERUMAHAN ----------
	_p("Perumahan", "Map1_City", "Node2D")
	_rectn("BlockA", "Map1_City/Perumahan", Vector2(40, 40), Vector2(695, 535), g_grass, -28)
	_rectn("BlockB", "Map1_City/Perumahan", Vector2(695, 40), Vector2(1430, 535), g_grass2, -28)
	_rectn("BlockC", "Map1_City/Perumahan", Vector2(40, 535), Vector2(695, 1030), g_grass2, -28)
	_rectn("BlockD", "Map1_City/Perumahan", Vector2(695, 535), Vector2(1430, 1030), g_grass, -28)

	# halaman depan rumah
	_spr("YardBushA1", "Map1_City/Perumahan", tex_p + "Bushes Small.png", Vector2(250, 880), 2)
	_spr("YardBushA2", "Map1_City/Perumahan", tex_p + "Bushes Small.png", Vector2(490, 880), 2)
	_spr("YardBushB1", "Map1_City/Perumahan", tex_p + "Bushes Small.png", Vector2(930, 880), 2)
	_spr("YardBushB2", "Map1_City/Perumahan", tex_p + "Bushes Small.png", Vector2(1170, 880), 2)
	_spr("YardRock1", "Map1_City/Perumahan", tex_p + "Rock 01.png", Vector2(240, 600), 2)
	_spr("YardRock2", "Map1_City/Perumahan", tex_p + "Rock 02.png", Vector2(1160, 620), 2)

	# lahan komunal antar rumah
	_spr("WellHousing", "Map1_City/Perumahan", tex_p + "Well.png", Vector2(710, 380), 4)
	_spr("WellBush1", "Map1_City/Perumahan", tex_p + "Bushes Medium.png", Vector2(560, 360), 2)
	_spr("WellBush2", "Map1_City/Perumahan", tex_p + "Bushes Medium.png", Vector2(860, 360), 2)
	_spr("WellRock", "Map1_City/Perumahan", tex_p + "Rock 03.png", Vector2(710, 520), 2)

	# sudut blok perumahan
	_spr("CornerBush1", "Map1_City/Perumahan", tex_p + "Bushes Medium.png", Vector2(170, 170), 2)
	_spr("CornerBush2", "Map1_City/Perumahan", tex_p + "Bushes Large.png", Vector2(1260, 170), 2)
	_spr("CornerStump", "Map1_City/Perumahan", tex_p + "Tree Stump Tall.png", Vector2(170, 900), 2)
	_spr("CornerRock", "Map1_City/Perumahan", tex_p + "Rock 04.png", Vector2(1260, 920), 2)

	# rumah digambar terakhir biar di atas rumput/rock/bushes halaman
	_spr("HouseA", "Map1_City/Perumahan", tex_p + "House.png", Vector2(370, 470), 0)
	_spr("HouseB", "Map1_City/Perumahan", tex_p + "House.png", Vector2(1050, 470), 0)
	_spr("FenceA", "Map1_City/Perumahan", tex_p + "Wooden Fence Horizontal.png", Vector2(370, 835), 0)
	_spr("FenceB", "Map1_City/Perumahan", tex_p + "Wooden Fence Horizontal.png", Vector2(1050, 835), 0)

	# ---------- ZONA TAMAN ----------
	_p("Taman", "Map1_City", "Node2D")
	_rectn("ParkFloor", "Map1_City/Taman", Vector2(1790, 40), Vector2(3180, 1030), park_g, -28)
	_rectn("ParkPathV", "Map1_City/Taman", Vector2(2440, 40), Vector2(2500, 1030), path_c, -18)
	_rectn("ParkPathH", "Map1_City/Taman", Vector2(1790, 520), Vector2(3180, 580), path_c, -18)
	_rectn("Plaza", "Map1_City/Taman", Vector2(2405, 470), Vector2(2555, 610), plaza_c, -16)

	_spr("Fountain", "Map1_City/Taman", tex_p + "Well.png", Vector2(2480, 540), 4)
	_spr("BenchStump1", "Map1_City/Taman", tex_p + "Tree Stump Tall.png", Vector2(2090, 610), 3)
	_spr("BenchStump2", "Map1_City/Taman", tex_p + "Tree Stump Tall.png", Vector2(2870, 610), 3)
	_spr("RockPark1", "Map1_City/Taman", tex_p + "Rock 01.png", Vector2(1850, 120), 2)
	_spr("RockPark2", "Map1_City/Taman", tex_p + "Rock 02.png", Vector2(3110, 120), 2)
	_spr("RockPark3", "Map1_City/Taman", tex_p + "Rock 03.png", Vector2(1850, 970), 2)
	_spr("RockPark4", "Map1_City/Taman", tex_p + "Rock 05.png", Vector2(3110, 970), 2)

	# pohon taman grid rapi (no-overlap)
	var park_rows := [
		[Vector2(1960, 150), Vector2(2220, 150), Vector2(2700, 150), Vector2(2960, 150)],
		[Vector2(2090, 380), Vector2(2350, 380), Vector2(2830, 380), Vector2(3050, 380)],
		[Vector2(1960, 700), Vector2(2220, 700), Vector2(2700, 700), Vector2(2960, 700)],
		[Vector2(2090, 930), Vector2(2350, 930), Vector2(2830, 930), Vector2(3050, 930)],
	]
	var ti := 0
	for row in park_rows:
		for pt in row:
			_spr("ParkTree_%d" % ti, "Map1_City/Taman", tex_p + "Tree Small.png", pt, 5)
			ti += 1
	_spr("ParkTreeBig1", "Map1_City/Taman", tex_p + "Tree Medium.png", Vector2(2470, 290), 5)
	_spr("ParkTreeBig2", "Map1_City/Taman", tex_p + "Tree Medium.png", Vector2(2470, 790), 5)

	# ---------- ZONA PASAR ----------
	_p("Pasar", "Map1_City", "Node2D")
	_rectn("MarketFloor", "Map1_City/Pasar", Vector2(60, 1380), Vector2(1420, 2340), market_c, -28)
	_rectn("MarketRing", "Map1_City/Pasar", Vector2(60, 1380), Vector2(1420, 1412), market_ring, -27)
	_rectn("MarketRingB", "Map1_City/Pasar", Vector2(60, 2308), Vector2(1420, 2340), market_ring, -27)
	_rectn("MarketRingL", "Map1_City/Pasar", Vector2(60, 1380), Vector2(92, 2340), market_ring, -27)
	_rectn("MarketRingR", "Map1_City/Pasar", Vector2(1388, 1380), Vector2(1420, 2340), market_ring, -27)
	_rectn("MarketPlaza", "Map1_City/Pasar", Vector2(560, 1760), Vector2(920, 1960), plaza_c, -16)

	_spr("TentA", "Map1_City/Pasar", tex_p + "Tent.png", Vector2(390, 1640), 4)
	_spr("TentB", "Map1_City/Pasar", tex_p + "Tent.png", Vector2(1090, 1640), 4)
	_spr("TentC", "Map1_City/Pasar", tex_p + "Tent.png", Vector2(390, 2080), 4)
	_spr("TentD", "Map1_City/Pasar", tex_p + "Tent.png", Vector2(1090, 2080), 4)
	_spr("Cart", "Map1_City/Pasar", tex_p + "Wooden Cart.png", Vector2(740, 1530), 4)
	_spr("WellPasar", "Map1_City/Pasar", tex_p + "Well.png", Vector2(740, 1880), 4)
	_spr("StumpSeat1", "Map1_City/Pasar", tex_p + "Tree Stump Tall.png", Vector2(560, 2000), 3)
	_spr("StumpSeat2", "Map1_City/Pasar", tex_p + "Tree Stump Tall.png", Vector2(920, 2000), 3)
	_spr("Chest", "Map1_City/Pasar", tex_p + "Treasure Chest.png", Vector2(740, 2140), 4)
	_spr("Campfire", "Map1_City/Pasar", tex_p + "Campfire.png", Vector2(220, 2200), 4)
	_spr("BannerBlue", "Map1_City/Pasar", tex_p + "Blue Banner.png", Vector2(1300, 1500), 4)
	_spr("BannerRed", "Map1_City/Pasar", tex_p + "Red Banner.png", Vector2(180, 1500), 4)

	var barrel_x := 260.0
	var bi := 0
	while barrel_x < 1200.0:
		_spr("Barrel_%d" % bi, "Map1_City/Pasar", tex_p + "Wooden Barrel.png", Vector2(barrel_x, 2240), 3)
		barrel_x += 200.0
		bi += 1

	# ---------- ZONA PENGOLAHAN ----------
	_p("Pengolahan", "Map1_City", "Node2D")
	_rectn("FactoryFloor", "Map1_City/Pengolahan", Vector2(1770, 1360), Vector2(3180, 2360), concrete, -28)
	_rectn("Platform", "Map1_City/Pengolahan", Vector2(2100, 1600), Vector2(2860, 2160), platform, -27)

	_rectn("MesinPemilah", "Map1_City/Pengolahan", Vector2(2110, 1720), Vector2(2370, 1920), machine_a, 0)
	_lbl("LabelPemilah", "Map1_City/Pengolahan/MesinPemilah", Vector2(0, 0), Vector2(260, 200), "PEMILAH", 16)
	_rectn("MesinPengolah", "Map1_City/Pengolahan", Vector2(2590, 1720), Vector2(2850, 1920), machine_b, 0)
	_lbl("LabelPengolah", "Map1_City/Pengolahan/MesinPengolah", Vector2(0, 0), Vector2(260, 200), "PENGOLAH", 16)
	_rectn("Conveyor", "Map1_City/Pengolahan", Vector2(2380, 1840), Vector2(2580, 1900), belt, 0)

	_rectn("SignRecycling", "Map1_City/Pengolahan", Vector2(2280, 1420), Vector2(2680, 1472), sign_red, 0)
	_lbl("LabelSign", "Map1_City/Pengolahan/SignRecycling", Vector2(0, 0), Vector2(400, 52), "DAUR ULANG SAMPAH", 16)

	var px := 2150.0
	var pi := 0
	while px < 2870.0:
		_spr("PBarrel_%d" % pi, "Map1_City/Pengolahan", tex_p + "Wooden Barrel.png", Vector2(px, 2160), 3)
		px += 180.0
		pi += 1
	_spr("PChest", "Map1_City/Pengolahan", tex_p + "Treasure Chest.png", Vector2(3030, 2180), 3)
	_spr("PCampfire", "Map1_City/Pengolahan", tex_p + "Campfire.png", Vector2(1940, 2240), 3)
	_spr("PTower", "Map1_City/Pengolahan", tex_p + "Magic Stone Tower.png", Vector2(3030, 1490), 4)
	_spr("PStump1", "Map1_City/Pengolahan", tex_p + "Tree Stump Short.png", Vector2(1940, 1510), 2)
	_spr("PStump2", "Map1_City/Pengolahan", tex_p + "Tree Stump Short.png", Vector2(2140, 1510), 2)

	# ---------- DEKOR JALAN ----------
	_p("DekorJalan", "Map1_City", "Node2D")

	var street_trees := [210, 560, 910, 1260, 1800, 2150, 2500, 2850]
	var ti2 := 0
	for tx in street_trees:
		_spr("StreetTreeTop_%d" % ti2, "Map1_City/DekorJalan", tex_p + "Tree Small.png", Vector2(tx, 985), 5)
		ti2 += 1
	var street_bush := [360, 710, 1060, 1950, 2300, 2650, 3000]
	var bi2 := 0
	for bx in street_bush:
		_spr("StreetBushTop_%d" % bi2, "Map1_City/DekorJalan", tex_p + "Bushes Small.png", Vector2(bx, 985), 2)
		bi2 += 1

	var side_trees := [280, 620, 1600, 1940]
	var si2 := 0
	for sy in side_trees:
		_spr("StreetTreeSide_%d" % si2, "Map1_City/DekorJalan", tex_p + "Tree Small.png", Vector2(1390, sy), 5)
		si2 += 1
	var side_bush := [280, 620, 1600, 1940]
	var bi3 := 0
	for by in side_bush:
		_spr("StreetBushSide_%d" % bi3, "Map1_City/DekorJalan", tex_p + "Bushes Small.png", Vector2(1790, by), 2)
		bi3 += 1

	# 4 pojok persimpangan
	_spr("XBush1", "Map1_City/DekorJalan", tex_p + "Bushes Small.png", Vector2(1450, 1060), 3)
	_spr("XBush2", "Map1_City/DekorJalan", tex_p + "Bushes Small.png", Vector2(1750, 1060), 3)
	_spr("XBush3", "Map1_City/DekorJalan", tex_p + "Bushes Small.png", Vector2(1450, 1340), 3)
	_spr("XBush4", "Map1_City/DekorJalan", tex_p + "Bushes Small.png", Vector2(1750, 1340), 3)

	# ---------- PAGAR PERIMETER ----------
	_p("Fence", "Map1_City", "Node2D")
	var fi := 0
	var fx := 150.0
	while fx < 3050.0:
		_spr("FenceTop_%d" % fi, "Map1_City/Fence", tex_p + "Wooden Fence Horizontal.png", Vector2(fx, 60), 4)
		if not (fx > 1420.0 and fx < 2020.0):
			_spr("FenceBottom_%d" % fi, "Map1_City/Fence", tex_p + "Wooden Fence Horizontal.png", Vector2(fx, 2340), 4)
		fx += 220.0
		fi += 1
	var fy := 150.0
	while fy < 2250.0:
		_spr("FenceLeft_%d" % fi, "Map1_City/Fence", tex_p + "Wooden Fence Vertical.png", Vector2(60, fy), 4)
		_spr("FenceRight_%d" % fi, "Map1_City/Fence", tex_p + "Wooden Fence Vertical.png", Vector2(3140, fy), 4)
		fy += 220.0
		fi += 1

	_build_desa(tex_p, tex_p2)

# ------------------------------------------------------------
# ZONA 5: DESA PERTANIAN (tambahan selatan, lewat jalan ke bawah)
# ------------------------------------------------------------
func _build_desa(tex_p: String, tex_p2: String) -> void:
	_p("Desa", "Map1_City", "Node2D")

	# alas desa
	_rectn("FarmGrass", "Map1_City/Desa", Vector2(0, 2400), Vector2(MAP_W, 4000), Color(0.50, 0.66, 0.38), -28)

	# sawah/kebun grid (2 baris x 4 kolom, sisakan koridor jalan tengah)
	var cols := [[120, 760], [760, 1400], [1800, 2440], [2440, 3080]]
	var rows := [[2560, 3000], [3000, 3440]]
	var ci := 0
	for col in cols:
		var ri := 0
		for row in rows:
			var colr: Color
			if ri == 0:
				colr = Color(0.44, 0.66, 0.34)
			elif ci % 2 == 0:
				colr = Color(0.58, 0.64, 0.32)
			else:
				colr = Color(0.52, 0.60, 0.31)
			_rectn("Field_%d_%d" % [ri, ci], "Map1_City/Desa", Vector2(col[0], row[0]), Vector2(col[1], row[1]), colr, -27)
			ri += 1
		ci += 1

	# jalan tanah melintang (tidak menutup aspal tengah)
	_rectn("DirtRoadW", "Map1_City/Desa", Vector2(120, 3420), Vector2(1400, 3480), Color(0.72, 0.66, 0.50), -26)
	_rectn("DirtRoadE", "Map1_City/Desa", Vector2(1800, 3420), Vector2(3080, 3480), Color(0.72, 0.66, 0.50), -26)

	# sungai melintang
	_rectn("River", "Map1_City/Desa", Vector2(0, 3560), Vector2(MAP_W, 3660), Color(0.30, 0.58, 0.87), -27)

	# halaman pertanian (barat: kincir angin, timur: rumah petani)
	_rectn("FarmYardW", "Map1_City/Desa", Vector2(120, 2400), Vector2(1000, 3160), Color(0.56, 0.70, 0.42), -27)
	_rectn("FarmYardE", "Map1_City/Desa", Vector2(2450, 2400), Vector2(3100, 3060), Color(0.56, 0.70, 0.42), -27)

	# rumah petani (timur)
	_spr("FarmHouse", "Map1_City/Desa", tex_p + "House.png", Vector2(2770, 2700), 0)
	_spr("FarmFence", "Map1_City/Desa", tex_p + "Wooden Fence Horizontal.png", Vector2(2770, 3060), 0)
	_spr("FarmBush1", "Map1_City/Desa", tex_p + "Bushes Small.png", Vector2(2460, 3080), 0)
	_spr("FarmBush2", "Map1_City/Desa", tex_p + "Bushes Small.png", Vector2(3060, 3080), 0)
	_spr("FarmStump", "Map1_City/Desa", tex_p + "Tree Stump Tall.png", Vector2(2580, 2820), 0)
	_spr("FarmRock", "Map1_City/Desa", tex_p + "Rock 01.png", Vector2(2450, 2820), 0)

	# kincir angin (barat)
	_spr("Windmill", "Map1_City/Desa", tex_p2 + "Windmill.png", Vector2(560, 2720), 0)
	_spr("WindmillStump1", "Map1_City/Desa", tex_p + "Tree Stump Short.png", Vector2(840, 2620), 0)
	_spr("WindmillStump2", "Map1_City/Desa", tex_p + "Tree Stump Short.png", Vector2(840, 2880), 0)
	_spr("WindmillRock", "Map1_City/Desa", tex_p + "Rock 02.png", Vector2(300, 3060), 0)
	_spr("WindmillBush", "Map1_City/Desa", tex_p + "Bushes Medium.png", Vector2(880, 3040), 0)
	_spr("WindmillCamp", "Map1_City/Desa", tex_p + "Campfire.png", Vector2(560, 3100), 0)

	# gapura desa: menara jaga + spanduk, angin-angin pohon
	_spr("GuardTowerW", "Map1_City/Desa", tex_p + "Watchtower Short.png", Vector2(1260, 2460), 0)
	_spr("GuardTowerE", "Map1_City/Desa", tex_p + "Watchtower Short.png", Vector2(2020, 2460), 0)
	_spr("GateBush1", "Map1_City/Desa", tex_p + "Bushes Large.png", Vector2(1440, 2500), 0)
	_spr("GateBush2", "Map1_City/Desa", tex_p + "Bushes Large.png", Vector2(1760, 2500), 0)
	var windbreak_w := [200, 440, 680]
	var bi4 := 0
	for wx in windbreak_w:
		_spr("WindbreakW_%d" % bi4, "Map1_City/Desa", tex_p + "Tree Small.png", Vector2(wx, 2500), 0)
		bi4 += 1
	_spr("WindbreakE", "Map1_City/Desa", tex_p + "Tree Small.png", Vector2(2280, 2500), 0)

	# plaza desa + sumur (timur jalan dekat sungai)
	_rectn("VillagePlaza", "Map1_City/Desa", Vector2(1960, 3260), Vector2(2360, 3480), Color(0.60, 0.55, 0.42), -16)
	_spr("VillageWell", "Map1_City/Desa", tex_p + "Well.png", Vector2(2160, 3380), 0)
	_spr("VillageSeat1", "Map1_City/Desa", tex_p + "Tree Stump Tall.png", Vector2(2020, 3460), 0)
	_spr("VillageSeat2", "Map1_City/Desa", tex_p + "Tree Stump Tall.png", Vector2(2300, 3460), 0)
	_spr("VillageCart", "Map1_City/Desa", tex_p + "Wooden Cart.png", Vector2(2060, 3280), 0)
	_spr("VillageBanner1", "Map1_City/Desa", tex_p + "Red Banner.png", Vector2(1760, 3320), 0)
	_spr("VillageBanner2", "Map1_City/Desa", tex_p + "Blue Banner.png", Vector2(2520, 3300), 0)

	var vbarrel_x := 1920.0
	var vbi := 0
	while vbarrel_x < 2600.0:
		_spr("VillageBarrel_%d" % vbi, "Map1_City/Desa", tex_p + "Wooden Barrel.png", Vector2(vbarrel_x, 3460), 0)
		vbarrel_x += 200.0
		vbi += 1

	# jembatan kayu melintasi sungai
	_spr("BridgeFarmW", "Map1_City/Desa", tex_p + "Wooden Bridge Horizontal.png", Vector2(900, 3610), 0)
	_spr("BridgeRoad", "Map1_City/Desa", tex_p + "Wooden Bridge Horizontal.png", Vector2(1600, 3610), 0, 0.5)
	_spr("BridgeFarmE", "Map1_City/Desa", tex_p + "Wooden Bridge Horizontal.png", Vector2(2550, 3610), 0)

	# padang selatan: landmark
	_spr("MagicTower", "Map1_City/Desa", tex_p + "Magic Stone Tower.png", Vector2(320, 3800), 0)
	_spr("CastleSquare", "Map1_City/Desa", tex_p + "Castle Square.png", Vector2(3000, 3780), 0)
	_spr("PastureCampfire", "Map1_City/Desa", tex_p + "Campfire.png", Vector2(830, 3900), 0)
	_spr("PastureRock1", "Map1_City/Desa", tex_p + "Rock 01.png", Vector2(700, 3860), 0)
	_spr("PastureRock2", "Map1_City/Desa", tex_p + "Rock 03.png", Vector2(960, 3860), 0)
	_spr("PastureTree1", "Map1_City/Desa", tex_p + "Tree Small.png", Vector2(1200, 3860), 0)
	_spr("PastureTree2", "Map1_City/Desa", tex_p + "Tree Small.png", Vector2(2050, 3860), 0)
	var south_bush := [[120, 3920], [680, 3920], [1800, 3920], [2450, 3920], [2900, 3920]]
	var sbi := 0
	for sb in south_bush:
		_spr("SouthBush_%d" % sbi, "Map1_City/Desa", tex_p + "Bushes Small.png", Vector2(sb[0], sb[1]), 0)
		sbi += 1

func _write_file() -> void:
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		push_error("Gagal nulis " + OUT)
		return
	var text := ""
	for line in _l:
		text += line + "\n"
	f.store_string(text)
	f.close()
