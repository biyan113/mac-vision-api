import Carbon
import Foundation

/// 全局快捷键 ⌃⌥⌘O：应用在后台时也能触发。使用 Carbon 的热键接口，不需要辅助功能权限。
final class GlobalHotKey {
    /// 快捷键被按下时在主线程发出
    static let pressedNotification = Notification.Name("VisionGlobalHotKeyPressed")
    static let displayName = "⌃⌥⌘O"

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// 注册快捷键。被其他应用占用等原因导致注册失败时返回 false。
    @discardableResult
    func register() -> Bool {
        guard hotKeyRef == nil else { return true }

        if handlerRef == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let handler: EventHandlerUPP = { _, _, _ in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: GlobalHotKey.pressedNotification, object: nil)
                }
                return noErr
            }
            InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &handlerRef)
        }

        // 签名 "VISN"
        let hotKeyID = EventHotKeyID(signature: OSType(0x5649_534E), id: 1)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_O),
            UInt32(cmdKey | optionKey | controlKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }
}
