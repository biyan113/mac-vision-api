import Foundation

enum InterfaceLanguage: String, CaseIterable {
    case system
    case chinese
    case english

    var title: String {
        switch self {
        case .system: return L("跟随系统", "System Default")
        case .chinese: return "简体中文"
        case .english: return "English"
        }
    }
}

/// OCR 可选语言
enum OCRLanguage {
    static let options: [(title: String, codes: [String])] = [
        (L("自动检测语言", "Detect Language"), []),
        ("简体中文 + English", ["zh-Hans", "en-US"]),
        ("繁體中文 + English", ["zh-Hant", "en-US"]),
        ("English", ["en-US"]),
        ("日本語", ["ja-JP"]),
        ("한국어", ["ko-KR"]),
    ]

    static func codes(at index: Int) -> [String] {
        guard options.indices.contains(index) else { return [] }
        return options[index].codes
    }
}

/// 保存在 UserDefaults 中的偏好设置
enum Settings {
    private enum Key {
        static let interfaceLanguage = "interfaceLanguage"
        static let defaultFeature = "defaultFeature"
        static let ocrLanguageIndex = "ocrLanguageIndex"
        static let ocrFastMode = "ocrFastMode"
        static let serverHostname = "serverHostname"
        static let serverPort = "serverPort"
        static let startServerAtLaunch = "startServerAtLaunch"
        static let hidesMenuBarIcon = "hidesMenuBarIcon"
        static let serverAPIKey = "serverAPIKey"
        static let disablesGlobalHotKey = "disablesGlobalHotKey"
    }

    static var interfaceLanguage: InterfaceLanguage {
        get { InterfaceLanguage(rawValue: UserDefaults.standard.string(forKey: Key.interfaceLanguage) ?? "") ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.interfaceLanguage) }
    }

    static var defaultFeature: VisionFeature {
        get { VisionFeature(rawValue: UserDefaults.standard.integer(forKey: Key.defaultFeature)) ?? .ocr }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.defaultFeature) }
    }

    static var ocrLanguageIndex: Int {
        get {
            let index = UserDefaults.standard.integer(forKey: Key.ocrLanguageIndex)
            return OCRLanguage.options.indices.contains(index) ? index : 0
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.ocrLanguageIndex) }
    }

    static var ocrFastMode: Bool {
        get { UserDefaults.standard.bool(forKey: Key.ocrFastMode) }
        set { UserDefaults.standard.set(newValue, forKey: Key.ocrFastMode) }
    }

    static var serverHostname: String {
        get {
            let value = UserDefaults.standard.string(forKey: Key.serverHostname) ?? ""
            return value.isEmpty ? "127.0.0.1" : value
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.serverHostname) }
    }

    static var serverPort: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: Key.serverPort)
            return (1...65535).contains(value) ? value : 8080
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.serverPort) }
    }

    static var startServerAtLaunch: Bool {
        get { UserDefaults.standard.bool(forKey: Key.startServerAtLaunch) }
        set { UserDefaults.standard.set(newValue, forKey: Key.startServerAtLaunch) }
    }

    /// 内嵌 API 服务的访问密钥，空字符串表示不启用鉴权
    static var serverAPIKey: String {
        get { UserDefaults.standard.string(forKey: Key.serverAPIKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Key.serverAPIKey) }
    }

    /// 是否启用全局快捷键（⌃⌥⌘O）截屏识别
    static var usesGlobalHotKey: Bool {
        get { !UserDefaults.standard.bool(forKey: Key.disablesGlobalHotKey) }
        set { UserDefaults.standard.set(!newValue, forKey: Key.disablesGlobalHotKey) }
    }

    static var showsMenuBarIcon: Bool {
        get { !UserDefaults.standard.bool(forKey: Key.hidesMenuBarIcon) }
        set { UserDefaults.standard.set(!newValue, forKey: Key.hidesMenuBarIcon) }
    }
}
