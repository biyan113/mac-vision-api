import Foundation
import Vapor

/// 保存服务日志，供图形界面显示
final class ServerLogStore: @unchecked Sendable {
    static let shared = ServerLogStore()

    /// 每追加一行日志后在主线程发出，userInfo["line"] 为该行文本
    static let didAppendNotification = Notification.Name("VisionServerLogDidAppend")

    private let lock = NSLock()
    private var storage: [String] = []
    private let capacity = 2000

    private init() {}

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ line: String) {
        lock.lock()
        storage.append(line)
        if storage.count > capacity {
            storage.removeFirst(storage.count - capacity)
        }
        lock.unlock()

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: ServerLogStore.didAppendNotification,
                object: nil,
                userInfo: ["line": line]
            )
        }
    }

    func clear() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }

    /// 把进程内的日志输出接管到 ServerLogStore（同时仍打印到标准错误）。
    /// 每个进程只能调用一次，且必须在创建任何 Logger 之前调用。
    static func installAsLoggingBackend() {
        LoggingSystem.bootstrap { label in
            CapturingLogHandler(label: label)
        }
    }
}

struct CapturingLogHandler: LogHandler {
    let label: String
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .info

    init(label: String) {
        self.label = label
    }

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let text = "\(formatter.string(from: Date())) [\(level.rawValue.uppercased())] \(message)"
        ServerLogStore.shared.append(text)
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}
