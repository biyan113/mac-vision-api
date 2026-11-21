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

cd vision-web && npm ci && npm run build        # web UI
docker compose up --build        # web UI image only (nginx, proxies /api to the Mac host)
```

## Layout

- `Sources/VisionAPI/` — library target with everything. `configure.swift` (middleware + `version`), `routes.swift` (route registration, `/health`, `/capabilities`).
- `Sources/VisionAPI/Controllers/` — one `RouteCollection` per area.
- `Sources/VisionAPI/Support/` — `ServiceConfig` (env config + API key middleware), `InputResolver` (shared input handling + `Offload`), `VisionSupport` (shared models and helpers).
- `Sources/App/entrypoint.swift` — thin executable that calls `VisionAPI.configure`.
- `Tests/VisionAPITests/` — XCTVapor tests.
- `Public/Swagger/` — Swagger UI static files; reads `/Swagger/swagger.json`.
- `.github/workflows/` — `ci.yml` (macOS build/test, web build), `release.yml` (tagged release: macOS tarball + web image to GHCR).

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
