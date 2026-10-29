# Tiket tambahan: zoom, lensa & cahaya

Tiket untuk background yang lebih rapi lewat zoom, pemilihan focal length, ISO dan shutter saat backlight, serta posisi berdiri dari arah matahari. Format tiket sama dengan tab utama.

## Teknologi

| Teknologi | Bisa apa | Kondisi dipakai | Perangkat | Tiket |
| --- | --- | --- | --- | --- |
| Kamera tele & ultra wide (virtual device) | Ganti focal length: 0.5×, 1×, 2×, 3–5× | Ruang sempit atau grup (0.5×); background ingin rapi atau jauh (tele) | Tergantung model; tele hanya iPhone Pro | Z2 |
| DETR segmentation (sudah ada) | Label isi background (orang lain, kendaraan, benda) | Mendeteksi background berantakan di pinggir frame | Semua iPhone | Z1 |
| `exposureTargetBias` | Naikkan atau turunkan terang otomatis tanpa mode manual | Wajah masih gelap saat backlight walau titik exposure sudah di wajah | Semua iPhone | X1 |
| SunKit (Swift package, Apache-2.0) + CoreLocation | Posisi matahari (azimuth, ketinggian), golden hour, tanpa internet | Outdoor, siang, izin lokasi diberikan | Semua iPhone | S1 |
| Core Motion (true north) + kompas | Arah kamera belakang menghadap | Dibandingkan dengan arah matahari | Semua iPhone | S1 |

## Tiket: zoom & focal length

Prinsipnya: ukuran orang di frame tetap, fotografer mundur, zoom dinaikkan. Background yang masuk jadi lebih sempit (2× = kira-kira setengah lebar) dan terlihat lebih besar di belakang orang, jadi benda berantakan di pinggir ikut terbuang. Zoom 2× dari sensor 48 MP tidak menambah blur; lensa tele (3× ke atas) menambah sedikit blur.

### Z1 · Zoom untuk background lebih sempit dan rapi

**Type:** Story · **Priority:** Medium · **Estimate:** 5

**Story:** Sebagai fotografer, saya ingin background lebih sempit tanpa mengecilkan orangnya, supaya sampah atau barang di sekitar tidak ikut masuk foto.

**Acceptance Criteria**

- Given background di pinggir frame berisi benda pengganggu (orang lain, kendaraan, tempat sampah) menurut segmentasi, When langkah jarak selesai, Then muncul saran "Zoom in and step back for a cleaner background" dengan tombol 2×.
- Given user tap 2×, When kamera pindah ke 2×, Then guide jarak menyuruh mundur sampai ukuran orang kembali sama dengan target, dan semua hitungan tinggi / tilt memakai FOV 2×.
- Given zoom 2× aktif, When user tap 1×, Then kamera kembali ke 1× (untuk ruang yang tidak bisa mundur).
- Given perkiraan resolusi akhir setelah crop kurang dari 8 MP, When app menimbang saran, Then saran 2× tidak muncul.
- Given iPhone tanpa sensor 48 MP, When background berantakan, Then saran tetap muncul tapi memakai zoom digital dengan batas resolusi yang sama.

**Tech notes:** `videoZoomFactor` di kamera utama (2× crop sensor lewat `secondaryNativeResolutionZoomFactors`); `CameraService.verticalFOV` harus ikut zoom. Deteksi benda pakai DETR segmentation yang sudah ada, dijalankan di snapshot (± 1× per detik), bukan tiap frame. Terkait C2 (versi berbasis preference).

### Z2 · Pilih lensa (focal length) sesuai tujuan

**Type:** Spike lalu Story · **Priority:** Low · **Estimate:** Spike 3, Story 8

**Story:** Sebagai fotografer, saya ingin app memilih lensa yang cocok dengan situasi, supaya tidak perlu paham focal length.

**Acceptance Criteria**

- Given ruang sempit atau foto grup yang tidak muat di 1×, When orang terpotong di tepi dan fotografer tidak bisa mundur, Then app menyarankan 0.5× dan memberi tahu bahwa orang di pinggir bisa terlihat melar.
- Given iPhone dengan lensa tele dan background berantakan atau preset dari jarak jauh, When cahaya cukup, Then app menyarankan tele (3× ke atas) sebagai pilihan di atas 2×.
- Given cahaya redup (ISO tinggi), When app menimbang tele, Then tele tidak disarankan dan maksimal 2×.
- Given lensa berganti, When guide menghitung, Then FOV dan jarak minimum fokus mengikuti lensa aktif.
- Given spike selesai, When hasil dicatat, Then ada tabel per model iPhone: lensa tersedia, FOV, dan kualitas di redup.

**Tech notes:** kamera virtual (`builtInTripleCamera` / `builtInDualWideCamera`) dengan `virtualDeviceSwitchOverVideoZoomFactors`, atau pindah perangkat fisik. Di redup, iOS bisa diam-diam memakai crop kamera utama alih-alih tele; cek lensa aktif lewat `activePrimaryConstituent`. Mengganti tipe perangkat mengubah perilaku zoom dan FOV untuk semua mode, jadi dites di mode 2 dulu.

## Tiket: cahaya & matahari

Titik exposure sudah di wajah (sudah jalan). X1 memberi tahu ke mana harus pindah kalau wajah masih gelap karena backlight; S1 mencegah backlight sejak awal dengan memberi tahu posisi berdiri dari arah matahari. Keduanya hanya saran: app tidak mengubah exposure kamera dan tidak mengedit foto, karena kamera tidak bisa menerangkan wajah backlit tanpa membakar background (percobaan bias exposure, relight person matte, dan bracket sudah dicoba lalu dibuang).

### X1 · Saran pindah posisi saat backlight

**Type:** Story · **Priority:** High · **Estimate:** 3

**Story:** Sebagai orang yang difoto, saya ingin fotografer diberi tahu ke mana harus bergeser saat wajah saya gelap karena membelakangi cahaya, supaya foto bagus tanpa diedit.

**Acceptance Criteria**

- Given wajah terdeteksi, frame cukup terang (≥ 0,20), dan terang wajah < 70% terang frame selama 1 detik (backlight), When app menilai, Then muncul satu tip pindah posisi.
- Given satu sisi background lebih terang ≥ 15% dari sisi lain, When tip muncul, Then tip menyuruh bergeser ke sisi terang itu ("Backlit. Step to your left/right, they turn to face you.").
- Given kedua sisi background hampir sama terang (< 15%), When tip muncul, Then tip menyuruh tukar posisi ("Backlit. Swap places so the light is behind you.").
- Given wajah naik ke ≥ 85% terang frame, atau backlight/wajah hilang selama 1 detik, When app menilai, Then tip hilang (hysteresis 70%/85% mencegah berkedip).
- Given ruangan gelap (frame < 0,20), When app menilai, Then tidak ada tip (gelap bukan backlight).
- Given tip backlight dan tip matahari (S1) aktif bersamaan, When tip dipilih, Then hanya satu tampil dengan prioritas: geser kiri/kanan, lalu "swap places" matahari, lalu "swap places" backlight, lalu "harsh sun", lalu "golden hour".
- Given debug nyala, When kamera berjalan, Then panel menampilkan status backlit dan tip saat ini.

**Tech notes:** `BacklightController` (logika murni) dan `LuminanceMeter` mengukur terang wajah, frame, dan background kiri/kanan dari pixel buffer di `videoQueue`. `LightTip.choose` memilih satu tip dari `BacklightController` dan `SunGuidance`; `LightingCoordinator` menyimpannya di satu properti `tip`. Tidak ada perubahan pada `AVCaptureDevice`.

### S1 · Posisi berdiri dari arah matahari (SunKit)

**Type:** Spike lalu Story · **Priority:** Medium · **Estimate:** Spike 3, Story 5

**Story:** Sebagai fotografer di luar ruangan, saya ingin tahu harus menghadap ke mana, supaya wajah teman kena cahaya bagus dan tidak backlight.

**Acceptance Criteria**

- Given izin lokasi diberikan, siang hari, dan frame sangat terang (outdoor), When kamera menghadap ± 45° ke arah matahari dan wajah lebih gelap dari background, Then muncul kalimat: "Swap places so the sun is behind you."
- Given matahari tinggi (> 60° di atas horizon), When ada orang di frame, Then muncul saran: "Harsh sun overhead. Find some shade."
- Given matahari di samping kamera (45°–135°), When ada orang di frame, Then tidak ada saran matahari (cahaya samping bagus).
- Given izin lokasi ditolak, malam hari, atau indoor (frame tidak terang), When kamera berjalan, Then fitur diam dan tidak ada saran.
- Given saran sudah muncul, When posisi berubah sesuai saran, Then saran hilang.
- Given 30 menit sebelum matahari terbenam (golden hour), When kamera dibuka, Then app boleh memberi tahu "Golden hour" sekali.

**Tech notes:** [SunKit](https://swiftpackageregistry.com/Sunlitt/SunKit) 2.8.1 (Apache-2.0, minta atribusi, hitung lokal tanpa internet, butuh CoreLocation) memberi azimuth, ketinggian matahari, dan golden hour. Arah kamera belakang dari Core Motion dengan acuan `xTrueNorthZVertical` (sumbu −z perangkat), bukan heading kompas biasa (yang mengikuti sisi atas HP). Spike: cek akurasi arah di lapangan dan kalibrasi kompas. Lokasi tidak disimpan; izin "When In Use" saja. Awan tidak terbaca tanpa data cuaca, jadi syaratnya tetap terang frame + kontras wajah.
