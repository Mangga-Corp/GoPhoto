# Scene Ideas (Apple Foundation Models) — change log for AI and developers

Status: working tree on `main`, **not committed**. Ported from the GoPhotoNIMA prototype
(`~/Documents/Codex/2026-10-28/bsiak/outputs/GoPhotoNIMA 2`, see its `AI_HANDOFF.md`).

## What it does

1. Camera screen: an AI button (SF Symbol `apple.intelligence`, fallback `sparkles`) sits right of the shutter.
2. Tap → grab the current live frame (upright, long side 640 px) → one Apple Intelligence-style colour sweep
   over the camera preview (DIY SwiftUI gradients, not an Apple API, ~1.5 s). The model already runs meanwhile.
3. The ideas sheet opens full height: scanned image (pinned, 16 pt side margin) + two placeholder (skeleton) cards;
   the ideas fill in one by one when the result arrives.
4. Each idea card shows role, element, why, what to keep visible. Tapping a card selects it and opens a
   the person/photographer lines and **Skip** / **Use this idea** (both ≥ 44 pt). The staging (person outline +
   element box, same layout as the prototype guide) is drawn on the scanned image at the top of the sheet; that
   image stays pinned (max ~45% of the sheet height) while the cards scroll below. Bottom: **More ideas**
   (new model run on the same image, no new sweep) and **Scan again** (only closes the sheet → back to camera).
5. **Use this idea** shows a place-guide card under the preview (person + photographer lines, expandable, X to close).
   While a guide is on, the AI button is yellow; closing the guide (X) turns it white again. Tapping the AI
   button always starts a new scan.
6. Without tapping the AI button the camera works exactly as before (shutter, auto-save, person guide unchanged).

Pipeline: InputCheck v1 (blurry / too dark → soft block with "Find ideas anyway") → prompt V00, 1 run,
temperature 0.7 → role guard v2 → first 2 ideas → app templates for every sentence (the model only names
elements and picks a role from a fixed list). Do not edit the prompt without a new test (see prototype notes).

## Files

### New

| File | Contents |
|---|---|
| `gophoto/Core/SceneIdeas/SceneIdeasEngine.swift` | `FMSceneRole`, `FMSceneElement`, `FMSceneSurvey` (@Generable schema); `SceneIdeaAdvisor` (prompt V00, `run(_:)`, availability + error text); `SceneIdea`, `SceneIdeasResult`; `SceneText` (why/keep templates, role titles/icons); `SceneRoleGuard` v2 (frame allow-list, plain backdrop ≠ floor/ground, landmark ≠ person); `ScenePersonGuide` v1.2 (metres, phone height, shot, thirds); `SceneInputCheck` v1 (Laplacian 8×8, thresholds p90 < 0.0067 blurry, dark ≥ 0.90 too dark) |
| `gophoto/Features/Camera/Components/SceneIdeasViews.swift` | `SceneIdeasModel` (@Observable state: phase, frame, chosen idea, skipped, scanID); `SceneIdeasButton`; `SceneIdeasSheet` (image, skeletons, staggered reveal, cards); `PlaceGuideCard`; `SceneScanSweep` (one sweep over the preview, `duration` = 1.5 s); `SkeletonIdeaCard`; `SceneStagingOverlay` + `SceneSilhouette` (staging preview per role) |
| `Docs/SceneIdeas.md` | This file |

### Changed

| File | Change |
|---|---|
| `gophoto/Core/Camera/CameraService.swift` | Protocol `CameraServiceProtocol`: new `latestFrame() async -> CGImage?` with a default `nil` in a protocol extension (mocks keep compiling). `CameraService`: `frameRequest` / `frameRequestID` (video queue), extension `latestFrame()` (waits for the next frame, 2 s timeout), and `captureOutput` answers a pending request first with `FrameDownscaler.cgImage(from:longEdge: 640)` |
| `gophoto/Features/Camera/ViewModels/CameraViewModel.swift` | `sceneFrame()` → `cameraService.latestFrame()` |
| `gophoto/Features/Camera/Views/CameraView.swift` | State `sceneIdeas`, `isShowingIdeas`, `isScanningPlace`; `PlaceGuideCard` between preview and shutter when an idea is chosen; `SceneIdeasButton` as trailing overlay of the shutter row; `.overlay { SceneScanSweep }` on the preview; ideas sheet (`.presentationDetents([.large])`); `scanPlace()` |

`gophoto.xcodeproj/project.pbxproj` was already modified before this work (not part of Scene Ideas).
The project uses synchronized folders, so the new files need no project-file edits.

## Tuning points

| What | Where |
|---|---|
| Image side margin in the sheet | `SceneIdeasViews.swift`, `SceneIdeasSheet.body`, `.padding(.horizontal, 16)` |
| Sweep length / delay before the sheet | `SceneScanSweep.duration` and the `withAnimation(.easeInOut(duration: 1.4))` in `SceneScanSweep.onAppear` |
| Sweep colours | `SceneScanSweep.palette` |
| Delay between cards | `SceneIdeasSheet`, `.onChange(of: model.phase)` (150 ms first, 450 ms next) |
| Staging layout per role | `SceneStagingOverlay.spec` in `SceneIdeasViews.swift` |
| Guard word lists | `SceneRoleGuard` in `SceneIdeasEngine.swift` |
| Guide sentences | `ScenePersonGuide.lines(_:)` |
| InputCheck thresholds | `SceneInputCheck.blurThreshold`, `.darkThreshold` |

## Known limits

- Foundation does not know where an element sits in the frame (column test ≈ guessing "centre"), so guides never say left/right; the user picks the side.
- Role errors still happen (e.g. chairs or poles as leading lines); the guard only catches known patterns.
- InputCheck thresholds were set on still photos; live video frames may be softer. Watch for false "blurry".
- `LanguageModelSession.GenerationError` gives a deprecation warning on iOS 27.
- No pilot logging and no saving of results to the gallery in this app (prototype only).
