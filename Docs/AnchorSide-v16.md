# Anchor side (PresetAnalysis v16)

Asal: debugphoto (anchor-side-v3 + agregat robust + gaya). Belum di-commit.

## Logika
- Hanya **shot variant** (foto berdiri, satu ukuran shot). Analisis utama, varian framing, varian duduk tetap pakai voting garis mata lama.
- Anchor per ukuran shot: full → **lutut**, three-quarter → **dada** (garis bahu, kalau tidak ada pakai leher), half → **mata**, quarter → tidak ada (pakai logika lama).
- Tiap foto voting kamera **di atas / di bawah** anchor (yang ragu tetap ikut). Seri = tidak dipakai, kembali ke logika lama.
- Hanya foto di sisi pemenang yang dipakai. Kalau ≥ 6 foto: dibagi 1–3 **gaya** (split 1-D sudut anchor, tiap gaya ≥ 3 foto, tiap tambahan gaya harus menjelaskan ≥ 15% sebaran lagi, median gaya yang berdampingan berjarak ≥ median σ). Diambil gaya dengan foto terbanyak.
- Target untuk `GuideFlow` tidak berubah bentuknya: `eyeElevation` = median kamera-vs-mata, tilt = median pitch dari foto terpilih. `GuideFlow` tetap memandu berdasarkan mata.
- `eyeSideSource = taste`; sisinya ditentukan dari tanda median sudut mata.

## File
| File | Perubahan |
|---|---|
| `gophoto/Core/PreferenceAnalysis/Pipeline/AnchorSide.swift` | baru: titik anchor, sudut + σ, voting, gaya |
| `gophoto/Core/PreferenceAnalysis/Pipeline/PreferenceAnalyzer.swift` | `build(... shot:)`, `eyeSide(... shot:)` jalur anchor, `EyeSideResult.anchor/weightedElevation` |
| `gophoto/Core/PreferenceAnalysis/Pipeline/PresetAnalysis.swift` | `currentVersion` 15 → 16 (preset dianalisis ulang); field debug `anchorReference`, `anchorAbove/Below`, `anchorStyleCount`, `anchorTargetPhotoCount`, `eyeElevationWeighted` |
| `gophoto/Core/PreferenceAnalysis/CameraAngle/GeoCalib/GeoCalibAngleInterpreter.swift` | `CameraAngleMethodDetail.calibration` + `focalLength35mm` |
| `gophoto/Features/Camera/Components/GuideDebugPanel.swift` | baris target: `[knee 29↑/2↓ · style 12 of 3 · eyes med … w …]` |

# v17: tinggi HP dalam satuan wajah + cek potongan badan

| Sebelum | Sesudah | File |
|---|---|---|
| Tinggi HP dinilai dalam derajat (±3°/±5°) → bisa diakali dengan maju-mundur | Dinilai dalam **satuan wajah**: (y mata − y horizon) / tinggi wajah. Toleransi ±0,4 wajah (≈ ±8 cm), dikali `heightFacesScale` supaya batas enter/exit/break yang lama tetap dipakai | `GuideFlow.swift`, `PreferenceAnalyzer.swift` (`EyeVote.faces`, `facesTarget`), `PresetAnalysis.eyeOffsetFaces` |
| Jarak hanya dinilai dari ukuran → full body bisa lolos sebagai 3/4 | **Cek potongan badan** dari pose live (sendi asli, bukan asumsi proporsi): 3/4 → mata kaki kelihatan = maju, pinggul keluar frame = mundur; half → lutut kelihatan = maju; quarter → pinggul kelihatan = maju | `PersonDetector.swift` (`visibleJoints`), `GuideFlow.cutGuard`, `CameraViewModel.swift` |
| — | Batas angkat HP: `maxLiftAboveEyes / faceHeightMeters` = 1,5 wajah | `GuideFlow.swift` |
| — | Panel debug: `faces +x / +y (used)` dan alasan potongan badan | `GuideDebugPanel.swift` |

- Target satuan wajah = median `horizonCue.offsetInHeadHeights` dari foto yang sama dengan target sudut.
- Fallback: preset tanpa wajah terbaca → tetap pakai derajat. Pose live yang lebih tua dari 1 detik → cek potongan menunggu.
- `PresetAnalysis.currentVersion` 17 → semua preset dianalisis ulang.

# Zoom otomatis: halus + FOV ikut zoom

| Sebelum | Sesudah | File |
|---|---|---|
| `verticalFOV` diambil sekali di zoom 1x, padahal frame sudah ter-zoom → horizon, sudut mata, jarak salah saat zoom | FOV per frame = 2·atan(tan(FOV1x/2)/zoom frame itu) | `CameraService.swift` (`effectiveFOV`, `videoDevice`) |
| Zoom loncat (`videoZoomFactor = x`) | `ramp(toVideoZoomFactor:withRate: 1.0)` | `CameraService.applyZoom` |
| Target dibatasi 0,5×/detik tiap deteksi → zoom bertangga | Satu target per keputusan, kecepatan dari ramp | `CameraViewModel.evaluateAdaptiveFOV` |
| Dinilai saat zoom bergerak / frame lama | Tunggu zoom diam + 0,3 s; sampel di-reset saat zoom berubah (juga snapshot diam) | `CameraViewModel` (`recordZoom`, `zoomSettled`) |
| Kotak orang 1 frame, deadband 5% | Median 5 frame (min 3), deadband 10% | `CameraViewModel`, `AdaptiveFOV.deadband` |
| Kaki kena tepi → zoom out total → zoom in lagi (ping-pong) | Zoom out /1,12 per langkah; zoom in dibatasi supaya ada ruang 3% di tepi yang bebas di referensi | `AdaptiveFOV.swift` (`edgeStep`, `edgeRoom`) |

`PersonDetection` kini membawa `zoomFactor` dan `isZooming`.

# Blur latar (sementara, mode developer / appMode 2)

| File | Perubahan |
|---|---|
| `gophoto/Core/Camera/BokehProcessor.swift` | baru: segmentasi orang Vision (`.accurate`) → `CIMaskedVariableBlur` di latar; kekuatan 0,5 × maks (maks = 3% sisi pendek), tepi di-feather |
| `gophoto/Features/Camera/ViewModels/CameraViewModel.swift` | `bokehEnabled` (default off); setelah foto asli tersimpan, kalau on → simpan salinan blur (galeri + Foto) |
| `gophoto/Features/Camera/Views/CameraView.swift` | tombol Blur Off / On di kanan shutter, hanya `isDeveloper` (appMode 2) |

- v2 blur (2026-11-06): maks 3% → 1% sisi pendek (setengah = ~15 px, dulu ~45 px); mask orang dilebarkan 0,3% lalu feather 0,15%; orang asli ditempel lagi lewat `CIBlendWithMask` (tidak ikut blur).

- Blur Apple (2026-11-06): Blur On → `CameraService.setDepthCapture(true)` pindah ke kamera virtual (dual-wide/dual/triple), zoom app 1× = switch-over lensa utama (`zoomScale`), depth + portrait matte diembed di foto; salinan blur dirender `CIContext.depthBlurEffectFilter` (aperture default Apple, nilai dicatat di timing). Tanpa depth → blur custom v2. Blur Off → kembali ke kamera utama.

# Giliran zoom ↔ guide (2026-11-07)

| # | Masalah | Perbaikan | File |
|---|---|---|---|
| 1 | Zoom dan "maju/mundur" jalan bersamaan | Selama zoom bergerak/menetap/akan berubah (`zoomWillHandleSize`), langkah jarak menampilkan `.waitForZoom` ("Hold on, zooming"); minta jalan hanya kalau zoom mentok | `GuideFlow` (1c), `CameraViewModel` |
| 2 | Potongan badan vs zoom berlawanan | `AdaptiveFOV` menjalankan `GuideFlow.cutGuard` lebih dulu (zoom in/out ×1,12); zoom-in karena potongan menyimpan `cutFloorZoom`, zoom-out karena ukuran tidak boleh di bawahnya | `AdaptiveFOV`, `CameraViewModel` |
| 3 | Zoom jalan lagi setelah siap | `adaptiveFOVMayAct` hanya saat langkah aktif = jarak (zoom terkunci setelah jarak selesai) | `CameraViewModel` |
| 4 | Snapshot tercampur antar-zoom | Snapshot hanya dari frame zoom diam, direset saat zoom berubah, menyimpan FOV-nya sendiri | `CameraViewModel` |
| 5 | Pindah langkah tanpa stabil | Langkah OK hanya setelah 0,4 s di toleransi; sebelumnya `.keepSteady` ("Hold it there") | `GuideFlow.judge`, `GuideInstruction`, `InstructionPill`, `GuidanceMotion` |

- Rotasi (2026-11-07): salinan blur Apple berputar 90° karena orientasi dipasang dua kali (filter sudah memutar). Sekarang diputar hanya kalau bentuk output (potret/lanskap) beda dari foto tegak.
