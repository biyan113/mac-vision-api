# Vision API

## Introduction
Self-Host, Out of the box OCR and Image Classification and more.

Vision API is an open-source project built with the Vapor framework, designed to expose various machine learning methods from Apple’s Vision framework as a RESTful API. This project aims to make it easier for independent developers and small companies to leverage powerful machine learning models for tasks like image classification, object detection, and text recognition, all hosted and self-managed.

## Project Goals

- Provide easy-to-use APIs for utilizing machine learning models from Apple Vision framework.
- Allow developers to self-host the API, reducing reliance on third-party cloud services.
- Enable seamless integration of machine learning and image analysis into developers' workflows through simple RESTful interfaces.

## Features

- **Text Recognition (OCR)**: Extract text from images using Optical Character Recognition (OCR).
- **Background Removal**: Remove the background from images.
- ~~**Image Classification**: Use Vision framework for image classification.~~
- ~~**Object Detection**: Detect objects and facial features within images.~~
- ~~**Barcode Recognition**: Scan and decode barcodes and QR codes in images.~~

For more feature visit: [Vision Framwork](https://developer.apple.com/documentation/vision/)

## Getting Started

### Prerequisites

- macOS only
- Vapor

### Installation

1. Clone the project to your local machine:
   ```bash
   git clone https://github.com/biyan113/mac-vision-api
   cd mac-vision-api
   ```

2. Install dependencies:
   ```bash
   swift package resolve
   ```

3. Run the project:
   ```bash
   swift run App
   ```

   This will start the local server, which will listen on `http://localhost:8080` by default.

### Desktop App (AppKit)

A native AppKit app is included. It calls the Vision framework directly, so the HTTP server does not need to be running, and it can also start and stop the API server from its own window or menu bar icon.

```bash
# Run directly
swift run VisionApp

# Or build a double-clickable bundle at .build/VisionApp.app (plus a zip for distribution)
./scripts/build-app.sh
open .build/VisionApp.app
```

What it does:

- Text recognition, background removal (macOS 14+), image classification, object detection, barcode scanning
- Open, drag in or paste (⌘V) images and PDFs; page through a PDF, extract its embedded text, or OCR every page
- Capture a screen region and recognize its text (⇧⌘2)
- Click a detected box to select the matching result line, and the other way round
- Copy or save results, export JSON in the same shape as the API responses
- Batch-process many files into an output folder (⌘B)
- Start and stop the API server in-process, with a log view (⇧⌘L)
- Chinese and English interface

`scripts/build-app.sh` reads `CODESIGN_IDENTITY` and `NOTARY_PROFILE` for Developer ID signing and notarization; without them the app is ad-hoc signed for local use only.

### Using the API

Once the server is running, you can send HTTP requests to interact with the API.

For more API detail visit: http://localhost:8080/Swagger/index.html

## TODO
- [ ] Text Area Recognition
- [ ] Image Classification
- [ ] Face and body detection
- [ ] Barcode detection
- [ ] Image aesthetics analysis
- [ ] Animal detection
- [x] Background removal

## Contributing

Contributions are welcome! If you have suggestions for features or if you encounter issues, feel free to submit an issue or pull request.