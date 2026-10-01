extends CanvasLayer

## Panel-objective malam patrol, di sisi kiri-tengah layar.
##
## Isinya tiga hal dan tidak lebih:
##   1. Judul "TANGKAP PEMBUANG SAMPAH" - selalu terlihat, biar player tahu
##      apa tujuannya tanpa harus membuka menu.
##   2. "TERTANGKAP n/2" - progres malam ini. Penyebutnya 2 dari detik pertama,
##      bukan setelah NPC kedua muncul, supaya player tahu ada dua orang yang
##      harus dikejar sejak awal.
##   3. Tombol "KLAIM 100 EMAS" - hidup hanya setelah 2/2. Ditekan sekali per
##      malam; setelah diklaim tombol mati dan uang benar-benar masuk.
##
## Yang DIHAPUS dari versi lama, dan kenapa:
##   - Meter pollution. Pollution dicabut dari game, jadi meter ini cuma
##     menampilkan angka yang tidak lagi dihitung siapa pun.
##   - Bar "MEMBUANG" (progress rata-rata aggregate). Bar itu jawabannya
##     "sekarang waktunya lari ke sana", tapi sekarang cuma ada SATU pembuang
##     aktif pada satu waktu, dan minigame tangkapan yang pegang kendali
##     atas player adalah cara dia tahu harus dekat. Bar aggregate jadi
##     informasi yang tidak lagi relevan.
##
## Koneksinya lewat nama node di root, bukan group, karena NightPatrol dan
## GameManager tidak pernah memanggil add_to_group(). Kalau autoload tidak ada,
## HUD diam-diam menampilkan placeholder dan tidak crash.

@onready var _caught_label: Label = $Box/CaughtLabel
@onready var _status_label: Label = $Box/Status
@onready var _claim_button: Button = $Box/ClaimButton
@onready var _title_label: Label = $Box/Title
@onready var _minimize_button: Button = $Box/MinimizeButton

var _night_patrol: Node = null

## Total target yang terakhir diterima dari NightPatrol; dipakai untuk
## messaging tombol dan status.
var _total: int = 0

## true kalau uang malam ini sudah diambil. Disimpan terpisah dari state
## NightPatrol supaya HUD bisa menampilkan "sudah diklaim" tanpa memanggil
## ke autoload tiap frame.
var _claimed := false

## Ukuran panel saat terbuka dan saat diperkecil.
##
## Tingginya harus muat tombol klaim: Button punya tinggi minimum sendiri
## (~59px untuk font 17), jadi panel 208px akan membuat tombol meluber.
const NORMAL_SIZE := Vector2(280, 224)
const MINIMIZED_SIZE := Vector2(112, 34)

## Angka tangkapan terakhir, dipakai penjaga tombol dan tab kecil.
var _caught := 0

## true = panel sedang diperkecil jadi tab kecil.
var _minimized := false


func _ready() -> void:
	var r := get_tree().root
	_night_patrol = r.get_node_or_null(^"NightPatrol")
	if _night_patrol != null:
		if _night_patrol.has_signal("patrol_progress"):
			_night_patrol.patrol_progress.connect(_on_patrol_progress)
		if _night_patrol.has_signal("patrol_claimed"):
			_night_patrol.patrol_claimed.connect(_on_patrol_claimed)
	# Tombol sengaja dikoneksikan di _ready, tidak lewat scene connection:
	# signal `pressed` membawa argumen, jadi handler harus menerima dan
	# membuangnya, dan lebih jelas ditulis di satu tempat.
	_claim_button.pressed.connect(_on_claim_pressed)
	_minimize_button.pressed.connect(_on_minimize_pressed)
	_apply_panel_size()
	# Palse pertama: belum ada malam yang berjalan, jadi 0/N dan tombol mati.
	_on_patrol_progress(0, 0)


## Perkecil / perbesar panel.
##
## Yang disembunyikan hanya isi (judul, angka, status, tombol klaim); tombol
## minimize sendiri tetap terlihat, jadi panel tidak pernah hilang total dan
## selalu bisa dikembalikan. Judul berubah jadi ringkasan singkat supaya tab
	# kecil tetap bisa tahu berapa yang sudah tertangkap.
func _on_minimize_pressed() -> void:
	_minimized = not _minimized
	_apply_panel_size()


func _apply_panel_size() -> void:
	var box := _box()
	if box == null:
		return
	var want := MINIMIZED_SIZE if _minimized else NORMAL_SIZE
	# Box dijangkarkan kiri-tengah vertikal, jadi saat tinggi berubah offset
	# atas harus digeser juga - kalau tidak panel akan "nempel" ke atas dan
	# meloncat ke bawah saat diperkecil.
	var prev_h := box.size.y
	box.size = want
	box.position.y += (prev_h - want.y) * 0.5
	_title_label.visible = not _minimized
	_caught_label.visible = not _minimized
	_status_label.visible = not _minimized
	_claim_button.visible = not _minimized
	_minimize_button.text = "+" if _minimized else "–"
	_minimize_button.tooltip_text = "Perbesar panel" if _minimized else "Perkecil panel"
	if _minimized:
		# Tab kecil menulis progresnya sendiri supaya tetap informatif.
		_title_label.text = "%d/%d" % [_caught, _total]
		_title_label.visible = true
		_title_label.offset_left = 8.0
		_title_label.offset_right = 66.0
		_title_label.offset_top = 4.0
		_title_label.offset_bottom = 30.0
		# Tombol pindah ke kiri tab. Posisi PENUH (222, -2) sengaja tidak
		# dipakai: itu menabrak judul yang berakhir di x=228.
		_minimize_button.position = Vector2(70, 2)
	else:
		_title_label.text = "TANGKAP PEMBUANG SAMPAH"
		_title_label.offset_left = 14.0
		_title_label.offset_right = 228.0
		_title_label.offset_top = 12.0
		_title_label.offset_bottom = 72.0
		_minimize_button.position = Vector2(234, 10)


func _box() -> Control:
	if _caught_label == null:
		return null
	return _caught_label.get_parent() as Control


func is_minimized() -> bool:
	return _minimized


func _on_patrol_progress(caught: int, total: int) -> void:
	_total = total
	if _caught_label == null:
		return
	# `total` = 0 di siang hari, saat tidak ada rute aktif. "0/0" terbaca
	# seperti bug, jadi malam tanpa rute ditampilkan sebagai "TERTANGKAP -".
	if total <= 0:
		_caught_label.text = "TERTANGKAP -"
	elif _claimed:
		_caught_label.text = "TERTANGKAP %d/%d" % [caught, total]
	else:
		_caught_label.text = "TERTANGKAP %d/%d" % [caught, total]
	_refresh_claim(caught, total)
	_refresh_status(caught, total)


## Tombol hanya hidup saat 2/2 DAN belum diklaim. Setelah diklaim, mati lagi
## supaya +100 tidak bisa ditekan dua kali - pengaman kedua, setelah pengaman
## pertama di NightPatrol.claim_reward().
func _refresh_claim(caught: int, total: int) -> void:
	_caught = caught
	_total = total
	if _claim_button == null:
		return
	var ready_now := _can_press_claim()
	_claim_button.disabled = not ready_now
	if ready_now:
		_claim_button.text = "KLAIM 100"
	# Tab kecil ikut berubah kalau panel sedang diperkecil, supaya angka
	# "n/2" yang kecil itu selalu benar dan bukan sisa frame terakhir.
	if _minimized and _title_label != null:
		_title_label.text = "%d/%d" % [caught, total]


func _refresh_status(caught: int, total: int) -> void:
	if _status_label == null:
		return
	if total <= 0:
		_status_label.text = "Tidak ada pembuang malam ini"
	elif _claimed:
		_status_label.text = "Hadiah sudah diambil"
	elif caught >= total:
		_status_label.text = "Tekan tombol untuk klaim hadiah"
	else:
		var left := total - caught
		_status_label.text = "%d pembuang lagi" % left


func _on_patrol_claimed() -> void:
	_claimed = true
	if _caught_label == null:
		return
	_caught_label.text = "TERTANGKAP %d/%d" % [_total, _total]
	_refresh_claim(_total, _total)
	_refresh_status(_total, _total)


func _on_claim_pressed() -> void:
	# Penjaga LOKAL, sebelum menyentuh autoload. NightPatrol.claim_reward()
	# memang menolak klaim kedua, tapi HUD tidak boleh bergantung sepenuhnya
	# pada backside itu: kalau backend-nya longgar (atau diganti implementasi),
	# satu malam bisa dibayar dua kali hanya karena player klik cepat. Tombol
	# yang sudah dibayar tidak boleh bisa dibayar lagi dari sisi mana pun.
	if _claimed or not _can_press_claim():
		return
	if _night_patrol == null or not _night_patrol.has_method("claim_reward"):
		return
	if bool(_night_patrol.call("claim_reward")):
		# `patrol_claimed` akan memanggil _on_patrol_claimed; baris di sini
		# memastikan tombol mati SEKETIKA walau signal-nya telat sampai frame
		# berikutnya.
		_claimed = true
		_refresh_claim(_total, _total)
		_refresh_status(_total, _total)


## Syarat tombol boleh ditekan: malam berjalan, sudah 2/2, belum dibayar.
## Sama dengan syarat NightPatrol.can_claim(), tapi dihitung HUD sendiri supaya
## tidak perlu memanggil autoload tiap frame.
func _can_press_claim() -> bool:
	return _total > 0 and _caught >= _total and not _claimed


