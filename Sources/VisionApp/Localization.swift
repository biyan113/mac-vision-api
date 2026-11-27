import Foundation

/// 界面语言。文案直接写在代码里，不依赖资源包，这样 `swift run` 和打包后的 .app 行为一致。
enum Localization {
    /// 启动时确定，修改偏好设置后需要重启应用才生效
    static let usesChinese: Bool = {
        switch Settings.interfaceLanguage {
        case .chinese: return true
        case .english: return false
        case .system: return (Locale.preferredLanguages.first ?? "zh").hasPrefix("zh")
        }
    }()
}

/// 按当前界面语言返回对应文案
func L(_ chinese: String, _ english: String) -> String {
    Localization.usesChinese ? chinese : english
}
