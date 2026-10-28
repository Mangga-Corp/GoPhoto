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

Titik exposure sudah di wajah (sudah jalan). X1 menambah terang kalau wajah masih gelap; S1 mencegah backlight sejak awal dengan memberi tahu posisi berdiri.

### X1 · ISO & shutter otomatis saat backlight

**Type:** Story · **Priority:** High · **Estimate:** 3

**Story:** Sebagai orang yang difoto, saya ingin wajah saya tetap terang walau membelakangi langit, supaya foto tidak perlu diedit.

**Acceptance Criteria**

- Given wajah terdeteksi dan terang rata-rata wajah jauh di bawah terang frame (backlight), When kamera menyesuaikan, Then bias exposure naik bertahap (maks +1 EV) sampai terang wajah mendekati target.
- Given bias naik, When kamera mengatur shutter, Then shutter tidak lebih lambat dari ± 1/60 detik; kekurangan cahaya ditutup dengan ISO.
- Given backlight hilang atau orang tidak terdeteksi, When 1 detik berlalu, Then bias kembali ke 0.
- Given langit jadi putih karena bias, When hasil dinilai, Then itu diterima: wajah jadi prioritas.
- Given debug nyala, When kamera berjalan, Then panel menampilkan bias, ISO, dan shutter saat ini.

**Tech notes:** ukur terang wajah vs frame dari pixel buffer di `videoQueue` (rata-rata area, misal `CIAreaAverage` di frame kecil, tiap ± 0,5 detik); `exposureTargetBias` lewat `setExposureTargetBias` dalam batas `minExposureTargetBias`…`maxExposureTargetBias`; batas shutter dari A2. Hindari mode exposure custom penuh agar auto-exposure tetap jalan.

### S1 · Posisi berdiri dari arah matahari (SunKit)

**Type:** Spike lalu Story · **Priority:** Medium · **Estimate:** Spike 3, Story 5

**Story:** Sebagai fotografer di luar ruangan, saya ingin tahu harus menghadap ke mana, supaya wajah teman kena cahaya bagus dan tidak backlight.

**Acceptance Criteria**

- Given izin lokasi diberikan, siang hari, dan frame sangat terang (outdoor), When kamera menghadap ± 45° ke arah matahari dan wajah lebih gelap dari background, Then muncul kalimat: "Swap places so the sun is behind you."
- Given matahari tinggi (> 60° di atas horizon), When ada orang di frame, Then muncul saran: "Harsh sun overhead. Find some shade."
- Given matahari di samping kamera (45°–135°), When ada orang di frame, Then tidak ada saran (cahaya samping bagus).
- Given izin lokasi ditolak, malam hari, atau indoor (frame tidak terang), When kamera berjalan, Then fitur diam dan tidak ada saran.
- Given saran sudah muncul, When posisi berubah sesuai saran, Then saran hilang.
- Given 30 menit sebelum matahari terbenam (golden hour), When kamera dibuka, Then app boleh memberi tahu "Golden hour" sekali.

**Tech notes:** [SunKit](https://swiftpackageregistry.com/Sunlitt/SunKit) 2.8.1 (Apache-2.0, minta atribusi, hitung lokal tanpa internet, butuh CoreLocation) memberi azimuth, ketinggian matahari, dan golden hour. Arah kamera belakang dari Core Motion dengan acuan `xTrueNorthZVertical` (sumbu −z perangkat), bukan heading kompas biasa (yang mengikuti sisi atas HP). Spike: cek akurasi arah di lapangan dan kalibrasi kompas. Lokasi tidak disimpan; izin "When In Use" saja. Awan tidak terbaca tanpa data cuaca, jadi syaratnya tetap terang frame + kontras wajah.
