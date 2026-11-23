@testable import VisionAPI
import XCTVapor

final class VisionAPITests: XCTestCase {
    private func withApp(
        config: ServiceConfig = ServiceConfig(),
        _ test: (Application) async throws -> Void
    ) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app, config: config)
            try await test(app)
        } catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    func testHealth() async throws {
        try await withApp { app in
            try await app.test(.GET, "health", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let body = try res.content.decode(HealthStatus.self)
                XCTAssertEqual(body.status, "healthy")
                XCTAssertEqual(body.version, VisionAPI.version)
            })
        }
    }

    func testCapabilities() async throws {
        try await withApp { app in
            try await app.test(.GET, "capabilities", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let caps = try res.content.decode(Capabilities.self)
                XCTAssertTrue(caps.textRecognition)
            })
        }
    }

    func testOpenAPIDocumentIsServed() async throws {
        try await withApp { app in
            try await app.test(.GET, "Swagger/swagger.json", afterResponse: { res async in
                XCTAssertEqual(res.status, .ok)
                XCTAssertTrue(res.body.string.contains("recognize-text"))
            })
        }
    }

    func testMissingImageReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.POST, "text-detection/recognize-text", beforeRequest: { req in
                try req.content.encode(["recognitionLevel": "0"])
            }, afterResponse: { res async in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testLocalPathDisabledByDefault() async throws {
        try await withApp { app in
            try await app.test(.POST, "text-detection/recognize-text", beforeRequest: { req in
                try req.content.encode(["imagePath": "/etc/hosts"])
            }, afterResponse: { res async in
                XCTAssertEqual(res.status, .forbidden)
            })
        }
    }

    func testPrivateURLBlockedByDefault() async throws {
        try await withApp { app in
            try await app.test(.POST, "vision/classify", beforeRequest: { req in
                try req.content.encode(["imageURL": "http://127.0.0.1:1/secret.png"])
            }, afterResponse: { res async in
                XCTAssertEqual(res.status, .forbidden)
            })
        }
    }

    func testInvalidBase64ReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(.POST, "vision/scan-barcode", beforeRequest: { req in
                try req.content.encode(["imageBase64": "!!!"])
            }, afterResponse: { res async in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testInvalidImageReturnsUnprocessable() async throws {
        try await withApp { app in
            try await app.test(.POST, "text-detection/recognize-text", beforeRequest: { req in
                try req.content.encode(["imageBase64": Data("not an image".utf8).base64EncodedString()])
            }, afterResponse: { res async in
                XCTAssertEqual(res.status, .unprocessableEntity)
            })
        }
    }

    func testAPIKeyEnforced() async throws {
        try await withApp(config: ServiceConfig(apiKey: "secret")) { app in
            // 健康检查不需要密钥
            try await app.test(.GET, "health", afterResponse: { res async in
                XCTAssertEqual(res.status, .ok)
            })
            try await app.test(.GET, "capabilities", afterResponse: { res async in
                XCTAssertEqual(res.status, .unauthorized)
            })
            try await app.test(.GET, "capabilities", headers: ["X-API-Key": "wrong"], afterResponse: { res async in
                XCTAssertEqual(res.status, .unauthorized)
            })
            try await app.test(.GET, "capabilities", headers: ["X-API-Key": "secret"], afterResponse: { res async in
                XCTAssertEqual(res.status, .ok)
            })
            try await app.test(.GET, "capabilities", headers: ["Authorization": "Bearer secret"], afterResponse: { res async in
                XCTAssertEqual(res.status, .ok)
            })
        }
    }

    func testPrivateHostDetection() {
        for host in ["localhost", "127.0.0.1", "10.1.2.3", "192.168.0.1", "172.16.5.5", "169.254.169.254", "::1", "[::1]", "printer.local"] {
            XCTAssertTrue(InputResolver.isPrivateHost(host), host)
        }
        for host in ["example.com", "8.8.8.8", "172.32.0.1", "1.1.1.1"] {
            XCTAssertFalse(InputResolver.isPrivateHost(host), host)
        }
    }
}
