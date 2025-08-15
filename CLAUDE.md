# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Vision API is a Swift/Vapor-based RESTful service that exposes Apple Vision framework capabilities for self-hosted image processing. The service provides OCR (text recognition) and background removal features through HTTP APIs.

**Key Technologies:**
- **Framework**: Vapor 4.x (Swift server-side web framework)
- **Platform**: macOS only (requires Apple Vision framework)
- **Swift Version**: 6.0 with strict concurrency
- **Dependencies**: VaporToOpenAPI for documentation, SwiftNIO for networking

## Development Commands

### Core Development Workflow
```bash
# Install/update dependencies
swift package resolve

# Run development server (default: localhost:8080)
swift run App

# Run with specific environment
swift run App serve --env development --hostname 0.0.0.0 --port 8080

# Build the project
swift build

# Run tests
swift test
```

### Docker Development
```bash
# Build Docker image
docker-compose build

# Start service in production mode
docker-compose up app

# Stop all services
docker-compose down
```

### Testing
```bash
# Run all tests
swift test

# Test specific target
swift test --filter AppTests
```

## Architecture Overview

### Route Structure
- **Root Path**: `/` → Redirects to Swagger UI
- **Text Detection**: `/text-detection/recognize-text` → OCR functionality
- **Image Features**: `/image-feature/background-removal` → Background removal (macOS 15.0+)
- **Documentation**: `/Swagger/index.html` → Auto-generated API docs

### Controller Architecture
The application follows a controller-based architecture:

1. **TextDetectionController**: Handles OCR operations using VNRecognizeTextRequest
2. **ImageFeatureController**: Handles background removal using VNGenerateForegroundInstanceMaskRequest (macOS 15.0+)
3. **OpenAPIController**: Generates Swagger documentation

### Request Handling Pattern
All controllers support multiple image input methods:
- **File Upload**: `imageFile` parameter (multipart/form-data)
- **Local Path**: `imagePath` parameter  
- **Remote URL**: `imageURL` parameter
- **Base64**: `imageBase64` parameter

### Vision Framework Integration
- **OCR**: Uses `VNImageRequestHandler` with `VNRecognizeTextRequest`
  - Supports multiple languages via `recognitionLanguages` 
  - Configurable accuracy with `recognitionLevel` (0=accurate, 1=fast)
- **Background Removal**: Uses `VNGenerateForegroundInstanceMaskRequest`
  - Returns PNG with transparent background
  - Requires macOS 15.0+

### Configuration
- **Max Request Size**: 20MB (configured in routes.swift)
- **Static Files**: Served from Public/ directory
- **Default Response**: Redirect to Swagger UI

## Key Implementation Details

### Error Handling
- Uses Vapor's `Abort` for HTTP errors
- Validates image data before processing
- Handles Vision framework errors gracefully

### Async/Await Pattern
All request handlers use `@Sendable` async functions for concurrency safety.

### OpenAPI Integration
- Auto-generates API documentation using VaporToOpenAPI
- Controllers use `.openAPI()` modifiers for endpoint documentation
- Request/response models conform to `@OpenAPIDescriptable`

### Platform Availability
- Core OCR features: macOS 13.0+
- Background removal: macOS 15.0+ (feature-gated in routes.swift)

## Development Guidelines

### Adding New Vision Features
1. Create new controller in `Sources/App/Controllers/`
2. Define request/response models with `@OpenAPIDescriptable`
3. Register routes in `routes.swift` with version checks if needed
4. Use consistent error handling patterns from existing controllers

### Testing Image Processing
- Test with various image formats (PNG, JPEG, HEIC)
- Verify multipart form data handling
- Test error conditions (invalid images, network failures)
- Validate Vision framework integration

### API Documentation
- All endpoints automatically appear in Swagger UI
- Use `.openAPI()` modifiers for endpoint descriptions
- Define proper Content-Type headers for responses