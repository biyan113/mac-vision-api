import Logging
import Vapor
import VisionAPI

/// 应用程序入口点
@main
enum Entrypoint {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)

        let app = try await Application.make(env)

        do {
            try await VisionAPI.configure(app)
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }

        app.logger.info("Vision API \(VisionAPI.version) — 由微信公众号 字节笔记本提供")
        try await app.execute()
        try await app.asyncShutdown()
    }
}
