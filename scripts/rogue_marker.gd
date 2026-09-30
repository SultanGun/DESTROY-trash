extends CanvasLayer

## Penunjuk pembuang liar yang masih hidup, supaya player tidak perlu
## menebak "apakah dia sudah spawn".
##
## Dua mode, dipilih otomatis:
##   1. Layar: chevron kecil di atas kepala NPC.
##   2. Tepi: panah yang menempel di sisi layar,Plus label peta, kalau NPC di
##      luar bidang pandang. Ini yang paling penting untuk Map 2, yang jaraknya
##      ribuan piksel dari Map 1 - tanpa penunjuk tepi, player tidak
##      mungkin tahu ada NPC di sana yang menunggu.
##
## Sumber kebenaran tetap NightPatrol (`active_dumpers()`), jadi kalau NPC
## belum spawn, penunjuk ini TIDAK muncul. Itu justru gunanya: kalau tidak ada
## chevron di layar, berarti memang belum ada NPC aktif, bukan marker-nya yang
## salah.
##
## Ditempel di Player scene, jadi posisinya selalu mengikuti player.

## Node PatrolHUD yang jadi induk penunjuk, ditambahkan lewat setup().
var _anchor: Node2D = null
var _night_patrol: Node = null

## Jarak panah dari tepi layar.
const EDGE_MARGIN := 34.0

## Seberapa tinggi chevron digambar di atas NPC, dalam PIKSEL LAYAR (bukan
## world), supaya jaraknya tetap sama pada zoom berapa pun.
##
## Nilainya harus jauh di atas badge "[E] Tangkap" (yang menggambar dirinya
## sekitar 105px di atas NPC). Kalau chevron dan badge di tinggi yang sama,
## badge menutup chevron: badge ada di layer 20, marker di layer 1, jadi yang
## menang adalah badge dan chevron tidak pernah terlihat sama sekali.
const CHEVRON_UP := 150.0

var _on_screen: Control = null
var _chevron: Polygon2D = null
var _on_screen_label: Label = null

var _edge: Control = null
var _edge_arrow: Polygon2D = null
var _edge_label: Label = null
var _edge_sub: Label = null


func _ready() -> void:
	_build()
	# Process TIDAK pernah dimatikan. Marker ini tugasnya justru memberi tahu
	# player bahwa NPC baru saja muncul, jadi harus terus poll: kalau process
	# dimatikan saat belum ada target, marker tidak akan pernah menyala lagi
	# karena tidak ada yang memanggil _refresh() lagi.
	set_process(true)
	visible = false


func setup(anchor: Node2D) -> void:
	_anchor = anchor
	_night_patrol = get_tree().root.get_node_or_null(^"NightPatrol")
	_build()
	_refresh()


## NPC hidup pertama yang layak ditunjuk. Kalau ada beberapa (mis. player
## belum sempat menangkap yang pertama), yang paling dekat dari player yang
## dipilih supaya panahnya tidak menunjuk ke seberang peta.
func _target() -> Node2D:
	if not is_instance_valid(_anchor) or _night_patrol == null:
		return null
	if not _night_patrol.has_method("active_dumpers"):
		return null
	var list: Array = _night_patrol.call("active_dumpers")
	var best: Node2D = null
	var best_d := INF
	for d in list:
		if not is_instance_valid(d):
			continue
		# Hanya NPC yang masih bisa ditutup: skip yang terminal (4/5) DAN yang
		# sedang kabur setelah tertangkap (FLEEING=7). Keduanya tidak lagi
		# jadi target, jadi marker tidak boleh menunjuk ke sana.
		if d.has_method("current_state"):
			var st := int(d.call("current_state"))
			if st == 4 or st == 5 or st == 7:
				continue
		var dist: float = _anchor.global_position.distance_to(d.global_position)
		if dist < best_d:
			best_d = dist
			best = d
	return best


func _process(_delta: float) -> void:
	_refresh()


## Hitung posisi layar NPC lalu pilih mode on-screen / edge.
func _refresh() -> void:
	var t := _target()
	if t == null:
		visible = false
		return
	visible = true
	var vp := get_viewport()
	if vp == null:
		return
	var view_size := vp.get_visible_rect().size
	var ct: Transform2D = vp.get_canvas_transform()
	# On/off-screen ditentukan dari posisi NPC itu sendiri, BUKAN dari posisi
	# chevron. Kalau pakai posisi chevron, NPC yang berdiri tepat di tepi atas
	# akan terhitung "di luar layar" hanya karena chevronnya naik 150px.
	var screen: Vector2 = ct * t.global_position
	# Toleransi: chevron dianggap "di layar" kalau NPC masih sedikit di dalam
	# tepi, supaya tidak berkedip-hilang tepat di batas.
	var margin := 8.0
	var on_screen := screen.x >= margin and screen.y >= margin \
		and screen.x <= view_size.x - margin and screen.y <= view_size.y - margin
	if on_screen:
		_on_screen.visible = true
		_on_screen_label.text = "PEMBUANG"
		_on_screen.position = screen + Vector2(0, -CHEVRON_UP)
		_edge.visible = false
	else:
		_on_screen.visible = false
		_edge.visible = true
		_place_edge(screen, view_size, t)


## Panel tepi: panah digambar di sisi yang paling dekat ke NPC, dengan label
## peta supaya player tahu harus menyeberang ke Map 1 atau Map 2.
func _place_edge(screen: Vector2, view_size: Vector2, target: Node2D) -> void:
	var center := view_size * 0.5
	var dir := (screen - center)
	# Jaga agar tidak nol, kalau NPC tepat di tengah layar.
	if dir.length() < 0.001:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	# Project ke persegi tepi: ambil komponen terbesar supaya panah menempel
	# di sisi yang benar, bukan miring di sudut.
	var half := view_size * 0.5 - Vector2(EDGE_MARGIN, EDGE_MARGIN)
	var scale: float = min(half.x / max(absf(dir.x), 0.0001), half.y / max(absf(dir.y), 0.0001))
	var pos := center + dir * scale
	_edge.position = pos
	# Putar panah mengikuti arah, tapi snap ke 8 arah supaya tidak miring
	# seperti jarum jam - panah harus terbaca jelas.
	_edge_arrow.rotation = snappedf(dir.angle(), PI / 4.0)
	_edge_label.text = "PEMBUANG"
	_edge_sub.text = _map_hint(target)


## Peta tempat rute ini berada, supaya panel tepi bisa bilang "Map 2" dan
## player tahu ia harus menyeberang, bukan cuma berjalan lebih jauh.
func _map_hint(target: Node2D) -> String:
	if not target.has_method("get"):
		return ""
	var rid := int(target.get("route_id"))
	return "Map %d" % _map_of_route(rid)


func _map_of_route(rid: int) -> int:
	var DumperRoutes := load("res://scripts/dumper_routes.gd")
	if rid < 0 or rid >= DumperRoutes.ALL.size():
		return 0
	return int(DumperRoutes.ALL[rid].get("map", 0))


func _build() -> void:
	if _on_screen != null:
		return
	# --- on-screen: chevron kecil di atas kepala NPC -----------------------
	_on_screen = Control.new()
	_on_screen.name = "OnScreenMarker"
	_on_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_on_screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	add_child(_on_screen)
	_chevron = Polygon2D.new()
	# Segitiga kecil menghadap bawah, seperti tanda "di sini".
	_chevron.polygon = PackedVector2Array([
		Vector2(0, 6), Vector2(-7, -5), Vector2(7, -5),
	])
	_chevron.color = Color(1, 0.85, 0.2)
	_on_screen.add_child(_chevron)
	_on_screen_label = Label.new()
	_on_screen_label.add_theme_font_size_override("font_size", 11)
	_on_screen_label.add_theme_color_override("font_color", Color(1, 0.92, 0.55))
	_on_screen_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_on_screen_label.add_theme_constant_override("outline_size", 4)
	_on_screen_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_on_screen_label.size = Vector2(90, 14)
	_on_screen_label.position = Vector2(-45, -24)
	_on_screen.add_child(_on_screen_label)

	# --- edge: panah di tepi layar + label peta -----------------------------
	_edge = Control.new()
	_edge.name = "EdgeMarker"
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.set_anchors_preset(Control.PRESET_TOP_LEFT)
	add_child(_edge)
	_edge_arrow = Polygon2D.new()
	_edge_arrow.polygon = PackedVector2Array([
		Vector2(11, 0), Vector2(-7, -7), Vector2(-7, 7),
	])
	_edge_arrow.color = Color(1, 0.85, 0.2)
	# Outline hitam lewat polygon kedua yang sedikit lebih besar di belakang,
	# karena Polygon2D tidak punya add_outline().
	var edge_bg := Polygon2D.new()
	edge_bg.polygon = PackedVector2Array([
		Vector2(14, 0), Vector2(-10, -10), Vector2(-10, 10),
	])
	edge_bg.color = Color(0, 0, 0, 0.85)
	_edge.add_child(edge_bg)
	_edge.add_child(_edge_arrow)
	_edge_label = Label.new()
	_edge_label.add_theme_font_size_override("font_size", 12)
	_edge_label.add_theme_color_override("font_color", Color(1, 0.92, 0.55))
	_edge_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_edge_label.add_theme_constant_override("outline_size", 4)
	_edge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edge_label.size = Vector2(110, 16)
	_edge_label.position = Vector2(-55, 10)
	_edge.add_child(_edge_label)
	_edge_sub = Label.new()
	_edge_sub.add_theme_font_size_override("font_size", 12)
	_edge_sub.add_theme_color_override("font_color", Color(1, 0.8, 0.4))
	_edge_sub.add_theme_color_override("font_outline_color", Color.BLACK)
	_edge_sub.add_theme_constant_override("outline_size", 4)
	_edge_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edge_sub.size = Vector2(110, 16)
	_edge_sub.position = Vector2(-55, 26)
	_edge.add_child(_edge_sub)
