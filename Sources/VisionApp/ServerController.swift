import AppKit
import VisionServer

/// 管理内嵌 API 服务的启动与停止，并把状态变化通知给界面
@MainActor
final class ServerController {
    enum State {
        case stopped
        case starting
        case running
        case stopping
    }

    static let shared = ServerController()

    /// 状态变化后在主线程发出
    static let stateDidChangeNotification = Notification.Name("ServerControllerStateDidChange")

    private let server = EmbeddedServer()

    private(set) var state: State = .stopped {
        didSet {
            NotificationCenter.default.post(name: ServerController.stateDidChangeNotification, object: self)
        }
    }

    /// 最近一次启动失败的原因
    private(set) var lastError: String?
    /// 服务正在使用的地址（启动时从偏好设置读取）
    private(set) var hostname = Settings.serverHostname
    private(set) var port = Settings.serverPort

    private init() {}

    var isRunning: Bool {
        state == .running
    }

    /// 浏览器中访问服务用的地址
    var baseURL: URL? {
        let host = hostname == "0.0.0.0" ? "127.0.0.1" : hostname
        return URL(string: "http://\(host):\(port)/")
    }

    var statusText: String {
        switch state {
        case .stopped:
            if let lastError = lastError {
                return L("启动失败：", "Failed to start: ") + lastError
            }
            return L("服务未运行", "Server is stopped")
        case .starting: return L("正在启动…", "Starting…")
        case .running: return L("正在运行：", "Running at ") + "http://\(hostname):\(port)"
        case .stopping: return L("正在停止…", "Stopping…")
        }
    }

    func start() {
        guard state == .stopped else { return }
        let host = Settings.serverHostname
        let portNumber = Settings.serverPort
        hostname = host
        port = portNumber
        lastError = nil
        state = .starting

        let workingDirectory = ServerController.publicWorkingDirectory()
        Task {
            do {
                try await self.server.start(hostname: host, port: portNumber, workingDirectory: workingDirectory)
                self.state = .running
            } catch {
                self.lastError = "\(error)"
                self.state = .stopped
            }
        }
    }

    func stop() {
        guard state == .running else { return }
        state = .stopping
        Task {
            await self.server.stop()
            self.state = .stopped
        }
    }

    func toggle() {
        switch state {
        case .stopped: start()
        case .running: stop()
        case .starting, .stopping: break
        }
    }

    /// 退出应用前调用：等待服务完全停止
    func stopAndWait() async {
        await server.stop()
        state = .stopped
    }

    /// 查找包含 Public 目录的工作目录：优先使用 .app 包内的资源目录，其次是当前目录
    private static func publicWorkingDirectory() -> String? {
        let fileManager = FileManager.default
        var candidates: [String] = []
        if let resourcePath = Bundle.main.resourcePath {
            candidates.append(resourcePath)
        }
        candidates.append(fileManager.currentDirectoryPath)

        for candidate in candidates {
            var isDirectory: ObjCBool = false
            let publicPath = (candidate as NSString).appendingPathComponent("Public")
            if fileManager.fileExists(atPath: publicPath, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate
            }
        }
        return nil
    }
}
