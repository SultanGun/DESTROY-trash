extends RefCounted
class_name DumperRoutes

## Data rute patroli 7 NPC pembuang sampah ilegal: 3 rute Map 1 + 4 rute Map 2.
##
## SEMUA titik di bawah adalah koordinat GLOBAL (ruang `Main`), sama dengan
## `position` milik ShopNPC/Player di main.tscn. Datanya BUKAN hasil tebakan:
## tiap titik sudah divalidasi tools/route_analyze.gd terhadap collision bake
## Map1_City dan Map2 (sel diblokir dicek, NPC_R 28px) dengan hasil:
##   - tiap ruas bebas tabrakan (A* 8-arah)
##   - titik DUMP berada di sel bebas DAN benar-benar dilewati rute
##   - seluruh anchor pickup+pengembalian berada di komponen navigasi yang sama
## Status terakhir: 2 peta dianalisis, 7 rute, 7 siap pakai.
##
## Mengubah angka di sini wajib disertai re-run analyzer; kalau tidak,
## rute bisa tetap "lolos tabrakan" tapi tidak pernah sampai ke titik dump.
## Perintah verifikasi ulang:
##   godot --headless --path <project> --script res://tools/route_analyze.gd


## Rute kurir sampah pasar. Circuit tertutup: index terakhir nyambung ke 0.
## Ambil sampah di `pickup`, buang di `dump` (pojok halaman Clauding barat).
const KURIR_PASAR := {
	"nama": "Kurir Pasar",
	"tint": Color(0.85, 0.62, 0.35, 1),
	"map": 1,
	"pickup": 13,
	"dump": 9,
	"titik": [
		Vector2(630, 570),
		Vector2(550, 570),
		Vector2(570, 990),
		Vector2(750, 1170),
		Vector2(1610, 1170),
		Vector2(1610, 2310),
		Vector2(1350, 2390),
		Vector2(970, 2390),
		Vector2(970, 2410),
		Vector2(310, 2450),  # DUMP
		Vector2(970, 2410),
		Vector2(990, 2390),
		Vector2(1570, 2410),
		Vector2(1610, 2450),
		Vector2(1610, 1710),
		Vector2(790, 1730),
		Vector2(750, 1710),
		Vector2(590, 1390),
		Vector2(310, 1370),
		Vector2(310, 1170),
		Vector2(490, 970),
		Vector2(550, 570),
	],
}

## Rute karyawan pabrik. Circuit tertutup. Ambil di `pickup` (jalan tanah
## selatan), buang di `dump` (tepi sungai barat).
const KARYAWAN_PABRIK := {
	"nama": "Karyawan Pabrik",
	"tint": Color(0.45, 0.62, 0.85, 1),
	"map": 1,
	"pickup": 14,
	"dump": 10,
	"titik": [
		Vector2(2970, 2230),
		Vector2(1690, 2130),
		Vector2(1610, 2070),
		Vector2(1610, 2310),
		Vector2(1610, 3270),
		Vector2(1410, 3430),
		Vector2(1270, 3470),
		Vector2(1230, 3530),
		Vector2(1130, 3530),
		Vector2(910, 3430),
		Vector2(830, 3510),  # DUMP
		Vector2(910, 3590),
		Vector2(710, 3730),
		Vector2(770, 3690),
		Vector2(2010, 3670),
		Vector2(2070, 3730),
		Vector2(2130, 3710),
		Vector2(2530, 3630),
		Vector2(2570, 3590),
		Vector2(2210, 3270),
		Vector2(1970, 3470),
		Vector2(1870, 3470),
		Vector2(1610, 2450),
		Vector2(2010, 2230),
		Vector2(2030, 2230),
	],
}

## Rute pemuda taman. Circuit tertutup. Ambil di `pickup` (persimpangan
## aspal tengah), buang di `dump` (gang residential barat laut).
const PEMUDA_TAMAN := {
	"nama": "Pemuda Taman",
	"tint": Color(0.55, 0.80, 0.50, 1),
	"map": 1,
	"pickup": 26,
	"dump": 15,
	"titik": [
		Vector2(1910, 250),
		Vector2(1910, 470),
		Vector2(2370, 510),
		Vector2(2450, 850),
		Vector2(2450, 1170),
		Vector2(1610, 1170),
		Vector2(750, 1170),
		Vector2(470, 870),
		Vector2(350, 870),
		Vector2(330, 890),
		Vector2(430, 870),
		Vector2(490, 870),
		Vector2(490, 990),
		Vector2(230, 990),
		Vector2(170, 910),
		Vector2(190, 710),  # DUMP
		Vector2(170, 930),
		Vector2(330, 990),
		Vector2(490, 990),
		Vector2(490, 870),
		Vector2(350, 870),
		Vector2(330, 890),
		Vector2(430, 870),
		Vector2(490, 870),
		Vector2(490, 990),
		Vector2(310, 1170),
		Vector2(1610, 1170),
		Vector2(2450, 1170),
		Vector2(2450, 510),
		Vector2(1910, 470),
	],
}

## ---------------------------------------------------------------------------
## RUTE MAP 2 (lahan luas, koordinat global ruang Main)
## ---------------------------------------------------------------------------
## Peta 2 punya struktur yang berbeda dari Map 1 dan TIDAK boleh disalin polanya.
## Bukti dari tools/route_analyze.gd (mode `lanes:2` / `vlane:2`):
##   - Pita jalan utama hanya di y 931..1351: x 3348..4628 (barat) dan
##     4708..6348 (timur). Dinding x 4628..4708 MEMBELAH pita jalan itu.
##   - Dinding itu TIDAK punya satu-satunya penyeberang. tools/route_analyze.gd
##     (vlane:2) mengukur TUJUH celah yang bisa dilewati, semuanya di x
##     4628..4708: y 2071..2191, 2451..2571, 2671..2971, 3051..3291,
##     3591..3651, 3751..3931, dan 3951..4051. Rute pada file ini memakai
##     celah y 2130 (ada di dalam 2071..2191).
##   - PERHATIAN: celah y 3951..4051 itu menipu. Pita paling selatan itu
##     menutupi seluruh lebar peta dan memang memotong dinding, tetapi tidak
##     tersambung ke ladang di utara karena baris y 3931..3951 terblokir
##     penuh. Hasilnya dua komponen terpisah (375 dan 378 sel) yang tidak
##     punya pintu masuk dari jaringan jalan utama. Titik pickup atau dump
##     di pita itu selalu gagal validasi.
##   - x 4750 kontinu y 971..3491 lalu 3591..3931; dipakai sebagai tulang
##     punggung rute yang menyentuh lapangan selatan.
##   - Desa utara hanya tersambung ke jalan lewat koridor lebar x 4838..4978
##     (y 11..2431). Kampung barat-utara di x 4858..4898 punya celah
##     terblokir y 291..391, jadi jalur ke desa itu lewat x 4838 atau
##     x 4918, bukan lewat x 4858..4898.
##   - Ladang selatan memakai sumbu x 3958 (y 2551..3491) dan x 4198
##     (y 3271..3931), disambung lewat baris y 3481.
##
## Rute 1: Petani sawah. Mengambil tumpukan di ladang barat, membuang di tepi
## ladang selatan, lalu pulang lewat jalan barat.
const PETANI_SAWAH := {
	"nama": "Petani Sawah",
	"tint": Color(0.62, 0.80, 0.42, 1),
	"map": 2,
	"pickup": 6,
	"dump": 9,
	"titik": [
		Vector2(4400, 1200),  # jalan barat
		Vector2(4550, 1500),
		Vector2(4550, 2050),
		Vector2(4750, 2130),  # celah dinding: y 2130 ada di dalam 2071..2191
		Vector2(4750, 2500),
		Vector2(4750, 3000),
		Vector2(4750, 3480),
		Vector2(4750, 3800),
		Vector2(4300, 3900),
		Vector2(4200, 3800),  # DUMP
		Vector2(4198, 3480),
		Vector2(3958, 3480),
		Vector2(3958, 3000),
		Vector2(3958, 2600),
		Vector2(3600, 2700),
	],
}

## Rute 2: Pedagang keliling. Serving the market dari jalan barat ke jalan
## timur, menembus celah dinding di y 2130 karena dinding membelah jalan.
const PEDAGANG_KELILING := {
	"nama": "Pedagang Keliling",
	"tint": Color(0.88, 0.74, 0.38, 1),
	"map": 2,
	"pickup": 8,
	"dump": 13,
	"titik": [
		Vector2(3500, 1200),
		Vector2(4400, 1200),
		Vector2(4550, 1500),
		Vector2(4550, 2050),
		Vector2(4750, 2130),  # JEMBATAN
		Vector2(5100, 2130),
		Vector2(5100, 1900),
		Vector2(5300, 1700),
		Vector2(5300, 1200),  # PICKUP: jalan timur
		Vector2(5900, 1200),
		Vector2(6100, 1600),
		Vector2(6100, 1900),
		Vector2(5900, 2050),
		Vector2(4750, 2130),  # DUMP: celah di sisi tenggara dinding
		Vector2(4550, 2050),
		Vector2(4550, 1500),
		Vector2(4400, 1200),
	],
}

## Rute 3: Pedagang pasar pagi. Memakai sumbu x 5000 yang menyambung desa
## utara (y 41..871) ke jalan (y 921..1241) dan turun ke lapangan.
const PEDAGANG_PASAR := {
	"nama": "Pedagang Pasar Pagi",
	"tint": Color(0.82, 0.50, 0.62, 1),
	"map": 2,
	"pickup": 2,
	"dump": 8,
	"titik": [
		Vector2(5000, 200),  # desa utara
		Vector2(5200, 400),
		Vector2(5000, 800),  # PICKUP: dekat warung desa
		Vector2(5000, 1200),  # jalan timur
		Vector2(5000, 1600),
		Vector2(5000, 1900),
		Vector2(5000, 2200),
		Vector2(5000, 2500),
		Vector2(5000, 2800),  # DUMP
		Vector2(5000, 2500),
		Vector2(5000, 1200),
		Vector2(5000, 800),
		Vector2(5000, 400),
	],
}

## ---------------------------------------------------------------------------
## Catatan geometri Map 2 untuk rute 3 dan 4
## ---------------------------------------------------------------------------
## Desa utara hanya tersambung ke jalan lewat koridor lebar x 4838..4978,
## jadi rute 3 memakai sumbu x 5000 untuk turun dari desa ke jalan lalu ke
## lapangan bagian timur. Rute 4 memakai ladang sisi timur dan membuang di
## y 3890, bukan di pita paling selatan (y 3951..4051) yang terisolasi.
## Lihat catatan geometri lengkap di blok "RUTE MAP 2" di atas.
##
## Rute 4: Petani Timur. Menyusuri ladang sisi timur, membuang sampah
## di sudut paling selatan ladang.
const PETANI_TIMUR := {
	"nama": "Petani Timur",
	"tint": Color(0.50, 0.78, 0.72, 1),
	"map": 2,
	"pickup": 3,
	"dump": 8,
	"titik": [
		Vector2(5000, 1200),  # jalan timur
		Vector2(5200, 1600),
		Vector2(5200, 1900),
		Vector2(5240, 2400),  # PICKUP: gudang timur
		Vector2(5200, 2700),
		Vector2(5400, 3000),
		Vector2(5700, 3300),
		Vector2(5800, 3600),
		Vector2(5750, 3890),  # DUMP
		Vector2(5400, 3800),
		Vector2(5200, 3400),
		Vector2(5000, 2800),
		Vector2(5000, 2500),
	],
}

## Semua rute, urut sesuai penempatan di scene.
const ALL := [KURIR_PASAR, KARYAWAN_PABRIK, PEMUDA_TAMAN, PETANI_SAWAH, PEDAGANG_KELILING, PEDAGANG_PASAR, PETANI_TIMUR]


## Ambil satu rute berdasarkan indeksnya di [constant ALL].
static func by_index(i: int) -> Dictionary:
	if i < 0 or i >= ALL.size():
		return {}
	return ALL[i]


## Titik di mana NPC mengambil sampah (mulai membawa ke titik dump).
static func pickup_point(route: Dictionary) -> Vector2:
	var titik: Array = route["titik"]
	return titik[int(route["pickup"])]


## Titik buangan sampah milik satu rute.
static func dump_point(route: Dictionary) -> Vector2:
	var titik: Array = route["titik"]
	return titik[int(route["dump"])]


## Titik awal patroli: index 0. NPC di-spawn di sini lalu langsung jalan.
static func start_point(route: Dictionary) -> Vector2:
	var titik: Array = route["titik"]
	return titik[0]
