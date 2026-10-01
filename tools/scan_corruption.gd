extends SceneTree

## Deteksi teks korup di komentar/finalisasi file GDScript.
##
## Dua kelas yang pernah muncul:
##   1. CJK/Cyrillic acak (token seperti `赛中`, `борь`, `死活`).
##   2. Kata fuses / tanda baca nyempil: `->/`, `membawa->`, `yang/Ambil`,
##      `dan,invalidate`, `activate()menyala`.
##
## Kelas 2 lolos dari filter karakter non-ASCII, jadi harus pakai regex ASCII.
## Kelas 1 cukup pakai range Unicode; kelas 2 butuh pola kata.
##
## Pemakaian:
##   godot --headless --path <project> --script res://tools/scan_corruption.gd
##
## Exit 0 = bersih, 1 = ada korupsi.

## Semua file .gd yang dipindai, rekursif.
const SCAN_DIRS := ["scripts/", "tests/", "tools/"]
const TARGET_EXT := ".gd"

## File yang dilewati. Scanner ini melewati dirinya sendiri karena baris
## dokumentasinya memuat pola yang dicari sebagai contoh literal, jadi akan
## selalu cocok. File ini tetap diperiksa manual.
const SKIP_FILES := ["tools/scan_corruption.gd"]

## Pola kata fuses di baris KOMENTAR saja. Dipakai di kode akan salah
## positives: `Trash.TrashType.ORGANIC` dan `$Visual/Anim` itu kode sah.
## Pola yang dipertahankan hanya yang tidak mungkin muncul di path/kode sah:
##   panah pecah:  `membawa muatan ->/APPROACH_DUMP`
##   koma raket:   `dan,invalidate cache`
##   kurung raket: `activate()menyala`
## Pola `word/Word` dan `word.Word` sengaja DIBUANG: path sah
## (`Visual/Anim`, `State.PATROL`) akan memicu keduanya.
var FUSED: Array[RegEx] = [
	_re(r"->/"),
	_re(r"[a-z],[a-z]"),
	_re(r"\)[A-Za-z]"),
]

## Non-ASCII CJK/Cyrillic. Dicek di SELURUH baris, bukan cuma komentar,
## karena karakter segitiga di kode selalu salah.
var CJK := _re("[\u2E80-\u9FFF\u0400-\u04FF\u3000-\u30FF\uFF01-\uFF5E]")


func _re(pattern: String) -> RegEx:
	var r := RegEx.new()
	r.compile(pattern)
	return r


func _initialize() -> void:
	var files := _gd_files()
	var bad := 0
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			print("  (kosong) ", path)
			continue
		for i in _scan(text):
			bad += 1
			print("  CORRUPT  %s:%d: %s" % [path, i.line, i.text])
	print("  diperiksa: %d file .gd (%s)" % [files.size(), ", ".join(SCAN_DIRS)])
	print("")
	if bad == 0:
		print("scan_corruption: BERSIH (0 temuan)")
	else:
		print("scan_corruption: %d temuan korupsi" % bad)
	quit(1 if bad > 0 else 0)


## Kembalikan daftar {line, text} untuk setiap baris yang mencurigakan.
func _scan(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lines := text.split("\n")
	for n in lines.size():
		var line: String = lines[n]
		if CJK.search(line) != null:
			out.append({"line": n + 1, "text": line.strip_edges()})
			continue
		if not _is_comment(line):
			continue
		for r in FUSED:
			if r.search(line) != null:
				out.append({"line": n + 1, "text": line.strip_edges()})
				break
	return out


## Baris komentar GDScript: diawali `#` (termasuk `##` dan `###`).
func _is_comment(line: String) -> bool:
	return line.strip_edges().begins_with("#")


## Kumpulkan path .gd rekursif di bawah SCAN_DIRS, sudah terurut.
func _gd_files() -> PackedStringArray:
	var out := PackedStringArray()
	for d in SCAN_DIRS:
		_collect(d, out)
	out.sort()
	return out


func _collect(rel_dir: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(rel_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			var rel := rel_dir + name
			if name.ends_with(TARGET_EXT) and not SKIP_FILES.has(rel):
				out.append(rel)
		elif not name.begins_with("."):
			_collect(rel_dir + name + "/", out)
		name = dir.get_next()
	dir.list_dir_end()
