import Foundation

/// 调用系统自带的 screencapture 工具框选屏幕区域
enum ScreenCapture {
    /// 让用户框选一块屏幕区域，返回 PNG 数据；用户按 Esc 取消或截屏失败时返回 nil。
    /// 首次使用时系统可能会要求授予“屏幕录制”权限。
    static func captureInteractively() async -> Data? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vision-capture-\(UUID().uuidString).png")

        return await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            // -i 交互式框选，-x 不播放快门声
            process.arguments = ["-i", "-x", url.path]
            process.terminationHandler = { _ in
                let data = try? Data(contentsOf: url)
                try? FileManager.default.removeItem(at: url)
                continuation.resume(returning: data)
            }
            do {
                try process.run()
            } catch {
                // 启动失败时 terminationHandler 不会被调用
                continuation.resume(returning: nil)
            }
        }
    }
}
