#if compiler(>=6.2) && canImport(Translation)
import NaturalLanguage
import SwiftOpenAPI
import Translation
import Vapor

/// 本地翻译：macOS 26.0+（Translation 框架）
@available(macOS 26.0, *)
struct TranslationController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let group = routes.grouped("translation")

        group.post("translate", use: translateRequest)
            .openAPI(
                description: "本地翻译（macOS 26+）。sourceLanguage 可省略（自动检测）。所需语言包必须已在“系统设置 → 通用 → 语言与地区 → 翻译语言”中下载。",
                body: .type(TranslateRequest.self),
                response: .type(TranslateResponse.self)
            )

        group.get("supported-languages", use: supportedLanguagesRequest)
            .openAPI(
                description: "返回翻译框架支持的语言。",
                response: .type(TranslationLanguagesResponse.self)
            )
    }

    @Sendable func translateRequest(req: Request) async throws -> TranslateResponse {
        let body = try req.content.decode(TranslateRequest.self)

        var texts = body.texts ?? []
        if let single = body.text { texts.insert(single, at: 0) }
        texts = texts.filter { !$0.isEmpty }
        guard !texts.isEmpty else {
            throw Abort(.badRequest, reason: "请提供 text 或 texts")
        }

        let target = Locale.Language(identifier: body.targetLanguage)

        let source: Locale.Language
        if let explicit = body.sourceLanguage, !explicit.isEmpty {
            source = Locale.Language(identifier: explicit)
        } else {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(texts.joined(separator: "\n"))
            guard let detected = recognizer.dominantLanguage else {
                throw Abort(.badRequest, reason: "无法自动检测源语言，请指定 sourceLanguage")
            }
            source = Locale.Language(identifier: detected.rawValue)
        }

        let status = await LanguageAvailability().status(from: source, to: target)
        switch status {
        case .installed:
            break
        case .supported:
            throw Abort(.conflict, reason: "该语言对的翻译语言包尚未下载。请在“系统设置 → 通用 → 语言与地区 → 翻译语言”中下载后重试")
        default:
            throw Abort(.badRequest, reason: "不支持从 \(source.minimalIdentifier) 翻译到 \(target.minimalIdentifier)")
        }

        let session = TranslationSession(installedSource: source, target: target)
        var translations: [String] = []
        do {
            for text in texts {
                let response = try await session.translate(text)
                translations.append(response.targetText)
            }
        } catch {
            throw Abort(.unprocessableEntity, reason: "翻译失败：\(error.localizedDescription)")
        }

        return TranslateResponse(
            sourceLanguage: source.minimalIdentifier,
            targetLanguage: target.minimalIdentifier,
            translations: translations
        )
    }

    @Sendable func supportedLanguagesRequest(req: Request) async throws -> TranslationLanguagesResponse {
        let languages = await LanguageAvailability().supportedLanguages
            .map { $0.minimalIdentifier }
            .sorted()
        return TranslationLanguagesResponse(languages: languages)
    }
}

/// 翻译请求
@OpenAPIDescriptable
struct TranslateRequest: Content {
    /// 待翻译文本
    var text: String?
    /// 批量待翻译文本
    var texts: [String]?
    /// 源语言代码，例如 en；省略则自动检测
    var sourceLanguage: String?
    /// 目标语言代码，例如 zh-Hans
    var targetLanguage: String
}

struct TranslateResponse: Content {
    var sourceLanguage: String
    var targetLanguage: String
    /// 与输入顺序一致的译文
    var translations: [String]
}

struct TranslationLanguagesResponse: Content {
    var languages: [String]
}
#endif
