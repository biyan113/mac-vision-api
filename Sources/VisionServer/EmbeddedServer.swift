import Foundation
import Vapor

/// 可在其他进程（例如图形界面）内启动和停止的 Vision API 服务
public actor EmbeddedServer {
    private var app: Application?

    public init() {}

    public var isRunning: Bool {
        app != nil
    }

    /// 启动服务。已在运行时不做任何事。
    /// - Parameters:
    ///   - hostname: 监听地址，例如 127.0.0.1 或 0.0.0.0
    ///   - port: 监听端口
    ///   - workingDirectory: 包含 Public 目录的工作目录；为 nil 时使用进程当前目录
    public func start(hostname: String, port: Int, workingDirectory: String? = nil) async throws {
        guard app == nil else { return }

        // 不解析宿主进程的命令行参数
        let environment = Environment(name: "development", arguments: ["vapor"])
        let app = try await Application.make(environment)
        do {
            if let workingDirectory = workingDirectory {
                app.directory = DirectoryConfiguration(workingDirectory: workingDirectory)
            }
            app.http.server.configuration.hostname = hostname
            app.http.server.configuration.port = port
            try await configure(app)
            try await app.asyncBoot()
            try await app.server.start(address: .hostname(hostname, port: port))
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        self.app = app
    }

    /// 停止服务并释放端口。未在运行时不做任何事。
    public func stop() async {
        guard let app = app else { return }
        self.app = nil
        await app.server.shutdown()
        try? await app.asyncShutdown()
    }
}
