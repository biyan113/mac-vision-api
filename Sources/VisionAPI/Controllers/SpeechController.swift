#if compiler(>=6.2)
import AVFoundation
import Speech
import SwiftOpenAPI
import Vapor

/// 本地语音转写：macOS 26.0+（SpeechAnalyzer / SpeechTranscriber）
@available(macOS 26.0, *)
struct SpeechController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let group = routes.grouped("speech")

        group.post("transcribe", use: transcribeRequest)
            .openAPI(
                description: "语音转文字（macOS 26+）：完全在本机处理。locale 例如 en-US、zh-CN（默认 en-US）。首次使用某语言时会自动下载对应的系统语音模型。",
                body: .type(TranscribeRequest.self),
                contentType: .multipart(.formData),
                response: .type(TranscribeResponse.self)
            )

        group.get("supported-locales", use: supportedLocalesRequest)
            .openAPI(
                description: "返回语音转写支持的语言，以及已安装模型的语言。",
                response: .type(SpeechLocalesResponse.self)
            )
    }

    @Sendable func transcribeRequest(req: Request) async throws -> TranscribeResponse {
        let input = try await InputResolver.resolve(from: req, prefix: "audio", label: "音频")
        let requested = (try? req.content.get(String.self, at: "locale")) ?? "en-US"

        guard let locale = await Self.matchLocale(requested) else {
            throw Abort(.badRequest, reason: "不支持的语言：\(requested)。可通过 GET /speech/supported-locales 查看支持列表")
        }

        // AVAudioFile 需要从文件读取，先写入临时文件
        let ext = input.filename.flatMap { name -> String? in
            let value = URL(fileURLWithPath: name).pathExtension
            return value.isEmpty ? nil : value
        } ?? "m4a"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vision-api-\(UUID().uuidString).\(ext)")
        try input.data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: tempURL)
        } catch {
            throw Abort(.unprocessableEntity, reason: "无法读取音频文件：\(error.localizedDescription)")
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        // 按需下载语音模型
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            req.logger.notice("正在下载语音模型：\(locale.identifier(.bcp47))")
            try await installation.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        let collector = Task { () throws -> [TranscriptSegment] in
            var segments: [TranscriptSegment] = []
            for try await result in transcriber.results {
                let text = String(result.text.characters)
                guard !text.isEmpty else { continue }
                segments.append(TranscriptSegment(
                    text: text,
                    start: Self.seconds(result.range.start),
                    duration: Self.seconds(result.range.duration)
                ))
            }
            return segments
        }

        do {
            if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            collector.cancel()
            throw Abort(.unprocessableEntity, reason: "语音转写失败：\(error.localizedDescription)")
        }

        let segments = try await collector.value
        return TranscribeResponse(
            locale: locale.identifier(.bcp47),
            text: segments.map(\.text).joined(),
            segments: segments
        )
    }

    @Sendable func supportedLocalesRequest(req: Request) async throws -> SpeechLocalesResponse {
        let supported = await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }.sorted()
        let installed = await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) }.sorted()
        return SpeechLocalesResponse(supported: supported, installed: installed)
    }

    // MARK: - Helpers

    /// 在支持列表中查找与请求最接近的语言：先精确匹配，再按语言代码匹配
    private static func matchLocale(_ identifier: String) async -> Locale? {
        let supported = await SpeechTranscriber.supportedLocales
        let wanted = Locale(identifier: identifier)
        let wantedTag = wanted.identifier(.bcp47).lowercased()

        if let exact = supported.first(where: { $0.identifier(.bcp47).lowercased() == wantedTag }) {
            return exact
        }
        guard let language = wanted.language.languageCode?.identifier else { return nil }
        return supported.first { $0.language.languageCode?.identifier == language }
    }

    private static func seconds(_ time: CMTime) -> Double {
        let value = time.seconds
        return value.isFinite ? value : 0
    }
}

/// 语音转写请求（仅用于 OpenAPI 文档）
@OpenAPIDescriptable
struct TranscribeRequest: Content {
    /// 上传的音频文件（m4a、mp3、wav、caf 等 AVFoundation 支持的格式）
    var audioFile: Data?
    /// 服务器本地音频路径（需开启 VISION_ALLOW_LOCAL_FILES）
    var audioPath: String?
    /// 远程音频 URL
    var audioURL: String?
    /// Base64 编码的音频数据
    var audioBase64: String?
    /// 语言，例如 en-US、zh-CN，默认 en-US
    var locale: String?
}

struct TranscriptSegment: Content {
    var text: String
    /// 起始时间（秒）
    var start: Double
    /// 时长（秒）
    var duration: Double
}

struct TranscribeResponse: Content {
    var locale: String
    var text: String
    var segments: [TranscriptSegment]
}

struct SpeechLocalesResponse: Content {
    var supported: [String]
    var installed: [String]
}
#endif
