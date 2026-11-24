import Foundation

/// 一种可选的语言，以及它在各个系统框架里对应的标识
struct LanguageOption: Identifiable, Hashable {
    /// 翻译框架使用的标识
    let id: String
    let name: String
    /// 语音识别与朗读使用的区域标识
    let speechLocale: String
    /// 文字识别使用的语言；为空表示让 Vision 自动检测
    let visionLanguages: [String]

    var language: Locale.Language { Locale.Language(identifier: id) }

    /// 系统翻译框架支持的语言（macOS 26 上实测的列表，不含马来语）
    static let all: [LanguageOption] = [
        LanguageOption(id: "zh-Hans", name: "中文（简体）", speechLocale: "zh-CN", visionLanguages: ["zh-Hans", "en-US"]),
        LanguageOption(id: "zh-Hant", name: "中文（繁体）", speechLocale: "zh-TW", visionLanguages: ["zh-Hant", "en-US"]),
        LanguageOption(id: "en", name: "英语", speechLocale: "en-US", visionLanguages: ["en-US"]),
        LanguageOption(id: "ja", name: "日语", speechLocale: "ja-JP", visionLanguages: ["ja-JP", "en-US"]),
        LanguageOption(id: "ko", name: "韩语", speechLocale: "ko-KR", visionLanguages: ["ko-KR", "en-US"]),
        LanguageOption(id: "id", name: "印尼语", speechLocale: "id-ID", visionLanguages: []),
        LanguageOption(id: "th", name: "泰语", speechLocale: "th-TH", visionLanguages: ["th-TH", "en-US"]),
        LanguageOption(id: "vi", name: "越南语", speechLocale: "vi-VN", visionLanguages: ["vi-VN", "en-US"]),
        LanguageOption(id: "fr", name: "法语", speechLocale: "fr-FR", visionLanguages: ["fr-FR"]),
        LanguageOption(id: "de", name: "德语", speechLocale: "de-DE", visionLanguages: ["de-DE"]),
        LanguageOption(id: "es", name: "西班牙语", speechLocale: "es-ES", visionLanguages: ["es-ES"]),
        LanguageOption(id: "it", name: "意大利语", speechLocale: "it-IT", visionLanguages: ["it-IT"]),
        LanguageOption(id: "pt", name: "葡萄牙语", speechLocale: "pt-BR", visionLanguages: ["pt-BR"]),
        LanguageOption(id: "ru", name: "俄语", speechLocale: "ru-RU", visionLanguages: ["ru-RU"]),
        LanguageOption(id: "ar-AE", name: "阿拉伯语", speechLocale: "ar-AE", visionLanguages: []),
        LanguageOption(id: "hi", name: "印地语", speechLocale: "hi-IN", visionLanguages: []),
        LanguageOption(id: "nl", name: "荷兰语", speechLocale: "nl-NL", visionLanguages: []),
        LanguageOption(id: "pl", name: "波兰语", speechLocale: "pl-PL", visionLanguages: []),
        LanguageOption(id: "tr", name: "土耳其语", speechLocale: "tr-TR", visionLanguages: []),
        LanguageOption(id: "uk", name: "乌克兰语", speechLocale: "uk-UA", visionLanguages: ["uk-UA"]),
    ]

    static func option(for id: String) -> LanguageOption? {
        all.first { $0.id == id }
    }
}
