# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Vision API is a Swift/Vapor service that exposes on-device macOS capabilities (Apple Vision, PDFKit, Speech, Translation) as a REST API. It is macOS only: the backend cannot be built or run on Linux, so there is no backend Docker image. Apple Intelligence / Foundation Models are deliberately not used.

- **Framework**: Vapor 4.x, VaporToOpenAPI for docs
- **Swift**: tools version 6.0, language mode 5 with strict concurrency checking
- **Minimum OS**: macOS 13; newer features are gated at runtime
- **Frontend**: `vision-web/` (React + Vite), optional

## Commands

```bash
swift build                      # build
swift test                       # run tests
swift test --filter VisionAPITests/testHealth   # single test
swift run App serve --hostname 127.0.0.1 --port 8080
swift run VisionApp              # AppKit desktop app
./scripts/build-app.sh           # package .build/VisionApp.app + zip (local only, never in CI)
swift run VisionMCP              # MCP server over stdio

cd vision-web && npm ci && npm run build        # web UI
docker compose up --build        # web UI image only (nginx, proxies /api to the Mac host)
```

## Layout

- `Sources/VisionAPI/` — library target with everything. `configure.swift` (middleware + `version`), `routes.swift` (route registration, `/health`, `/capabilities`).
- `Sources/VisionAPI/Controllers/` — one `RouteCollection` per area.
- `Sources/VisionAPI/Support/` — `ServiceConfig` (env config + API key middleware), `InputResolver` (shared input handling + `Offload`), `VisionSupport` (shared models and helpers).
- `Sources/App/entrypoint.swift` — thin executable that calls `VisionAPI.configure`.
- `Tests/VisionAPITests/` — XCTVapor tests.
- `Sources/VisionCore/` — library with no Vapor and no AppKit: `VisionEngine` (OCR, background removal, classify, detect, barcodes), `PDFEngine`, `SearchablePDF`, `Redactor`, `TextInsights`. Functions take `Data`, run synchronously and throw. Used by the desktop app and the MCP server. It overlaps with logic inside the `VisionAPI` controllers; the server does not use it.
- `Sources/VisionApp/` — pure-AppKit desktop app, programmatic layout (no storyboards, no SwiftUI). `MainWindowController` owns the window, unified toolbar and split view; `SidebarViewController` navigates between `RecognitionViewController`, `BatchViewController` and `ServerViewController`. `EmbeddedServer` runs `VisionAPI.configure` in-process. UI strings are written in code as `L("中文", "English")`, not in resource bundles.
- `Sources/VisionMCP/main.swift` — MCP server (JSON-RPC over stdio) exposing `VisionCore` as tools.
- `Tests/VisionCoreTests/` — XCTest; fixtures (text image, QR code, PDF) are generated at runtime.
- `scripts/build-app.sh` — packages the desktop app; optional signing and notarization via environment variables.
- `vision-web/src/` — web UI. One page component per feature in `components/`; all HTTP calls go through `services/api.ts` (shared axios instance, API key header, `errorMessage`); `components/ui/Common.tsx` has shared page pieces; `hooks/useCapabilities.ts` reads `/capabilities` to flag unsupported features. Uses `HashRouter` so it works when served by the backend.
- `Public/Swagger/` — Swagger UI static files; reads `/Swagger/swagger.json`.
- `.github/workflows/` — `ci.yml` (macOS build/test, web build), `release.yml` (tagged release: macOS tarball + web image to GHCR).

## iOS app (`ios/`)

A companion iPhone app ("译镜", LensTranslate). It does not call this service; it uses the same system frameworks directly on iOS.

- `ios/LensCore/` — UI-independent logic as a Swift package (coordinate mapping, lemmatizer, vocab SQLite store, wordbook). Has unit tests that run on macOS: `swift test --package-path ios/LensCore`. Put anything testable here.
- `ios/LensTranslate/` — SwiftUI app (iOS 18+, Swift 5 language mode). `App/` state and languages, `Camera/`, `Services/` (Vision OCR, Translation bridge, speech), `Views/`.
- `ios/project.yml` — XcodeGen spec. The `.xcodeproj` and `Info.plist` are generated and git-ignored: `cd ios && xcodegen generate`.
- Translation goes through `.translationTask` in `RootView`; `TranslationBridge` feeds requests into that session via an `AsyncStream`. Do not create `TranslationSession` directly.
- The system Translation framework does not support Malay; `LanguageOption.all` lists what was measured on macOS 26.
- Nothing under `ios/` can be built on Linux. CI (`ios` job) is the only compile check: it runs the LensCore tests, builds for the simulator, verifies the app bundle, launches it in a simulator and uploads a screenshot. Camera, microphone and translation behaviour cannot be verified in CI.

## Tools

- `tools/vocab/build_vocab.py` — merges the English Vocabulary Vault spreadsheets into the SQLite database the iOS app imports. The data is CC BY-NC-SA 4.0; never commit the generated database.

## Routes

| Path | Controller | Min macOS |
|---|---|---|
| `/text-detection/recognize-text`, `/supported-languages` | TextDetectionController | 13 |
| `/text-detection/recognize-document`, `/vision/lens-smudge` | DocumentController | 26 |
| `/vision/classify`, `detect-objects`, `scan-barcode`, `detect-faces`, `detect-body-pose`, `detect-hand-pose`, `saliency`, `detect-rectangles`, `detect-horizon` | VisionAnalysisController | 13 |
| `/vision/aesthetics` | AestheticsController (in ImageFeatureController.swift) | 15 |
| `/image-feature/background-removal` | ImageFeatureController | 14 |
| `/pdf/render`, `/pdf/extract-text` | PDFController | 13 |
| `/speech/transcribe`, `/speech/supported-locales` | SpeechController | 26 |
| `/translation/translate`, `/translation/supported-languages` | TranslationController | 26 |

## Conventions

- **Inputs**: always go through `InputResolver`. `InputResolver.image(from:)` handles `imageFile` / `imagePath` / `imageURL` / `imageBase64`; `resolve(from:prefix:label:)` does the same for other prefixes (`pdf`, `audio`). Do not read paths or fetch URLs directly in controllers: the resolver enforces `allowLocalFiles` and `allowPrivateURLs`.
- **Blocking work**: synchronous Vision / PDFKit / CoreGraphics calls run inside `Offload.run(req) { ... }` (NIO thread pool). Never call `.wait()` in a handler.
- **Errors**: throw `Abort`. 400 for bad input, 403 for disabled input modes, 422 when the file cannot be processed or contains nothing usable. Use `VisionSupport.perform` to map Vision errors to 422. Do not return errors inside a 200 body.
- **Availability gating**: annotate the controller with `@available(macOS N, *)` and register it under `if #available` in `routes.swift`. Code using macOS 26 SDK symbols must also be wrapped in `#if compiler(>=6.2)` so older Xcode versions still build. Update `Capabilities.current` when adding a gated feature.
- **OpenAPI**: every route gets `.openAPI(...)`; request models used only for documentation are marked `@OpenAPIDescriptable`.
- **Coordinates**: normalized 0–1, origin bottom-left (`BoundingBox`, `Point2D`, `KeyPoint`).
- **Config**: `ServiceConfig` is read from `VISION_API_KEY`, `VISION_ALLOW_LOCAL_FILES`, `VISION_ALLOW_PRIVATE_URLS`, `VISION_MAX_BODY_SIZE`. Tests inject it via `configure(app, config:)`.

## Adding a feature

1. Add a controller (or a handler in an existing one) using `InputResolver` and `Offload`.
2. Register it in `routes.swift` with the right availability check; update `Capabilities`.
3. Add a test for input validation in `Tests/VisionAPITests/`.
4. Document it in `README.md` and `API_DOCUMENTATION.md`.
5. If it should be usable from the web UI, add the API call to `vision-web/src/services/api.ts` and a page (or a mode in `VisionAnalysisPage.tsx`).
