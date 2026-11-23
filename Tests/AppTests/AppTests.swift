@testable import VisionServer
import XCTVapor
import Testing

@Suite("App Tests")
struct AppTests {
    private func withApp(_ test: (Application) async throws -> ()) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await test(app)
        }
        catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("健康检查接口返回 200")
    func health() async throws {
        try await withApp { app in
            try await app.test(.GET, "health", afterResponse: { res async in
                #expect(res.status == .ok)
            })
        }
    }

    @Test("缺少图片参数时返回 400")
    func classifyWithoutImage() async throws {
        try await withApp { app in
            try await app.test(.POST, "vision/classify", afterResponse: { res async in
                #expect(res.status == .badRequest)
            })
        }
    }
}
