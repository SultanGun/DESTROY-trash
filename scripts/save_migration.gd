extends RefCounted

## Migrasi save v1 -> v3 (GameData/GameManager state).
##
## Sengaja stateless + static, TANPA sentuhan autoload. Alasannya: mode
## `--script` tidak memuat autoload sama sekali, jadi kode yang mau diuji
## headless tidak boleh menyentuh `GameManager` / `NightPatrol` sebagai
## identifier. Pola yang sama sudah dipakai `map_seam.gd` (lihat catatan
## `_report_map()` di sana), jadi ini bukan pola baru.
##
## Kontrak:
##   v1 = koin + hari + waktu + posisi player + inventaris + buffer pilah.
##        TIDAK punya peta.
##   v2 = v1 + pollution (0..100) + current_map.
##   v3 = v1 + current_map. Pollution DIHAPUS total: mekaniknya dicabut dari
##        game, jadi tidak ada lagi yang perlu disimpan.
##
## Aturan yang dijaga modul ini:
##   1. <v1 (dan key `version` yang hilang) SELALU jadi peta 1, bahkan kalau
##      save-nya kebetulan punya key `current_map`. Save v1 tidak pernah
##      menuliskannya, jadi kalau dibaca, itu berarti file rusak atau
##      half-written — bukan data yang boleh dipercaya.
##   2. Save v1/v2 dibaca dengan layout v3. Kunci `pollution` yang masih ada di
##      file v2 diabaikan diam-diam, bukan error: save lama milik player harus
##      tetap bisa dimuat, dan tidak ada mesin di dalam file itu yang boleh
##      membuat load gagal.
##   3. Save dari game yang lebih baru (`version` > 3) juga dibaca dengan
##      layout v3, supaya save dari game yang lebih baru tidak ditolak.
##   4. Nilai SELALU divalidasi di kedua arah: `stamp()` menjaga jalur tulis,
##      `normalize()` menjaga jalur baca. Tidak ada jalur yang bisa menghasilkan
##      peta yang tidak dikenal.
##
## Return `normalize()` hanya berisi dua key yang sudah tervalidasi:
## `{version: int, current_map: int}`.

const CURRENT_VERSION := 3
const FALLBACK_MAP := 1

## Peta yang benar-benar ada di dunia (lihat MapSeam + NightPatrol).
const KNOWN_MAPS := [1, 2]

## Baca key `version` dari save mentah lalu kembalikan field tervalidasi.
## Save rusak, half-written, atau versi lawas tidak membuat crash: semuanya
## turun ke default yang bisa dimainkan.
static func normalize(data: Dictionary) -> Dictionary:
	var version := _as_int(data.get("version", 1), 1)
	if version < 1:
		version = 1
	if version < 2:
		return {
			"version": version,
			"current_map": FALLBACK_MAP,
		}
	return {
		"version": version,
		"current_map": _as_map(data.get("current_map", FALLBACK_MAP)),
	}


## Key save yang ditulis ke disk. Dipakai `SaveLoad.gather_data()` supaya
## nomor versi hanya hidup di satu tempat.
static func stamp(current_map: int) -> Dictionary:
	return {
		"version": CURRENT_VERSION,
		"current_map": _as_map(current_map),
	}


## Peta harus salah satu peta yang benar-benar ada; selain itu jatuh ke peta 1
## supaya player tidak pernah load ke wilayah yang tidak digambar.
static func _as_map(value: Variant) -> int:
	var map_id := _as_int(value, FALLBACK_MAP)
	return map_id if map_id in KNOWN_MAPS else FALLBACK_MAP


## JSON bisa menyimpan angka sebagai float, dan file yang diedit tangan bisa
## menyimpan `"12"` — atau `"abc"`. `int()` akan error kalau argumennya bukan
## number, jadi semua lewat sini.
static func _as_int(value: Variant, fallback: int) -> int:
	if value is int or value is float:
		return int(value)
	if value is String:
		return int(value) if value.is_valid_int() else fallback
	return fallback
